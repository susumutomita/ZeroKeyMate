import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { randomBytes } from 'node:crypto';
import { createPublicClient, createWalletClient, http, keccak256, encodeAbiParameters, toFunctionSelector } from 'viem';
import { mnemonicToAccount } from 'viem/accounts';
import { foundry } from 'viem/chains';

// Disposable loopback accounts only. Never use .env, real credentials or public RPC.
const accounts=Array.from({length:7},(_,addressIndex)=>mnemonicToAccount('test test test test test test test test test test test junk',{addressIndex}));
const [owner,agentA,agentB,merchant,stranger,relayerA,relayerB]=accounts;
const artifact=name=>JSON.parse(fs.readFileSync(new URL(`../../.build/contracts/${name}.json`,import.meta.url)));
const budgetABI=artifact('MateCatalogBudget'),tokenABI=artifact('SharedBudgetTestToken'),gateABI=artifact('MateAgeGate');
const zeroInputs=Array(8).fill(0n);
const fresh=()=>`0x${randomBytes(32).toString('hex')}`;
let anvil,client,wallets;
before(async()=>{
  const reservation=createServer();await new Promise(resolve=>reservation.listen(0,'127.0.0.1',resolve));
  const port=reservation.address().port;await new Promise(resolve=>reservation.close(resolve));
  let startError;
  anvil=spawn('anvil',['--host','127.0.0.1','--port',String(port),'--chain-id','31337','--silent'],{stdio:'ignore'});
  anvil.on('error',error=>{startError=error;});
  const transport=http(`http://127.0.0.1:${port}`,{timeout:2000,retryCount:0});
  client=createPublicClient({chain:foundry,transport,pollingInterval:20});
  wallets=accounts.map(account=>createWalletClient({chain:foundry,transport,account}));
  for(let i=0;i<100;i++) {
    if(startError)throw startError;assert.equal(anvil.exitCode,null,'Owned local chain exited');
    try {assert.equal(await client.getChainId(),31337);return;}catch {await new Promise(resolve=>setTimeout(resolve,100));}
  }
  throw new Error('Local Anvil is required; never skip enforcement tests');
});
after(()=>anvil?.kill('SIGTERM'));
async function mined(hash,status='success') {const receipt=await client.waitForTransactionReceipt({hash});assert.equal(receipt.status,status);return receipt;}
async function deploy(a,args=[]) {return (await mined(await wallets[0].deployContract({abi:a.abi,bytecode:a.bytecode,args}))).contractAddress;}
const read=(address,a,functionName,args=[])=>client.readContract({address,abi:a.abi,functionName,args});
async function call(address,a,functionName,args=[],wallet=wallets[0]) {
  const {request}=await client.simulateContract({address,abi:a.abi,functionName,args,account:wallet.account});
  return mined(await wallet.writeContract(request));
}
async function fixture(changes={}) {
  const token=await deploy(tokenABI);
  // Rejection-only verifier fixture: it CANNOT manufacture an accepted proof.
  const reject=await deploy({abi:[],bytecode:'0x6005600c60003960056000f360006000fd'});
  const gate=await deploy(gateABI,[reject,keccak256(await client.getCode({address:reject}))]);
  const now=(await client.getBlock()).timestamp;
  const limits={total:500000n,perPurchase:300000n,purchases:3,expiresAt:now+3600n,products:3,...changes};
  const gateHash=keccak256(await client.getCode({address:gate}));
  const args=[token,gate,gateHash,[agentA.address,agentB.address],[merchant.address],limits];
  const budget=await deploy(budgetABI,args);
  await call(token,tokenABI,'mint',[budget,2000000n]);
  return {token,gate,gateHash,budget,limits,args,
    domain:{name:'ZeroKey Mate Catalogue Budget',version:'1',chainId:31337,verifyingContract:budget}};
}
async function order(f,changes={}) {
  return {id:fresh(),product:2,quantity:1,merchant:merchant.address,
    expiresAt:(await client.getBlock()).timestamp+600n,paymentNonce:fresh(),...changes};
}
function expectedHash(f,o) {
  return keccak256(encodeAbiParameters(['string','uint256','address','bytes32','string','uint256','address','address','address','uint256','uint256','bytes32','uint256'].map(type=>({type})),[
    'ZKM-AGE-ORDER-1',31337n,f.gate,o.id,o.product===1?'mate-lager':'mate-sparkling-water',BigInt(o.quantity),f.budget,o.merchant,f.token,
    BigInt(o.quantity)*(o.product===1?100000n:50000n),o.expiresAt,o.paymentNonce,o.product===1?20n:0n]));
}
async function signed(f,o,agent=agentA,domain=f.domain) {
  const hash=expectedHash(f,o);
  const quote=await merchant.signTypedData({domain,primaryType:'Quote',types:{Quote:[{name:'orderHash',type:'bytes32'}]},message:{orderHash:hash}});
  const purchase=await agent.signTypedData({domain,primaryType:'Purchase',types:{Purchase:[{name:'agent',type:'address'},{name:'orderHash',type:'bytes32'}]},message:{agent:agent.address,orderHash:hash}});
  return [o,agent.address,purchase,quote,'0x',zeroInputs];
}
const execute=(f,args)=>call(f.budget,budgetABI,'execute',args,wallets[5]);
const state=(f,key,args=[])=>read(f.budget,budgetABI,key,args);
const balance=(f,address)=>read(f.token,tokenABI,'balanceOf',[address]);
const rejects=(f,args,error)=>assert.rejects(()=>execute(f,args),new RegExp(error==='TransfersPaused'?toFunctionSelector(`${error}()`):error));

