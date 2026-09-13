import test from 'node:test';
import assert from 'node:assert/strict';
import {encodePaymentSignatureHeader} from '@x402/core/http';
import {configuration,newOrder,orderHash,requirements,paymentPayload,USDC} from '../src/protocol.mjs';
import worker from '../src/worker.mjs';

// Public, synthetic addresses and disposable order keys; no private keys.
const env={SHOP_CHAIN_ID:'5042002',AGE_GATE_ADDRESS:'0x'+'11'.repeat(20),AGE_GATE_CODE_HASH:'0x'+'aa'.repeat(32),PAYMENT_RECIPIENT:'0x'+'22'.repeat(20),ORDERS:{},API_LIMIT:{async limit(){return {success:true};}}};
const key='ab'.repeat(32), now=1_800_000_000;
const make=()=>newOrder({productId:'mate-lager',quantity:1,payer:'0x'+'33'.repeat(20)},key,env,now);
function payload(order){return {x402Version:2,accepted:requirements(order),payload:{signature:'0x'+'44'.repeat(65),authorization:{from:order.payer,to:order.recipient,value:order.amount,validAfter:String(now-1),validBefore:String(now+200),nonce:order.paymentNonce}}};}

test('unconfigured catalog reports unavailable and all order operations remain closed',async()=>{
  const response=await worker.fetch(new Request('https://shop.example/api/catalog'),{API_LIMIT:env.API_LIMIT});
  const value=await response.json();assert.equal(value.checkoutAvailable,false);assert.equal(value.shipsPhysicalGoods,false);
  for(const endpoint of ['/api/orders','/api/orders/0x'+key+'/age','/api/orders/0x'+key+'/pay']){
    const result=await worker.fetch(new Request('https://shop.example'+endpoint,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({over20:true,proofVerified:true})}),{});
    assert.equal(result.status,503);
  }
});
test('configuration cannot enable a real-money chain or an unpinned age gate',()=>{
  assert.equal(Boolean(configuration(env)),true);
  for(const changed of [{SHOP_CHAIN_ID:'84532'},{SHOP_CHAIN_ID:'8453'},{AGE_GATE_ADDRESS:''},{AGE_GATE_CODE_HASH:''},{PAYMENT_RECIPIENT:'0x'+'00'.repeat(20)},{ORDERS:null}])assert.equal(Boolean(configuration({...env,...changed})),false);
});
test('order commitments bind all payment and age conditions',()=>{
  const order=make();assert.equal(order.state,'awaiting_age');assert.equal(order.minimumAge,20);assert.equal(order.token,USDC);
  for(const changed of [{payer:env.PAYMENT_RECIPIENT},{recipient:order.payer},{amount:'200000'},{chainId:8453},{productId:'different'},{quantity:2},{expiresAt:order.expiresAt+1},{minimumAge:18},{ageGate:order.payer},{paymentNonce:'0x'+key}])assert.notEqual(orderHash({...order,...changed}),order.orderHash);
});
test('the same request key yields the same payment nonce across retries',()=>{
  assert.equal(make().paymentNonce,make().paymentNonce);
  assert.notEqual(newOrder({productId:'mate-lager',quantity:1,payer:make().payer},'cd'.repeat(32),env,now).paymentNonce,make().paymentNonce);
});
test('product and quantity cannot be invented by the agent',()=>{
  for(const input of [{productId:'unknown',quantity:1},{productId:'mate-lager',quantity:2},{productId:'mate-lager',quantity:-1}])assert.throws(()=>newOrder({...input,payer:make().payer},key,env,now),/invalid_order/);
});
test('x402 v2 payload is decoded using the actual SDK',()=>{
  const order=make();const raw=payload(order);
  const value=paymentPayload(encodePaymentSignatureHeader(raw),order,now);
  assert.equal(value.payload.authorization.nonce,order.paymentNonce);
  // This is payload validation, NOT signature verification or a payment.
});
test('a copied payment cannot authorize a different payer, recipient, amount or order',()=>{
  const order=make();
  for(const changed of [{from:env.PAYMENT_RECIPIENT},{to:order.payer},{value:'1'},{nonce:'0x'+'99'.repeat(32)},{validBefore:String(order.expiresAt+1)},{validBefore:String(now)},{validAfter:String(now+1)}]){
    const raw=payload(order);Object.assign(raw.payload.authorization,changed);
    assert.throws(()=>paymentPayload(encodePaymentSignatureHeader(raw),order,now),/payment_mismatch/);
  }
});
test('wrong token, network or mainnet payment requirements are rejected',()=>{
  const order=make();
  for(const changed of [{network:'eip155:84532'},{network:'eip155:8453'},{asset:env.PAYMENT_RECIPIENT},{amount:'900000'},{payTo:order.payer}]){
    const raw=payload(order);Object.assign(raw.accepted,changed);
    assert.throws(()=>paymentPayload(encodePaymentSignatureHeader(raw),order,now),/payment_mismatch/);
  }
});
test('foreign browser origins and missing capability cannot create an order',async()=>{
  const request=new Request('https://shop.example/api/orders',{method:'POST',headers:{origin:'https://attacker.example','X-Order-Key':key}});
  assert.equal((await worker.fetch(request,env)).status,403);
  assert.equal((await worker.fetch(new Request('https://shop.example/api/orders',{method:'POST'}),env)).status,401);
});
