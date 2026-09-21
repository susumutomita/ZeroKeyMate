// Real Groth16 proof + atomic local-EVM purchase, using a FRESH SYNTHETIC issuer.
// No real credentials, existing wallet keys, public RPC or application settings.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomBytes } from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createInterface } from 'node:readline';
import { createServer } from 'node:net';
import { once } from 'node:events';
import solc from 'solc';
import { createPublicClient,createWalletClient,http,keccak256 } from 'viem';
import { mnemonicToAccount } from 'viem/accounts';
import { foundry } from 'viem/chains';
const run=promisify(execFile);
const root=path.resolve(import.meta.dirname,'..');
const base=path.resolve(root,process.argv[2]??'.build/age-proof-engine/artifacts');
const cli=path.resolve(root,process.argv[3]??'.build/age-proof-engine/target/release/provekit-cli');
for(const p of [base,cli]) assert.ok(p.startsWith(path.join(root,'.build')+path.sep),'Local build artifacts only');
const out=fs.mkdtempSync(path.join(root,'.build/catalog-age-'));
const sha=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const provenance=JSON.parse(fs.readFileSync(path.join(base,'provenance.json')));
assert.equal(provenance.sameWitnessCommitmentsDiffer,true);
for(const [name,hash] of Object.entries(provenance.circuitSHA256)) assert.equal(sha(path.join(root,name)),hash,'Current circuit must match proving artifacts');
for(const name of ['age.pkp','age.pkv','Verifier.sol']) assert.equal(sha(path.join(base,name)),provenance.artifactSHA256[name]);
const generator=spawn('python3',[path.join(root,'scripts/catalog-age-fixture.py'),out],{stdio:['pipe','pipe','inherit']});
const generatorExit=once(generator,'exit');
const lines=createInterface({input:generator.stdout})[Symbol.asyncIterator]();
let chain;
try {
  const first=await lines.next();assert.equal(first.done,false,'Synthetic fixture generator failed');
  const {syntheticRoot}=JSON.parse(first.value);
  const sources={};
  for(const name of ['MateCatalogBudget.sol','MateAgeGate.sol']) sources[name]={content:fs.readFileSync(path.join(root,'contracts/src',name),'utf8')};
  sources['Token.sol']={content:fs.readFileSync(path.join(root,'contracts/test/SharedBudgetTestToken.sol'),'utf8')};
  sources['Verifier.sol']={content:fs.readFileSync(path.join(base,'Verifier.sol'),'utf8')};
  sources['SyntheticGate.sol']={content:`// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;import "./MateAgeGate.sol";
contract SyntheticCatalogAgeGate is MateAgeGate {
 constructor(address verifier,bytes32 hash) MateAgeGate(verifier,hash) {}
 function _rootValid(bytes32 h,uint256 start,uint256 end) internal pure override returns(bool) {
  return h==${syntheticRoot} && start>=1735689600 && end<=1893456000;
 }
}`};
  const compiled=JSON.parse(solc.compile(JSON.stringify({language:'Solidity',sources,
    settings:{viaIR:true,optimizer:{enabled:true,runs:200},evmVersion:'cancun',outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}}),{
    import:name=>({contents:fs.readFileSync(path.join(root,'node_modules',name),'utf8')})}));
  assert.deepEqual((compiled.errors??[]).filter(e=>e.severity==='error'),[]);
  const artifact=(file,name)=>compiled.contracts[file][name];
  const reservation=createServer();await new Promise(resolve=>reservation.listen(0,'127.0.0.1',resolve));
  const port=reservation.address().port;await new Promise(resolve=>reservation.close(resolve));
  chain=spawn('anvil',['--host','127.0.0.1','--port',String(port),'--chain-id','31337','--silent'],{stdio:'ignore'});
  let startError;chain.on('error',e=>{startError=e;});
  const transport=http(`http://127.0.0.1:${port}`,{timeout:3000,retryCount:0});
  const client=createPublicClient({chain:foundry,transport,pollingInterval:30});
  const actors=Array.from({length:3},(_,addressIndex)=>mnemonicToAccount('test test test test test test test test test test test junk',{addressIndex}));
  const [owner,agent,merchant]=actors;
  const wallet=createWalletClient({chain:foundry,transport,account:owner});
  let ready=false;
  for(let i=0;i<100;i++) {
    if(startError)throw startError;assert.equal(chain.exitCode,null);
    try {assert.equal(await client.getChainId(),31337);ready=true;break;}catch {await new Promise(resolve=>setTimeout(resolve,100));}
  }
  assert.ok(ready,'Own local Anvil must start');
  await client.request({method:'evm_setNextBlockTimestamp',params:[1800000000]});await client.request({method:'evm_mine'});
  async function send(address,a,name,args) {
    const {request}=await client.simulateContract({address,abi:a.abi,functionName:name,args,account:owner});
    const r=await client.waitForTransactionReceipt({hash:await wallet.writeContract(request)});assert.equal(r.status,'success');return r;
  }
  const read=(address,a,functionName,args=[])=>client.readContract({address,abi:a.abi,functionName,args});
  async function deploy(a,args=[]) {
    const r=await client.waitForTransactionReceipt({hash:await wallet.deployContract({abi:a.abi,bytecode:'0x'+a.evm.bytecode.object,args})});
    assert.equal(r.status,'success');return r.contractAddress;
  }
  const verifier=await deploy(artifact('Verifier.sol','ProvekitGroth16Verifier'));
  const verifierHash=keccak256(await client.getCode({address:verifier}));
  const gateA=artifact('MateAgeGate.sol','MateAgeGate');
  const officialGate=await deploy(gateA,[verifier,verifierHash]);
  const gate=await deploy(artifact('SyntheticGate.sol','SyntheticCatalogAgeGate'),[verifier,verifierHash]);
  const tokenA=artifact('Token.sol','SharedBudgetTestToken'),token=await deploy(tokenA);
  const budgetA=artifact('MateCatalogBudget.sol','MateCatalogBudget');
  const current=(await client.getBlock()).timestamp;
  const budget=await deploy(budgetA,[token,gate,keccak256(await client.getCode({address:gate})),[agent.address],[merchant.address],
    {total:200000n,perPurchase:100000n,purchases:2,expiresAt:current+3600n,products:3}]);
  await send(token,tokenA,'mint',[budget,1000000n]);
  const referenceTime=(await client.getBlock()).timestamp;
  const nonce=()=>`0x${randomBytes(32).toString('hex')}`;
  const order={id:nonce(),product:1,quantity:1,merchant:merchant.address,expiresAt:referenceTime+900n,paymentNonce:nonce()};
  const orderHash=await read(budget,budgetA,'orderHash',[order]);
  generator.stdin.end(JSON.stringify({chainId:31337,orderHash,nonce:order.paymentNonce,referenceTime:String(referenceTime),expiresAt:String(order.expiresAt)})+'\n');
  assert.equal((await lines.next()).value,'synthetic witness ready');assert.equal((await generatorExit)[0],0);
  const start=performance.now();
  const env={...process.env,RAYON_NUM_THREADS:'2'};
  await run(cli,['prove','--prover',path.join(base,'age.pkp'),'--input',path.join(out,'input.toml'),'--out',path.join(out,'proof.np')],{env,timeout:300000,maxBuffer:2000000});
  const proveMs=Math.round(performance.now()-start);
  await run(cli,['verify','--verifier',path.join(base,'age.pkv'),'--proof',path.join(out,'proof.np')],{env,timeout:60000});
  await run(cli,['export-evm-proof','--proof',path.join(out,'proof.np'),'--out-dir',path.join(out,'evm')],{env,timeout:60000});
  const proof=fs.readFileSync(path.join(out,'evm/proof.hex'),'utf8').trim();
  const inputs=fs.readFileSync(path.join(out,'evm/inputs.txt'),'utf8').trim().split(/\s+/).map(BigInt);
  assert.equal(await read(officialGate,gateA,'verifyOrderAge',[orderHash,order.paymentNonce,order.expiresAt,proof,inputs]),false,'Production roots MUST reject the synthetic issuer');
  assert.equal(await read(gate,gateA,'verifyOrderAge',[orderHash,order.paymentNonce,order.expiresAt,proof,inputs]),true,'Actual proof under explicit synthetic test trust');
  const domain={name:'ZeroKey Mate Catalogue Budget',version:'1',chainId:31337,verifyingContract:budget};
  async function signed(o,p=proof) {
    const h=await read(budget,budgetA,'orderHash',[o]);
    const quote=await merchant.signTypedData({domain,primaryType:'Quote',types:{Quote:[{name:'orderHash',type:'bytes32'}]},message:{orderHash:h}});
    const authorization=await agent.signTypedData({domain,primaryType:'Purchase',types:{Purchase:[{name:'agent',type:'address'},{name:'orderHash',type:'bytes32'}]},message:{agent:agent.address,orderHash:h}});
    return[o,agent.address,authorization,quote,p,inputs];
  }
  const damaged='0x'+(parseInt(proof.slice(2,4),16)^1).toString(16).padStart(2,'0')+proof.slice(4);
  for(const args of [await signed(order,damaged),await signed({...order,id:nonce(),paymentNonce:nonce()})]) {
    await assert.rejects(()=>send(budget,budgetA,'execute',args),/AgeNotVerified/);
    assert.equal(await read(budget,budgetA,'spent'),0n);assert.equal(await read(budget,budgetA,'purchaseCount'),0);
  }
  const args=await signed(order);const receipt=await send(budget,budgetA,'execute',args);
  assert.equal(await read(token,tokenA,'balanceOf',[merchant.address]),100000n);
  assert.equal(await read(budget,budgetA,'spent'),100000n);assert.equal(await read(budget,budgetA,'purchaseCount'),1);
  await assert.rejects(()=>send(budget,budgetA,'execute',args),/OrderReplayed/);
  const result={scope:'LOCAL ONLY; real proof, synthetic issuer and test token',productionRejectsSyntheticIssuer:true,
    tamperedProofRejected:true,wrongOrderRejected:true,replayRejected:true,amount:'100000',spent:'100000',purchaseCount:1,
    proveMs,atomicPurchaseGas:String(receipt.gasUsed),localTransaction:receipt.transactionHash};
  fs.writeFileSync(path.join(out,'result.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
} finally {generator.stdin.destroy();generator.kill('SIGTERM');chain?.kill('SIGTERM');}
