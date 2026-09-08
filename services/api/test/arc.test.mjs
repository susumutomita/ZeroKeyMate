import {test} from 'node:test';
import assert from 'node:assert/strict';
import {verifyTypedData} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';
import {networkConfiguration,settlementNetwork,stateDirectory} from '../networks.mjs';
import {Discovery} from '../discovery.mjs';
import {CircleAttestor} from '../circle-attestor.mjs';
import {domain,proofTypes} from '../protocol.mjs';
const vault='0x'+'11'.repeat(20),recipient='0x'+'22'.repeat(20),owner='0x'+'33'.repeat(20);
const token=settlementNetwork(5042002).token;

test('Arc is explicit, USDC accounting stays at the ERC20 address, and old Sepolia configuration stays recoverable',()=>{
  assert.equal(networkConfiguration({}).chainId,5042002);
  assert.equal(networkConfiguration({SEPOLIA_RPC_URL:'https://example.com'}).chainId,11155111);
  assert.equal(networkConfiguration({MATE_CHAIN_ID:'5042002'}).token,token);
  assert.notEqual(stateDirectory('api',{MATE_CHAIN_ID:'5042002'}),stateDirectory('api',{MATE_CHAIN_ID:'11155111'}));
  assert.throws(()=>settlementNetwork(1),{code:'wrong_chain'});
});

test('Graph discovery requires the indexed recipient and the quote to bind the real settlement deployment',async()=>{
  // Explicit transport fixture; this is not live Graph acceptance.
  const provider={id:'11155111:7',owner,recipient,ensName:'',service:0,price:'100000',endpoint:'https://provider.example',bearerToken:'x'.repeat(32)};
  let indexed={id:provider.id,chainId:11155111,owner,agentWallet:recipient,totalFeedback:'4',registrationFile:{active:true,name:'Translator',webEndpoint:provider.endpoint}};
  let quote={chainId:5042002,vault,token,service:0,price:'100000',recipient,expiresAt:Math.floor(Date.now()/1000)+120,ready:true};
  const discovery=new Discovery({chainId:5042002,vault,token,graphApiKey:'fixture',graphSubgraphId:'fixture',providers:[provider]},null,
    async url=>String(url).startsWith('https://gateway.thegraph.com/')?{data:{agents:[indexed],_meta:{block:{number:123},hasIndexingErrors:false}}}:quote);
  assert.equal((await discovery.list(0)).providers.length,1);
  for(const change of [{chainId:11155111},{vault:owner},{token:recipient},{recipient:owner},{price:'999'},{expiresAt:0}]) {
    const saved=quote;quote={...saved,...change};assert.equal((await discovery.list(0)).providers.length,0);quote=saved;
  }
  indexed={...indexed,agentWallet:owner};assert.equal((await discovery.list(0)).providers.length,0);
});

test('Circle adapter signs only proof approval hashes and rejects local-wallet substitution',async()=>{
  // CLI transport fixture with a real secp256k1 signer, not a fabricated verifier.
  const account=privateKeyToAccount('0x'+'12'.repeat(32));
  let sent,local=false;
  const adapter=new CircleAttestor({walletAddress:account.address,vault,chainId:5042002},async(_command,args)=>{
    if(args[1]==='list')return {stdout:JSON.stringify({data:{wallets:[{type:local?'local':'agent',blockchain:'ARC-TESTNET',address:account.address}]}})};
    sent=JSON.parse(args[3]);return {stdout:JSON.stringify({data:{signature:await account.signTypedData(sent)}})};
  });
  await adapter.prepare();
  const document={domain:domain(5042002,vault),types:proofTypes,primaryType:'ProofApproval',message:{actionHash:'0x'+'44'.repeat(32),proofHash:'0x'+'55'.repeat(32)}};
  const signature=await adapter.signTypedData({...document,privatePolicy:'must not leave',domain:{...document.domain,budget:'secret'},message:{...document.message,salt:'secret'}});
  assert.equal(await verifyTypedData({...document,address:account.address,signature}),true);
  assert.equal(JSON.stringify(sent).includes('secret'),false);
  await assert.rejects(adapter.signTypedData({...document,domain:domain(11155111,vault)}),{code:'circle_scope'});
  await assert.rejects(adapter.signTypedData({...document,primaryType:'Grant'}),{code:'circle_scope'});
  local=true;await assert.rejects(adapter.prepare(),{code:'circle_wallet'});
});
