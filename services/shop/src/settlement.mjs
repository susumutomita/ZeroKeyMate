// The store sponsors gas for one exact x402 USDC authorization. This module is
// not an HTTP endpoint. Only the age-verified, reserved order path calls settle.
// ARC_SETTLER_KEY is a separately authorized, testnet-only Worker secret; never
// use a buyer key, model output, .env fallback, or general transaction payload.
import {createPublicClient,createWalletClient,http,encodeFunctionData,keccak256,parseAbi,parseSignature,verifyTypedData} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';
import {arcTestnet} from 'viem/chains';
import {CHAIN_ID,NETWORK,USDC,PRODUCTS,address,hex32} from './protocol.mjs';

export const SETTLEMENT_GAS = 150000n;
export const SETTLEMENT_MAX_FEE = 25000000000n; // 0.00375 test USDC maximum per attempt, native 18 decimals.
const abi=parseAbi(['function transferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,uint8 v,bytes32 r,bytes32 s)']);
const types={TransferWithAuthorization:[{name:'from',type:'address'},{name:'to',type:'address'},{name:'value',type:'uint256'},
 {name:'validAfter',type:'uint256'},{name:'validBefore',type:'uint256'},{name:'nonce',type:'bytes32'}]};
export const paymentTypedData=authorization=>({domain:{name:'USDC',version:'2',chainId:CHAIN_ID,verifyingContract:USDC},
 primaryType:'TransferWithAuthorization',types,message:authorization});

export function settlementConfigured(env) {
 try {
  if(!address(env.ARC_SETTLER_ADDRESS) || !/^0x[0-9a-fA-F]{64}$/.test(env.ARC_SETTLER_KEY??''))return false;
  return privateKeyToAccount(env.ARC_SETTLER_KEY).address.toLowerCase()===env.ARC_SETTLER_ADDRESS.toLowerCase();
 } catch {return false;}
}

// Readiness advertises only the locally configured settlement implementation.
// No third-party endpoint is presumed to support Arc from its marketing page.
export async function supportedSettlement(env,{client}={}) {
 if(!settlementConfigured(env) || !env.ARC_SETTLEMENT?.getByName)return {kinds:[]};
 const rpc=client??createPublicClient({chain:arcTestnet,transport:http('https://rpc.testnet.arc.io',{timeout:4000,retryCount:0})});
 const [chain,balance,price]=await Promise.all([rpc.getChainId(),rpc.getBalance({address:env.ARC_SETTLER_ADDRESS}),rpc.getGasPrice()]);
 const ready=chain===CHAIN_ID && balance>=SETTLEMENT_GAS*SETTLEMENT_MAX_FEE && price<=SETTLEMENT_MAX_FEE;
 return {kinds:ready?[{x402Version:2,scheme:'exact',network:NETWORK}]:[]};
}

