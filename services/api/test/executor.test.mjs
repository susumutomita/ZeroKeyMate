import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Journal} from '../journal.mjs';
import {Executor} from '../executor.mjs';
import {actionDigest,sha256} from '../protocol.mjs';

// These exercise rejection and recovery boundaries, never substitute a verifier
// that can accept a proof. Real proving has its own cryptographic acceptance job.
const vault='0x'+'11'.repeat(20);
const action={mandateId:'0x'+'22'.repeat(32),recipient:'0x'+'33'.repeat(20),amount:'100000',service:0,
  nonce:'0x'+'44'.repeat(32),expiresAt:Math.floor(Date.now()/1000)+300,requestHash:sha256('approved text'),spentBefore:'0'};
const request={action,agentSignature:'0x1234',payload:'approved text',providerId:'11155111:1',proof:'AAAA'};
const hash=actionDigest(11155111,vault,action);
const fail=()=>assert.fail('This boundary must not be reached');
function fixture(t,chain={}) {
  const journal=new Journal(':memory:','ab'.repeat(32));t.after(()=>journal.close());
  const executor=new Executor({config:{vault},journal,chain:{pay:fail,...chain},
    verifier:{verify:fail},discovery:{choose:fail,call:fail}});
  return {journal,executor};
}
test('changed approved disclosure is rejected before touching chain or verifier',async t=>{
  const {executor}=fixture(t,{state:fail});
  await assert.rejects(executor.execute({...request,payload:'substituted'}),{code:'payload_hash'});
});
test('revoked or changed spend state cannot reach proof validation or payment',async t=>{
  const {executor}=fixture(t,{state:async()=>({revoked:true,validUntil:action.expiresAt+100,spent:'0'})});
  await assert.rejects(executor.execute(request),{code:'stale_mandate'});
});
test('an invalid agent signature cannot reach discovery, proof verification, or payment',async t=>{
  const {executor}=fixture(t,{state:async()=>({revoked:false,validUntil:action.expiresAt+100,spent:'0'}),verifyAgent:async()=>false});
  await assert.rejects(executor.execute(request),{code:'agent_signature'});
});
test('cancelling an unreceived request rejects even its delayed first submission',async t=>{
  const {executor}=fixture(t,{state:fail});
  assert.deepEqual(await executor.cancel(hash),{actionHash:hash,status:'cancelled'});
  await assert.rejects(executor.execute(request),{code:'execution_cancelled'});
  await assert.rejects(executor.receipt(hash),{code:'execution_cancelled'});
  assert.deepEqual(await executor.cancel(hash),{actionHash:hash,status:'cancelled'});
});
test('requests with an uncertain payment can never be discarded',async t=>{
  const {journal,executor}=fixture(t);
  for(const state of ['ready','paid','complete']) {
    journal.put(`execution:${hash}`,state,{request});
    await assert.rejects(executor.cancel(hash),{code:'payment_pending'});
    assert.equal(journal.get(`execution:${hash}`).state,state);
  }
});
test('receipt recovery after paid state only releases the result, without a second payment',async t=>{
  const {journal,executor}=fixture(t);
  // Durable already-paid recovery fixture, not a cryptographic acceptance claim.
  const proofHash=sha256('fixture proof identifier'),payment={actionHash:hash,proofHash,transactionHash:'0x'+'55'.repeat(32),blockNumber:'7',spentAfter:'100000'};
  journal.put(`execution:${hash}`,'paid',{request,provider:{id:'11155111:1'},proofHash,payment});
  let calls=0;
  executor.discovery.call=async(_provider,route)=>{assert.equal(route,'/v1/release');calls++;return {actionHash:hash,result:'Fixture specialist result'};};
  const receipt=await executor.receipt(hash);
  assert.equal(receipt.transactionHash,payment.transactionHash);
  assert.equal(journal.get(`execution:${hash}`).state,'complete');
  assert.deepEqual(await executor.receipt(hash),receipt);assert.equal(calls,1);
});
