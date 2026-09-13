import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {keccak256,encodeEventTopics,encodeAbiParameters,parseAbi} from 'viem';
import {encodePaymentSignatureHeader,decodePaymentRequiredHeader,decodePaymentResponseHeader} from '@x402/core/http';
import {createShop} from '../src/worker.mjs';
import {requirements,USDC,NETWORK} from '../src/protocol.mjs';
import {ageArguments} from '../src/age.mjs';

// Failure-injection tests: real SQLite schema and worker routes, synthetic RPC
// and facilitator responses. These do not prove ZK, valid payment signatures,
// public facilitator support, D1 deployment, or public-chain settlement.
const events=parseAbi(['event Transfer(address indexed from,address indexed to,uint256 value)', 'event AuthorizationUsed(address indexed authorizer,bytes32 indexed nonce)']);
const transaction='0x'+'77'.repeat(32), blockHash='0x'+'88'.repeat(32);
function harness(t) {
  const db=new DatabaseSync(':memory:');t.after(()=>db.close());
  db.exec(readFileSync(new URL('../migrations/0001_orders.sql',import.meta.url),'utf8'));
  db.exec(readFileSync(new URL('../migrations/0002_payment_expiry.sql',import.meta.url),'utf8'));
  const state={age:true,settles:0,receipt:null,logs:[],updateCount:0,failUpdate:0,now:Math.floor(Date.now()/1000)};
  const env={SHOP_CHAIN_ID:'5042002',AGE_GATE_ADDRESS:'0x'+'11'.repeat(20),AGE_GATE_CODE_HASH:keccak256('0x6000'),PAYMENT_RECIPIENT:'0x'+'22'.repeat(20),ORDERS:{
    prepare(sql){return {async first(){return db.prepare(sql).get()??null;},bind(...values){return {
      async first(){return db.prepare(sql).get(...values)??null;},
      async run(){if(sql.startsWith('UPDATE') && ++state.updateCount===state.failUpdate)throw new Error('injected_write_failure');return {meta:{changes:Number(db.prepare(sql).run(...values).changes)}};}
    };}};}
  },API_LIMIT:{async limit(){return {success:true};}},ORDER_CREATION_LIMIT:{async limit(){return {success:true};}}};
  const rpc={async getChainId(){return 5042002;},async getCode(){return '0x6000';},async readContract({args}){return args[2]===0n?false:state.age;},async getBlockNumber(){return 102n;},
    async getBlock({blockNumber=102n}={}){return {number:blockNumber,hash:blockHash,timestamp:BigInt(Math.floor(Date.now()/1000))};},async getTransactionReceipt(){if(!state.receipt)throw new Error('not_found');return state.receipt;},
    async getLogs(){return state.logs;}};
  const facilitator={async verify(){return {isValid:true,payer:'0x'+'33'.repeat(20)};},async settle(){state.settles++;if(state.timeout)throw new Error('timeout');return {success:true,payer:'0x'+'33'.repeat(20),network:NETWORK,transaction};}};
  const supported=async()=>({kinds:[{x402Version:2,network:NETWORK,scheme:'exact'}]});
  const secondary={...rpc};
  const worker=createShop({client:()=>rpc,secondaryClient:()=>secondary,facilitatorClient:()=>facilitator,supported,clock:()=>state.now});
  const key='ab'.repeat(32);
  const request=(path,method='GET',body,headers={})=>worker.fetch(new Request('https://shop.example/api'+path,{method,headers:{'X-Order-Key':key,...(body===undefined?{}:{'content-type':'application/json'}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})}),env);
  async function order(){const res=await request('/orders','POST',{productId:'mate-lager',quantity:1,payer:'0x'+'33'.repeat(20)});assert.equal(res.status,201);return (await res.json()).order;}
  async function approve(order){assert.equal((await request(`/orders/${order.id}/age`,'POST',{proof:'0x'+'55'.repeat(384),rootKeyHash:'0x'+'66'.repeat(32)})).status,200);}
  function header(order){const now=Math.floor(Date.now()/1000);return encodePaymentSignatureHeader({x402Version:2,accepted:requirements(order),payload:{signature:'0x'+'44'.repeat(65),authorization:{from:order.payer,to:order.recipient,value:order.amount,validAfter:String(now-1),validBefore:String(now+200),nonce:order.paymentNonce}}});}
  const pay=order=>request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':header(order)});
  function settleReceipt(order,nonce=order.paymentNonce){state.receipt={status:'success',blockNumber:100n,blockHash,logs:[
    {address:USDC,topics:encodeEventTopics({abi:events,eventName:'Transfer',args:{from:order.payer,to:order.recipient}}),data:encodeAbiParameters([{type:'uint256'}],[BigInt(order.amount)])},
    {address:USDC,topics:encodeEventTopics({abi:events,eventName:'AuthorizationUsed',args:{authorizer:order.payer,nonce}}),data:'0x'}
  ]};state.logs=[{transactionHash:transaction}];}
  return {db,env,state,rpc,secondary,facilitator,worker,key,request,order,approve,header,pay,settleReceipt,supported};
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
  assert.equal((await h.request(`/orders/${order.id}/age`,'POST',{over20:true,proofVerified:true})).status,400);
  assert.equal((await h.pay(order)).status,403);assert.equal(h.state.settles,0);
});
test('age submission sends only the proof and server-bound inputs to the EVM contract',async t=>{
  const h=harness(t),order=await h.order();let call;
  h.rpc.readContract=async value=>{call=value;return true;};
  await h.approve(order);
  const saved=(await (await h.request(`/orders/${order.id}`)).json()).order;
  assert.equal(saved.state,'age_verified');assert.equal(call.functionName,'verifyOrderAge');
  assert.deepEqual(call.args,ageArguments(saved));assert.equal(call.gas,1000000n);
  assert.equal(call.args[0],order.orderHash);assert.equal(call.args[1],order.paymentNonce);
  assert.equal(call.args[4][6],BigInt(order.createdAt));assert.equal(call.args[4][7],BigInt(order.expiresAt));
  for(const field of ['birthDate','certificate','signature','pin'])assert.equal(saved[field],undefined);
});
test('unexpected private fields, malformed proofs and caller-supplied inputs are rejected before RPC',async t=>{
  const h=harness(t),order=await h.order();let calls=0;h.rpc.readContract=async()=>{calls++;return true;};
  const valid={proof:'0x'+'55'.repeat(384),rootKeyHash:'0x'+'66'.repeat(32)};
  for(const input of [{...valid,birthDate:'synthetic'},{...valid,inputs:[]},{...valid,proof:'0x'},{...valid,rootKeyHash:'bad'}]){
    assert.equal((await h.request(`/orders/${order.id}/age`,'POST',input)).status,400);
  }
  assert.equal(calls,0);assert.equal(h.state.settles,0);
  assert.equal((await (await h.request(`/orders/${order.id}`)).json()).order.state,'awaiting_age');
});
test('a proof rejected by the contract or a wrong chain cannot grant age status',async t=>{
  const h=harness(t),order=await h.order();
  const input={proof:'0x'+'55'.repeat(384),rootKeyHash:'0x'+'66'.repeat(32)};
  h.state.age=false;
  assert.equal((await h.request(`/orders/${order.id}/age`,'POST',input)).status,403);
  h.state.age=true;h.rpc.getChainId=async()=>8453;
  assert.equal((await h.request(`/orders/${order.id}/age`,'POST',input)).status,403);
  assert.equal((await (await h.request(`/orders/${order.id}`)).json()).order.state,'awaiting_age');
});
test('the 402 challenge carries official x402 v2 requirements and this order nonce',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);
  const response=await h.request(`/orders/${order.id}/pay`,'POST');assert.equal(response.status,402);
  const challenge=decodePaymentRequiredHeader(response.headers.get('PAYMENT-REQUIRED'));
  assert.deepEqual(challenge.accepts,[requirements(order)]);
  assert.equal((await response.json()).paymentNonce,order.paymentNonce);assert.equal(h.state.settles,0);
});
test('one fabricated RPC approval cannot unlock age or reach settlement',async t=>{
  const h=harness(t),order=await h.order();
  h.rpc.readContract=async()=>true;h.secondary.readContract=async()=>false;
  assert.equal((await h.request(`/orders/${order.id}/age`,'POST',{proof:'0x'+'55'.repeat(384),rootKeyHash:'0x'+'66'.repeat(32)})).status,403);
  assert.equal((await h.pay(order)).status,403);assert.equal(h.state.settles,0);
});
test('independent provider timeout, fork, wrong code or stale snapshot fails closed',async t=>{
  const h=harness(t),order=await h.order();const original={...h.secondary};
  const request=()=>h.request(`/orders/${order.id}/age`,'POST',{proof:'0x'+'55'.repeat(384),rootKeyHash:'0x'+'66'.repeat(32)});
  for(const failure of [
    {readContract:async()=>{throw new Error('timeout');}},
    {getBlock:async()=>({number:102n,hash:'0x'+'99'.repeat(32),timestamp:BigInt(Math.floor(Date.now()/1000))})},
    {getBlock:async()=>({number:102n,hash:blockHash,timestamp:1n})},
    {getCode:async()=> '0x6001'},
    {getChainId:async()=>8453},
  ]) {
    Object.assign(h.secondary,original,failure);
    assert.equal((await request()).status,403);
    assert.equal(h.state.settles,0);
  }
});
test('age is checked again by both providers immediately before payment',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);
  h.secondary.readContract=async()=>false;
  assert.equal((await h.pay(order)).status,403);assert.equal(h.state.settles,0);
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
test('a pre-broadcast timeout can retry only the original authorization after its lease',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.state.timeout=true;
  const original=h.header(order),retry=()=>h.request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':original});
  assert.equal((await retry()).status,202);assert.equal(h.state.settles,1);
  await retry();assert.equal(h.state.settles,1);
  h.state.now+=61;h.state.timeout=false;h.settleReceipt(order);
  const results=await Promise.all([retry(),retry(),retry()]);
  assert.ok(results.some(response=>response.status===200));assert.equal(h.state.settles,2);
  const saved=(await (await h.request(`/orders/${order.id}`)).json()).order;
  assert.equal(saved.state,'complete');assert.equal(saved.paymentNonce,order.paymentNonce);
});
test('retry cannot replace the signature, extend authorization, or act without age approval',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.state.timeout=true;
  const original=h.header(order);
  await h.request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':original});
  h.state.now+=61;
  const replacement=encodePaymentSignatureHeader({x402Version:2,accepted:requirements(order),payload:{signature:'0x'+'55'.repeat(65),authorization:{from:order.payer,to:order.recipient,value:order.amount,validAfter:String(h.state.now-1),validBefore:String(h.state.now+200),nonce:order.paymentNonce}}});
  assert.equal((await h.request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':replacement})).status,400);
  h.state.age=false;
  assert.equal((await h.request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':original})).status,403);
  assert.equal(h.state.settles,1);
});
test('recovery stores the transaction hash even when receipt polling fails',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);
  assert.equal((await h.pay(order)).status,202);
  const saved=JSON.parse(h.db.prepare('SELECT value FROM orders WHERE id=?').get(order.id).value);
  assert.equal(saved.state,'payment_pending');assert.equal(saved.paymentTransaction,transaction);
  h.settleReceipt(order);h.state.now+=61;
  assert.equal((await (await h.request(`/orders/${order.id}`)).json()).order.state,'complete');
  assert.equal(h.state.settles,1);
});
test('the x402 success header is withheld until both providers confirm the exact payment',async t=>{
  for(const confirmed of [false,true]) {
    const h=harness(t),order=await h.order();await h.approve(order);
    if(confirmed)h.settleReceipt(order);
    const response=await h.pay(order),header=response.headers.get('PAYMENT-RESPONSE');
    assert.equal(response.status,confirmed?200:202);
    if(!confirmed)assert.equal(header,null);
    else assert.deepEqual(decodePaymentResponseHeader(header),{success:true,payer:order.payer,network:NETWORK,transaction});
  }
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
test('an invalid proof or a changed bytecode pin blocks payment',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.state.age=false;
  assert.equal((await h.pay(order)).status,403);h.state.age=true;h.env.AGE_GATE_CODE_HASH='0x'+'aa'.repeat(32);
  assert.equal((await h.pay(order)).status,403);assert.equal(h.state.settles,0);
});
test('catalog stays unavailable when RPC, code, clock, storage or facilitator are not ready',async t=>{
  const h=harness(t);
  assert.equal((await (await h.request('/catalog')).json()).checkoutAvailable,true);
  const base={...h.rpc};
  for(const override of [
    {getChainId:async()=>1}, {getCode:async()=>'0x'},
    {getCode:async()=>'0x6001'}, {readContract:async()=>true},
    {getBlock:async()=>({timestamp:1n})}, {getBlock:async()=>{throw new Error('offline');}}
  ]) {
    Object.assign(h.rpc,base,override);
    assert.equal((await (await h.request('/catalog')).json()).checkoutAvailable,false);
  }
  Object.assign(h.rpc,base);
  for(const kinds of [[],[{x402Version:1,network:NETWORK,scheme:'exact'}],[{x402Version:2,network:'eip155:1',scheme:'exact'}]]) {
    const worker=createShop({client:()=>h.rpc,secondaryClient:()=>h.secondary,supported:async()=>({kinds})});
    const response=await worker.fetch(new Request('https://shop.example/api/catalog'),h.env);
    assert.equal((await response.json()).checkoutAvailable,false);
  }
  h.db.exec('DROP TABLE orders');
  assert.equal((await (await h.request('/catalog')).json()).checkoutAvailable,false);
});
test('an outage prevents new orders but leaves existing order recovery available',async t=>{
  const h=harness(t),order=await h.order();h.rpc.getChainId=async()=>{throw new Error('offline');};
  assert.equal((await h.order()).orderHash,order.orderHash);
  assert.equal((await h.request(`/orders/${order.id}`)).status,200);
  const response=await h.request('/orders','POST',{productId:'mate-lager',quantity:1,payer:order.payer},{'X-Order-Key':'cd'.repeat(32)});
  assert.equal(response.status,503);
  assert.equal(h.db.prepare('SELECT count(*) AS count FROM orders').get().count,1);
});
test('rate limits stop external work and new order creation',async t=>{
  const h=harness(t);let rpcCalls=0;h.rpc.getChainId=async()=>{rpcCalls++;return 5042002;};
  h.env.API_LIMIT.limit=async()=>({success:false});
  const response=await h.request('/catalog');assert.equal(response.status,429);assert.equal(response.headers.get('Retry-After'),'60');assert.equal(rpcCalls,0);
  h.env.API_LIMIT.limit=async()=>({success:true});h.env.ORDER_CREATION_LIMIT.limit=async()=>({success:false});
  assert.equal((await h.request('/orders','POST',{productId:'mate-lager',quantity:1,payer:'0x'+'33'.repeat(20)})).status,429);
  assert.equal(h.db.prepare('SELECT count(*) AS count FROM orders').get().count,0);
});
test('the test-shop order capacity survives concurrent requests',async t=>{
  const h=harness(t);const insert=h.db.prepare('INSERT INTO orders(id,state,value,created_at) VALUES(?,?,?,?)');
  for(let i=0;i<999;i++)insert.run(String(i),'awaiting_age','{}',1);
  const create=key=>h.request('/orders','POST',{productId:'mate-lager',quantity:1,payer:'0x'+'33'.repeat(20)},{'X-Order-Key':key.repeat(32)});
  const results=await Promise.all([create('ac'),create('ad'),create('ae')]);
  assert.equal(results.filter(r=>r.status===201).length,1);
  assert.equal(h.db.prepare('SELECT count(*) AS count FROM orders').get().count,1000);
  assert.equal((await (await h.request('/catalog')).json()).checkoutAvailable,false);
});


test('payment success requires both providers to agree on receipt evidence',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.settleReceipt(order);
  const receipt=h.secondary.getTransactionReceipt;
  h.secondary.getTransactionReceipt=async()=>({...h.state.receipt,logs:[]});
  assert.equal((await (await h.pay(order)).json()).order.state,'payment_pending');
  h.secondary.getTransactionReceipt=receipt;
  assert.equal((await (await h.request(`/orders/${order.id}`)).json()).order.state,'complete');
  assert.equal(h.state.settles,1);
});

test('expired unused payment reaches a terminal state without a new settlement',async t=>{
  const h=harness(t),order=await h.order();await h.approve(order);h.state.timeout=true;
  const response=await h.pay(order),pending=(await response.json()).order;
  assert.equal(pending.state,'payment_pending');assert.ok(pending.paymentValidBefore>h.state.now);
  h.state.now=pending.paymentValidBefore+1;
  for(const rpc of [h.rpc,h.secondary]) {
    rpc.getBlockNumber=async()=>104n;
    rpc.getBlock=async({blockNumber}={})=>({number:blockNumber??103n,hash:blockHash,timestamp:BigInt(h.state.now)});
    rpc.readContract=async()=>false;
  }
  const closed=(await (await h.request(`/orders/${order.id}`)).json()).order;
  assert.equal(closed.state,'payment_expired');assert.equal(closed.paymentNonce,order.paymentNonce);
  assert.equal(h.state.settles,1);
  assert.equal((await h.pay(order)).status,409);assert.equal(h.state.settles,1);
});
