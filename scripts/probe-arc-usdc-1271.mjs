// Read-only compatibility probe. No wallet, key, transaction or persistent state.
// The artificial account code/balances exist only inside each eth_call.
import assert from 'node:assert/strict';
import solc from 'solc';
import { encodeFunctionData, decodeFunctionResult, parseAbi, hashTypedData,
  keccak256, toBytes, toHex } from 'viem';

const token = '0x3600000000000000000000000000000000000000';
const payer = '0x00000000000000000000000000000000a8c01271';
const merchant = '0x00000000000000000000000000000000a8c00002';
const harness = '0x00000000000000000000000000000000a8c00003';
const signature = `0x${'71'.repeat(96)}`; // Arbitrary-length public sentinel, not a key signature.
const nonce = keccak256(toBytes('ZeroKeyMate read-only nonzero ERC1271 probe v1'));
const abi = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)',
]);
const harnessABI = parseAbi([
  'function run(address,address,address,uint256,uint256,bytes32,bytes) returns (uint256,uint256,bool,bool)',
]);
const types = { TransferWithAuthorization: [
  {name:'from',type:'address'}, {name:'to',type:'address'}, {name:'value',type:'uint256'},
  {name:'validAfter',type:'uint256'}, {name:'validBefore',type:'uint256'}, {name:'nonce',type:'bytes32'},
] };
let sequence = 0;
async function rpc(url, method, params) {
  assert.ok(['eth_chainId','eth_getCode','eth_getBlockByNumber','eth_call'].includes(method));
  const response = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'},
    body:JSON.stringify({jsonrpc:'2.0',id:++sequence,method,params}),signal:AbortSignal.timeout(20_000) });
  if (!response.ok) throw new Error(`RPC HTTP ${response.status}`);
  return response.json();
}
function compile(digest) {
  // The rejecting and digest-bound accounts are TEST FIXTURES, not proof verifiers.
  const source = `// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;
interface Token {
 function balanceOf(address) external view returns(uint256);
 function authorizationState(address,bytes32) external view returns(bool);
 function transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes calldata) external;
}
contract DigestAccount {
 function isValidSignature(bytes32 digest, bytes calldata signature) external view returns(bytes4) {
  return msg.sender == ${token} && digest == ${digest} && keccak256(signature) == ${keccak256(signature)}
    ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
 }
}
contract RejectAccount {
 function isValidSignature(bytes32,bytes calldata) external pure returns(bytes4) {return 0xffffffff;}
}
contract ProbeHarness {
 function run(address t,address from,address to,uint256 amount,uint256 end,bytes32 nonce,bytes calldata signature)
   external returns(uint256 spent,uint256 received,bool used,bool replayRejected) {
  Token coin=Token(t); uint256 beforeFrom=coin.balanceOf(from); uint256 beforeTo=coin.balanceOf(to);
  require(!coin.authorizationState(from,nonce), "fixture nonce already used");
  coin.transferWithAuthorization(from,to,amount,0,end,nonce,signature);
  spent=beforeFrom-coin.balanceOf(from);received=coin.balanceOf(to)-beforeTo;
  used=coin.authorizationState(from,nonce);
  try coin.transferWithAuthorization(from,to,amount,0,end,nonce,signature) {replayRejected=false;}
    catch {replayRejected=true;}
 }
}`;
  const output=JSON.parse(solc.compile(JSON.stringify({language:'Solidity',sources:{'Probe.sol':{content:source}},
    settings:{viaIR:true,optimizer:{enabled:true,runs:200},evmVersion:'paris',outputSelection:{'*':{'*':['evm.deployedBytecode.object']}}}})));
  const errors=(output.errors??[]).filter(e=>e.severity==='error');
  assert.deepEqual(errors,[]);
  return Object.fromEntries(Object.entries(output.contracts['Probe.sol'])
    .map(([name,data])=>[name,`0x${data.evm.deployedBytecode.object}`]));
}

for (const url of ['https://rpc.testnet.arc.io','https://rpc.drpc.testnet.arc.io']) {
  assert.equal((await rpc(url,'eth_chainId',[])).result,'0x4cef52','Arc Testnet only');
  const block=(await rpc(url,'eth_getBlockByNumber',['latest',false])).result;
  const code=(await rpc(url,'eth_getCode',[token,block.number])).result;
  assert.ok(code?.length>2,'real USDC code must exist');
  // Never replace an existing account with fixture code, even in ephemeral state.
  for (const address of [payer,merchant,harness]) {
    assert.equal((await rpc(url,'eth_getCode',[address,block.number])).result,'0x');
  }
  const end=BigInt(block.timestamp)+300n;
  const message={from:payer,to:merchant,value:250000n,validAfter:0n,validBefore:end,nonce};
  const digest=hashTypedData({domain:{name:'USDC',version:'2',chainId:5042002,verifyingContract:token},
    types,primaryType:'TransferWithAuthorization',message});
  const fixture=compile(digest);
  const override={
    [payer]:{code:fixture.DigestAccount,balance:toHex(10n**18n)},
    [merchant]:{balance:'0x0'},[harness]:{code:fixture.ProbeHarness,balance:'0x0'},
  };
  const balanceData=encodeFunctionData({abi,functionName:'balanceOf',args:[payer]});
  const balance=await rpc(url,'eth_call',[{to:token,data:balanceData},block.number,override]);
  assert.equal(BigInt(balance.result??'-1'),1000000n,JSON.stringify(balance));
  const runData=encodeFunctionData({abi:harnessABI,functionName:'run',args:[token,payer,merchant,250000n,end,nonce,signature]});
  const successful=await rpc(url,'eth_call',[{to:harness,data:runData,gas:'0x4c4b40'},block.number,override]);
  assert.ok(!successful.error,JSON.stringify(successful.error));
  const result=decodeFunctionResult({abi:harnessABI,functionName:'run',data:successful.result});
  assert.deepEqual(result,[250000n,250000n,true,true]);
  const negatives=[];
  for (const kind of ['reject_signature','different_amount','different_recipient','different_nonce','different_signature','insufficient_balance']) {
    const changes={...message};let sig=signature;let state=override;
    if(kind==='reject_signature') state={...override,[payer]:{...override[payer],code:fixture.RejectAccount}};
    if(kind==='different_amount') changes.value=249999n;
    if(kind==='different_recipient') changes.to=harness;
    if(kind==='different_nonce') changes.nonce=keccak256(toBytes('wrong nonce'));
    if(kind==='different_signature') sig='0x1234';
    if(kind==='insufficient_balance') state={...override,[payer]:{...override[payer],balance:'0x0'}};
    const data=encodeFunctionData({abi,functionName:'transferWithAuthorization',args:[changes.from,changes.to,changes.value,changes.validAfter,changes.validBefore,changes.nonce,sig]});
    const rejected=await rpc(url,'eth_call',[{to:token,data,gas:'0x4c4b40'},block.number,state]);
    assert.ok(rejected.error?.message?.toLowerCase().includes('revert'),`${kind}: ${JSON.stringify(rejected)}`);
    negatives.push(kind);
  }
  console.log(JSON.stringify({rpc:url,chainId:5042002,block:block.number,blockHash:block.hash,
    token,tokenCodeHash:keccak256(code),signatureBytes:96,virtualStartingBalance:'1000000',
    spent:result[0].toString(),received:result[1].toString(),nonceConsumed:result[2],replayRejected:result[3],
    negativeCases:negatives,readOnly:true,realTransaction:false}));
}
