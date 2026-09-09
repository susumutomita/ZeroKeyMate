import fs from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {ROOT} from './config.mjs';

export const OWNERSHIP_PATH=path.join(ROOT,'.data','launcher-owner.json');
function alive(pid) {
  try { process.kill(pid,0); return true; }
  catch (error) { if(error.code==='ESRCH')return false;throw error; }
}
export function readLauncherOwnership(file=OWNERSHIP_PATH) {
  let stat;
  try {stat=fs.lstatSync(file);}catch(error){if(error.code==='ENOENT')return null;throw error;}
  if(!stat.isFile() || stat.isSymbolicLink())throw new Error('Invalid launcher ownership file.');
  const record=JSON.parse(fs.readFileSync(file,'utf8'));
  if(!Number.isSafeInteger(record.pid) || record.pid<=0 ||
    ![record.apiPort,record.providerPort].every(p=>Number.isInteger(p)&&p>0&&p<=65535) ||
    typeof record.instance!=='string' || typeof record.environment!=='string')throw new Error('Invalid launcher ownership record.');
  return record;
}
// Serialize claims and releases; a crashed guard is never stolen on a timer.
function locked(file,operation) {
  fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});
  const guard=file+'.guard';
  try{fs.mkdirSync(guard,{mode:0o700});}catch(error){if(error.code==='EEXIST')throw new Error('Launcher ownership is being updated. Retry after the other launcher exits; inspect a persistent guard before removing it.');throw error;}
  try{return operation();}finally{fs.rmdirSync(guard);}
}
export function claimLauncherOwnership(ports,file=OWNERSHIP_PATH) {
  return locked(file,()=>{
    const existing=readLauncherOwnership(file);
    if(existing && alive(existing.pid)) {
      if(existing.apiPort!==ports.apiPort || existing.providerPort!==ports.providerPort || existing.environment!==(ports.environment??''))
        throw new Error('The running launcher uses different settings. Stop it before changing the environment.');
      return {reuse:true,record:existing};
    }
    if(existing)fs.unlinkSync(file);
    const record={pid:process.pid,apiPort:ports.apiPort,providerPort:ports.providerPort,
      startedAt:new Date().toISOString(),instance:randomUUID(),environment:ports.environment??''};
    fs.writeFileSync(file,JSON.stringify(record),{mode:0o600,flag:'wx'});
    let released=false;
    return {reuse:false,record,release(){
      if(released)return;
      locked(file,()=>{
        const current=readLauncherOwnership(file);
        if(current?.instance===record.instance && current.pid===record.pid)fs.unlinkSync(file);
        released=true;
      });
    }};
  });
}
