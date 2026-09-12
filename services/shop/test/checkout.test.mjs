import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {keccak256,encodeEventTopics,encodeAbiParameters,parseAbi} from 'viem';
import {encodePaymentSignatureHeader,decodePaymentRequiredHeader} from '@x402/core/http';
import {createShop} from '../src/worker.mjs';
import {requirements,USDC,NETWORK} from '../src/protocol.mjs';

// Failure-injection tests: real SQLite schema and worker routes, synthetic RPC
// and facilitator responses. These do not prove ZK, valid payment signatures,
// public facilitator support, D1 deployment, or public-chain settlement.
const events=parseAbi(['event Transfer(address indexed from,address indexed to,uint256 value)', 'event AuthorizationUsed(address indexed authorizer,bytes32 indexed nonce)']);
const transaction='0x'+'77'.repeat(32), blockHash='0x'+'88'.repeat(32);
function harness(t) {
  const db=new DatabaseSync(':memory:');t.after(()=>db.close());
  db.exec(readFileSync(new URL('../migrations/0001_orders.sql',import.meta.url),'utf8'));
  const state={age:true,settles:0,receipt:null,logs:[],updateCount:0,failUpdate:0};
  const env={SHOP_CHAIN_ID:'84532',AGE_GATE_ADDRESS:'0x'+'11'.repeat(20),AGE_GATE_CODE_HASH:keccak256('0x6000'),PAYMENT_RECIPIENT:'0x'+'22'.repeat(20),ORDERS:{
    prepare(sql){return {bind(...values){return {
      async first(){return db.prepare(sql).get(...values)??null;},
      async run(){if(sql.startsWith('UPDATE') && ++state.updateCount===state.failUpdate)throw new Error('injected_write_failure');return {meta:{changes:Number(db.prepare(sql).run(...values).changes)}};}
    };}};}
  }};
  const rpc={async getCode(){return '0x6000';},async readContract(){return state.age;},async getBlockNumber(){return 102n;},
    async getBlock(){return {hash:blockHash};},async getTransactionReceipt(){if(!state.receipt)throw new Error('not_found');return state.receipt;},
    async getLogs(){return state.logs;}};
  const facilitator={async verify(){return {isValid:true,payer:'0x'+'33'.repeat(20)};},async settle(){state.settles++;if(state.timeout)throw new Error('timeout');return {success:true,payer:'0x'+'33'.repeat(20),network:NETWORK,transaction};}};
  const worker=createShop({client:()=>rpc,facilitatorClient:()=>facilitator});
  const key='ab'.repeat(32);
  const request=(path,method='GET',body,headers={})=>worker.fetch(new Request('https://shop.example/api'+path,{method,headers:{'X-Order-Key':key,...(body===undefined?{}:{'content-type':'application/json'}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})}),env);
  async function order(){const res=await request('/orders','POST',{productId:'mate-lager',quantity:1,payer:'0x'+'33'.repeat(20)});assert.equal(res.status,201);return (await res.json()).order;}
  async function approve(order){assert.equal((await request(`/orders/${order.id}/age`,'POST')).status,200);}
  function header(order){const now=Math.floor(Date.now()/1000);return encodePaymentSignatureHeader({x402Version:2,accepted:requirements(order),payload:{signature:'0x'+'44'.repeat(65),authorization:{from:order.payer,to:order.recipient,value:order.amount,validAfter:String(now-1),validBefore:String(now+200),nonce:order.paymentNonce}}});}
  const pay=order=>request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':header(order)});
  function settleReceipt(order,nonce=order.paymentNonce){state.receipt={status:'success',blockNumber:100n,blockHash,logs:[
    {address:USDC,topics:encodeEventTopics({abi:events,eventName:'Transfer',args:{from:order.payer,to:order.recipient}}),data:encodeAbiParameters([{type:'uint256'}],[BigInt(order.amount)])},
    {address:USDC,topics:encodeEventTopics({abi:events,eventName:'AuthorizationUsed',args:{authorizer:order.payer,nonce}}),data:'0x'}
  ]};state.logs=[{transactionHash:transaction}];}
  return {db,env,state,rpc,facilitator,worker,key,request,order,approve,header,pay,settleReceipt};
}

