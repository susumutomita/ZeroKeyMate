import {createPublicClient,http,encodeFunctionData,parseAbi} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';
import {sepolia} from 'viem/chains';
import fs from 'node:fs';
import path from 'node:path';
import {ROOT,SEPOLIA_USDC,loadArtifact,httpsURL,secretKey,ensName} from '../services/api/config.mjs';
import {Journal} from '../services/api/journal.mjs';
import {TransactionLane} from '../services/api/chain.mjs';
import {registryABI} from '../services/api/names.mjs';
import {acquireProcessLock} from '../services/api/process-lock.mjs';
import {saveEnvironment} from './environment.mjs';
import {requireValue} from '../services/api/errors.mjs';

process.umask(0o077);
async function main(){
 const e=process.env;
 const rpcURL=httpsURL.parse(e.SEPOLIA_RPC_URL);
 const relayerKey=secretKey.parse(e.MATE_RELAYER_PRIVATE_KEY), attestorKey=secretKey.parse(e.MATE_ATTESTOR_PRIVATE_KEY);
 requireValue(relayerKey!==attestorKey,'keys','Use separate relayer and proof-attestor keys.');
 requireValue(/^[\da-fA-F]{64}$/.test(e.MATE_JOURNAL_KEY??''),'key','Initialize the journal key with ./mate configure.');
 const client=createPublicClient({chain:sepolia,transport:http(rpcURL)});
 requireValue(await client.getChainId()===11155111,'chain','Sepolia is required.');
 const relayer=privateKeyToAccount(relayerKey),attestor=privateKeyToAccount(attestorKey);
 requireValue(await client.getBalance({address:relayer.address})>0n,'gas',`Fund the testnet relayer ${relayer.address} with Sepolia ETH before deployment.`);
 const directory=path.join(ROOT,'.data');fs.mkdirSync(directory,{recursive:true,mode:0o700});
 const unlock=acquireProcessLock(path.join(directory,'api.lock'));
 const journal=new Journal(path.join(directory,'journal.sqlite'),e.MATE_JOURNAL_KEY);
 try{
  const lane=new TransactionLane({publicClient:client,rpcURL,key:relayerKey,journal});
  const deployment=JSON.parse(fs.readFileSync(path.join(ROOT,'config/ens-sepolia.json'),'utf8'));
  const {encodeDeployData}=await import('viem');
  async function deploy(key,artifact,args){
   if(e[key]){
    const code=await client.getCode({address:e[key]});requireValue(code&&code!=='0x','deployment','Configured contract is absent.');return e[key];
   }
   const transaction=await lane.send(`deployment:${key}`,{data:encodeDeployData({abi:artifact.abi,bytecode:artifact.bytecode,args})});
   const receipt=await client.getTransactionReceipt({hash:transaction.hash});
   requireValue(receipt.contractAddress,'deployment','No deployment address was returned.');
   saveEnvironment({[key]:receipt.contractAddress});e[key]=receipt.contractAddress;
   console.log(`${key}=${receipt.contractAddress}`);return receipt.contractAddress;
  }
  const vault=await deploy('MATE_VAULT_ADDRESS',loadArtifact('MateVault'),[SEPOLIA_USDC,attestor.address]);
  const vaultABI=loadArtifact('MateVault').abi;
  const [deployedToken,deployedAttestor]=await Promise.all(['token','attestor'].map(functionName=>client.readContract({address:vault,abi:vaultABI,functionName})));
  requireValue(deployedToken.toLowerCase()===SEPOLIA_USDC.toLowerCase()&&deployedAttestor.toLowerCase()===attestor.address.toLowerCase(),'vault','The deployed vault uses different security parameters.');
  saveEnvironment({MATE_TOKEN_ADDRESS:SEPOLIA_USDC});
  if(!e.ENS_PARENT_NAME){console.log('Vault deployed. ENS setup requires an already owned Sepolia ENSv2 parent in ENS_PARENT_NAME.');return;}
  ensName.parse(e.ENS_PARENT_NAME);
  const operatorKey=secretKey.parse(e.ENS_OPERATOR_PRIVATE_KEY);
  requireValue(operatorKey!==relayerKey&&operatorKey!==attestorKey,'keys','Use a separate ENS operator key.');
  const operator=privateKeyToAccount(operatorKey);
  const ensLane=new TransactionLane({publicClient:client,rpcURL,key:operatorKey,journal});
  const labels=e.ENS_PARENT_NAME.split('.').reverse();let registry=deployment.rootRegistry;
  for(const label of labels.slice(0,-1)){
   registry=await client.readContract({address:registry,abi:registryABI,functionName:'getSubregistry',args:[label]});
   requireValue(registry!=='0x0000000000000000000000000000000000000000','parent','Parent namespace cannot be resolved.');
  }
  const label=labels.at(-1);
  const owner=await client.readContract({address:registry,abi:registryABI,functionName:'findOwner',args:[label]});
  requireValue(owner.toLowerCase()===operator.address.toLowerCase(),'owner',`ENS operator ${operator.address} must own ${e.ENS_PARENT_NAME} on the configured ENSv2 Sepolia deployment.`);
  const factory=await deploy('ENS_RESOLVER_FACTORY',loadArtifact('MateResolverFactory'),[deployment.resolverImplementation]);
  const current=await client.readContract({address:registry,abi:registryABI,functionName:'getSubregistry',args:[label]});
  let subregistry=e.ENS_SUBREGISTRY_ADDRESS;
  if(!subregistry){
   requireValue(current==='0x0000000000000000000000000000000000000000','existing_registry','A subregistry is already attached. Set ENS_SUBREGISTRY_ADDRESS explicitly instead of overwriting it.');
   // Registrar + setParent, with admin counterparts. No root unregister or resolver
   // rewrite role is installed in this new subregistry.
   const roles=1n|(1n<<8n);const rootRoles=roles|(roles<<128n);
   const initialization=encodeFunctionData({abi:registryABI,functionName:'initialize',args:[operator.address,rootRoles]});
   subregistry=await deploy('ENS_SUBREGISTRY_ADDRESS',loadArtifact('MateProxy'),[deployment.userRegistryImplementation,initialization]);
  }
  if(current==='0x0000000000000000000000000000000000000000'){
   const findToken=parseAbi(['function findTokenId(string label) view returns(uint256)']);
   const id=await client.readContract({address:registry,abi:findToken,functionName:'findTokenId',args:[label]});
   await ensLane.send(`attach:${subregistry.toLowerCase()}`,{to:registry,data:encodeFunctionData({abi:registryABI,functionName:'setSubregistry',args:[id,subregistry]})});
  }else requireValue(current.toLowerCase()===subregistry.toLowerCase(),'parent_changed','Parent points to a different subregistry.');
  await ensLane.send(`parent:${subregistry.toLowerCase()}`,{to:subregistry,data:encodeFunctionData({abi:registryABI,functionName:'setParent',args:[registry,label]})});
  const actual=await client.readContract({address:registry,abi:registryABI,functionName:'getSubregistry',args:[label]});
  requireValue(actual.toLowerCase()===subregistry.toLowerCase(),'ens_link','ENS namespace is not linked.');
  console.log(`ENSv2 linked: ${e.ENS_PARENT_NAME}; resolver factory ${factory}. No user name has been claimed.`);
 }finally{journal.close();unlock();}
}
main().catch(error=>{console.error(error?.message?.startsWith('Fund ')||error?.name==='ProductError'?error.message:'Setup failed. Check actual testnet balances, parent ownership and .env. Existing deployment records are retained.');process.exit(1);});
