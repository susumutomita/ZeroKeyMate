import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import {spawn,execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createPublicClient,createWalletClient,http,toHex} from 'viem';
import {sepolia} from 'viem/chains';
import {mnemonicToAccount} from 'viem/accounts';
import {ROOT} from '../config.mjs';
import {Chain} from '../chain.mjs';
import {Journal} from '../journal.mjs';
import {ProofVerifier} from '../verifier.mjs';
import {Executor} from '../executor.mjs';
import {Discovery} from '../discovery.mjs';
import {jsonServer} from '../http.mjs';
import {apiHandler} from '../server.mjs';
import {Specialist,providerHandler} from '../../provider/server.mjs';
import {SpecialistModel} from '../../provider/model.mjs';
import {sha256,u64,domain,grantTypes,executionTypes,actionDigest,actionPreimage,newNonce} from '../protocol.mjs';

// Local payment SIMULATION. These are Anvil's published test accounts.
// Proof, signatures, vault execution, HTTP and journal recovery are real.
// Discovery is an explicit fixture; this is never live Graph/ENS/Sepolia acceptance.
// The default model is also a fixture. An explicitly selected, already installed
// local Ollama model can be evaluated without downloading weights or a fallback.
const modelName=process.env.MATE_TEST_OLLAMA_MODEL;
test(`local payment simulation: real proof → HTTP API → vault → HTTP specialist (${modelName?'actual Ollama':'model fixture'}), without duplicate spend`,async t=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'mate-local-acceptance-'));
  t.after(()=>fs.rmSync(directory,{recursive:true,force:true}));
  const reservation=net.createServer();
  await new Promise(resolve=>reservation.listen(0,'127.0.0.1',resolve));
  const port=reservation.address().port;await new Promise(resolve=>reservation.close(resolve));
  const child=spawn('anvil',['--port',String(port),'--chain-id','11155111','--block-time','1','--silent'],{stdio:'ignore'});
  let childError;child.on('error',error=>{childError=error;});t.after(()=>child.kill('SIGTERM'));
  const rpcURL=`http://127.0.0.1:${port}`;
  const client=createPublicClient({chain:sepolia,transport:http(rpcURL,{retryCount:0}),pollingInterval:100});
  const deadline=Date.now()+15_000;
  while(true){
    if(childError)throw childError;
    if(child.exitCode!==null)throw new Error('Local Anvil failed to start');
    try{assert.equal(await client.getChainId(),11155111);break;}catch(error){if(Date.now()>deadline)throw error;}
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  const accounts=Array.from({length:5},(_,addressIndex)=>mnemonicToAccount('test test test test test test test test test test test junk',{addressIndex}));
  const [owner,agent,attestor,relayer,recipient]=accounts;
  const wallet=createWalletClient({account:owner,chain:sepolia,transport:http(rpcURL)});
  const mined=async hash=>{
    const receipt=await client.waitForTransactionReceipt({hash,timeout:20_000,pollingInterval:100});
    assert.equal(receipt.status,'success');return receipt;
  };
  const artifact=name=>JSON.parse(fs.readFileSync(path.join(ROOT,'.build/contracts',`${name}.json`),'utf8'));
  const tokenArtifact=artifact('TestToken'),vaultArtifact=artifact('MateVault');
  const token=(await mined(await wallet.deployContract({abi:tokenArtifact.abi,bytecode:tokenArtifact.bytecode}))).contractAddress;
  const vault=(await mined(await wallet.deployContract({abi:vaultArtifact.abi,bytecode:vaultArtifact.bytecode,args:[token,attestor.address]}))).contractAddress;
  for(const [address,abi,functionName,args] of [
    [token,tokenArtifact.abi,'mint',[owner.address,10_000_000n]],
    [token,tokenArtifact.abi,'approve',[vault,10_000_000n]],
    [vault,vaultArtifact.abi,'deposit',[10_000_000n]],
  ])await mined(await wallet.writeContract({address,abi,functionName,args}));
  let journal=new Journal(path.join(directory,'api.sqlite'),'ab'.repeat(32));t.after(()=>journal.close());
  const providerJournal=new Journal(path.join(directory,'provider.sqlite'),'cd'.repeat(32));t.after(()=>providerJournal.close());
  const config={rpcURL,vault,token,attestorKey:toHex(attestor.getHdKey().privateKey),relayerKey:toHex(relayer.getHdKey().privateKey)};
  const chain=new Chain(config,journal);await chain.prepare();
  const providerChain=new Chain({rpcURL,vault,token,attestorAddress:attestor.address},providerJournal);await providerChain.prepare();
  const modelURL=process.env.MATE_TEST_OLLAMA_URL||'http://127.0.0.1:11434';
  if(modelName) {
    const url=new URL(modelURL);
    assert.equal(url.protocol,'http:');
    assert.ok(['127.0.0.1','[::1]'].includes(url.hostname),'Model evaluation must stay on loopback');
    assert.equal(url.username+url.password+url.search+url.hash,'');
  }
  const model=modelName?new SpecialistModel({model:modelName,modelURL}):{
    ready:async()=>{},run:async(_service,text)=>`LOCAL TEST FIXTURE: ${text}`,
  };
  let modelCalls=0;
  const specialist=new Specialist({config:{vault,service:0,price:'100000',recipient:recipient.address},chain:providerChain,journal:providerJournal,
    model:{ready:()=>model.ready(),run:async(...args)=>{modelCalls++;return model.run(...args);}}});
  const specialistToken='f'.repeat(64);
  const providerServer=jsonServer({token:specialistToken,handler:providerHandler(specialist)});
  await new Promise(resolve=>providerServer.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>providerServer.close(resolve)));
  const provider={id:'11155111:1',endpoint:`http://127.0.0.1:${providerServer.address().port}`,bearerToken:specialistToken};
  assert.equal((await fetch(provider.endpoint+'/v1/quote?service=0')).status,401);
  const transport=new Discovery({},{});
  const quote=await transport.call(provider,'/v1/quote?service=0');
  assert.equal(quote.ready,true);assert.equal(quote.price,'100000');
  const discovery={
    choose:async()=>({provider,indexedBlock:'local-fixture-not-The-Graph'}),
    call:(...args)=>transport.call(...args),
  };
  const verifier=new ProofVerifier({binary:path.join(ROOT,'services/verifier/target/release/mate-verify'),
    verifier:path.join(ROOT,'.build/proofs/mate_policy.pkv'),manifest:path.join(ROOT,'.build/proofs/manifest.json')});
  const executor=new Executor({config,chain,journal,verifier,discovery});
  const pairing='e'.repeat(64);
  let server=jsonServer({token:pairing,handler:apiHandler({chain,executor,discovery,names:{}})});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  let base=`http://127.0.0.1:${server.address().port}`;
  const post=async(route,body)=>{
    const response=await fetch(base+route,{method:'POST',headers:{authorization:`Bearer ${pairing}`,'content-type':'application/json'},body:JSON.stringify(body)});
    return {status:response.status,body:await response.json()};
  };
  const budget=5_000_000n,salt=Buffer.from(Array.from({length:32},(_,i)=>i)),services=3;
  const policyHash=sha256(Buffer.concat([Buffer.from('ZKM-POL1'),u64(budget),Buffer.from([services]),salt]));
  const grant={owner:owner.address,agent:agent.address,policyHash,validUntil:Math.floor(Date.now()/1000)+3600,nonce:'0'};
  const signature=await owner.signTypedData({domain:domain(11155111,vault),types:grantTypes,primaryType:'Grant',message:{...grant,validUntil:BigInt(grant.validUntil),nonce:0n}});
  const registered=await post('/v1/grants',{grant,signature});assert.equal(registered.status,200,JSON.stringify(registered.body));
  const payload=modelName?'おはようございます。今日の会議は午前10時に始まります。':'Explicit local test disclosure';
  const action={mandateId:registered.body.mandateId,recipient:recipient.address,amount:'100000',service:0,nonce:newNonce(),
    expiresAt:Math.floor(Date.now()/1000)+300,requestHash:sha256(payload),spentBefore:'0'};
  const hash=actionDigest(11155111,vault,action);
  const witness={policy_hash:[...Buffer.from(policyHash.slice(2),'hex')],action_hash:[...Buffer.from(hash.slice(2),'hex')],
    spent:'0',amount:action.amount,service:'0',budget:String(budget),services:String(services),salt:[...salt],context:[...actionPreimage(11155111,vault,action).subarray(0,160)]};
  const input=path.join(directory,'input.json'),proofFile=path.join(directory,'proof.np');
  fs.writeFileSync(input,JSON.stringify(witness),{mode:0o600});
  await promisify(execFile)(path.join(ROOT,'.tools/bin/provekit-cli'),['prove','--prover',path.join(ROOT,'.build/proofs/mate_policy.pkp'),'--input',input,'--out',proofFile],{timeout:90_000,maxBuffer:4*1024*1024});
  const agentSignature=await agent.signTypedData({domain:domain(11155111,vault),types:executionTypes,primaryType:'Execution',message:{actionHash:hash}});
  const request={action,payload,agentSignature,proof:fs.readFileSync(proofFile).toString('base64'),providerId:'11155111:1'};
  assert.equal((await post('/v1/execute',{...request,payload:'changed'})).status,409);
  const executed=await post('/v1/execute',request);assert.equal(executed.status,200,JSON.stringify(executed.body));
  if(modelName) {
    assert.match(executed.body.result,/meeting/i);assert.match(executed.body.result,/10|ten/i);
    t.diagnostic(`Actual local model response: ${executed.body.result}`);
  } else assert.equal(executed.body.result,`LOCAL TEST FIXTURE: ${payload}`);
  assert.equal(executed.body.spentAfter,'100000');assert.equal(modelCalls,1);
  // Close the HTTP endpoint and SQLite connection, then reconstruct the API
  // from disk. A recovered receipt must not call the model or spend again.
  await new Promise(resolve=>server.close(resolve));journal.close();
  journal=new Journal(path.join(directory,'api.sqlite'),'ab'.repeat(32));
  const recoveredChain=new Chain(config,journal);await recoveredChain.prepare();
  const recoveredExecutor=new Executor({config,chain:recoveredChain,journal,verifier,discovery});
  server=jsonServer({token:pairing,handler:apiHandler({chain:recoveredChain,executor:recoveredExecutor,discovery,names:{}})});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base=`http://127.0.0.1:${server.address().port}`;
  const recovered=await fetch(base+`/v1/receipts?actionHash=${hash}`,{headers:{authorization:`Bearer ${pairing}`}});
  assert.equal(recovered.status,200);assert.deepEqual(await recovered.json(),executed.body);
  const repeated=await post('/v1/execute',request);assert.deepEqual(repeated,executed);
  assert.equal(await chain.read('balances',[owner.address]),9_900_000n);assert.equal(modelCalls,1);
  const altered={...action,nonce:newNonce(),spentBefore:'100000'},alteredHash=actionDigest(11155111,vault,altered);
  const alteredSignature=await agent.signTypedData({domain:domain(11155111,vault),types:executionTypes,primaryType:'Execution',message:{actionHash:alteredHash}});
  assert.equal((await post('/v1/execute',{...request,action:altered,agentSignature:alteredSignature})).status,422);
  assert.equal((await post('/v1/executions/cancel',{actionHash:alteredHash})).status,200);
  assert.equal((await post('/v1/execute',{...request,action:altered,agentSignature:alteredSignature})).status,409);
  assert.equal(await chain.read('balances',[owner.address]),9_900_000n);
});