test('SQLite persists one order and one nonce under concurrent creation/restart',async t=>{
  const h=harness(t);const orders=await Promise.all([h.order(),h.order(),h.order()]);
  assert.equal(new Set(orders.map(o=>o.orderHash)).size,1);
  assert.equal(h.db.prepare('SELECT count(*) AS count FROM orders').get().count,1);
  const response=await h.request(`/orders/${orders[0].id}`);
  assert.equal((await response.json()).order.paymentNonce,orders[0].paymentNonce);
});
test('raw age claims cannot unlock a shop order or reach the facilitator',async t=>{
  const h=harness(t),order=await h.order();h.state.age=false;
  assert.equal((await h.request(`/orders/${order.id}/age`,'POST',{over20:true,proofVerified:true})).status,403);
  assert.equal((await h.pay(order)).status,403);assert.equal(h.state.settles,0);
});
test('the 402 challenge carries official x402 v2 requirements and this order nonce',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);
  const response=await h.request(`/orders/${order.id}/pay`,'POST');assert.equal(response.status,402);
  const challenge=decodePaymentRequiredHeader(response.headers.get('PAYMENT-REQUIRED'));
  assert.deepEqual(challenge.accepts,[requirements(order)]);
  assert.equal((await response.json()).paymentNonce,order.paymentNonce);assert.equal(h.state.settles,0);
});
test('concurrent payment requests reserve durably and settle at most once',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.settleReceipt(order);
  await Promise.all([h.pay(order),h.pay(order),h.pay(order)]);
  assert.equal(h.state.settles,1);
  const saved=(await (await h.request(`/orders/${order.id}`)).json()).order;
  assert.equal(saved.state,'complete');assert.equal(saved.paymentTransaction,transaction);
  assert.equal((await h.pay(order)).status,200);assert.equal(h.state.settles,1);
  const persisted=h.db.prepare('SELECT value FROM orders').get().value;
  assert.ok(!persisted.includes('44'.repeat(65)));assert.ok(!persisted.includes('authorization'));
});
test('timeout with lost transaction hash recovers the original nonce without settling again',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.state.timeout=true;
  assert.equal((await h.pay(order)).status,202);h.settleReceipt(order);
  h.rpc.getBlockNumber=async()=>105n;
  const saved=(await (await h.request(`/orders/${order.id}`)).json()).order;
  assert.equal(saved.state,'complete');assert.equal(saved.paymentNonce,order.paymentNonce);assert.equal(h.state.settles,1);
});
test('a write failure after settlement is recoverable from the reserved order',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.settleReceipt(order);
  h.state.failUpdate=h.state.updateCount+2;
  assert.equal((await h.pay(order)).status,503);h.rpc.getBlockNumber=async()=>105n;
  const saved=(await (await h.request(`/orders/${order.id}`)).json()).order;
  assert.equal(saved.state,'complete');assert.equal(h.state.settles,1);
});
test('a transfer with a different authorization nonce never completes the order',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.settleReceipt(order,'0x'+'99'.repeat(32));
  const response=await h.pay(order);assert.equal(response.status,202);
  assert.equal((await response.json()).order.state,'payment_pending');
});
test('an unconfirmed or reorged receipt never completes checkout',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.settleReceipt(order);
  h.state.receipt.blockNumber=102n;
  assert.equal((await h.pay(order)).status,202);
  h.state.receipt.blockNumber=100n;h.state.receipt.blockHash='0x'+'99'.repeat(32);
  assert.equal((await (await h.request(`/orders/${order.id}`)).json()).order.state,'payment_pending');
});
test('unknown settlement remains pending on repeat POST without a new signature or charge',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.state.timeout=true;
  await h.pay(order);assert.equal((await h.pay(order)).status,202);assert.equal(h.state.settles,1);
});
test('a malformed payment header is a client error and never reaches settlement',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);
  const response=await h.request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':'not-json'});
  assert.equal(response.status,400);assert.equal(h.state.settles,0);
});
test('invalid JSON and non-object orders are client errors without database writes',async t=>{
  const h=harness(t);
  for(const body of ['null','[]','true','"order"','3','{']) {
    const response=await h.worker.fetch(new Request('https://shop.example/api/orders',{
      method:'POST',headers:{'X-Order-Key':h.key,'content-type':'application/json'},body
    }),h.env);
    assert.equal(response.status,400,body);
    assert.equal((await response.json()).error,'invalid_request');
  }
  assert.equal(h.db.prepare('SELECT count(*) AS count FROM orders').get().count,0);
});
test('revoked on-chain age approval or a changed bytecode pin blocks payment',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.state.age=false;
  assert.equal((await h.pay(order)).status,403);h.state.age=true;h.env.AGE_GATE_CODE_HASH='0x'+'aa'.repeat(32);
  assert.equal((await h.pay(order)).status,403);assert.equal(h.state.settles,0);
});
