import {createPublicClient, http, keccak256, parseAbi, decodeEventLog} from 'viem';
import {baseSepolia} from 'viem/chains';
import {HTTPFacilitatorClient} from '@x402/core/server';
import {encodePaymentRequiredHeader, encodePaymentResponseHeader} from '@x402/core/http';
import {CHAIN_ID, NETWORK, USDC, PRODUCTS, configuration, hex32, hashKey, newOrder, nowSeconds, requirements, paymentPayload} from './protocol.mjs';
import {checkoutReady, supportedNetworks, MAX_ORDERS} from './readiness.mjs';
import {ageArguments, ageSubmission} from './age.mjs';
import {checkedAgeCall} from './age-rpc.mjs';
import {expiredUnusedPayment} from './expiry.mjs';

const TRANSFER_ABI = parseAbi(['event Transfer(address indexed from, address indexed to, uint256 value)', 'event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce)']);
const security = {'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
const json = (value,status=200,headers={}) => Response.json(value,{status,headers:{...security,...headers}});
const productionClient = () => createPublicClient({chain:baseSepolia,transport:http('https://sepolia.base.org',{timeout:4000,retryCount:0})});
const independentClient = () => createPublicClient({chain:baseSepolia,transport:http('https://base-sepolia-rpc.publicnode.com',{timeout:4000,retryCount:0})});

async function body(request) {
  if (!request.headers.get('content-type')?.startsWith('application/json')) throw new Error('invalid_request');
  const reader=request.body?.getReader(); if (!reader) throw new Error('invalid_request');
  let text='',size=0; const decoder=new TextDecoder();
  try {
    while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>2048)throw new Error('request_too_large');text+=decoder.decode(value,{stream:true});}
    let parsed;
    try { parsed=JSON.parse(text+decoder.decode()); } catch { throw new Error('invalid_request'); }
    if(!parsed || typeof parsed!=='object' || Array.isArray(parsed))throw new Error('invalid_request');
    return parsed;
  } finally { await reader.cancel(); }
}

