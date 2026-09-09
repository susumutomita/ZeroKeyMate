import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {claimLauncherOwnership,readLauncherOwnership} from '../launcher-ownership.mjs';

test('a fresh launch claims ownership and records this process, not a placeholder',()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-launcher-'));
  const file=path.join(directory,'launcher-owner.json');
  try {
    const claim=claimLauncherOwnership({apiPort:8787,providerPort:8788},file);
    assert.equal(claim.reuse,false);
    assert.equal(claim.record.pid,process.pid);
    assert.equal(readLauncherOwnership(file).apiPort,8787);
    claim.release();
    assert.equal(readLauncherOwnership(file),null);
  } finally { fs.rmSync(directory,{recursive:true,force:true}); }
});

test('a second invocation reuses a still-running owner instead of starting twice',()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-launcher-'));
  const file=path.join(directory,'launcher-owner.json');
  try {
    const first=claimLauncherOwnership({apiPort:8787,providerPort:8788},file);
    const second=claimLauncherOwnership({apiPort:8787,providerPort:8788},file);
    assert.equal(second.reuse,true);
    assert.equal(second.record.pid,process.pid);
    first.release();
  } finally { fs.rmSync(directory,{recursive:true,force:true}); }
});

test('a stale record from a dead process is replaced, never reused',()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-launcher-'));
  const file=path.join(directory,'launcher-owner.json');
  try {
    // A PID that cannot belong to a real, currently-running process in this test.
    fs.writeFileSync(file,JSON.stringify({pid:999_999,apiPort:8787,providerPort:8788,startedAt:new Date().toISOString()}));
    const claim=claimLauncherOwnership({apiPort:8787,providerPort:8788},file);
    assert.equal(claim.reuse,false);
    assert.equal(claim.record.pid,process.pid);
    claim.release();
  } finally { fs.rmSync(directory,{recursive:true,force:true}); }
});

test('release only removes a record this process still owns',()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-launcher-'));
  const file=path.join(directory,'launcher-owner.json');
  try {
    const claim=claimLauncherOwnership({apiPort:8787,providerPort:8788},file);
    fs.writeFileSync(file,JSON.stringify({pid:999_999,apiPort:8787,providerPort:8788,startedAt:new Date().toISOString()}));
    claim.release();
    assert.equal(readLauncherOwnership(file).pid,999_999);
  } finally { fs.rmSync(directory,{recursive:true,force:true}); }
});