test('water uses canonical quantity/price and no age proof; both signatures bind the exact order',async()=>{
  const f=await fixture();const o=await order(f,{quantity:3});
  assert.equal(await state(f,'orderHash',[o]),expectedHash(f,o));
  await execute(f,await signed(f,o));
  assert.equal(await state(f,'spent'),150000n);assert.equal(await state(f,'purchaseCount'),1);
  assert.equal(await balance(f,merchant.address),150000n);
  await rejects(f,await signed(f,o,agentB),'OrderReplayed');
  await rejects(f,await signed(f,{...o,paymentNonce:fresh()},agentB),'OrderReplayed');
  await rejects(f,await signed(f,{...o,id:fresh()},agentB),'OrderReplayed');
});
test('count cap holds with excess funds, a different agent and later top-ups',async()=>{
  const f=await fixture({purchases:1});await execute(f,await signed(f,await order(f)));
  await call(f.token,tokenABI,'mint',[f.budget,2000000n]);
  await rejects(f,await signed(f,await order(f),agentB),'PurchaseCountExceeded');
  assert.equal(await state(f,'purchaseCount'),1);assert.equal(await state(f,'spent'),50000n);
});
test('same-block purchases cannot jointly exceed the shared budget',async()=>{
  const f=await fixture({total:250000n,perPurchase:250000n});
  const args=[await signed(f,await order(f,{quantity:3})),await signed(f,await order(f,{quantity:3}),agentB)];
  await client.request({method:'evm_setAutomine',params:[false]});
  try {
    const hashes=await Promise.all(args.map((value,i)=>wallets[5+i].writeContract({address:f.budget,abi:budgetABI.abi,functionName:'execute',args:value,gas:1000000n})));
    await client.request({method:'evm_mine',params:[]});
    const receipts=await Promise.all(hashes.map(hash=>client.waitForTransactionReceipt({hash})));
    assert.equal(receipts[0].blockNumber,receipts[1].blockNumber);
    assert.deepEqual(receipts.map(r=>r.status).sort(),['reverted','success']);
    assert.equal(await state(f,'spent'),150000n);assert.equal(await state(f,'purchaseCount'),1);
    assert.equal(await balance(f,merchant.address),150000n);
  } finally {await client.request({method:'evm_setAutomine',params:[true]});}
});
test('unknown SKU, bad quantity, disallowed product and merchant fail closed',async()=>{
  const f=await fixture({products:2});const original=await signed(f,await order(f));
  for(const change of [{product:0},{product:3},{quantity:0},{quantity:6}]) await rejects(f,[{...original[0],...change},...original.slice(1)],'InvalidOrder');
  await rejects(f,await signed(f,await order(f,{product:1})),'ProductNotAllowed');
  await rejects(f,await signed(f,await order(f,{merchant:stranger.address})),'MerchantNotAllowed');
});
test('tampered quote fields, forged signatures and chain/account domains are rejected',async()=>{
  const f=await fixture();const args=await signed(f,await order(f));
  for(const change of [{quantity:2},{id:fresh()},{paymentNonce:fresh()},{expiresAt:args[0].expiresAt-1n}]) await rejects(f,[{...args[0],...change},...args.slice(1)],'InvalidQuote');
  await rejects(f,[args[0],args[1],'0x1234',...args.slice(3)],'InvalidAgentSignature');
  await rejects(f,[...args.slice(0,3),'0x1234',...args.slice(4)],'InvalidQuote');
  await rejects(f,await signed(f,args[0],stranger),'InvalidAgent');
  for(const domain of [{...f.domain,chainId:5042002},{...f.domain,verifyingContract:merchant.address}]) await rejects(f,await signed(f,args[0],agentA,domain),'InvalidQuote');
});
test('beer never settles without a valid order-bound age proof from the pinned gate',async()=>{
  const f=await fixture();const args=await signed(f,await order(f,{product:1}));
  await rejects(f,args,'AgeNotVerified');
  await rejects(f,[...args.slice(0,4),`0x${'00'.repeat(384)}`,zeroInputs],'AgeNotVerified');
  assert.equal(await state(f,'spent'),0n);assert.equal(await state(f,'purchaseCount'),0);
  assert.equal(await balance(f,merchant.address),0n);
  assert.equal(await state(f,'usedOrders',[args[0].id]),false);
  await client.request({method:'anvil_setCode',params:[f.gate,'0x60006000fd']});
  await rejects(f,args,'AgeNotVerified');
});
test('transfer failure rolls back nonce, order, count and spend; retry can then succeed',async()=>{
  const f=await fixture();const args=await signed(f,await order(f));
  await call(f.token,tokenABI,'configure',[true,false]);await rejects(f,args,'TransfersPaused');
  await call(f.token,tokenABI,'configure',[false,true]);await rejects(f,args,'UnsupportedTokenBehavior');
  assert.equal(await state(f,'spent'),0n);assert.equal(await state(f,'purchaseCount'),0);
  assert.equal(await state(f,'usedOrders',[args[0].id]),false);assert.equal(await state(f,'usedNonces',[args[0].paymentNonce]),false);
  assert.equal(await balance(f,merchant.address),0n);
  await call(f.token,tokenABI,'configure',[false,false]);await execute(f,args);
});
test('owner stop invalidates both agents existing signatures and withdrawal only returns to owner',async()=>{
  const f=await fixture();const a=await signed(f,await order(f));const b=await signed(f,await order(f),agentB);
  await assert.rejects(()=>call(f.budget,budgetABI,'revokeAll',[],wallets[4]),/Unauthorized/);
  await assert.rejects(()=>call(f.budget,budgetABI,'withdraw',[1n],wallets[4]),/Unauthorized/);
  await call(f.budget,budgetABI,'revokeAll');
  await rejects(f,a,'BudgetStopped');await rejects(f,b,'BudgetStopped');
  await call(f.budget,budgetABI,'withdraw',[2000000n]);
  assert.equal(await balance(f,owner.address),2000000n);assert.equal(await balance(f,stranger.address),0n);
});
test('expired quotes, excessive per-purchase amounts and unexpected water proof are rejected',async()=>{
  const f=await fixture({perPurchase:50000n});
  await rejects(f,await signed(f,await order(f,{quantity:2})),'BudgetExceeded');
  const args=await signed(f,await order(f));
  await rejects(f,[...args.slice(0,4),'0x1234',zeroInputs],'InvalidOrder');
  await rejects(f,[...args.slice(0,4),'0x',[1n,...zeroInputs.slice(1)]],'InvalidOrder');
  await client.request({method:'evm_increaseTime',params:[601]});await client.request({method:'evm_mine',params:[]});
  await rejects(f,args,'OrderExpired');
});
test('invalid authorization terms and changed gate hash cannot deploy',async()=>{
  const f=await fixture();
  for(const changes of [{total:0n},{perPurchase:600000n},{purchases:0},{purchases:101},{products:0},{products:4},{expiresAt:1n}])
    await assert.rejects(()=>deploy(budgetABI,[...f.args.slice(0,5),{...f.limits,...changes}]),new RegExp(toFunctionSelector('InvalidPolicy()')));
  await assert.rejects(()=>deploy(budgetABI,[f.token,f.gate,fresh(),...f.args.slice(3)]),new RegExp(toFunctionSelector('InvalidPolicy()')));
});
