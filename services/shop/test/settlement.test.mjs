import test from 'node:test';
import assert from 'node:assert/strict';
import {generatePrivateKey,privateKeyToAccount} from 'viem/accounts';
import {createArcSettlement,paymentTypedData,settlementConfigured,supportedSettlement,SETTLEMENT_GAS,SETTLEMENT_MAX_FEE} from '../src/settlement.mjs';
import {CHAIN_ID,NETWORK,newOrder,requirements} from '../src/protocol.mjs';

// Fresh process-memory keys for isolated tests only. No public requests.
async function fixture() {
 const key=generatePrivateKey(),sponsor=privateKeyToAccount(key),buyer=privateKeyToAccount(generatePrivateKey());
 const env={ARC_SETTLER_KEY:key,ARC_SETTLER_ADDRESS:sponsor.address,PAYMENT_RECIPIENT:'0x'+'22'.repeat(20),AGE_GATE_ADDRESS:'0x'+'11'.repeat(20)};
 const now=1800000000,order=newOrder({payer:buyer.address,productId:'mate-lager',quantity:1},'ab'.repeat(32),env,now);
 const required=requirements(order),a={from:buyer.address,to:order.recipient,value:order.amount,validAfter:String(now-1),validBefore:String(now+180),nonce:order.paymentNonce};
 const payload={x402Version:2,accepted:required,payload:{authorization:a,signature:await buyer.signTypedData(paymentTypedData(a))}};
 const state={sends:[],simulations:0,chain:CHAIN_ID,price:21000000000n,balance:10n**18n,revert:false};
 const client={getChainId:async()=>state.chain,getBalance:async()=>state.balance,getGasPrice:async()=>state.price,
  async simulateContract(){state.simulations++;if(state.revert)throw Error('USDC rejected');}};
 const wallet={async writeContract(call){state.sends.push(call);return '0x'+'aa'.repeat(32);}};
 const settlement=createArcSettlement(env,{client,wallet,clock:()=>now});
 return {env,buyer,now,required,payload,state,client,settlement};
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
 const call=f.state.sends[0];assert.equal(call.chain.id,CHAIN_ID);assert.equal(call.functionName,'transferWithAuthorization');
 assert.equal(call.args[2],100000n);assert.equal(call.gas,SETTLEMENT_GAS);assert.equal(call.maxFeePerGas,SETTLEMENT_MAX_FEE);
 assert.equal(call.gas*call.maxFeePerGas,3750000000000000n);assert.equal(call.value,undefined);
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
