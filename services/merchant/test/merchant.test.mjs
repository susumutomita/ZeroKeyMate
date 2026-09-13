import {test} from 'node:test';
import http from 'node:http';
import assert from 'node:assert/strict';
import {merchantServer,orderSummaries} from '../server.mjs';
import {Specialist} from '../../provider/server.mjs';
import {Journal} from '../../api/journal.mjs';
import {actionDigest,sha256} from '../../api/protocol.mjs';

// Unit doubles exercise orchestration only, never stand in for cryptographic evidence.
function fixture(t,{rejectProof=false,rejectPayment=false,failModelOnce=false}={}){
  const journal=new Journal(':memory:','ab'.repeat(32));t.after(()=>journal.close());
  const config={chainId:11155111,vault:'0x'+'11'.repeat(20),recipient:'0x'+'33'.repeat(20),price:'10000',service:0};
  const action={mandateId:'0x'+'22'.repeat(32),recipient:config.recipient,amount:config.price,service:0,
    nonce:'0x'+'44'.repeat(32),expiresAt:Math.floor(Date.now()/1000)+300,requestHash:sha256('hello'),spentBefore:'0'};
  const request={action,payload:'hello',agentSignature:'0x1234',proof:Buffer.from('unit double').toString('base64'),proofHash:sha256('unit double')};
  let runs=0,verifications=0,payments=0;
  const specialist=new Specialist({config,journal,
    chain:{state:async()=>({revoked:false,spent:'0',validUntil:action.expiresAt+10,policyHash:sha256('policy')}),verifyAgent:async()=>true,
      executionEvent:async()=>{payments++;if(rejectPayment)throw new Error('Payment unconfirmed');}},
    verifier:{prepare:async()=>{},verify:async(proof,expected)=>{verifications++;assert.equal(proof,request.proof);assert.equal(expected.actionHash,actionDigest(config.chainId,config.vault,action));assert.equal(expected.policyHash,sha256('policy'));if(rejectProof)throw new Error('Proof rejected');return {proofHash:request.proofHash};}},
    model:{ready:async()=>{},run:async()=>{runs++;if(failModelOnce&&runs===1)throw new Error('Model unavailable');return 'こんにちは';}},
  });
  return {specialist,request,journal,counts:()=>({runs,verifications,payments})};
}
test('shop independently verifies proof before work, then withholds result until payment',async t=>{
  const {specialist,request,journal,counts}=fixture(t);
  const ready=await specialist.prepare(request);
  assert.deepEqual(Object.keys(ready).sort(),['actionHash','status']);
  assert.equal(counts().verifications,1);assert.equal(counts().runs,1);
  assert.equal(journal.get(`work:${ready.actionHash}`).value.request.proof,undefined);
  assert.equal(orderSummaries(specialist)[0].status,'ready');
  assert.equal(JSON.stringify(orderSummaries(specialist)).includes('hello'),false);
  await specialist.prepare(request);assert.equal(counts().runs,1);
  const receipt=await specialist.release({actionHash:ready.actionHash,proofHash:request.proofHash,transactionHash:'0x'+'66'.repeat(32)});
  assert.equal(receipt.result,'こんにちは');assert.equal(counts().payments,1);
  assert.equal(orderSummaries(specialist)[0].status,'complete');
});
test('missing, rejected and mismatched proofs never prepare goods',async t=>{
  const f=fixture(t,{rejectProof:true});
  const {proof,...missing}=f.request;
  await assert.rejects(f.specialist.prepare(missing),{code:'proof_required'});
  await assert.rejects(f.specialist.prepare(f.request),/Proof rejected/);
  assert.equal(f.counts().runs,0);assert.equal(f.journal.recentWork().length,0);
  const g=fixture(t);
  await assert.rejects(g.specialist.prepare({...g.request,proofHash:sha256('different')}),{code:'proof_mismatch'});
  assert.equal(g.counts().runs,0);
});
test('unconfirmed payment cannot unlock a proof-verified order',async t=>{
  const f=fixture(t,{rejectPayment:true});const ready=await f.specialist.prepare(f.request);
  await assert.rejects(f.specialist.release({actionHash:ready.actionHash,proofHash:f.request.proofHash,transactionHash:'0x'+'66'.repeat(32)}),/unconfirmed/);
  assert.equal(orderSummaries(f.specialist)[0].status,'ready');
});
test('failed model work remains verified, and retry really prepares it',async t=>{
  const f=fixture(t,{failModelOnce:true});
  await assert.rejects(f.specialist.prepare(f.request),/Model unavailable/);
  assert.equal(orderSummaries(f.specialist)[0].status,'verified');
  await assert.rejects(f.specialist.release({actionHash:orderSummaries(f.specialist)[0].id,
    proofHash:f.request.proofHash,transactionHash:'0x'+'66'.repeat(32)}),{code:'work_not_ready'});
  assert.equal(f.counts().payments,0);
  await assert.rejects(f.specialist.prepare({...f.request,proofHash:sha256('changed')}),{code:'work_conflict'});
  await f.specialist.prepare(f.request);
  assert.equal(f.counts().runs,2);assert.equal(orderSummaries(f.specialist)[0].status,'ready');
});
test('operator HTTP view protects orders, rejects writes and foreign hosts, serves no embedded credential',async t=>{
  const token='private-operator-token-'.repeat(3);
  const server=merchantServer({token,catalog:{product:'Translation'},readiness:async()=>({ready:false}),orders:()=>[{id:'real-order'}]});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const base=`http://127.0.0.1:${server.address().port}`;
  const page=await fetch(base);assert.equal(page.status,200);assert.match(page.headers.get('content-security-policy'),/frame-ancestors 'none'/);
  assert.equal((await page.text()).includes(token),false);
  assert.equal((await fetch(base+'/api/orders')).status,401);
  const orders=await fetch(base+'/api/orders',{headers:{authorization:`Bearer ${token}`}});assert.deepEqual(await orders.json(),{orders:[{id:'real-order'}]});
  assert.equal((await fetch(base+'/api/orders',{method:'POST',headers:{authorization:`Bearer ${token}`}})).status,405);
  assert.equal((await fetch(base+'/api/orders',{headers:{authorization:`Bearer ${token}`,origin:'https://other.example'}})).status,403);
  assert.equal(await new Promise((resolve,reject)=>{const req=http.get(base+'/api/shop',{headers:{host:'other.example'}},res=>{res.resume();resolve(res.statusCode);});req.on('error',reject);}),403);
  assert.equal((await fetch(base+'/api/shop?token=oops')).status,400);
  assert.equal((await fetch(base+'/api/shop')).status,200);
});
