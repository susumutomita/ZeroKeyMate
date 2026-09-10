import {test} from 'node:test';
import assert from 'node:assert/strict';
import {encodeEventTopics,encodeAbiParameters,decodeFunctionData,verifyTypedData} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';
import {Journal} from '../journal.mjs';
import {ProductError} from '../errors.mjs';
import {REGISTRY,registrationABI,registrationConfiguration,registerProvider} from '../provider-registration.mjs';
const owner=privateKeyToAccount('0x'+'11'.repeat(32)),recipient=privateKeyToAccount('0x'+'22'.repeat(32));
function fixture(separate=false) {
  const config=registrationConfiguration({PROVIDER_RECIPIENT:separate?recipient.address:owner.address,PROVIDER_PUBLIC_URL:'https://specialist.example.com'},owner.address);
  const journal=new Journal(':memory:','ab'.repeat(32)),transactions=new Map(),calls=[];
  let uri='',wallet=owner.address,loseMetadata=true,revertWallet=false,loseWallet=false;
  const hash='0x'+'aa'.repeat(32);
  const client={getChainId:async()=>11155111,getCode:async()=> '0x01',getBlock:async()=>({timestamp:1000n}),verifyTypedData,
    getTransactionReceipt:async()=>({status:'success',transactionHash:hash,logs:[{address:REGISTRY,
      topics:encodeEventTopics({abi:registrationABI,eventName:'Registered',args:{agentId:42n,owner:owner.address}}),
      data:encodeAbiParameters([{type:'string'}],[''])}]}),
    readContract:async({functionName})=>functionName==='ownerOf'?owner.address:functionName==='getAgentWallet'?wallet:uri};
  const lane={address:owner.address,send:async(operation,request)=>{
    if(transactions.has(operation)){assert.deepEqual(request,transactions.get(operation));return {hash};}
    const decoded=decodeFunctionData({abi:registrationABI,data:request.data});
    if(decoded.functionName==='setAgentWallet' && revertWallet){revertWallet=false;throw new ProductError('transaction_reverted','fixture revert');}
    transactions.set(operation,request);calls.push(decoded.functionName);
    if(decoded.functionName==='setAgentURI') {uri=decoded.args[1];if(loseMetadata){loseMetadata=false;throw new Error('fixture lost response');}}
    if(decoded.functionName==='setAgentWallet'){wallet=decoded.args[1];if(loseWallet){loseWallet=false;throw new Error('fixture wallet response lost');}}
    return {hash};
  }};
  return {config,journal,client,lane,calls,recipientSigner:separate?recipient:owner,setRevert:()=>{revertWallet=true;},setLoseWallet:()=>{loseWallet=true;}};
}
test('registration resumes identical transactions after a lost response and verifies public metadata',async()=>{
  const f=fixture();
  try {
    await assert.rejects(registerProvider(f),/fixture lost response/);
    const result=await registerProvider(f);
    assert.equal(result.id,'11155111:42');assert.equal(result.indexing,'not-verified');
    assert.deepEqual(f.calls,['register','setAgentURI']);
    const uri=await f.client.readContract({functionName:'tokenURI'});
    const document=JSON.parse(Buffer.from(uri.split(',')[1],'base64'));
    assert.equal(document.registrations[0].agentId,42);assert.equal(document.services[0].endpoint,f.config.endpoint);
    assert.deepEqual(document.supportedTrust,[]);
    await assert.rejects(registerProvider({...f,config:{...f.config,endpoint:'https://other.example.com'}}),{code:'registration_changed'});
    assert.equal(f.calls.length,2);
  }finally{f.journal.close();}
});
test('a separate payout wallet signs the domain-bound authorization; unknown work cannot be renewed',async()=>{
  const f=fixture(true);
  try {
    await assert.rejects(registerProvider({...f,recipientSigner:owner}),{code:'registration_wallet'});assert.equal(f.calls.length,0);
    await assert.rejects(registerProvider(f),/fixture lost response/);
    const stored=f.journal.get('registration-wallet');assert.equal(stored.state,'confirmed');assert.equal(stored.value.deadline,1240);
    await assert.rejects(registerProvider({...f,renewWalletAuthorization:true}),{code:'registration_wallet_pending'});
    assert.equal((await registerProvider(f)).recipient,recipient.address);
    assert.deepEqual(f.calls,['register','setAgentWallet','setAgentURI']);
  }finally{f.journal.close();}
});
test('confirmed wallet reverts require explicit renewal without minting another identity',async()=>{
  const f=fixture(true);f.setRevert();
  try {
    await assert.rejects(registerProvider(f),{code:'transaction_reverted'});
    await assert.rejects(registerProvider(f),{code:'registration_wallet_expired'});
    await assert.rejects(registerProvider({...f,renewWalletAuthorization:true}),/fixture lost response/);
    assert.equal((await registerProvider(f)).id,'11155111:42');
    assert.equal(f.calls.filter(call=>call==='register').length,1);
    assert.equal(f.journal.get('registration-wallet').value.attempt,2);
  }finally{f.journal.close();}
});
test('public registration input excludes credential-bearing endpoint URLs',()=>{
  for(const endpoint of ['https://user:secret@example.com','https://example.com?token=secret','http://example.com'])
    assert.throws(()=>registrationConfiguration({PROVIDER_RECIPIENT:owner.address,PROVIDER_PUBLIC_URL:endpoint},owner.address));
});

test('an unknown wallet outcome reuses its signature and cannot create a renewal',async()=>{
  const f=fixture(true);f.setLoseWallet();
  try {
    await assert.rejects(registerProvider(f),/fixture wallet response lost/);
    assert.equal(f.journal.get('registration-wallet').state,'prepared');
    const signature=f.journal.get('registration-wallet').value.signature;
    await assert.rejects(registerProvider({...f,renewWalletAuthorization:true}),{code:'registration_wallet_pending'});
    await assert.rejects(registerProvider(f),/fixture lost response/);
    assert.equal(f.journal.get('registration-wallet').value.signature,signature);
    assert.equal((await registerProvider(f)).recipient,recipient.address);
    assert.equal(f.calls.filter(call=>call==='setAgentWallet').length,1);
  }finally{f.journal.close();}
});
test('wrong network and unexpected receipt owner stop before subsequent transactions',async()=>{
  const f=fixture();
  try {
    await assert.rejects(registerProvider({...f,client:{...f.client,getChainId:async()=>5042002}}),{code:'registration_chain'});
    assert.equal(f.calls.length,0);
    await assert.rejects(registerProvider({...f,client:{...f.client,getTransactionReceipt:async()=>({status:'success',transactionHash:'0x'+'aa'.repeat(32),logs:[]})}}),{code:'registration_event'});
    assert.deepEqual(f.calls,['register']);
  }finally{f.journal.close();}
});

test('CLI defaults to a public preview and never prints configured private material',async()=>{
  const {execFileSync}=await import('node:child_process');
  const key='0x'+'11'.repeat(32),secret='private-journal-fixture';
  const output=execFileSync(process.execPath,['scripts/register-provider.mjs'],{encoding:'utf8',env:{
    PROVIDER_REGISTRATION_PRIVATE_KEY:key,PROVIDER_RECIPIENT:owner.address,PROVIDER_PUBLIC_URL:'https://specialist.example.com',MATE_JOURNAL_KEY:secret,
  }});
  assert.match(output,/preview-only/);assert.match(output,/No transaction signed or sent/);
  assert.equal(output.includes(key),false);assert.equal(output.includes(secret),false);
});
