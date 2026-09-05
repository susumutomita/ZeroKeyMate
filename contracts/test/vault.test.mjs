import {after, before, test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import {createPublicClient, createWalletClient, http, hashTypedData, decodeEventLog, parseAbi} from 'viem';
import {foundry} from 'viem/chains';
import {mnemonicToAccount} from 'viem/accounts';
import {actionDigest,contractAction,domain,grantTypes,executionTypes,proofTypes,newNonce,sha256} from '../../services/api/protocol.mjs';

// Public Anvil development accounts. NEVER used outside this loopback test chain.
const phrase = 'test test test test test test test test test test test junk';
const accounts = Array.from({length:5},(_,addressIndex)=>mnemonicToAccount(phrase,{addressIndex}));
const [owner,agent,attestor,attacker,recipient] = accounts;
const rpc='http://127.0.0.1:8547';
const publicClient=createPublicClient({chain:foundry,transport:http(rpc)});
const wallets=accounts.map(account=>createWalletClient({account,chain:foundry,transport:http(rpc)}));
const tokenArtifact=JSON.parse(fs.readFileSync(new URL('../../.build/contracts/TestToken.json',import.meta.url),'utf8'));
const vaultArtifact=JSON.parse(fs.readFileSync(new URL('../../.build/contracts/MateVault.json',import.meta.url),'utf8'));
let anvil;
let processError;

before(async()=>{
  anvil=spawn('anvil',['--port','8547','--chain-id','31337','--silent'],{stdio:'ignore'});
  anvil.on('error',error=>{processError=error;});
  const deadline=Date.now()+20_000;
  while(Date.now()<deadline){
    if(processError) throw processError;
    try {assert.equal(await publicClient.getChainId(),31337);return;} catch {await new Promise(r=>setTimeout(r,150));}
  }
  throw new Error('Anvil did not start');
});
after(()=>{anvil?.kill('SIGTERM');});

async function mined(hash){
  const receipt=await publicClient.waitForTransactionReceipt({hash});
  assert.equal(receipt.status,'success'); return receipt;
}
async function read(vault,name,args=[]){return publicClient.readContract({address:vault,abi:vaultArtifact.abi,functionName:name,args});}
async function call(vault,name,args=[],wallet=wallets[0]){
  const {request}=await publicClient.simulateContract({address:vault,abi:vaultArtifact.abi,functionName:name,args,account:wallet.account});
  return mined(await wallet.writeContract(request));
}
async function rejects(vault,name,args,errorName,wallet=wallets[0]){
  await assert.rejects(()=>call(vault,name,args,wallet),error=>{
    assert.match(error.message,new RegExp(errorName));return true;
  });
}
async function fixture(){
  const tokenReceipt=await mined(await wallets[0].deployContract({abi:tokenArtifact.abi,bytecode:tokenArtifact.bytecode}));
  const token=tokenReceipt.contractAddress; assert.ok(token);
  const vaultReceipt=await mined(await wallets[0].deployContract({abi:vaultArtifact.abi,bytecode:vaultArtifact.bytecode,args:[token,attestor.address]}));
  const vault=vaultReceipt.contractAddress;assert.ok(vault);
  await mined(await wallets[0].writeContract({address:token,abi:tokenArtifact.abi,functionName:'mint',args:[owner.address,20_000_000n]}));
  await mined(await wallets[0].writeContract({address:token,abi:tokenArtifact.abi,functionName:'approve',args:[vault,20_000_000n]}));
  await call(vault,'deposit',[20_000_000n]);
  const block=await publicClient.getBlock();
  const grant={owner:owner.address,agent:agent.address,policyHash:sha256('public unit-test commitment'),validUntil:block.timestamp+3600n,nonce:0n};
  const d=domain(31337,vault);
  const sig=await owner.signTypedData({domain:d,types:grantTypes,primaryType:'Grant',message:grant});
  const id=hashTypedData({domain:d,types:grantTypes,primaryType:'Grant',message:grant});
  await call(vault,'register',[grant,sig],wallets[3]);
  const action={mandateId:id,recipient:recipient.address,amount:'3000000',service:0,nonce:newNonce(),
    expiresAt:Number(block.timestamp)+300,requestHash:sha256('approved disclosure'),spentBefore:'0'};
  return {token,vault,grant,grantSignature:sig,id,action,d};
}
async function signatures(f,action=f.action,signer=agent){
  const actionHash=actionDigest(31337,f.vault,action);
  // This test exercises the attestation trust boundary, not a fake ZK verifier.
  // Real cryptographic proofs are exercised by the separate acceptance job.
  const proofHash=sha256('public contract-test attestation bytes');
  const agentSignature=await signer.signTypedData({domain:f.d,types:executionTypes,primaryType:'Execution',message:{actionHash}});
  const approval=await attestor.signTypedData({domain:f.d,types:proofTypes,primaryType:'ProofApproval',message:{actionHash,proofHash}});
  return [contractAction(action),proofHash,agentSignature,approval];
}

test('real contract execution transfers tokens and records the exact action',async()=>{
  const f=await fixture();
  assert.equal(await read(f.vault,'actionHash',[contractAction(f.action)]),actionDigest(31337,f.vault,f.action));
  const receipt=await call(f.vault,'execute',await signatures(f),wallets[3]);
  assert.equal(await read(f.vault,'balances',[owner.address]),17_000_000n);
  const balance=await publicClient.readContract({address:f.token,abi:tokenArtifact.abi,functionName:'balanceOf',args:[recipient.address]});
  assert.equal(balance,3_000_000n);
  const events=receipt.logs.flatMap(log=>{try{return [decodeEventLog({abi:vaultArtifact.abi,...log})];}catch{return [];}});
  const event=events.find(e=>e.eventName==='Executed');assert.ok(event);
  assert.equal(event.args.spentAfter,3_000_000n);
});
test('an already consumed action cannot spend twice',async()=>{
  const f=await fixture();const args=await signatures(f);
  await call(f.vault,'execute',args);
  await rejects(f.vault,'execute',args,'InvalidNonce');
  assert.equal(await read(f.vault,'balances',[owner.address]),17_000_000n);
});
test('parallel agents cannot reuse an old spend snapshot',async()=>{
  const f=await fixture();const a=await signatures(f);const b=await signatures(f,{...f.action,nonce:newNonce()});
  await call(f.vault,'execute',a);
  await rejects(f.vault,'execute',b,'StaleSpendState');
});
test('recipient, payload, amount and nonce substitution invalidate the agent signature',async()=>{
  const f=await fixture();const args=await signatures(f);
  for(const changes of [{recipient:attacker.address},{requestHash:sha256('changed')},{amount:'1'},{nonce:newNonce()}]) {
    await rejects(f.vault,'execute',[contractAction({...f.action,...changes}),...args.slice(1)],'InvalidAgentSignature');
  }
});
test('proof hash substitution and forged verifier signature are rejected',async()=>{
  const f=await fixture();const args=await signatures(f);
  await rejects(f.vault,'execute',[args[0],sha256('different proof'),args[2],args[3]],'InvalidProofApproval');
  await rejects(f.vault,'execute',[args[0],args[1],args[2],'0x1234'],'InvalidProofApproval');
});
test('another agent key cannot spend',async()=>{
  const f=await fixture();await rejects(f.vault,'execute',await signatures(f,f.action,attacker),'InvalidAgentSignature');
});
test('only owner can revoke and a revoked mandate cannot execute',async()=>{
  const f=await fixture();const args=await signatures(f);
  await rejects(f.vault,'revoke',[f.id],'Unauthorized',wallets[3]);
  await call(f.vault,'revoke',[f.id]);
  await rejects(f.vault,'execute',args,'Revoked');
});
test('expired action is rejected even when all signatures are otherwise valid',async()=>{
  const f=await fixture();const args=await signatures(f);
  await publicClient.request({method:'evm_increaseTime',params:[301]});
  await publicClient.request({method:'evm_mine'});
  await rejects(f.vault,'execute',args,'Expired');
});
test('owner grant signature cannot be replayed or replaced',async()=>{
  const f=await fixture();
  await rejects(f.vault,'register',[f.grant,f.grantSignature],'InvalidNonce');
  const next={...f.grant,nonce:1n};
  const fake=await attacker.signTypedData({domain:f.d,types:grantTypes,primaryType:'Grant',message:next});
  await rejects(f.vault,'register',[next,fake],'InvalidOwnerSignature');
  assert.equal(await read(f.vault,'ownerNonces',[owner.address]),1n);
});
test('owner funds stay isolated and can be withdrawn without the attestor',async()=>{
  const f=await fixture();
  await rejects(f.vault,'withdraw',[1n],'InsufficientBalance',wallets[3]);
  await call(f.vault,'withdraw',[20_000_000n]);
  assert.equal(await read(f.vault,'balances',[owner.address]),0n);
  await rejects(f.vault,'execute',await signatures(f),'InsufficientBalance');
});
test('signatures from a different EIP-712 domain cannot be transplanted',async()=>{
  const f=await fixture();const args=await signatures(f);
  const actionHash=actionDigest(31337,f.vault,f.action);
  args[2]=await agent.signTypedData({domain:{...f.d,chainId:1},types:executionTypes,primaryType:'Execution',message:{actionHash}});
  await rejects(f.vault,'execute',args,'InvalidAgentSignature');
});