export function createArcTransaction(env,{client,secondary,wallet,clock=()=>Math.floor(Date.now()/1000)}={}) {
 if(!settlementConfigured(env))throw new Error('settlement_unavailable');
 const account=privateKeyToAccount(env.ARC_SETTLER_KEY);
 const rpc=client??createPublicClient({chain:arcTestnet,transport:http('https://rpc.testnet.arc.io',{timeout:4000,retryCount:0})});
 const other=secondary??createPublicClient({chain:arcTestnet,transport:http('https://rpc.drpc.testnet.arc.io',{timeout:4000,retryCount:0})});
 const signer=wallet??createWalletClient({chain:arcTestnet,account,transport:http('https://rpc.testnet.arc.io',{timeout:8000,retryCount:0})});
 async function validate(payload,required) {
  if(payload?.x402Version!==2 || !address(env.PAYMENT_RECIPIENT))throw new Error('invalid_payment');
  const expected={scheme:'exact',network:NETWORK,asset:USDC,amount:PRODUCTS[0].amount,payTo:env.PAYMENT_RECIPIENT};
  for(const [key,value] of Object.entries(expected))for(const terms of [payload.accepted,required])
   if(String(terms?.[key]).toLowerCase()!==value.toLowerCase())throw new Error('payment_mismatch');
  for(const terms of [payload.accepted,required])if(terms?.extra?.name!=='USDC' || terms.extra.version!=='2')throw new Error('payment_mismatch');
  const a=payload.payload?.authorization,signature=payload.payload?.signature,now=BigInt(clock());
  if(!a || !address(a.from) || a.from.toLowerCase()===account.address.toLowerCase() || !hex32(a.nonce)
    || String(a.to).toLowerCase()!==env.PAYMENT_RECIPIENT.toLowerCase() || a.value!==PRODUCTS[0].amount
    || !/^[0-9]{1,12}$/.test(a.validAfter) || !/^[0-9]{1,12}$/.test(a.validBefore)
    || BigInt(a.validAfter)>=now || BigInt(a.validBefore)<=now || BigInt(a.validBefore)>now+300n
    || !/^0x[0-9a-fA-F]{130}$/.test(signature??''))throw new Error('invalid_payment');
  if(!await verifyTypedData({...paymentTypedData(a),address:a.from,signature}))throw new Error('invalid_payment');
  if(await rpc.getChainId()!==CHAIN_ID)throw new Error('wrong_chain');
  const {v,r,s}=parseSignature(signature);
  const args=[a.from,a.to,BigInt(a.value),BigInt(a.validAfter),BigInt(a.validBefore),a.nonce,Number(v),r,s];
  // The actual USDC contract rejects used nonces, insufficient balance, paused
  // or blocked accounts and wrong signatures before the sponsor spends gas.
  await rpc.simulateContract({account:account.address,address:USDC,abi,functionName:'transferWithAuthorization',args,gas:SETTLEMENT_GAS});
  return args;
 }
 return {
  async verify(payload,required) {
   try {await validate(payload,required);return {isValid:true,payer:payload.payload.authorization.from};}
   catch {return {isValid:false,invalidReason:'invalid_exact_arc_payment'};}
  },
  sponsor:account.address.toLowerCase(),
  async nonce(blockTag) {
   const values=await Promise.all([rpc,other].map(async provider=>{
    if(await provider.getChainId()!==CHAIN_ID)throw new Error('wrong_chain');
    return provider.getTransactionCount({address:account.address,blockTag});
   }));
   if(values[0]!==values[1] || !Number.isSafeInteger(values[0]) || values[0]<0)throw new Error('settlement_nonce_unconfirmed');
   return values[0];
  },
  async prepare(payload,required,nonce) {
   const args=await validate(payload,required);
   // Arc silently drops fees below 20 gwei. Never exceed the reviewed USDC cap
   // when congestion changes; the existing pending-order flow handles retries.
   if(await rpc.getGasPrice()>SETTLEMENT_MAX_FEE)throw new Error('settlement_fee_cap');
   if(!Number.isSafeInteger(nonce) || nonce<0)throw new Error('invalid_nonce');
   const raw=await signer.signTransaction({chain:arcTestnet,account,to:USDC,
    data:encodeFunctionData({abi,functionName:'transferWithAuthorization',args}),nonce,type:'eip1559',
    gas:SETTLEMENT_GAS,maxFeePerGas:SETTLEMENT_MAX_FEE,maxPriorityFeePerGas:1000000000n});
   return {raw,nonce,sponsor:account.address.toLowerCase(),result:{success:true,network:NETWORK,
    payer:payload.payload.authorization.from,transaction:keccak256(raw)}};
  },
  async broadcast(record) {
   if(record.sponsor!==account.address.toLowerCase())throw new Error('settlement_configuration_changed');
   if(await rpc.getChainId()!==CHAIN_ID)throw new Error('wrong_chain');
   const hash=await rpc.sendRawTransaction({serializedTransaction:record.raw});
   if(hash.toLowerCase()!==record.result.transaction)throw new Error('settlement_hash_mismatch');
  }
 };
}

// Requests from all Worker instances use the same durable coordinator for this
// sponsor. Only the already age-verified and durably reserved order reaches it.
export function createArcSettlement(env,options={}) {
 const transaction=createArcTransaction(env,options);
 if(!env.ARC_SETTLEMENT?.getByName)throw new Error('settlement_unavailable');
 return {verify:transaction.verify,settle:(payload,required)=>
  env.ARC_SETTLEMENT.getByName(`${CHAIN_ID}:${transaction.sponsor}`).settle(payload,required)};
}
