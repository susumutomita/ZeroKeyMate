import {createPublicClient, http, keccak256, parseAbi, decodeEventLog} from 'viem';
import {baseSepolia} from 'viem/chains';
import {HTTPFacilitatorClient} from '@x402/core/server';
import {encodePaymentRequiredHeader, encodePaymentResponseHeader} from '@x402/core/http';
import {CHAIN_ID, NETWORK, USDC, PRODUCTS, configuration, hex32, hashKey, newOrder, nowSeconds, requirements, paymentPayload} from './protocol.mjs';

const AGE_ABI = parseAbi(['function isOrderAgeVerified(bytes32 orderHash, address payer, uint256 minimumAge, uint256 expiresAt) view returns (bool)']);
const TRANSFER_ABI = parseAbi(['event Transfer(address indexed from, address indexed to, uint256 value)', 'event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce)']);
const security = {'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
const json = (value,status=200,headers={}) => Response.json(value,{status,headers:{...security,...headers}});
const productionClient = () => createPublicClient({chain:baseSepolia,transport:http('https://sepolia.base.org',{timeout:15000,retryCount:0})});

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
// or a Worker binding. The deployed export always uses the fixed testnet RPC.
export function createShop({client=productionClient, facilitatorClient=()=>new HTTPFacilitatorClient({url:'https://x402.org/facilitator',timeoutMs:20000})}={}) {
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
  const rpc=client();
  const code=await rpc.getCode({address:order.ageGate});
  if (!code || code==='0x' || keccak256(code).toLowerCase()!==env.AGE_GATE_CODE_HASH.toLowerCase()) return false;
  return await rpc.readContract({address:order.ageGate,abi:AGE_ABI,functionName:'isOrderAgeVerified',
    args:[order.orderHash,order.payer,BigInt(order.minimumAge),BigInt(order.expiresAt)]}) === true;
}

async function confirmedPayment(order,transaction) {
  const rpc=client();
  const receipt=await rpc.getTransactionReceipt({hash:transaction});
  if(receipt.status!=='success' || await rpc.getBlockNumber()<receipt.blockNumber+1n)return false;
  const block=await rpc.getBlock({blockNumber:receipt.blockNumber});
  if(block.hash!==receipt.blockHash)return false;
  const events=receipt.logs.flatMap(log=>{
    if(log.address.toLowerCase()!==USDC.toLowerCase())return [];
    try {return [decodeEventLog({abi:TRANSFER_ABI,data:log.data,topics:log.topics})];} catch {return [];}
  });
  return events.some(event=>event.eventName==='Transfer' && event.args.from.toLowerCase()===order.payer && event.args.to.toLowerCase()===order.recipient && event.args.value===BigInt(order.amount))
    && events.some(event=>event.eventName==='AuthorizationUsed' && event.args.authorizer.toLowerCase()===order.payer && event.args.nonce.toLowerCase()===order.paymentNonce.toLowerCase());
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
  await save(env,record,next);
  return (await load(env,order.id)).order;
}

async function route(request,env) {
  const url=new URL(request.url);
  if(request.method==='GET' && url.pathname==='/api/catalog') {
    return json({name:'Mate Atelier',products:PRODUCTS,network:NETWORK,chainId:CHAIN_ID,testnet:true,shipsPhysicalGoods:false,
      checkoutAvailable:configuration(env),unavailableReason:configuration(env)?null:'The shop is connecting age verification and testnet checkout. No order or payment will be sent yet.'});
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
    const candidate=newOrder(input,key,env);
    await env.ORDERS.prepare('INSERT OR IGNORE INTO orders(id,state,value,created_at) VALUES(?,?,?,?)')
      .bind(id,candidate.state,JSON.stringify(candidate),candidate.createdAt).run();
    const record=await load(env,id);
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
  // Pending settlement must be reconciled with its original signed payment;
  // never create a replacement nonce, even after order expiry.
  if(order.state==='payment_pending') {
    const current=await reconcile(env,record);
    return json({order:current,message:current.state==='complete'?'Order complete.':'Checking the original payment. Do not pay again.'},current.state==='complete'?200:202);
  }
  if(order.ageGate!==env.AGE_GATE_ADDRESS.toLowerCase() || order.recipient!==env.PAYMENT_RECIPIENT.toLowerCase())return json({error:'shop_configuration_changed'},409);
  if(nowSeconds()>=order.expiresAt)return json({error:'order_expired'},410);
  if(match[2]==='age') {
    // Only the proof-verifying on-chain gate can grant this status. Client
    // booleans, birth dates and raw card data are never accepted by this route.
    if(!await verifiedAge(env,order))return json({error:'age_not_verified'},403);
    const next={...order,state:'age_verified'};
    await save(env,record,next);
    return json({order:(await load(env,id)).order});
  }
  if(match[2]!=='pay')return json({error:'not_found'},404);
  if(order.state!=='age_verified' || !await verifiedAge(env,order))return json({error:'age_not_verified'},403);
  const required=requirements(order);
  const header=request.headers.get('PAYMENT-SIGNATURE');
  if(!header){const challenge={x402Version:2,resource:{url:`${url.origin}${url.pathname}`,description:'Mate Lager testnet order',mimeType:'application/json'},accepts:[required]};
    return json({...challenge,paymentNonce:order.paymentNonce,expiresAt:order.expiresAt},402,{'PAYMENT-REQUIRED':encodePaymentRequiredHeader(challenge)});}
  const payload=paymentPayload(header,order);
  const facilitator=facilitatorClient();
  const verification=await facilitator.verify(payload,required);
  if(!verification.isValid || verification.payer?.toLowerCase()!==order.payer)return json({error:'payment_rejected'},402);
  const paymentStartBlock=(await client().getBlockNumber()).toString();
  const pending={...order,state:'payment_pending',paymentStartBlock,paymentDigest:keccak256(new TextEncoder().encode(header))};
  if(!await save(env,record,pending))return json({order:(await load(env,id)).order},202);
  // Reserve the order durably before the external effect. A timeout stays
  // pending for reconciliation, never returns to a button that signs anew.
  let settled;
  try {settled=await facilitator.settle(payload,required);}catch{return json({order:pending,message:'Checking the original payment. Do not pay again.'},202);}
  if(!settled.success || settled.network!==NETWORK || settled.payer?.toLowerCase()!==order.payer || !hex32(settled.transaction))return json({order:pending,message:'Settlement requires reconciliation.'},202);
  const current=await load(env,id);
  if(current.order.state==='complete')return json({order:current.order});
  const next={...pending,paymentTransaction:settled.transaction};
  if(await confirmedPayment(order,settled.transaction))next.state='complete';
  await save(env,current,next);
  return json({order:(await load(env,id)).order},next.state==='complete'?200:202,{'PAYMENT-RESPONSE':encodePaymentResponseHeader(settled)});
}

return {
  async fetch(request,env) {
    if(!new URL(request.url).pathname.startsWith('/api/'))return env.ASSETS.fetch(request);
    try{return await route(request,env);}catch(error){
      const expected=['invalid_order','invalid_request','request_too_large','invalid_payment','payment_mismatch'];
      const known=expected.includes(error?.message);
      return json({error:known?error.message:'temporarily_unavailable',message:known?'Check this request before trying again.':'The shop could not confirm this step. Keep the same order and check again.'},known?400:503);
    }
  }
};
}

export default createShop();
