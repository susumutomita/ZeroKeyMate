import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {claimLauncherOwnership,readLauncherOwnership} from '../launcher-ownership.mjs';
import {startLauncherControl,requestLauncherStop} from '../launcher-control.mjs';

test('stop requests wait for owned work and cannot stop another checkout',async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'mate-control-'));
  const first=path.join(dir,'first.json'),second=path.join(dir,'second.json');
  const a=claimLauncherOwnership({apiPort:8787,providerPort:8788},first);
  const b=claimLauncherOwnership({apiPort:8887,providerPort:8888},second);
  let finish,entered;
  const draining=new Promise(resolve=>{finish=resolve;});
  const called=new Promise(resolve=>{entered=resolve;});
  let otherStopped=false;
  const server=await startLauncherControl(a.record,async()=>{entered();await draining;a.release();},first);
  const other=await startLauncherControl(b.record,()=>{otherStopped=true;b.release();},second);
  try {
    const stop=requestLauncherStop(first);await called;
    assert.ok(readLauncherOwnership(first));
    assert.equal(otherStopped,false);
    finish();assert.deepEqual(await stop,{running:true});
    assert.equal(readLauncherOwnership(first),null);
    assert.ok(readLauncherOwnership(second));
    assert.deepEqual(await requestLauncherStop(first),{running:false});
    assert.deepEqual(await requestLauncherStop(second),{running:true});
    assert.equal(otherStopped,true);
  }finally{finish();server.close();other.close();a.release();b.release();fs.rmSync(dir,{recursive:true,force:true});}
});

test('missing or unconfirmed control never signals the PID or releases its record',async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'mate-control-')),file=path.join(dir,'owner.json');
  const claim=claimLauncherOwnership({apiPort:8787,providerPort:8788},file);
  let server,finish;
  try {
    await assert.rejects(requestLauncherStop(file),/No process was signalled/);
    assert.equal(readLauncherOwnership(file).pid,process.pid);
    const work=new Promise(resolve=>{finish=resolve;});
    server=await startLauncherControl(claim.record,()=>work,file);
    await assert.rejects(requestLauncherStop(file,25),/unconfirmed/);
    assert.ok(readLauncherOwnership(file));
    process.kill(process.pid,0);
  }finally{finish?.();server?.close();claim.release();fs.rmSync(dir,{recursive:true,force:true});}
});
