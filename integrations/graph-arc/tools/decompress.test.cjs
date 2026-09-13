const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const decompress = require('./decompress/index.cjs');

function archive(name) {
  const header = Buffer.alloc(512);
  const body = Buffer.from('synthetic test only\n');
  header.write(name, 0);
  header.write('0000644\0', 100);
  header.write('0000000\0', 108);
  header.write('0000000\0', 116);
  header.write(body.length.toString(8).padStart(11, '0') + '\0', 124);
  header.write('00000000000\0', 136);
  header.fill(32, 148, 156);
  header.write('0', 156);
  header.write('ustar\0', 257);
  header.write('00', 263);
  const checksum = header.reduce((sum, byte) => sum + byte, 0);
  header.write(checksum.toString(8).padStart(6, '0') + '\0 ', 148);
  return Buffer.concat([header, body, Buffer.alloc(512 - body.length), Buffer.alloc(1024)]);
}

test('CommonJS adapter extracts a normal archive and prevents parent-directory writes', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'mate-graph-archive-'));
  try {
    const output = path.join(root, 'output');
    await decompress(archive('receipt.txt'), output);
    assert.equal(await fs.readFile(path.join(output, 'receipt.txt'), 'utf8'), 'synthetic test only\n');
    try { await decompress(archive('../escaped.txt'), output); } catch { /* Rejecting is valid too. */ }
    await assert.rejects(fs.access(path.join(root, 'escaped.txt')), {code: 'ENOENT'});
  } finally { await fs.rm(root, {recursive: true, force: true}); }
});
