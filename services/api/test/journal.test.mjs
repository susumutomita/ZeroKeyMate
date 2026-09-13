import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {Journal} from '../journal.mjs';
import {processLock} from '../process-lock.mjs';

test('encrypted recovery survives restart without plaintext disclosure on disk',()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-journal-test-'));
  try {
    const filename=path.join(directory,'journal.sqlite'),key='ab'.repeat(32);
    const first=new Journal(filename,key);
    first.put('execution:test','paid',{payload:'PRIVATE_APPROVED_DISCLOSURE',hash:'transaction'});
    first.close();
    assert.ok(!fs.readFileSync(filename).includes(Buffer.from('PRIVATE_APPROVED_DISCLOSURE')));
    const second=new Journal(filename,key);
    assert.equal(second.get('execution:test').value.payload,'PRIVATE_APPROVED_DISCLOSURE');second.close();
    const wrong=new Journal(filename,'cd'.repeat(32));
    assert.throws(()=>wrong.get('execution:test'));wrong.close();
  }finally{fs.rmSync(directory,{recursive:true,force:true});}
});
test('a transaction journal cannot have two process owners',()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-lock-test-')),filename=path.join(directory,'process.lock');
  try {
    const release=processLock(filename);
    assert.throws(()=>processLock(filename),{code:'process_locked'});
    release();release();
    const next=processLock(filename);next();
  }finally{fs.rmSync(directory,{recursive:true,force:true});}
});
