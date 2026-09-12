// Real local-EVM acceptance. Inputs are SYNTHETIC; the production gate MUST
// reject the synthetic root. No wallet, mnemonic, .env or external RPC is read.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
import path from 'node:path';
import net from 'node:net';
import solc from 'solc';
import {createPublicClient,createWalletClient,http,keccak256} from 'viem';
import {generatePrivateKey,privateKeyToAccount} from 'viem/accounts';
import {foundry} from 'viem/chains';

const root=path.resolve(import.meta.dirname,'..');
const base=path.resolve(root,process.argv[2]??'.build/age-proof-engine/artifacts');
assert.ok(base.startsWith(path.join(root,'.build')+path.sep),'Use an isolated local test artifact directory');
const proof=readFileSync(path.join(base,'evm/proof.hex'),'utf8').trim();
const inputs=readFileSync(path.join(base,'evm/inputs.txt'),'utf8').trim().split(/\s+/).map(BigInt);
assert.equal(inputs.length,8);
const packed=(hi,lo)=>'0x'+hi.toString(16).padStart(32,'0')+lo.toString(16).padStart(32,'0');
const orderHash=packed(inputs[0],inputs[1]),nonce=packed(inputs[2],inputs[3]),syntheticRoot=packed(inputs[4],inputs[5]);
assert.equal(orderHash,'0x'+'01'.repeat(32),'Only the repository synthetic order is accepted by this test');
assert.equal(nonce,'0x'+'02'.repeat(32));
const verifierSource=readFileSync(path.join(base,'Verifier.sol'),'utf8');
const provenance=JSON.parse(readFileSync(path.join(base,'provenance.json'),'utf8'));
assert.equal(provenance.sameWitnessCommitmentsDiffer,true,'Use the masked prover and regenerate its setup');
assert.equal((verifierSource.match(/uint256\[5\] memory buf/g)??[]).length,3,'Apply the pinned memory-boundary fix');
const sources={
  'Verifier.sol':{content:verifierSource},
  'MateAgeGate.sol':{content:readFileSync(path.join(root,'contracts/src/MateAgeGate.sol'),'utf8')},
  'TestAgeGate.sol':{content:`// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;
import "./MateAgeGate.sol";
// Generated test-only subclass. Never compiled into a product artifact.
contract SyntheticAgeGate is MateAgeGate {
  constructor(address v,bytes32 h) MateAgeGate(v,h) {}
  function _rootValid(bytes32 h,uint256 start,uint256 end) internal pure override returns(bool) {
    return h == ${syntheticRoot} && start >= 1735689600 && end <= 1893456000;
  }
}`},
  'MemoryCheck.sol':{content:`// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./Verifier.sol";
contract MemoryCheck is ProvekitGroth16Verifier {
  function probe() external view returns(bool,uint256) {
    uint256[5] memory buf;
    uint256[1] memory canary;
    uint256 distance;
    assembly ("memory-safe") {mstore(canary,0xfeed) distance := sub(canary,buf)}
    _msmStep(buf,1,2,3);
    uint256 afterValue;
    assembly ("memory-safe") {afterValue := mload(canary)}
    return (afterValue == 0xfeed && buf[0] != 0,distance);
  }
}`}
};
const compiled=JSON.parse(solc.compile(JSON.stringify({language:'Solidity',sources,settings:{optimizer:{enabled:true,runs:200},evmVersion:'cancun',viaIR:true,outputSelection:{'*':{'*':['abi','evm.bytecode.object','evm.deployedBytecode.object']}}}})));
assert.equal((compiled.errors??[]).filter(e=>e.severity==='error').length,0,JSON.stringify(compiled.errors));
const get=(file,name)=>compiled.contracts[file][name];
const verifierArtifact=get('Verifier.sol','ProvekitGroth16Verifier');
assert.ok(verifierArtifact.evm.deployedBytecode.object.length/2<=24576,'EIP-170 code size');
const listener=net.createServer();await new Promise(resolve=>listener.listen(0,'127.0.0.1',resolve));
const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
const url=`http://127.0.0.1:${port}`;
const client=createPublicClient({chain:foundry,transport:http(url,{retryCount:0,timeout:3000})});
const account=privateKeyToAccount(generatePrivateKey()); // Fresh, never persisted.
const wallet=createWalletClient({chain:foundry,transport:http(url),account});
const chain=spawn('anvil',['--host','127.0.0.1','--port',String(port),'--chain-id','31337','--silent'],{stdio:'ignore'});
let startError;chain.on('error',error=>{startError=error;});
try {
  let ready=false;
  for(let i=0;i<80;i++){
    if(startError)throw startError;
    assert.equal(chain.exitCode,null,'Own test chain exited; do not connect to another process');
    try {assert.equal(await client.getChainId(),31337);ready=true;break;}
    catch {await new Promise(resolve=>setTimeout(resolve,100));}
  }
  assert.ok(ready,'Local test chain failed to start');
  await client.request({method:'anvil_setBalance',params:[account.address,'0x56BC75E2D63100000']});
  await client.request({method:'evm_setNextBlockTimestamp',params:[Number(inputs[6])]});
  await client.request({method:'evm_mine',params:[]});
  async function deploy(artifact,args=[]) {
    const hash=await wallet.deployContract({abi:artifact.abi,bytecode:'0x'+artifact.evm.bytecode.object,args});
    const receipt=await client.waitForTransactionReceipt({hash});assert.equal(receipt.status,'success');return receipt.contractAddress;
  }
  const verifier=await deploy(verifierArtifact);
  const codeHash=keccak256(await client.getCode({address:verifier}));
  const gateArtifact=get('MateAgeGate.sol','MateAgeGate');
  const officialGate=await deploy(gateArtifact,[verifier,codeHash]);
  const testGate=await deploy(get('TestAgeGate.sol','SyntheticAgeGate'),[verifier,codeHash]);
  const memoryArtifact=get('MemoryCheck.sol','MemoryCheck'),memory=await deploy(memoryArtifact);
  assert.deepEqual(await client.readContract({address:memory,abi:memoryArtifact.abi,functionName:'probe'}),[true,160n]);
  const verify=(p,v)=>client.simulateContract({address:verifier,abi:verifierArtifact.abi,functionName:'verifyProof',args:[p,v]});
  const gate=(address,p=proof,v=inputs,hash=orderHash,n=nonce,end=inputs[7])=>client.readContract({address,abi:gateArtifact.abi,functionName:'verifyOrderAge',args:[hash,n,end,p,v]});
  await verify(proof,inputs);
  const second=readFileSync(path.join(base,'second-evm/proof.hex'),'utf8').trim();
  assert.notEqual(second.slice(2+256*2,2+320*2),proof.slice(2+256*2,2+320*2));
  await verify(second,inputs);assert.equal(await gate(testGate,second),true);
  const native=process.argv.includes('--native');
  if(native){
    let previous;
    for(const folder of ['native-evm','native-second-evm']){
      const p=readFileSync(path.join(base,folder,'proof.hex'),'utf8').trim();
      const values=readFileSync(path.join(base,folder,'inputs.txt'),'utf8').trim().split(/\s+/).map(BigInt);
      assert.deepEqual(values,inputs);await verify(p,values);assert.equal(await gate(testGate,p,values),true);
      if(previous)assert.notEqual(previous.slice(514,642),p.slice(514,642));previous=p;
    }
  }
  assert.equal(await gate(officialGate),false,'Synthetic credentials must never pass official trust');
  assert.equal(await gate(testGate),true,'Actual proof under explicitly synthetic test-only trust');
  const damaged='0x'+(parseInt(proof.slice(2,4),16)^1).toString(16).padStart(2,'0')+proof.slice(4);
  await assert.rejects(()=>verify(damaged,inputs));assert.equal(await gate(testGate,damaged),false);
  for(let i=0;i<8;i++){const other=inputs.slice();other[i]^=1n;await assert.rejects(()=>verify(proof,other));assert.equal(await gate(testGate,proof,other),false);}
  for(const value of ['0x','0x'+'00'.repeat(384),proof+'00'])assert.equal(await gate(testGate,value),false);
  assert.equal(await gate(testGate,proof,inputs,nonce),false);
  assert.equal(await gate(testGate,proof,inputs,orderHash,orderHash),false);
  assert.equal(await gate(testGate,proof,inputs,orderHash,nonce,inputs[7]+1n),false);
  // Estimate the reverting verifier entry point. Estimating the boolean gate
  // can return an insufficient budget whose caught out-of-gas simply says false.
  const gas=await client.estimateContractGas({address:verifier,abi:verifierArtifact.abi,functionName:'verifyProof',args:[proof,inputs],account:account.address});
  await client.request({method:'evm_setNextBlockTimestamp',params:[Number(inputs[7])]});await client.request({method:'evm_mine',params:[]});
  assert.equal(await gate(testGate),false,'Expiry must remain effective after proof acceptance');
  const result={syntheticOnly:true,chainId:31337,validProofAccepted:true,officialGateRejectedSyntheticRoot:true,
    tamperedProofRejected:true,tamperedPublicInputsRejected:8,orderNonceExpiryBound:true,memoryCanaryIntact:true,sameWitnessCommitmentsDiffer:true,
    proofBytes:(proof.length-2)/2,publicInputs:8,runtimeBytes:verifierArtifact.evm.deployedBytecode.object.length/2,
    estimatedVerifierGas:gas.toString(),nativeFFIAccepted:native,verificationUses:'eth_call; no payment or age transaction',setup:'local single-party prototype, not a production ceremony'};
  writeFileSync(path.join(base,'local-acceptance.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
} finally {chain.kill('SIGTERM');}
