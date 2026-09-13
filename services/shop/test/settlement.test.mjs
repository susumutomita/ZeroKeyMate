import test from 'node:test';
import {parseTransaction,decodeFunctionData,parseAbi} from 'viem';
import {SettlementQueue} from '../src/settlement-queue.mjs';
import {QueueStorage} from './queue-storage.mjs';
import assert from 'node:assert/strict';
import {generatePrivateKey,privateKeyToAccount} from 'viem/accounts';
import {createArcSettlement,createArcTransaction,paymentTypedData,settlementConfigured,supportedSettlement,SETTLEMENT_GAS,SETTLEMENT_MAX_FEE} from '../src/settlement.mjs';
import {CHAIN_ID,NETWORK,newOrder,requirements} from '../src/protocol.mjs';

// Fresh process-memory keys for isolated tests only. No public requests.
async function fixture() {
 const key=generatePrivateKey(),sponsor=privateKeyToAccount(key),buyer=privateKeyToAccount(generatePrivateKey());
 const env={ARC_SETTLER_KEY:key,ARC_SETTLER_ADDRESS:sponsor.address,PAYMENT_RECIPIENT:'0x'+'22'.repeat(20),AGE_GATE_ADDRESS:'0x'+'11'.repeat(20)};
 const now=1800000000,order=newOrder({payer:buyer.address,productId:'mate-lager',quantity:1},'ab'.repeat(32),env,now);
 const required=requirements(order),a={from:buyer.address,to:order.recipient,value:order.amount,validAfter:String(now-1),validBefore:String(now+180),nonce:order.paymentNonce};
 const payload={x402Version:2,accepted:required,payload:{authorization:a,signature:await buyer.signTypedData(paymentTypedData(a))}};
 const state={sends:[],simulations:0,chain:CHAIN_ID,price:21000000000n,balance:10n**18n,revert:false,nonce:0,finalized:0,signs:0,sendFails:false};
 const client={getChainId:async()=>state.chain,getBalance:async()=>state.balance,getGasPrice:async()=>state.price,
  getTransactionCount:async({blockTag})=>blockTag==='finalized'?state.finalized:state.nonce,
  async sendRawTransaction({serializedTransaction}){state.sends.push(serializedTransaction);if(state.sendFails)throw Error('submission timeout');return (await import('viem')).keccak256(serializedTransaction);},
  async simulateContract(){state.simulations++;if(state.revert)throw Error('USDC rejected');}};
 const wallet={async signTransaction(call){state.signs++;return sponsor.signTransaction({...call,chainId:CHAIN_ID});}};
 const transaction=createArcTransaction(env,{client,secondary:client,wallet,clock:()=>now});
 const storage=new QueueStorage(),queue=new SettlementQueue(storage,transaction);
 env.ARC_SETTLEMENT={getByName:()=>queue};
 const settlement=createArcSettlement(env,{client,secondary:client,wallet,clock:()=>now});
 return {env,buyer,now,required,payload,state,client,settlement,transaction,storage,queue};
}
test('no sponsor, mismatched key, unsupported chain, low balance or fee spike keeps the shop unavailable',async()=>{
 assert.equal(settlementConfigured({}),false);assert.deepEqual(await supportedSettlement({}),{kinds:[]});
 const f=await fixture();assert.equal(settlementConfigured({...f.env,ARC_SETTLER_ADDRESS:f.buyer.address}),false);
 assert.equal((await supportedSettlement(f.env,{client:f.client})).kinds[0].network,NETWORK);
 for(const change of [{chain:84532},{balance:0n},{price:SETTLEMENT_MAX_FEE+1n}]){
  const saved={...f.state};Object.assign(f.state,change);
  assert.deepEqual(await supportedSettlement(f.env,{client:f.client}),{kinds:[]});Object.assign(f.state,saved);
 }
});
test('real buyer signature produces only the fixed Arc USDC call within its native gas budget',async()=>{
 const f=await fixture();assert.deepEqual(await f.settlement.verify(f.payload,f.required),{isValid:true,payer:f.buyer.address});
 assert.equal(f.state.sends.length,0);const result=await f.settlement.settle(f.payload,f.required);
 assert.equal(result.network,NETWORK);assert.equal(f.state.sends.length,1);
 const call=parseTransaction(f.state.sends[0]);assert.equal(call.chainId,CHAIN_ID);
 const decoded=decodeFunctionData({abi:parseAbi(['function transferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,uint8 v,bytes32 r,bytes32 s)']),data:call.data});
 assert.equal(decoded.functionName,'transferWithAuthorization');assert.equal(decoded.args[2],100000n);assert.equal(call.gas,SETTLEMENT_GAS);assert.equal(call.maxFeePerGas,SETTLEMENT_MAX_FEE);
 assert.equal(call.gas*call.maxFeePerGas,3750000000000000n);assert.equal(call.value??0n,0n);
});
test('a Base signature or changed receiver, amount, token, domain or deadline cannot use sponsor gas',async()=>{
 const f=await fixture();
 const baseSignature=await f.buyer.signTypedData({...paymentTypedData(f.payload.payload.authorization),domain:{...paymentTypedData({}).domain,chainId:84532}});
 const variants=[{...f.payload,payload:{...f.payload.payload,signature:baseSignature}}];
 for(const changes of [{to:f.buyer.address},{value:'100001'},{validAfter:String(f.now)},{validBefore:String(f.now)},{validBefore:String(f.now+301)}])
  variants.push({...f.payload,payload:{...f.payload.payload,authorization:{...f.payload.payload.authorization,...changes}}});
 for(const changes of [{network:'eip155:84532'},{asset:f.buyer.address},{extra:{name:'GatewayWalletBatched',version:'1'}}])
  variants.push({...f.payload,accepted:{...f.required,...changes}});
 for(const p of variants){assert.equal((await f.settlement.verify(p,f.required)).isValid,false);await assert.rejects(()=>f.settlement.settle(p,f.required));}
 assert.equal(f.state.sends.length,0);
});
test('USDC rejection, wrong chain and a fee above the cap prevent broadcasting',async()=>{
 for(const change of [{revert:true},{chain:84532},{price:SETTLEMENT_MAX_FEE+1n}]){
  const f=await fixture();Object.assign(f.state,change);await assert.rejects(()=>f.settlement.settle(f.payload,f.required));
  assert.equal(f.state.sends.length,0);
 }
});

