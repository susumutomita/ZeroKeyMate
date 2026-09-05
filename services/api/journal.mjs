import {DatabaseSync} from 'node:sqlite';
import {createCipheriv, createDecipheriv, randomBytes} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

/** Durable write-ahead journal. Sensitive payloads and signed transactions are encrypted. */
export class Journal {
  #database;
  #key;
  constructor(filename, key) {
    if (!/^[0-9a-fA-F]{64}$/.test(key)) throw new Error('MATE_JOURNAL_KEY must be 32 random bytes encoded as hex');
    this.#key = Buffer.from(key, 'hex');
    if (filename !== ':memory:') {
      fs.mkdirSync(path.dirname(filename), {recursive: true, mode: 0o700});
      if (fs.existsSync(filename) && fs.lstatSync(filename).isSymbolicLink()) throw new Error('Journal must not be a symlink');
    }
    this.#database = new DatabaseSync(filename);
    this.#database.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;');
    this.#database.exec(`CREATE TABLE IF NOT EXISTS entries (
      id TEXT PRIMARY KEY NOT NULL, state TEXT NOT NULL, ciphertext BLOB NOT NULL,
      updated_at INTEGER NOT NULL
    ) STRICT`);
    if (filename !== ':memory:') fs.chmodSync(filename, 0o600);
  }
  #encrypt(id, state, value) {
    const nonce = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.#key, nonce);
    cipher.setAAD(Buffer.from(`${id}\n${state}`));
    const bytes = Buffer.from(JSON.stringify(value));
    return Buffer.concat([nonce, cipher.getAuthTag ? Buffer.alloc(0) : Buffer.alloc(0),
      ...(() => {const encrypted=Buffer.concat([cipher.update(bytes),cipher.final()]);return [cipher.getAuthTag(),encrypted];})()]);
  }
  #decrypt(id, state, bytes) {
    const packed = Buffer.from(bytes);
    if (packed.length < 28) throw new Error('Corrupt journal entry');
    const decipher = createDecipheriv('aes-256-gcm', this.#key, packed.subarray(0, 12));
    decipher.setAAD(Buffer.from(`${id}\n${state}`));
    decipher.setAuthTag(packed.subarray(12, 28));
    return JSON.parse(Buffer.concat([decipher.update(packed.subarray(28)), decipher.final()]).toString('utf8'));
  }
  get(id) {
    const row = this.#database.prepare('SELECT state,ciphertext,updated_at FROM entries WHERE id=?').get(id);
    if (!row) return null;
    return {state: row.state, value: this.#decrypt(id, row.state, row.ciphertext), updatedAt: row.updated_at};
  }
  put(id, state, value) {
    if (typeof id !== 'string' || id.length > 200 || !/^[a-z]+$/.test(state)) throw new Error('Invalid journal key');
    const encrypted = this.#encrypt(id, state, value);
    this.#database.prepare(`INSERT INTO entries(id,state,ciphertext,updated_at) VALUES(?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET state=excluded.state,ciphertext=excluded.ciphertext,updated_at=excluded.updated_at`)
      .run(id, state, encrypted, Date.now());
  }
  pending(prefix) {
    return this.#database.prepare("SELECT id FROM entries WHERE state IN ('prepared','broadcast') AND id LIKE ?")
      .all(`${prefix}%`).map(row => ({id: row.id, ...this.get(row.id)}));
  }
  close() {this.#database.close(); this.#key.fill(0);}
}
