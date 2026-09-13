import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {encodeDeployData,getContractAddress,keccak256} from 'viem';
import {prepareAgeDeploymentPlan,writeAgeDeploymentPlan,DEPLOYMENT_BUDGET} from '../plan-age-deployment.mjs';

// Protocol/failure fixtures only; these bytecodes are not product verifier
// artifacts. The CLI authenticates its package through loadAgeDeployment first.
const deployer='0x'+'11'.repeat(20),now=1800000000,hash='0x'+'22'.repeat(32);
const runtime='0x'+'00'.repeat(64);
const pkg={chainId:5042002,testnetOnly:true,
 verifier:{abi:[],bytecode:'0x6000',runtimeTemplate:'0x6000',runtimeCodeHash:keccak256('0x6000')},
 gate:{abi:[{type:'constructor',inputs:[{name:'v',type:'address'},{name:'h',type:'bytes32'}],stateMutability:'nonpayable'}],
  bytecode:'0x6001',runtimeTemplate:runtime,runtimeCodeHash:keccak256(runtime),
  immutableNames:{a:'verifier',b:'verifierCodeHash'},immutableReferences:{a:[{start:0,length:32}],b:[{start:32,length:32}]}}};
function fixture() {
 const state={nonce:0,pending:0,chain:5042002,balance:0n,price:21000000000n,estimate:100000n,estimates:[],hash,time:now,code:undefined,occupied:false};
 const rpc={
  async getChainId(){return state.chain;},
  async getBlock({blockNumber=99n}={}){return {number:blockNumber,hash:state.hash,timestamp:BigInt(state.time)};},
  async getTransactionCount({address,blockTag}){return address===deployer?(blockTag==='pending'?state.pending:state.nonce):state.occupied?1:0;},
  async getBalance(){return state.balance;},async getGasPrice(){return state.price;},
  async getCode({address}){return address===deployer?state.code:undefined;},
  async estimateGas(call){state.estimates.push(call);return state.estimate;}
 };
 return {state,rpc};
}
test('unsigned Arc plan binds both CREATE addresses and constructor to consecutive deployer nonces',async()=>{
 const a=fixture(),b=fixture();b.state.estimate=120000n;
 const plan=await prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,b.rpc],{now,freshlyProvisioned:true});
 assert.equal(plan.verifier,getContractAddress({from:deployer,nonce:0n}).toLowerCase());
 assert.equal(plan.gate,getContractAddress({from:deployer,nonce:1n}).toLowerCase());
 assert.equal(plan.transactions[1].data,encodeDeployData({abi:pkg.gate.abi,bytecode:pkg.gate.bytecode,args:[plan.verifier,pkg.verifier.runtimeCodeHash]}));
 assert.deepEqual(plan.transactions.map(t=>[t.chainId,t.from,t.to,t.nonce,t.value,t.gas]),
  [[5042002,deployer,null,0,'0','144000'],[5042002,deployer,null,1,'0','144000']]);
 assert.equal(plan.maximumFee,'7200000000000000');assert.equal(plan.fundingRequired,plan.maximumFee);
 assert.equal(plan.maximumFeeUSDC,'0.0072');assert.equal(plan.nativeCurrency.decimals,18);
 assert.equal(plan.unsigned,true);assert.equal(plan.deployed,false);assert.equal(plan.notAuthorization,true);
 assert.equal(plan.expiresAt,now+120);assert.equal(plan.requiresFreshCheckBeforeSigning,true);
 assert.equal(a.state.estimates[1].stateOverride[1].code,pkg.verifier.runtimeTemplate);
 assert.equal(a.state.estimates[1].stateOverride[0].nonce,1);
 assert.ok(!JSON.stringify(plan).includes('privateKey'));
});
test('RPC disagreement, pending nonce, wrong network, stale head and occupied addresses reject preparation',async()=>{
 for(const change of [{chain:84532},{nonce:8,pending:8},{pending:8},{hash:'0x'+'33'.repeat(32)},
  {time:now-121},{time:now+31},{balance:1n},{code:'0xef0100'},{occupied:true}]) {
  const a=fixture(),b=fixture();Object.assign(b.state,change);
  await assert.rejects(()=>prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,b.rpc],{now,freshlyProvisioned:true}));
  assert.equal(a.state.estimates.length+b.state.estimates.length,0);
 }
 const a=fixture();await assert.rejects(()=>prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,fixture().rpc],{now}));
 await assert.rejects(()=>prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,a.rpc],{now,freshlyProvisioned:true}));
 await assert.rejects(()=>prepareAgeDeploymentPlan(pkg,'0x'+'00'.repeat(20),[a.rpc,fixture().rpc],{now,freshlyProvisioned:true}));
});
test('fee spikes and the combined deployment budget cannot be overridden by an estimate',async()=>{
 const a=fixture(),b=fixture();a.state.price=25000000001n;
 await assert.rejects(()=>prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,b.rpc],{now,freshlyProvisioned:true}),/fee exceeds/);
 a.state.price=21000000000n;a.state.estimate=2000000n;
 await assert.rejects(()=>prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,b.rpc],{now,freshlyProvisioned:true}),/total 0.10/);
 a.state.estimate=-1n;await assert.rejects(()=>prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,b.rpc],{now,freshlyProvisioned:true}),/Invalid deployment gas/);
 a.state.estimate=100000n;a.state.balance=DEPLOYMENT_BUDGET;b.state.balance=DEPLOYMENT_BUDGET;
 assert.equal((await prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,b.rpc],{now,freshlyProvisioned:true})).fundingRequired,'0');
});
test('nonce consumption during estimation invalidates both planned contract addresses',async()=>{
 const a=fixture(),b=fixture(),estimate=a.rpc.estimateGas;
 a.rpc.estimateGas=async call=>{const result=await estimate(call);a.state.pending++;return result;};
 await assert.rejects(()=>prepareAgeDeploymentPlan(pkg,deployer,[a.rpc,b.rpc],{now,freshlyProvisioned:true}),/nonce changed during/);
});
test('a plan never overwrites an existing review artifact',async()=>{
 const directory=await mkdtemp(path.join(os.tmpdir(),'mate-unsigned-plan-'));
 try {
  const file=path.join(directory,'plan.json');await writeAgeDeploymentPlan(file,{unsigned:true});
  await assert.rejects(()=>writeAgeDeploymentPlan(file,{unsigned:false}),{code:'EEXIST'});
  assert.deepEqual(JSON.parse(await readFile(file)),{unsigned:true});
 } finally {await rm(directory,{recursive:true,force:true});}
});
