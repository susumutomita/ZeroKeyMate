import fs from 'node:fs';
import path from 'node:path';
import {ProductError} from './errors.mjs';

// One writer owns each transaction journal. Never steal a lock on a timer:
// a paused process may still have a signed transaction in flight.
export function processLock(filename) {
  fs.mkdirSync(path.dirname(filename), {recursive:true, mode:0o700});
  let descriptor;
  try { descriptor=fs.openSync(filename, 'wx', 0o600); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    throw new ProductError('process_locked', 'この実行記録はロックされています。稼働中のプロセスを確認してください。',503);
  }
  fs.writeFileSync(descriptor, JSON.stringify({pid:process.pid,startedAt:new Date().toISOString()}));
  fs.fsyncSync(descriptor);
  const inode=fs.fstatSync(descriptor).ino;
  let closed=false;
  return () => {
    if (closed) return;
    closed=true;fs.closeSync(descriptor);
    if (fs.existsSync(filename) && fs.lstatSync(filename).ino===inode) fs.unlinkSync(filename);
  };
}
