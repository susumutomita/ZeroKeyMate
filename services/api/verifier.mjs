import fs from 'node:fs/promises';
import {constants} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {sha256, assertStatement} from './protocol.mjs';
import {ProductError, requireValue, SerialQueue} from './errors.mjs';

const executeFile = promisify(execFile);
const MAX_PROOF = 8 * 1024 * 1024;
export class ProofVerifier {
  #binary;
  #verifier;
  #manifest;
  #queue = new SerialQueue();
  #ready = false;
  constructor({binary, verifier, manifest}) {
    this.#binary = path.resolve(binary);
    this.#verifier = path.resolve(verifier);
    this.#manifest = path.resolve(manifest);
  }
  async prepare() {
    const manifest = JSON.parse(await fs.readFile(this.#manifest, 'utf8'));
    requireValue(manifest.system === 'ProveKit' && manifest.version === '1.0.1'
      && manifest.circuit === 'mate_policy' && manifest.hash === 'skyscraper',
      'circuit_configuration', '検証回路の設定が正しくありません。', 503);
    const verifier = await fs.readFile(this.#verifier);
    requireValue(sha256(verifier).slice(2) === manifest.files?.['mate_policy.pkv'],
      'circuit_integrity', '検証回路のハッシュが一致しません。', 503);
    await fs.access(this.#binary, constants.X_OK);
    this.#ready = true;
  }
  async verify(base64, expected) {
    requireValue(typeof base64 === 'string' && base64.length > 0 && base64.length <= Math.ceil(MAX_PROOF / 3) * 4
      && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(base64),
      'invalid_proof', '証明の形式が正しくありません。');
    const bytes = Buffer.from(base64, 'base64');
    requireValue(bytes.length > 0 && bytes.length <= MAX_PROOF && bytes.toString('base64') === base64,
      'invalid_proof', '証明の形式が正しくありません。');
    return this.#queue.run(async () => {
      if (!this.#ready) await this.prepare();
      const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'mate-verify-'));
      await fs.chmod(directory, 0o700);
      const filename = path.join(directory, 'proof.np');
      try {
        await fs.writeFile(filename, bytes, {mode: 0o600, flag: 'wx'});
        // No shell, no request-selected executable, verifier file, or filesystem path.
        const {stdout} = await executeFile(this.#binary, [this.#verifier, filename],
          {timeout: 90_000, maxBuffer: 128 * 1024, windowsHide: true});
        const statement = assertStatement(JSON.parse(stdout), expected);
        return {statement, proofHash: sha256(bytes), bytes: bytes.length};
      } catch (error) {
        if (error instanceof ProductError) throw error;
        throw new ProductError('proof_rejected', '証明を検証できませんでした。支払いは承認していません。', 422);
      } finally {await fs.rm(directory, {recursive: true, force: true});}
    });
  }
}
