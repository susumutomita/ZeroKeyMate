// SYNTHETIC LOCAL ACCEPTANCE ONLY. No public RPC, credential, wallet, .env or physical card.
// The USDC-shaped contract and synthetic-root subclass exist only in this harness.
import assert from 'node:assert/strict';
import {parseArgs} from 'node:util';
import {loadAgeDeployment,checkAgeDeployment,expectedGateRuntime} from './age-deployment.mjs';
import {readFileSync,writeFileSync,mkdtempSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import net from 'node:net';
import path from 'node:path';
import solc from 'solc';
import {createPublicClient,createWalletClient,http,keccak256} from 'viem';
import {arcTestnet} from 'viem/chains';
import {generatePrivateKey,privateKeyToAccount} from 'viem/accounts';
import {createShop} from '../services/shop/src/worker.mjs';
import {USDC,NETWORK,requirements} from '../services/shop/src/protocol.mjs';
import {createArcSettlement,supportedSettlement} from '../services/shop/src/settlement.mjs';
import {AGE_ABI,ageArguments} from '../services/shop/src/age.mjs';
import {encodePaymentSignatureHeader,decodePaymentRequiredHeader} from '../services/shop/node_modules/@x402/core/dist/esm/http/index.mjs';

const root=path.resolve(import.meta.dirname,'..');
const {values}=parseArgs({options:{'deployment-package':{type:'string'}}});
const pkg=values['deployment-package']?await loadAgeDeployment(values['deployment-package']):null;
const artifacts=path.join(root,'.build/age-proof-engine/artifacts');
assert.equal(JSON.parse(readFileSync(path.join(artifacts,'provenance.json'))).sameWitnessCommitmentsDiffer,true);
const bridge=spawn('python3',[path.join(import.meta.dirname,'shop-synthetic-proof.py')],{stdio:['pipe','pipe','pipe']});
let bridgeError='';bridge.stderr.on('data',data=>{bridgeError=(bridgeError+data.toString()).slice(-4096);});
const lines=createInterface({input:bridge.stdout})[Symbol.asyncIterator]();
const readBridge=async()=>{const line=await lines.next();assert.equal(line.done,false,'Synthetic prover exited: '+bridgeError);return JSON.parse(line.value);};
const {rootKeyHash}=await readBridge();assert.match(rootKeyHash,/^0x[0-9a-f]{64}$/);
const sources={
 'Verifier.sol':{content:readFileSync(path.join(artifacts,'Verifier.sol'),'utf8')},
 'MateAgeGate.sol':{content:readFileSync(path.join(root,'contracts/src/MateAgeGate.sol'),'utf8')},
 'SyntheticGate.sol':{content:`// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;
import "./MateAgeGate.sol";
contract SyntheticGate is MateAgeGate {
 constructor(address v,bytes32 h) MateAgeGate(v,h) {}
 function _rootValid(bytes32 h,uint256 start,uint256 end) internal pure override returns(bool) {
  return h==${rootKeyHash} && start>=1735689600 && end<=1893456000;
 }
}`},
 'SyntheticUSDC.sol':{content:`// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;
// Test-only token. Never compile/deploy this as USDC or into product artifacts.
contract SyntheticUSDC {
 mapping(address=>uint256) public balanceOf;
 mapping(address=>mapping(bytes32=>bool)) public authorizationState;
 event Transfer(address indexed from,address indexed to,uint256 value);
 event AuthorizationUsed(address indexed authorizer,bytes32 indexed nonce);
 function mint(address who,uint256 value) external {balanceOf[who]+=value;}
 function transferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce,uint8 v,bytes32 r,bytes32 s) external {
  require(block.timestamp>validAfter && block.timestamp<validBefore,"time");
  require(!authorizationState[from][nonce] && balanceOf[from]>=value,"state");
  bytes32 domain=keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),keccak256("USDC"),keccak256("2"),block.chainid,address(this)));
  bytes32 payload=keccak256(abi.encode(keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),from,to,value,validAfter,validBefore,nonce));
  require(from!=address(0) && ecrecover(keccak256(abi.encodePacked(hex"1901",domain,payload)),v,r,s)==from,"signature");
  authorizationState[from][nonce]=true;balanceOf[from]-=value;balanceOf[to]+=value;
  emit AuthorizationUsed(from,nonce);emit Transfer(from,to,value);
 }
}`}
};
const compiled=JSON.parse(solc.compile(JSON.stringify({language:'Solidity',sources,settings:{optimizer:{enabled:true,runs:200},evmVersion:'cancun',viaIR:true,outputSelection:{'*':{'*':['abi','evm.bytecode.object','evm.deployedBytecode.object']}}}})));
assert.equal((compiled.errors??[]).filter(e=>e.severity==='error').length,0,JSON.stringify(compiled.errors));
const artifact=(file,name)=>compiled.contracts[file][name];
const listener=net.createServer();await new Promise(resolve=>listener.listen(0,'127.0.0.1',resolve));const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
const url=`http://127.0.0.1:${port}`;
const rpc=()=>createPublicClient({chain:arcTestnet,cacheTime:0,transport:http(url,{retryCount:0,timeout:5000})});
const client=rpc(),secondary=rpc();
const settlementKey=generatePrivateKey();
const account=privateKeyToAccount(settlementKey);
const payer=privateKeyToAccount(generatePrivateKey());
const wallet=createWalletClient({chain:arcTestnet,account,transport:http(url)});
const chain=spawn('anvil',['--host','127.0.0.1','--port',String(port),'--chain-id','5042002','--silent'],{stdio:'ignore'});
let chainError;chain.on('error',e=>chainError=e);
const db=new DatabaseSync(':memory:');
try {
 let ready=false;
 for(let i=0;i<80;i++){
  if(chainError)throw chainError;
  assert.equal(chain.exitCode,null,'Own isolated chain stopped');
  try{assert.equal(await client.getChainId(),5042002);ready=true;break;}catch{await new Promise(resolve=>setTimeout(resolve,100));}
 }
 assert.ok(ready,'Own loopback test chain unavailable');
 await client.request({method:'anvil_setBalance',params:[account.address,'0x56BC75E2D63100000']});
 const deploy=async(a,args=[])=>{
  const hash=await wallet.deployContract({abi:a.abi,bytecode:'0x'+a.evm.bytecode.object,args});
  const receipt=await client.waitForTransactionReceipt({hash});assert.equal(receipt.status,'success');return receipt.contractAddress;
 };
 const asArtifact=c=>({abi:c.abi,evm:{bytecode:{object:c.bytecode.slice(2)}}});
 const verifier=await deploy(pkg?asArtifact(pkg.verifier):artifact('Verifier.sol','ProvekitGroth16Verifier'));
 const verifierHash=keccak256(await client.getCode({address:verifier}));
 const official=await deploy(pkg?asArtifact(pkg.gate):artifact('MateAgeGate.sol','MateAgeGate'),[verifier,verifierHash]);
 if(pkg){
  const checked=await checkAgeDeployment(pkg,{verifier,gate:official},[client,secondary]);
  assert.equal(checked.gateCodeHash,keccak256(expectedGateRuntime(pkg,verifier)));
  await assert.rejects(()=>checkAgeDeployment(pkg,{verifier:official,gate:verifier},[client,secondary]));
  await assert.rejects(()=>checkAgeDeployment(pkg,{verifier,gate:official},[client,{...secondary,getCode:async()=> '0x6000'}]));
  await assert.rejects(()=>checkAgeDeployment(pkg,{verifier,gate:official},[client,client]));
 }
 const gate=await deploy(artifact('SyntheticGate.sol','SyntheticGate'),[verifier,verifierHash]);
 const token=artifact('SyntheticUSDC.sol','SyntheticUSDC');
 await client.request({method:'anvil_setCode',params:[USDC,'0x'+token.evm.deployedBytecode.object]});
 const minted=await wallet.writeContract({address:USDC,abi:token.abi,functionName:'mint',args:[payer.address,100000n]});
 await client.waitForTransactionReceipt({hash:minted});
 for(const file of ['0001_orders.sql','0002_payment_expiry.sql'])db.exec(readFileSync(path.join(root,'services/shop/migrations',file),'utf8'));
 const database={
  prepare(sql){
   return {
    async first(){return db.prepare(sql).get()??null;},
    bind(...values){return {
     async first(){return db.prepare(sql).get(...values)??null;},
     async run(){return {meta:{changes:Number(db.prepare(sql).run(...values).changes)}};}
    };}
   };
  }
 };
 const env={ARC_SETTLER_KEY:settlementKey,ARC_SETTLER_ADDRESS:account.address,SHOP_CHAIN_ID:'5042002',AGE_GATE_ADDRESS:gate,AGE_GATE_CODE_HASH:keccak256(await client.getCode({address:gate})),PAYMENT_RECIPIENT:'0x'+'22'.repeat(20),ORDERS:database,API_LIMIT:{async limit(){return{success:true};}},ORDER_CREATION_LIMIT:{async limit(){return{success:true};}}};
 const types={TransferWithAuthorization:[{name:'from',type:'address'},{name:'to',type:'address'},{name:'value',type:'uint256'},{name:'validAfter',type:'uint256'},{name:'validBefore',type:'uint256'},{name:'nonce',type:'bytes32'}]};
 const typed=authorization=>({domain:{name:'USDC',version:'2',chainId:5042002,verifyingContract:USDC},primaryType:'TransferWithAuthorization',types,message:authorization});
 let settles=0;
 const actualSettlement=createArcSettlement(env,{client,wallet});
 const facilitator={
  verify:(...args)=>actualSettlement.verify(...args),
  async settle(...args){settles++;return actualSettlement.settle(...args);}
 };
 const supported=()=>supportedSettlement(env,{client});
 const makeWorker=()=>createShop({client:()=>client,secondaryClient:()=>secondary,facilitatorClient:()=>facilitator,supported});
 let worker=makeWorker();
 const key='ad'.repeat(32);
 const request=(p,method='GET',body,headers={})=>worker.fetch(new Request('https://synthetic.example/api'+p,{method,headers:{'X-Order-Key':key,...(body===undefined?{}:{'content-type':'application/json'}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})}),env);
 const catalog=await request('/catalog');assert.equal((await catalog.json()).checkoutAvailable,true);
 const created=await request('/orders','POST',{productId:'mate-lager',quantity:1,payer:payer.address});
 assert.equal(created.status,201);const order=(await created.json()).order;
 assert.equal((await request(`/orders/${order.id}/pay`,'POST')).status,403);assert.equal(settles,0);
 bridge.stdin.end(JSON.stringify({orderHash:order.orderHash,paymentNonce:order.paymentNonce,createdAt:order.createdAt,expiresAt:order.expiresAt})+'\n');
 const proof=await readBridge();assert.equal(proof.syntheticOnly,true);delete proof.syntheticOnly;
 const args=ageArguments({...order,ageProof:proof.proof,ageRootKeyHash:proof.rootKeyHash});
 assert.equal(await client.readContract({address:official,abi:AGE_ABI,functionName:'verifyOrderAge',args,gas:1000000n}),false,'Production government trust must reject synthetic credentials');
 const damaged={...proof,proof:'0x'+(parseInt(proof.proof.slice(2,4),16)^1).toString(16).padStart(2,'0')+proof.proof.slice(4)};
 assert.equal((await request(`/orders/${order.id}/age`,'POST',damaged)).status,403);
 const verified=await request(`/orders/${order.id}/age`,'POST',proof);assert.equal(verified.status,200);
 assert.equal((await verified.json()).order.state,'age_verified');
 const challenge=await request(`/orders/${order.id}/pay`,'POST');assert.equal(challenge.status,402);
 assert.deepEqual(decodePaymentRequiredHeader(challenge.headers.get('PAYMENT-REQUIRED')).accepts,[requirements(order)]);
 const now=Math.floor(Date.now()/1000);const authorization={from:order.payer,to:order.recipient,value:order.amount,validAfter:String(now-1),validBefore:String(now+180),nonce:order.paymentNonce};
 const signature=await payer.signTypedData(typed(authorization));
 const header=encodePaymentSignatureHeader({x402Version:2,accepted:requirements(order),payload:{authorization,signature}});
 // Anvil mines only on demand; advance its clock after native proving so the
 // real settlement adapter simulates against a current block, as Arc does.
 await client.request({method:'evm_mine',params:[]});
 const response=await request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':header});
 assert.ok([200,202].includes(response.status),`Unexpected payment HTTP status ${response.status}`);
 await client.request({method:'evm_mine',params:[]});
 const completed=(await (await request(`/orders/${order.id}`)).json()).order;
 assert.equal(completed.state,'complete');assert.equal(completed.orderHash,order.orderHash);
 assert.equal(await client.readContract({address:USDC,abi:token.abi,functionName:'balanceOf',args:[env.PAYMENT_RECIPIENT]}),100000n);
 assert.equal(await client.readContract({address:USDC,abi:token.abi,functionName:'authorizationState',args:[order.payer,order.paymentNonce]}),true);
 worker=makeWorker();assert.equal((await(await request(`/orders/${order.id}`)).json()).order.paymentTransaction,completed.paymentTransaction);
 assert.equal((await request(`/orders/${order.id}/pay`,'POST',undefined,{'PAYMENT-SIGNATURE':header})).status,200);assert.equal(settles,1);
 const saved=db.prepare('SELECT value FROM orders').get().value;
 for(const secret of ['card_signature','certificate_signature','root_modulus','419900102',signature])assert.equal(saved.includes(secret),false);
 const report={syntheticOnly:true,localChainOnly:true,physicalCard:false,publicFacilitator:false,realUSDC:false,independentRPCOperators:false,workerRoutes:true,realNativeAgeProof:true,realGroth16EVMVerification:true,officialGateRejectedSyntheticRoot:true,damagedProofRejected:true,realEIP712Signature:true,productionSettlementAdapter:true,localEVMTransfer:true,persistedCompletedOrder:true,restartAndRetryNoSecondSettlement:true,settlements:settles,unsignedPackageContractsVerified:Boolean(pkg)};
 const reportPath=path.join(mkdtempSync(path.join(root,'.build/shop-integration-')),'acceptance.json');
 writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));console.log('Acceptance report: '+path.relative(root,reportPath));
} finally {db.close();chain.kill('SIGTERM');bridge.kill('SIGTERM');}
