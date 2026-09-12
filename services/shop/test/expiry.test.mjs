import test from 'node:test';
import assert from 'node:assert/strict';
import {expiredUnusedPayment} from '../src/expiry.mjs';
import {USDC} from '../src/protocol.mjs';

// Explicit RPC failure-injection tests, not public-chain evidence.
function setup() {
  const order={createdAt:1000,expiresAt:1900,paymentValidBefore:1180,payer:'0x'+'11'.repeat(20),paymentNonce:'0x'+'22'.repeat(32)};
  const hash='0x'+'33'.repeat(32),calls=[];
  const rpc={async getChainId(){return 5042002;},async getBlock({blockNumber}={}){return {number:blockNumber??100n,hash,timestamp:1200n};},
    async readContract(call){calls.push(call);return false;}};
  return {order,hash,calls,clients:[{...rpc},{...rpc}]};
}
test('unused authorization closes only at the common finalized block past its exact deadline',async()=>{
  const h=setup();h.clients[1].getBlock=async({blockNumber}={})=>({number:blockNumber??99n,hash:h.hash,timestamp:1200n});
  assert.deepEqual(await expiredUnusedPayment(h.order,h.clients),{blockNumber:'99',blockHash:h.hash,timestamp:'1200'});
  assert.equal(h.calls.length,2);
  for(const call of h.calls){assert.equal(call.address,USDC);assert.equal(call.blockNumber,99n);assert.equal(call.functionName,'authorizationState');assert.deepEqual(call.args,[h.order.payer,h.order.paymentNonce]);}
});
test('absence of receipt is insufficient when either provider is stale, disagrees, reports used or fails',async()=>{
  for(const change of [
    {getChainId:async()=>8453},
    {getBlock:async()=>({number:100n,hash:'0x'+'44'.repeat(32),timestamp:1200n})},
    {getBlock:async()=>({number:100n,hash:'0x'+'33'.repeat(32),timestamp:1179n})},
    {getBlock:async()=>{throw new Error('not_finalized');}},
    {readContract:async()=>true},
    {readContract:async()=>undefined},
    {readContract:async()=>{throw new Error('timeout');}}
  ]){const h=setup();Object.assign(h.clients[1],change);assert.equal(await expiredUnusedPayment(h.order,h.clients),null);}
  for(const end of [undefined,999,1901,NaN]){const h=setup();h.order.paymentValidBefore=end;assert.equal(await expiredUnusedPayment(h.order,h.clients),null);}
});

test('expiry schema upgrade preserves existing order revisions and capabilities',async()=>{
  const {DatabaseSync}=await import('node:sqlite');
  const {readFileSync}=await import('node:fs');
  const db=new DatabaseSync(':memory:');
  try {
    db.exec(readFileSync(new URL('../migrations/0001_orders.sql',import.meta.url),'utf8'));
    db.prepare('INSERT INTO orders VALUES(?,?,?,?,?)').run('original',7,'payment_pending',JSON.stringify({paymentNonce:'original-nonce'}),1000);
    db.exec(readFileSync(new URL('../migrations/0002_payment_expiry.sql',import.meta.url),'utf8'));
    const row=db.prepare('SELECT * FROM orders').get();
    assert.equal(row.id,'original');assert.equal(row.revision,7);assert.equal(JSON.parse(row.value).paymentNonce,'original-nonce');
    db.prepare('UPDATE orders SET state=? WHERE id=?').run('payment_expired','original');
    assert.equal(db.prepare('SELECT state FROM orders').get().state,'payment_expired');
  } finally {db.close();}
});