// Dependencies can be replaced only by module-level tests, never by a request
// or a Worker binding. Age checks use fixed, separately operated testnet RPCs.
export function createShop({client=productionClient, secondaryClient=independentClient, facilitatorClient=()=>new HTTPFacilitatorClient({url:'https://x402.org/facilitator',timeoutMs:20000}),supported=supportedNetworks,clock=nowSeconds}={}) {
async function load(env,id) {
  const row=await env.ORDERS.prepare('SELECT revision,value FROM orders WHERE id=?').bind(id).first();
  return row ? {revision:row.revision,order:JSON.parse(row.value)} : null;
}
async function save(env,record,next) {
  const result=await env.ORDERS.prepare('UPDATE orders SET revision=revision+1,state=?,value=? WHERE id=? AND revision=?')
    .bind(next.state,JSON.stringify(next),next.id,record.revision).run();
  return result.meta.changes===1;
}

async function verifiedAge(env,order) {
  const args=ageArguments(order);
  if(!args || order.minimumAge!==20)return false;
  if(order.ageGate.toLowerCase()!==env.AGE_GATE_ADDRESS.toLowerCase())return false;
  return checkedAgeCall(env,[client(),secondaryClient()],args,true);
}

async function confirmedPaymentAt(rpc,order,transaction) {
  if(await rpc.getChainId()!==CHAIN_ID)return false;
  const receipt=await rpc.getTransactionReceipt({hash:transaction});
  if(receipt.status!=='success' || await rpc.getBlockNumber()<receipt.blockNumber+1n)return false;
  const block=await rpc.getBlock({blockNumber:receipt.blockNumber});
  if(block.hash!==receipt.blockHash)return false;
  const events=receipt.logs.flatMap(log=>{
    if(log.address.toLowerCase()!==USDC.toLowerCase())return [];
    try {return [decodeEventLog({abi:TRANSFER_ABI,data:log.data,topics:log.topics})];} catch {return [];}
  });
  const matches=events.some(event=>event.eventName==='Transfer' && event.args.from.toLowerCase()===order.payer && event.args.to.toLowerCase()===order.recipient && event.args.value===BigInt(order.amount))
    && events.some(event=>event.eventName==='AuthorizationUsed' && event.args.authorizer.toLowerCase()===order.payer && event.args.nonce.toLowerCase()===order.paymentNonce.toLowerCase());
  return matches ? receipt.blockHash : false;
}

async function confirmedPayment(order,transaction) {
  const results=await Promise.all([client(),secondaryClient()].map(rpc=>confirmedPaymentAt(rpc,order,transaction).catch(()=>false)));
  return results[0]!==false && results[0]===results[1];
}

async function reconcile(env,record) {
  const order=record.order;
  if(order.state!=='payment_pending')return order;
  const next={...order};
  if(!next.paymentTransaction && next.paymentStartBlock) {
    const rpc=client();const latest=await rpc.getBlockNumber();
    const from=BigInt(next.scanBlock??next.paymentStartBlock);
    if(latest<=from)return order;
    const to=latest-1n < from+1999n ? latest-1n : from+1999n;
    const logs=await rpc.getLogs({address:USDC,event:TRANSFER_ABI[1],args:{authorizer:order.payer,nonce:order.paymentNonce},fromBlock:from,toBlock:to});
    if(logs.length)next.paymentTransaction=logs[0].transactionHash;
    else next.scanBlock=(to+1n).toString();
  }
  if(next.paymentTransaction && await confirmedPayment(order,next.paymentTransaction))next.state='complete';
  if(next.state==='payment_pending' && clock()>=next.paymentValidBefore) {
    const evidence=await expiredUnusedPayment(next,[client(),secondaryClient()]);
    if(evidence){next.state='payment_expired';next.paymentExpiryEvidence=evidence;}
  }
  await save(env,record,next);
  return (await load(env,order.id)).order;
}

async function settleReserved(env,pending,payload,required) {
  let settled;
  try {settled=await facilitatorClient().settle(payload,required);}catch{return json({order:pending,message:'Checking the original payment. Keep this order.'},202);}
  if(!settled.success || settled.network!==NETWORK || settled.payer?.toLowerCase()!==pending.payer || !hex32(settled.transaction))return json({order:pending,message:'The original payment can be checked or resubmitted after one minute.'},202);
  let current=await load(env,pending.id);
  if(current.order.state==='complete')return json({order:current.order});
  if(current.order.paymentAttemptId!==pending.paymentAttemptId)return json({order:current.order},202);
  // Persist the transaction before receipt polling can fail. Another request
  // can recover using this hash without contacting the facilitator again.
  const next={...current.order,paymentTransaction:settled.transaction};
  if(!await save(env,current,next))return json({order:(await load(env,pending.id)).order},202);
  current=await load(env,pending.id);
  const result=await reconcile(env,current);
  return json({order:result},result.state==='complete'?200:202,{'PAYMENT-RESPONSE':encodePaymentResponseHeader(settled)});
}

async function route(request,env) {
  const url=new URL(request.url);
  if(request.method==='GET' && url.pathname==='/api/catalog') {
    const available=await checkoutReady(env,client(),supported,secondaryClient());
    return json({name:'Mate Atelier',products:PRODUCTS,network:NETWORK,chainId:CHAIN_ID,testnet:true,shipsPhysicalGoods:false,
      checkoutAvailable:available,unavailableReason:available?null:'The shop cannot accept new orders right now. Check again shortly. Existing orders can still be checked.'});
  }
  if(!configuration(env))return json({error:'shop_not_ready',message:'Age verification and testnet checkout are not connected yet.'},503);
  const origin=request.headers.get('origin');
  if(origin && origin!==url.origin)return json({error:'foreign_origin'},403);
  const key=request.headers.get('X-Order-Key');
  if(!key || !/^[a-f0-9]{64}$/.test(key))return json({error:'order_key_required'},401);
  const id=hashKey(key);
  if(request.method==='POST' && url.pathname==='/api/orders') {
    const input=await body(request);
    if(Object.keys(input).some(key=>!['productId','quantity','payer'].includes(key)))return json({error:'unexpected_data'},400);
    const candidate=newOrder(input,key,env,clock());
    let record=await load(env,id);
    if(!record) {
      if(!env.ORDER_CREATION_LIMIT || !(await env.ORDER_CREATION_LIMIT.limit({key:'new-orders'})).success)return json({error:'try_later'},429,{'Retry-After':'60'});
      if(!await checkoutReady(env,client(),supported,secondaryClient()))return json({error:'shop_not_ready'},503);
      // Bound this test shop's total stored orders atomically, even when many
      // callers pass the earlier readiness check at the same time.
      await env.ORDERS.prepare('INSERT OR IGNORE INTO orders(id,state,value,created_at) SELECT ?,?,?,? WHERE (SELECT count(*) FROM orders) < ?')
        .bind(id,candidate.state,JSON.stringify(candidate),candidate.createdAt,MAX_ORDERS).run();
      record=await load(env,id);
      if(!record)return json({error:'shop_capacity_reached'},503);
    }
    if(record.order.payer!==candidate.payer || record.order.productId!==candidate.productId || record.order.quantity!==candidate.quantity)return json({error:'order_conflict'},409);
    return json({order:record.order},201);
  }
  const match=url.pathname.match(/^\/api\/orders\/(0x[a-f0-9]{64})(?:\/(age|pay))?$/);
  if(!match || match[1]!==id)return json({error:'not_found'},404);
  const record=await load(env,id);if(!record)return json({error:'not_found'},404);
  const order=record.order;
  if(request.method==='GET' && !match[2])return json({order:await reconcile(env,record)});
  if(request.method!=='POST')return json({error:'method_not_allowed'},405);
  if(order.state==='complete')return json({order});
  if(order.state==='payment_expired')return json({order,error:'payment_window_closed'},409);
  // Pending settlement must be reconciled with its original signed payment;
  // never create a replacement nonce, even after order expiry.
  if(order.state==='payment_pending') {
    const current=await reconcile(env,record);
    if(current.state==='complete')return json({order:current});
    const header=request.headers.get('PAYMENT-SIGNATURE');
    // A retry must carry the exact previously verified authorization. Never
    // issue a fresh 402 challenge or extend its validity / nonce after a timeout.
    if(match[2]==='pay' && header && !current.paymentTransaction && current.paymentAttemptAt
       && clock()>=current.paymentAttemptAt+60 && clock()<current.expiresAt) {
      const payload=paymentPayload(header,current,clock());
      if(keccak256(new TextEncoder().encode(header))!==current.paymentDigest)return json({error:'payment_mismatch'},400);
      if(!await verifiedAge(env,current))return json({error:'age_not_verified'},403);
      const latest=await load(env,id);
      if(latest.order.state!=='payment_pending' || latest.order.paymentTransaction || latest.order.paymentAttemptAt!==current.paymentAttemptAt)return json({order:latest.order},202);
      const pending={...latest.order,paymentAttemptAt:clock(),paymentAttemptId:crypto.randomUUID()};
      if(!await save(env,latest,pending))return json({order:(await load(env,id)).order},202);
      return settleReserved(env,pending,payload,requirements(pending));
    }
    return json({order:current,message:'Checking the original payment. Keep this order and its original authorization.'},202);
  }
  if(order.ageGate!==env.AGE_GATE_ADDRESS.toLowerCase() || order.recipient!==env.PAYMENT_RECIPIENT.toLowerCase())return json({error:'shop_configuration_changed'},409);
  if(clock()>=order.expiresAt)return json({error:'order_expired'},410);
  if(match[2]==='age') {
    // The actual EVM verifier sees only an order-bound proof and public values.
    // No raw card field, date, certificate, signature or client boolean is used.
    const submission=ageSubmission(await body(request));
    const next={...order,...submission,state:'age_verified'};
    if(!await verifiedAge(env,next))return json({error:'age_not_verified'},403);
    await save(env,record,next);
    return json({order:(await load(env,id)).order});
  }
  if(match[2]!=='pay')return json({error:'not_found'},404);
  if(order.state!=='age_verified' || !await verifiedAge(env,order))return json({error:'age_not_verified'},403);
  const required=requirements(order);
  const header=request.headers.get('PAYMENT-SIGNATURE');
  if(!header){const challenge={x402Version:2,resource:{url:`${url.origin}${url.pathname}`,description:'Mate Lager testnet order',mimeType:'application/json'},accepts:[required]};
    return json({...challenge,paymentNonce:order.paymentNonce,expiresAt:order.expiresAt},402,{'PAYMENT-REQUIRED':encodePaymentRequiredHeader(challenge)});}
  const payload=paymentPayload(header,order,clock());
  const facilitator=facilitatorClient();
  const verification=await facilitator.verify(payload,required);
  if(!verification.isValid || verification.payer?.toLowerCase()!==order.payer)return json({error:'payment_rejected'},402);
  const paymentStartBlock=(await client().getBlockNumber()).toString();
  const pending={...order,state:'payment_pending',paymentStartBlock,paymentValidBefore:Number(payload.payload.authorization.validBefore),paymentDigest:keccak256(new TextEncoder().encode(header)),paymentAttemptAt:clock(),paymentAttemptId:crypto.randomUUID()};
  if(!await save(env,record,pending))return json({order:(await load(env,id)).order},202);
  // Reserve the order durably before the external effect. A timeout stays
  // pending for reconciliation, never returns to a button that signs anew.
  return settleReserved(env,pending,payload,required);
}

return {
  async fetch(request,env) {
    if(!new URL(request.url).pathname.startsWith('/api/'))return env.ASSETS.fetch(request);
    try{
      if(!env.API_LIMIT)return json({error:'shop_not_ready'},503);
      // No IP address or personal identifier is passed to the limiter. This is
      // an approximate per-location resource limit, never payment accounting.
      if(!(await env.API_LIMIT.limit({key:'shop-api'})).success)return json({error:'try_later'},429,{'Retry-After':'60'});
      return await route(request,env);
    }catch(error){
      const expected=['invalid_order','invalid_request','request_too_large','invalid_payment','payment_mismatch','invalid_age_proof'];
      const known=expected.includes(error?.message);
      return json({error:known?error.message:'temporarily_unavailable',message:known?'Check this request before trying again.':'The shop could not confirm this step. Keep the same order and check again.'},known?400:503);
    }
  }
};
}

export default createShop();
