import fs from 'node:fs';
import {z} from 'zod';
import {encodeFunctionData,parseAbi,namehash,keccak256,toHex,encodeAbiParameters,zeroAddress} from 'viem';
import {ensName,loadArtifact} from './config.mjs';
import {address,hash32,signatureSchema,sha256} from './protocol.mjs';
import {TransactionLane} from './chain.mjs';
import {requireValue,SerialQueue} from './errors.mjs';

const deployment=JSON.parse(fs.readFileSync(new URL('../../config/ens-sepolia.json',import.meta.url),'utf8'));
const registryABI=parseAbi([
  'function getSubregistry(string label) view returns (address)',
  'function getResolver(string label) view returns (address)',
  'function getOwner(uint256 anyId) view returns (address)',
  'function register(string label,address owner,address registry,address resolver,uint256 roleBitmap,uint64 expiry) returns (uint256)',
]);
const resolverABI=parseAbi(['function addr(bytes32 node) view returns (address)','function text(bytes32 node,string key) view returns (string)']);
export const nameClaimSchema=z.object({label:z.string().regex(/^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$/),
  owner:address,agent:address,signature:signatureSchema,nonce:hash32,expiresAt:z.number().int().positive().max(Number.MAX_SAFE_INTEGER)}).strict();
export function nameMessage(config,claim) {
  return `ZeroKey Mate name registration\nchain:11155111\nvault:${config.vault.toLowerCase()}\nname:${claim.label}.${config.ensParent}\nowner:${claim.owner.toLowerCase()}\nagent:${claim.agent.toLowerCase()}\nnonce:${claim.nonce.toLowerCase()}\nexpires:${claim.expiresAt}`;
}

export class Names {
  #queue=new SerialQueue();
  constructor(config,chain,journal) {
    Object.assign(this,{config,chain,journal});
    this.lane=config.ensKey ? new TransactionLane({publicClient:chain.public,rpcURL:config.rpcURL,key:config.ensKey,journal}) : null;
  }
  read(registry,functionName,args) {return this.chain.public.readContract({address:registry,abi:registryABI,functionName,args});}
  async registryFor(name) {
    ensName.parse(name);
    let registry=deployment.rootRegistry;
    const labels=name.split('.').reverse();
    for(const label of labels.slice(0,-1)) {
      registry=await this.read(registry,'getSubregistry',[label]);
      requireValue(registry!==zeroAddress,'ens_unresolved','ENSv2の公開レジストリから名前を解決できません。',404);
    }
    return {registry,label:labels.at(-1)};
  }
  async resolve(name) {
    const {registry,label}=await this.registryFor(name);
    const [owner,resolver]=await Promise.all([
      this.read(registry,'getOwner',[BigInt(keccak256(toHex(label)))]),this.read(registry,'getResolver',[label]),
    ]);
    requireValue(owner!==zeroAddress && resolver!==zeroAddress,'ens_unresolved','名前の所有者またはリゾルバーを確認できません。',404);
    const node=namehash(name);
    const account=await this.chain.public.readContract({address:resolver,abi:resolverABI,functionName:'addr',args:[node]});
    requireValue(account!==zeroAddress,'ens_unresolved','名前にアドレスが設定されていません。',404);
    const description=await this.chain.public.readContract({address:resolver,abi:resolverABI,functionName:'text',args:[node,'description']}).catch(()=>'');
    return {name,address:account,owner,description:String(description).slice(0,500)};
  }
  claim(input) {return this.#queue.run(async()=>{
    const claim=nameClaimSchema.parse(input), config=this.config;
    requireValue(config.ensParent && config.ensRegistry && config.ensFactory && this.lane,
      'ens_unconfigured','ENSv2の親ドメイン・登録権限・リゾルバーファクトリーが未設定です。',503);
    const name=`${claim.label}.${config.ensParent}`;
    const message=nameMessage(config,claim);
    requireValue(await this.chain.public.verifyMessage({address:claim.owner,message,signature:claim.signature}),
      'name_signature','名前の所有者の署名が無効です。',403);
    const id=`name:${sha256(message)}`;
    let entry=this.journal.get(id);
    if(!entry) {
      const now=Math.floor(Date.now()/1000);
      requireValue(claim.expiresAt>now && claim.expiresAt<=now+900,'name_expired','名前の承認期限が切れています。',409);
      const {registry}=await this.registryFor(name);
      requireValue(registry.toLowerCase()===config.ensRegistry.toLowerCase(),'ens_parent','親ドメインの登録先が設定と一致しません。',503);
      const owner=await this.read(registry,'getOwner',[BigInt(keccak256(toHex(claim.label)))]);
      if(owner!==zeroAddress) {
        const identity=await this.resolve(name);
        requireValue(identity.owner.toLowerCase()===claim.owner.toLowerCase() && identity.address.toLowerCase()===claim.agent.toLowerCase(),
          'name_taken','この名前は既に別の所有者またはアドレスで登録されています。',409);
        return identity;
      }
      const value={claim,name,expiry:now+365*24*3600};
      this.journal.put(id,'authorized',value);entry={state:'authorized',value};
    }
    const abi=loadArtifact('MateResolverFactory').abi;
    const node=namehash(name);
    await this.lane.send(`${id}:resolver`,{to:config.ensFactory,data:encodeFunctionData({abi,functionName:'create',args:[node,claim.agent]})});
    const key=keccak256(encodeAbiParameters([{type:'bytes32'},{type:'address'}],[node,claim.agent]));
    const resolver=await this.chain.public.readContract({address:config.ensFactory,abi,functionName:'resolvers',args:[key]});
    requireValue(resolver!==zeroAddress,'ens_resolver','リゾルバーを確認できません。',503);
    // Token owner receives the documented resolver/subregistry/renew/unregister
    // roles and their administration, including permission to transfer the name.
    const roles=[12n,16n,20n,24n].reduce((n,bit)=>n|(1n<<bit)|(1n<<(bit+128n)),1n<<156n);
    await this.lane.send(`${id}:register`,{to:config.ensRegistry,data:encodeFunctionData({abi:registryABI,functionName:'register',
      args:[claim.label,claim.owner,zeroAddress,resolver,roles,BigInt(entry.value.expiry)]})});
    const identity=await this.resolve(name);
    requireValue(identity.owner.toLowerCase()===claim.owner.toLowerCase() && identity.address.toLowerCase()===claim.agent.toLowerCase(),
      'ens_mismatch','登録後の名前とアドレスが一致しません。',409);
    this.journal.put(id,'complete',{...entry.value,identity});return identity;
  });}
}
