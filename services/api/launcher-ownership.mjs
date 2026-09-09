import fs from 'node:fs';
import path from 'node:path';
import {ROOT} from './config.mjs';

// One ownership record per checkout. A second invocation reuses the recorded
// services only when the PID they name is still running; it never claims,
// signals or stops a process this record does not name.
export const OWNERSHIP_PATH=path.join(ROOT,'.data','launcher-owner.json');

function alive(pid) {
  try { process.kill(pid,0); return true; }
  catch (error) { return error.code==='EPERM'; }
}

export function readLauncherOwnership(file=OWNERSHIP_PATH) {
  if (!fs.existsSync(file)) return null;
  try {
    const record=JSON.parse(fs.readFileSync(file,'utf8'));
    if (typeof record.pid!=='number' || typeof record.apiPort!=='number' || typeof record.providerPort!=='number') return null;
    return record;
  } catch { return null; }
}

// Returns {reuse:true, record} when a live process already owns this
// checkout's services. Returns {reuse:false, record, release} to claim
// ownership as a fresh launch; the caller must invoke release() on exit.
export function claimLauncherOwnership(ports,file=OWNERSHIP_PATH) {
  fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});
  const existing=readLauncherOwnership(file);
  if (existing && alive(existing.pid)) return {reuse:true,record:existing};
  const record={pid:process.pid,apiPort:ports.apiPort,providerPort:ports.providerPort,startedAt:new Date().toISOString()};
  fs.writeFileSync(file,JSON.stringify(record),{mode:0o600});
  let released=false;
  const release=() => {
    if (released) return; released=true;
    try {
      const current=readLauncherOwnership(file);
      if (current && current.pid===process.pid) fs.unlinkSync(file);
    } catch {}
  };
  return {reuse:false,record,release};
}