async function anotherPayment(f) {
 const authorization={...f.payload.payload.authorization,nonce:'0x'+'cd'.repeat(32)};
 return {...f.payload,payload:{authorization,signature:await f.buyer.signTypedData(paymentTypedData(authorization))}};
}
test('concurrent orders cannot sign the same sponsor nonce, including while the first send times out',async()=>{
 const f=await fixture(),second=await anotherPayment(f);f.state.sendFails=true;
 const results=await Promise.allSettled([f.queue.settle(f.payload,f.required),f.queue.settle(second,f.required)]);
 assert.equal(results[0].status,'fulfilled');assert.equal(results[1].status,'rejected');
 assert.equal(f.state.signs,1);assert.equal(new Set(f.state.sends).size,1);
 f.state.nonce=1; // Mined on one provider is insufficient: finalized must advance.
 await assert.rejects(()=>f.queue.settle(second,f.required),/settlement_busy/);
 f.state.finalized=1;f.state.sendFails=false;
 await f.queue.settle(second,f.required);assert.equal(f.state.signs,2);
 assert.deepEqual([...new Set(f.state.sends)].map(raw=>parseTransaction(raw).nonce),[0,1]);
});
test('failed atomic persistence broadcasts nothing and never leaves a partial active transaction',async()=>{
 const f=await fixture();f.storage.failCommit=true;
 await assert.rejects(()=>f.queue.settle(f.payload,f.required),/storage failed/);
 assert.equal(f.state.sends.length,0);assert.equal(await f.storage.get('active'),undefined);
});
test('eviction after commit before send is recovered by alarm using exactly the saved signed bytes',async()=>{
 const f=await fixture();
 // Save succeeds, then the process is interrupted before it can call broadcast.
 const original=f.storage.transaction.bind(f.storage);
 f.storage.transaction=async action=>{await original(action);throw Error('process interrupted');};
 await assert.rejects(()=>f.queue.settle(f.payload,f.required),/process interrupted/);
 assert.equal(f.state.sends.length,0);assert.equal(f.state.signs,1);
 const storage=new QueueStorage(structuredClone([...f.storage.values]));
 const restarted=new SettlementQueue(storage,f.transaction);
 const record=await storage.get(await storage.get('active'));
 assert.ok(await storage.get('alarm'));
 await restarted.alarm();await restarted.alarm();
 const result=await restarted.settle(f.payload,f.required);
 assert.equal(result.transaction,record.result.transaction);assert.equal(f.state.signs,1);
 assert.ok(f.state.sends.every(raw=>raw===record.raw));
 f.state.nonce=1;f.state.finalized=1;await restarted.alarm();
 assert.equal(await storage.get('active'),undefined);
 assert.equal((await storage.get(`payment:${f.buyer.address.toLowerCase()}:${f.payload.payload.authorization.nonce}`)).raw,undefined);
 assert.equal((await restarted.settle(f.payload,f.required)).transaction,result.transaction);
 assert.equal(f.state.signs,1); // Even a reverted transaction is never signed anew.
});
test('unknown pending sponsor transactions and disagreeing providers block nonce allocation',async()=>{
 const f=await fixture();
 f.transaction.nonce=async tag=>tag==='pending'?1:0;
 await assert.rejects(()=>f.queue.settle(f.payload,f.required),/nonce_unconfirmed/);assert.equal(f.state.signs,0);
 const mismatched=createArcTransaction(f.env,{client:f.client,secondary:{...f.client,getTransactionCount:async()=>7}});
 await assert.rejects(()=>mismatched.nonce('pending'),/nonce_unconfirmed/);
});
