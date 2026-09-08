import fs from 'node:fs';
import path from 'node:path';
import {createPublicClient,http,encodeDeployData} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';
import {networkConfiguration,settlementNetwork} from '../services/api/networks.mjs';
import {ROOT,loadArtifact,secretKey} from '../services/api/config.mjs';
import {address} from '../services/api/protocol.mjs';
import {TransactionLane,tokenABI} from '../services/api/chain.mjs';
import {Journal} from '../services/api/journal.mjs';
import {processLock} from '../services/api/process-lock.mjs';

const e=process.env;
let journal,release;
try {
  const config=networkConfiguration(e);
  const key=secretKey.parse(e.MATE_RELAYER_PRIVATE_KEY);
  const attestor=address.parse(e.MATE_ATTESTOR_MODE==='circle'?e.CIRCLE_ATTESTOR_ADDRESS:
    privateKeyToAccount(secretKey.parse(e.MATE_ATTESTOR_PRIVATE_KEY)).address);
  if(privateKeyToAccount(key).address.toLowerCase()===attestor.toLowerCase())throw new Error('Relayer and proof attestor must be separate wallets.');
  const rpc=new URL(config.rpcURL);
  if(rpc.username || rpc.password || rpc.hash || !(rpc.protocol==='https:' || (rpc.protocol==='http:' && ['127.0.0.1','localhost','[::1]'].includes(rpc.hostname))))throw new Error('Use HTTPS or a local test RPC.');
  const client=createPublicClient({chain:settlementNetwork(config.chainId).chain,transport:http(config.rpcURL,{timeout:20_000,retryCount:0})});
  if(await client.getChainId()!==config.chainId)throw new Error('RPC chain mismatch. Nothing deployed.');
  if(await client.readContract({address:config.token,abi:tokenABI,functionName:'decimals'})!==6)throw new Error('Unexpected USDC interface. Nothing deployed.');
  const directory=path.join(ROOT,'.data/deploy',String(config.chainId));
  release=processLock(path.join(directory,'deploy.lock'));
  journal=new Journal(path.join(directory,'deploy.sqlite'),e.MATE_JOURNAL_KEY);
  const lane=new TransactionLane({publicClient:client,rpcURL:config.rpcURL,key,journal,chainId:config.chainId});
  const artifact=loadArtifact('MateVault');
  const data=encodeDeployData({abi:artifact.abi,bytecode:artifact.bytecode,args:[config.token,attestor]});
  // One stable operation name per deployer/network; changed constructor/bytecode requires deliberate new journal.
  const tx=await lane.send('deploy-mate-vault-v1',{data});
  const receipt=await client.getTransactionReceipt({hash:tx.hash});
  const vault=receipt.contractAddress;
  if(!vault)throw new Error('No deployment address in the confirmed receipt.');
  const [actualToken,actualAttestor]=await Promise.all(['token','attestor'].map(functionName=>client.readContract({address:vault,abi:artifact.abi,functionName})));
  if(actualToken.toLowerCase()!==config.token.toLowerCase() || actualAttestor.toLowerCase()!==attestor.toLowerCase())throw new Error('Deployed contract configuration mismatch.');
  const record={chainId:config.chainId,vault,token:config.token,attestor,transactionHash:tx.hash,blockNumber:tx.blockNumber};
  fs.mkdirSync(path.join(ROOT,'.build/deployments'),{recursive:true});
  fs.writeFileSync(path.join(ROOT,'.build/deployments',`${config.chainId}.json`),JSON.stringify(record,null,2)+'\n');
  console.log(JSON.stringify(record,null,2));
  console.log('Set MATE_VAULT_ADDRESS to this confirmed address in the API and specialist configuration.');
} catch(error) {
  console.error(error.name==='ZodError'?'Complete the relayer, attestor and journal configuration first.':error.message);
  process.exitCode=1;
} finally {journal?.close();release?.();}
