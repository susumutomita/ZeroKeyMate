import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Journal} from '../../api/journal.mjs';
import {Specialist} from '../server.mjs';
import {actionDigest,sha256} from '../../api/protocol.mjs';
const config={vault:'0x'+'11'.repeat(20),recipient:'0x'+'33'.repeat(20),price:'100000',service:0};
const action={mandateId:'0x'+'22'.repeat(32),recipient:config.recipient,amount:config.price,service:0,
  nonce:'0x'+'44'.repeat(32),expiresAt:Math.floor(Date.now()/1000)+300,requestHash:sha256('approved'),spentBefore:'0'};
const request={action,payload:'approved',agentSignature:'0x1234',proofHash:sha256('test attestation identifier')};
test('specialist rejects altered disclosure and invalid agent signatures before model work',async t=>{
  const journal=new Journal(':memory:','ab'.repeat(32));t.after(()=>journal.close());
  let runs=0;
  const specialist=new Specialist({config,journal,model:{run:async()=>{runs++;assert.fail('must not run');}},
    chain:{state:async()=>({revoked:false,spent:'0',validUntil:action.expiresAt+100}),verifyAgent:async()=>false}});
  await assert.rejects(specialist.prepare({...request,payload:'altered'}),{code:'request_mismatch'});
  await assert.rejects(specialist.prepare(request),{code:'agent_signature'});assert.equal(runs,0);
});
test('prepared work is withheld when independent onchain payment verification fails',async t=>{
  const journal=new Journal(':memory:','ab'.repeat(32));t.after(()=>journal.close());
  const hash=actionDigest(11155111,config.vault,action);
  journal.put(`work:${hash}`,'ready',{request,result:'Private test result'});
  const specialist=new Specialist({config,journal,model:{},chain:{executionEvent:async()=>{throw new Error('unconfirmed transaction');}}});
  await assert.rejects(specialist.release({actionHash:hash,transactionHash:'0x'+'66'.repeat(32),proofHash:request.proofHash}),/unconfirmed/);
  assert.equal(journal.get(`work:${hash}`).state,'ready');
});
test('an unavailable actual model is never advertised as ready',async()=>{
  const specialist=new Specialist({config,model:{ready:async()=>{throw new Error('model not installed');}}});
  await assert.rejects(specialist.quote(0),/model not installed/);
  await assert.rejects(specialist.quote(1),{code:'service_unavailable'});
});
