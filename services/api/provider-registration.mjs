import {parseAbi,encodeFunctionData,parseEventLogs} from 'viem';
import {z} from 'zod';
import {address} from './protocol.mjs';
import {requireValue} from './errors.mjs';
export const REGISTRY='0x8004A818BFB912233c491871b3d84c89A494BD9e',REGISTRATION_CHAIN=11155111;
export const registrationABI=parseAbi([
  'function register() returns (uint256)',
  'function eip712Domain() view returns (bytes1 fields,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt,uint256[] extensions)',
  'function setAgentURI(uint256 agentId,string newURI)',
  'function ownerOf(uint256 agentId) view returns (address)',
  'function tokenURI(uint256 agentId) view returns (string)',
  'function getAgentWallet(uint256 agentId) view returns (address)',
  'function setAgentWallet(uint256 agentId,address newWallet,uint256 deadline,bytes signature)',
  'event Registered(uint256 indexed agentId,string agentURI,address indexed owner)',
]);
const endpoint=z.string().max(2048).refine(value=>{
  try {const url=new URL(value);return url.protocol==='https:' && !url.username && !url.password && !url.search && !url.hash;}
  catch{return false;}
});
export function registrationConfiguration(e,owner) {
  const config=z.object({owner:address,recipient:address,endpoint,
    name:z.string().min(1).max(120),description:z.string().min(1).max(1024),image:endpoint.or(z.literal(''))}).parse({
    owner,recipient:e.PROVIDER_RECIPIENT,endpoint:e.PROVIDER_PUBLIC_URL,
    name:e.PROVIDER_REGISTRATION_NAME||'Mate specialist',description:e.PROVIDER_REGISTRATION_DESCRIPTION||'A specialist service for explicitly authorized Mate requests.',image:e.PROVIDER_REGISTRATION_IMAGE_URL||'',
  });
  requireValue(Buffer.byteLength(JSON.stringify(registrationDocument(config,Number.MAX_SAFE_INTEGER)))<=6000,'registration_metadata_size','Shorten the public registration metadata before submitting.');
  return config;
}
export function registrationDocument(config,id) {
  return {type:'https://eips.ethereum.org/EIPS/eip-8004#registration-v1',name:config.name,description:config.description,
    ...(config.image?{image:config.image}:{}),services:[{name:'web',endpoint:config.endpoint}],active:true,x402Support:false,
    registrations:[{agentId:Number(id),agentRegistry:`eip155:${REGISTRATION_CHAIN}:${REGISTRY}`}],supportedTrust:[]};
}
export function walletAuthorization(id,owner,newWallet,deadline) {
  return {domain:{name:'ERC8004IdentityRegistry',version:'1',chainId:REGISTRATION_CHAIN,verifyingContract:REGISTRY},
    primaryType:'AgentWalletSet',types:{AgentWalletSet:[{name:'agentId',type:'uint256'},{name:'newWallet',type:'address'},{name:'owner',type:'address'},{name:'deadline',type:'uint256'}]},
    message:{agentId:BigInt(id),newWallet,owner,deadline:BigInt(deadline)}};
}
export async function registerProvider({config,client,lane,journal,recipientSigner,renewWalletAuthorization=false}) {
  requireValue(await client.getChainId()===REGISTRATION_CHAIN,'registration_chain','Provider registration requires Sepolia, independently of Arc settlement.');
  requireValue(lane.address.toLowerCase()===config.owner.toLowerCase(),'registration_owner','Registration signer does not match the selected owner.');
  const code=await client.getCode({address:REGISTRY});
  requireValue(code && code!=='0x','registration_registry','The selected RPC has no supported identity registry.');
  const domain=await client.readContract({address:REGISTRY,abi:registrationABI,functionName:'eip712Domain'});
  requireValue(domain[0]==='0x0f' && domain[1]==='ERC8004IdentityRegistry' && domain[2]==='1' && domain[3]===BigInt(REGISTRATION_CHAIN)
    && domain[4].toLowerCase()===REGISTRY.toLowerCase() && domain[5]==='0x'+'00'.repeat(32) && domain[6].length===0,
    'registration_domain','The registry signature domain changed. Review its current deployment before registering.');
  const binding={chainId:REGISTRATION_CHAIN,registry:REGISTRY,...config};
  const previous=journal.get('registration-binding');
  requireValue(!previous || JSON.stringify(previous.value)===JSON.stringify(binding),'registration_changed','This registration journal belongs to different public settings. Restore its original settings to recover pending work.');
  if(config.owner.toLowerCase()!==config.recipient.toLowerCase())
    requireValue(recipientSigner?.address.toLowerCase()===config.recipient.toLowerCase(),'registration_wallet','Provide the payout wallet signer before registration when it differs from the registration owner.');
  if(renewWalletAuthorization)requireValue(journal.get('registration-wallet')?.state==='reverted','registration_wallet_pending','Wallet authorization can be renewed only after its transaction is confirmed reverted.');
  if(!previous)journal.put('registration-binding','confirmed',binding);
  const mint=await lane.send('register-provider-v1',{to:REGISTRY,data:encodeFunctionData({abi:registrationABI,functionName:'register'})});
  const receipt=await client.getTransactionReceipt({hash:mint.hash});
  requireValue(receipt.status==='success' && receipt.transactionHash.toLowerCase()===mint.hash.toLowerCase(),'registration_receipt','Provider registration is not confirmed.');
  const events=parseEventLogs({abi:registrationABI,eventName:'Registered',logs:receipt.logs.filter(log=>log.address.toLowerCase()===REGISTRY.toLowerCase()),strict:true});
  requireValue(events.length===1 && events[0].args.owner.toLowerCase()===config.owner.toLowerCase(),'registration_event','The receipt does not contain the expected provider registration.');
  const id=events[0].args.agentId;
  requireValue(id>=0n && id<=BigInt(Number.MAX_SAFE_INTEGER),'registration_id','The registration identifier cannot be represented safely.');
  const read=functionName=>client.readContract({address:REGISTRY,abi:registrationABI,functionName,args:[id]});
  requireValue((await read('ownerOf')).toLowerCase()===config.owner.toLowerCase(),'registration_owner','The registered identity has a different owner.');
  const saved=journal.get('registration-wallet');
  if(saved || (await read('getAgentWallet')).toLowerCase()!==config.recipient.toLowerCase()) {
    requireValue(saved?.state!=='reverted' || renewWalletAuthorization,'registration_wallet_expired','The wallet authorization transaction reverted. Retry with --submit --renew-wallet-authorization to approve a new bounded signature.');
    let authorization=renewWalletAuthorization?null:saved?.value;
    const attempt=renewWalletAuthorization?(saved.value.attempt??1)+1:(saved?.value.attempt??1);
    if(!authorization) {
      requireValue(recipientSigner,'registration_wallet','A payout wallet signature is required.');
      const block=await client.getBlock();
      const deadline=Number(block.timestamp)+240;
      const document=walletAuthorization(id,config.owner,config.recipient,deadline);
      const signature=await recipientSigner.signTypedData(document);
      requireValue(await client.verifyTypedData({address:config.recipient,...document,signature}),'registration_signature','The payout wallet signature could not be verified.');
      authorization={deadline,signature,attempt};journal.put('registration-wallet','prepared',authorization);
    }
    try {
      await lane.send(`register-provider-wallet-v${authorization.attempt}`,{to:REGISTRY,data:encodeFunctionData({abi:registrationABI,functionName:'setAgentWallet',args:[id,config.recipient,BigInt(authorization.deadline),authorization.signature]})});
      journal.put('registration-wallet','confirmed',authorization);
    } catch(error) {
      if(error.code==='transaction_reverted')journal.put('registration-wallet','reverted',authorization);
      throw error;
    }
  }
  const document=registrationDocument(config,id);
  const uri='data:application/json;base64,'+Buffer.from(JSON.stringify(document)).toString('base64');
  const metadata=await lane.send('register-provider-metadata-v1',{to:REGISTRY,data:encodeFunctionData({abi:registrationABI,functionName:'setAgentURI',args:[id,uri]})});
  const [owner,wallet,actualURI]=await Promise.all(['ownerOf','getAgentWallet','tokenURI'].map(read));
  requireValue(owner.toLowerCase()===config.owner.toLowerCase() && wallet.toLowerCase()===config.recipient.toLowerCase() && actualURI===uri,'registration_readback','On-chain registration does not match the requested owner, payout wallet or metadata.');
  const result={id:`${REGISTRATION_CHAIN}:${id}`,registry:REGISTRY,owner,recipient:wallet,endpoint:config.endpoint,
    registrationTransaction:mint.hash,metadataTransaction:metadata.hash,indexing:'not-verified'};
  journal.put('registration-result','confirmed',result);
  return result;
}
