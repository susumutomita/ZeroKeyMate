// Read-only, unsigned Arc deployment preparation. No environment/key discovery,
// wallet client, signing, funding, or transaction submission exists here.
import assert from 'node:assert/strict';
import {parseArgs} from 'node:util';
import {writeFile,readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {createPublicClient,http,encodeDeployData,getContractAddress,isAddress,keccak256,formatUnits} from 'viem';
import {arcTestnet} from 'viem/chains';
import {loadAgeDeployment,expectedGateRuntime} from './age-deployment.mjs';

export const DEPLOYMENT_FEE_CAP=25000000000n;
export const DEPLOYMENT_BUDGET=100000000000000000n; // 0.10 native test USDC (18 decimals).
const priorityFee=1000000000n;
const endpoints=['https://rpc.testnet.arc.io','https://rpc.drpc.testnet.arc.io'];
const validNonce=n=>Number.isSafeInteger(n)&&n>=0&&n<Number.MAX_SAFE_INTEGER;
const noCode=code=>code===undefined||code==='0x';

// Only a newly provisioned exclusive deployer with no pre-signed transactions
// is supported. RPC pending counts cannot detect nonce-gap queued transactions.
// The caller confirms this external provisioning fact; nonce zero alone cannot.
// pkg must come from loadAgeDeployment, whose independent repository pin
// authenticates the entire compiler output before any RPC sees its bytecode.
export async function prepareAgeDeploymentPlan(pkg,deployer,rpcs,{now=Math.floor(Date.now()/1000),freshlyProvisioned=false}={}) {
 assert.equal(freshlyProvisioned,true,'Use only a freshly created deployer with no pre-signed transactions');
 assert.equal(pkg.chainId,5042002);assert.equal(pkg.testnetOnly,true);
 assert.ok(isAddress(deployer,{strict:false})&&!/^0x0{40}$/i.test(deployer),'Invalid public deployer address');
 assert.ok(Number.isSafeInteger(now)&&now>0);assert.equal(rpcs.length,2);assert.notEqual(rpcs[0],rpcs[1]);
 deployer=deployer.toLowerCase();
 const heads=await Promise.all(rpcs.map(async rpc=>{
  assert.equal(await rpc.getChainId(),5042002,'Wrong deployment chain');
  return rpc.getBlock({blockTag:'latest'});
 }));
 assert.ok(heads.every(b=>typeof b.number==='bigint'&&b.number>=0n),'Invalid chain head');
 const blockNumber=heads[0].number<heads[1].number?heads[0].number:heads[1].number;
 const observations=await Promise.all(rpcs.map(async rpc=>{
  const [block,nonce,pending,balance,price,code]=await Promise.all([
   rpc.getBlock({blockNumber}),rpc.getTransactionCount({address:deployer,blockNumber}),
   rpc.getTransactionCount({address:deployer,blockTag:'pending'}),
   rpc.getBalance({address:deployer,blockNumber}),rpc.getGasPrice(),rpc.getCode({address:deployer,blockNumber})
  ]);
  assert.equal(block.number,blockNumber);assert.match(block.hash,/^0x[0-9a-fA-F]{64}$/);
  assert.ok(typeof block.timestamp==='bigint'&&block.timestamp>=BigInt(now-120)&&block.timestamp<=BigInt(now+30),'Stale or future chain snapshot');
  assert.ok(validNonce(nonce)&&nonce===0&&pending===0,'Use a fresh deployer with unused nonce zero');
  assert.ok(typeof balance==='bigint'&&balance>=0n,'Invalid native balance');
  assert.ok(typeof price==='bigint'&&price>0n&&price<=DEPLOYMENT_FEE_CAP,'Arc fee exceeds deployment cap');
  assert.ok(noCode(code),'Deployer must be a dedicated undelegated EOA');
  return {hash:block.hash.toLowerCase(),timestamp:block.timestamp,nonce,balance};
 }));
 assert.deepEqual(observations[0],observations[1],'Deployment RPC providers disagree');
 const {nonce,balance,hash,timestamp}=observations[0];
 const verifier=getContractAddress({from:deployer,nonce:BigInt(nonce)}).toLowerCase();
 const gate=getContractAddress({from:deployer,nonce:BigInt(nonce+1)}).toLowerCase();
 for(const rpc of rpcs)for(const address of [verifier,gate]) {
  const [code,count]=await Promise.all([rpc.getCode({address,blockNumber}),rpc.getTransactionCount({address,blockNumber})]);
  assert.ok(noCode(code)&&count===0,'Predicted deployment address is already occupied');
 }
 const creation=[
  encodeDeployData({abi:pkg.verifier.abi,bytecode:pkg.verifier.bytecode}),
  encodeDeployData({abi:pkg.gate.abi,bytecode:pkg.gate.bytecode,args:[verifier,pkg.verifier.runtimeCodeHash]})
 ];
 const estimates=await Promise.all(rpcs.map(async rpc=>Promise.all(creation.map((data,index)=>rpc.estimateGas({
  account:deployer,data,nonce:nonce+index,value:0n,blockNumber,
  maxFeePerGas:DEPLOYMENT_FEE_CAP,maxPriorityFeePerGas:priorityFee,
  // Ephemeral RPC simulation of a funded deployer and, for the second call,
  // its already-deployed verifier. These overrides do not fund or deploy anything.
  stateOverride:[{address:deployer,balance:DEPLOYMENT_BUDGET,nonce:nonce+index},
   ...(index?[{address:verifier,code:pkg.verifier.runtimeTemplate}]:[])]
 })))));
 const gas=[0,1].map(index=>{
  const values=estimates.map(result=>result[index]);
  assert.ok(values.every(value=>typeof value==='bigint'&&value>=21000n),'Invalid deployment gas estimate');
  return ((values[0]>values[1]?values[0]:values[1])*120n+99n)/100n;
 });
 const maximumFee=(gas[0]+gas[1])*DEPLOYMENT_FEE_CAP;
 assert.ok(maximumFee<=DEPLOYMENT_BUDGET,'Deployment exceeds total 0.10 test USDC cap');
 // A nonce changing while the estimates run invalidates both predicted addresses.
 for(const rpc of rpcs)assert.equal(await rpc.getTransactionCount({address:deployer,blockTag:'pending'}),nonce,'Deployer nonce changed during preparation');
 return {format:1,chainId:5042002,testnetOnly:true,unsigned:true,deployed:false,notAuthorization:true,
  createdAt:now,expiresAt:now+120,requiresFreshCheckBeforeSigning:true,
  freshDeployerRequired:true,queuedTransactionsObservable:false,deployer,
  snapshot:{blockNumber:String(blockNumber),blockHash:hash,timestamp:String(timestamp)},
  verifier,gate,verifierCodeHash:pkg.verifier.runtimeCodeHash,gateCodeHash:keccak256(expectedGateRuntime(pkg,verifier)),
  nativeCurrency:{symbol:'test USDC',decimals:18},nativeBalance:String(balance),
  maximumFee:String(maximumFee),maximumFeeUSDC:formatUnits(maximumFee,18),budget:String(DEPLOYMENT_BUDGET),
  fundingRequired:String(balance<maximumFee?maximumFee-balance:0n),
  transactions:creation.map((data,index)=>({contract:index?'gate':'verifier',type:'eip1559',chainId:5042002,
   from:deployer,to:null,nonce:nonce+index,value:'0',data,gas:String(gas[index]),
   maxFeePerGas:String(DEPLOYMENT_FEE_CAP),maxPriorityFeePerGas:String(priorityFee)}))};
}

export async function writeAgeDeploymentPlan(file,plan) {
 // Review artifacts never overwrite a previous plan, let alone credentials.
 await writeFile(file,JSON.stringify(plan,null,2)+'\n',{flag:'wx',mode:0o600});
}

async function main() {
 const {values}=parseArgs({options:{'deployment-package':{type:'string'},deployer:{type:'string'},out:{type:'string'},'fresh-deployer':{type:'boolean'},help:{type:'boolean'}}});
 if(values.help){console.log('Read-only: node scripts/plan-age-deployment.mjs --deployment-package DIRECTORY --deployer PUBLIC_ADDRESS --fresh-deployer --out NEW_FILE');return;}
 assert.ok(values['deployment-package']&&values.deployer&&values.out,'Provide the reviewed package, public deployer address and new output file');
 assert.equal(values['fresh-deployer'],true,'Confirm a newly created deployer with no pre-signed or queued transactions');
 const pkg=await loadAgeDeployment(values['deployment-package']);
 const rpcs=endpoints.map(url=>createPublicClient({chain:arcTestnet,cacheTime:0,transport:http(url,{timeout:8000,retryCount:0})}));
 const plan=await prepareAgeDeploymentPlan(pkg,values.deployer,rpcs,{freshlyProvisioned:values['fresh-deployer']});
 const pins=JSON.parse(await readFile(new URL('../config/age-deployment-pins.json',import.meta.url)));
 await writeAgeDeploymentPlan(values.out,{...plan,deploymentSHA256:pins.deploymentSHA256,rpcProviders:endpoints});
 console.log(JSON.stringify({unsigned:true,deployed:false,chainId:plan.chainId,verifier:plan.verifier,gate:plan.gate,
  maximumFeeUSDC:plan.maximumFeeUSDC,fundingRequired:plan.fundingRequired,expiresAt:plan.expiresAt,out:values.out}));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main().catch(()=>{
 console.error('Deployment preparation failed. No transaction was signed or submitted; check the package, public address, RPC agreement, fee cap and output path.');
 process.exitCode=1;
});
