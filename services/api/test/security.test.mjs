import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {Readable} from 'node:stream';
import {randomBytes} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {authenticated, readJSON} from '../http.mjs';
import {Journal} from '../journal.mjs';
import {dnsEncode, nameMessage} from '../names.mjs';
import {ensName, providerSchema} from '../config.mjs';

// These are unit inputs to the real parsers/journal, not injected product outcomes.
test('pairing capability rejects prefixes, suffixes and malformed headers', () => {
  const token=randomBytes(32).toString('hex');
  assert.equal(authenticated({headers:{authorization:`Bearer ${token}`}},token),true);
  for(const value of ['',token,`Bearer ${token}x`,`Bearer ${token.slice(1)}`]) {
    assert.equal(authenticated({headers:{authorization:value}},token),false);
  }
});
test('request parser enforces object, length, UTF-8 and content encoding', async () => {
  const request=(bytes,headers={})=>Object.assign(Readable.from([Buffer.from(bytes)]),{headers:{'content-type':'application/json',...headers}});
  assert.deepEqual(await readJSON(request('{"amount":"1"}')), {amount:'1'});
  await assert.rejects(readJSON(request('[]')));
  await assert.rejects(readJSON(request('{"x":"123456"}'),5));
  await assert.rejects(readJSON(request('{}',{'content-encoding':'gzip'})));
  await assert.rejects(readJSON(request(Buffer.from([0xff]))));
});
test('encrypted journal survives reopen and rejects key/state substitution', () => {
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-journal-test-'));
  const filename=path.join(directory,'journal.sqlite');
  const key=randomBytes(32).toString('hex');
  let journal;
  try {
    journal=new Journal(filename,key);
    journal.put('execution:test','authorized',{payload:'private reviewed text',nonce:'one'});
    journal.close();journal=null;
    assert.equal(fs.readFileSync(filename).includes(Buffer.from('private reviewed text')),false);
    journal=new Journal(filename,key);
    assert.equal(journal.get('execution:test').value.payload,'private reviewed text');
    journal.close();journal=null;
    journal=new Journal(filename,randomBytes(32).toString('hex'));
    assert.throws(()=>journal.get('execution:test'));
    journal.close();journal=null;
    const database=new DatabaseSync(filename);
    database.prepare('UPDATE entries SET state=? WHERE id=?').run('complete','execution:test');
    database.close();
    journal=new Journal(filename,key);
    assert.throws(()=>journal.get('execution:test'));
  } finally {journal?.close();fs.rmSync(directory,{recursive:true,force:true});}
});
test('name encoding is strict and the signature includes its parent namespace', () => {
  assert.equal(dnsEncode('a.eth'),'0x01610365746800');
  for(const name of ['a..eth','A.eth','-a.eth','日本.eth',`${'a'.repeat(64)}.eth`])assert.equal(ensName.safeParse(name).success,false);
  const request={label:'mate',owner:'0x'+'11'.repeat(20),agent:'0x'+'22'.repeat(20),nonce:'0x'+'33'.repeat(32),expiresAt:123};
  const message=nameMessage(request,{vault:'0x'+'44'.repeat(20),ensParent:'first.eth'});
  assert.notEqual(message,nameMessage(request,{vault:'0x'+'44'.repeat(20),ensParent:'second.eth'}));
  assert.ok(message.includes('parent:first.eth\nlabel:mate'));
});
test('provider configuration never accepts a browser-supplied HTTP endpoint', () => {
  const provider={id:'11155111:7',service:0,price:'10000',owner:'0x'+'11'.repeat(20),recipient:'0x'+'22'.repeat(20),
    ensName:'specialist.example.eth',endpoint:'https://provider.example.org',bearerToken:'a'.repeat(64)};
  assert.equal(providerSchema.safeParse(provider).success,true);
  for(const endpoint of ['http://127.0.0.1','http://169.254.169.254','file:///etc/passwd','https://user:password@example.org']) {
    assert.equal(providerSchema.safeParse({...provider,endpoint}).success,false);
  }
});
