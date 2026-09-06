import {createPublicClient,http,parseAbi,encodeFunctionData,parseEventLogs,namehash,toHex} from 'viem';
import {sepolia} from 'viem/chains';
import {privateKeyToAccount} from 'viem/accounts';
import path from 'node:path';
import fs from 'node:fs';
import {configuration,httpsURL,ROOT} from '../services/api/config.mjs';
import {address} from '../services/api/protocol.mjs';
import {Journal} from '../services/api/journal.mjs';
import {Chain,TransactionLane} from '../services/api/chain.mjs';
import {Names,nameMessage,resolverABI} from '../services/api/names.mjs';
import {saveEnvironment} from './environment.mjs';
import {requireValue} from '../services/api/errors.mjs';
import {acquireProcessLock} from '../services/api/process-lock.mjs';
import {createHash} from 'node:crypto';
import {boundedJSON} from '../services/api/http.mjs';

process.umask(0o077);
async function main(){
 const config=configuration(),e=process.env;
 const endpoint=httpsURL.parse(e.PROVIDER_PUBLIC_URL).replace(/\/$/,'');
 const recipient=address.parse(e.PROVIDER_RECIPIENT_ADDRESS);
 const registry=address.parse(e.AGENT_REGISTRY_ADDRESS);
 requireValue(config.ensKey&&e.PROVIDER_API_TOKEN?.length>=32,'provider','Configure ENS operator, provider recipient and pairing token first.');
 const label=e.PROVIDER_ENS_LABEL||'specialist';
 const operator=privateKeyToAccount(config.ensKey);
 fs.mkdirSync(config.dataDirectory,{recursive:true,mode:0o700});
 const unlock=acquireProcessLock(path.join(config.dataDirectory,'api.lock'));
 const journal=new Journal(path.join(config.dataDirectory,'journal.sqlite'),config.journalKey);
 try{
  const chain=new Chain(config,journal);await chain.prepare();
  const names=new Names(config,chain,journal);
  const claim={label,owner:operator.address,agent:recipient,
   nonce:'0x'+createHash('sha256').update(`${label}:${endpoint}:${recipient}`).digest('hex'),
   expiresAt:Math.floor(Date.now()/1000)+600};
  // An incomplete name-registration transaction is deliberately recovered by the same
  // stored request, not signed again with a different expiration/nonce.
  const claimKey=`setup-provider-name:${label}`;
  const saved=journal.get(claimKey);
  let request;
  if(saved)request=saved.value;
  else {request={...claim,signature:await operator.signMessage({message:nameMessage(claim,config)})};journal.put(claimKey,'authorized',request);}
  const identity=await names.claim(request);
  const lane=new TransactionLane({publicClient:chain.public,rpcURL:config.rpcURL,key:config.ensKey,journal});
  await lane.send(`provider-endpoint:${label}`,{to:identity.resolver,data:encodeFunctionData({abi:resolverABI,functionName:'setText',
   args:[namehash(identity.name),'agent-endpoint[web]',endpoint]})});
  const registration={type:'https://eips.ethereum.org/EIPS/eip-8004#registration-v1',name:'Mate Specialist',
   description:'Local-model translation and summarization. Only the separately approved disclosure is processed.',
   active:true,x402Support:false,supportedTrust:['reputation'],
   services:[{name:'web',endpoint},{name:'ENS',endpoint:identity.name}]};
  const publication=path.join(ROOT,'.data','provider-registration.json');
  fs.writeFileSync(publication,JSON.stringify(registration,null,2)+'\n',{mode:0o600});
  saveEnvironment({PROVIDER_REGISTRATION_FILE:publication});
  const abi=parseAbi(['function register(string agentURI) returns(uint256)',
   'event Registered(uint256 indexed agentId,string agentURI,address indexed owner)']);
  const metadataURI=endpoint+'/agent.json';
  const published=await boundedJSON(metadataURI);
  requireValue(published.name===registration.name && published.active===true
    && published.services?.some(service=>service.name==='ENS'&&service.endpoint===identity.name)
    && published.services?.some(service=>service.name==='web'&&service.endpoint===endpoint),
    'metadata_publication','Publish the actual provider /agent.json via HTTPS before registration. Run ./mate provider with the configured TLS reverse proxy.');
  const tx=await lane.send(`provider-registration:${label}`,{to:registry,data:encodeFunctionData({abi,functionName:'register',args:[metadataURI]})});
  const receipt=await chain.public.getTransactionReceipt({hash:tx.hash});
  const event=parseEventLogs({abi,eventName:'Registered',logs:receipt.logs.filter(log=>log.address.toLowerCase()===registry.toLowerCase()),strict:true})[0];
  requireValue(event,'registration','The ERC-8004 registry did not emit a registration event.');
  const id=`11155111:${event.args.agentId}`;
  const price=e.PROVIDER_PRICE_UNITS||'10000';
  const entries=[0,1].map(service=>({id,service,price,owner:operator.address,recipient,ensName:identity.name,endpoint,bearerToken:e.PROVIDER_API_TOKEN}));
  saveEnvironment({MATE_PROVIDERS_JSON:JSON.stringify(entries)});
  console.log(`Registered ${id} with ENS ${identity.name}. Discovery will appear only after The Graph indexes the real record.`);
 }finally{journal.close();unlock();}
}
main().catch(error=>{console.error(error?.name==='ProductError'?error.message:'Provider registration failed. Existing transaction records are retained for recovery.');process.exit(1);});
