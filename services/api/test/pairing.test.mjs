import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {PairingStore,PAIRING_CODE_SECONDS,SESSION_SECONDS,SESSION_REQUESTS} from '../pairing.mjs';

test('one-time pairing yields purpose-bound expiring and counted sessions',()=>{
  const store=new PairingStore(':memory:','chain:vault');
  try {
    const code=store.issue(100).code;
    const session=store.exchange(code,101);
    assert.throws(()=>store.exchange(code,102),{code:'pairing_invalid'});
    assert.equal(store.authorize(code,102),false);
    for(let i=0;i<SESSION_REQUESTS;i++)assert.equal(store.authorize(session.token,102),true);
    assert.equal(store.authorize(session.token,102),false);
    const next=store.exchange(store.issue(200).code,200);
    assert.equal(store.authorize(next.token,200+SESSION_SECONDS),false);
    const expired=store.issue(300).code;
    assert.throws(()=>store.exchange(expired,300+PAIRING_CODE_SECONDS),{code:'pairing_invalid'});
  }finally{store.close();}
});

test('consumption survives restart, scopes stay separate and revocation is immediate',()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-pairing-')),filename=path.join(directory,'auth.sqlite');
  let store=new PairingStore(filename,'a');
  try {
    const first=store.issue(10).code,second=store.issue(11).code;
    assert.throws(()=>store.exchange(first,12),{code:'pairing_invalid'});
    const session=store.exchange(second,12);
    assert.equal(store.authorize(session.token,13),true);
    store.close();store=new PairingStore(filename,'a');
    assert.throws(()=>store.exchange(second,13),{code:'pairing_invalid'});
    const other=new PairingStore(filename,'b');
    try{assert.equal(other.authorize(session.token,13),false);}finally{other.close();}
    for(let i=1;i<SESSION_REQUESTS;i++)assert.equal(store.authorize(session.token,13),true);
    assert.equal(store.authorize(session.token,13),false);
    const renewed=store.exchange(store.issue(14).code,14);
    store.revoke();assert.equal(store.authorize(renewed.token,15),false);
    assert.equal(fs.statSync(filename).mode&0o777,0o600);
    for(const file of fs.readdirSync(directory)) {
      const bytes=fs.readFileSync(path.join(directory,file));
      assert.equal(bytes.includes(Buffer.from(second)),false);
      assert.equal(bytes.includes(Buffer.from(session.token)),false);
    }
  }finally{store.close();fs.rmSync(directory,{recursive:true,force:true});}
});
