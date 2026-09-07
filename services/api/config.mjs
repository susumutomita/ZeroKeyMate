import fs from 'node:fs';
import path from 'node:path';
import {z} from 'zod';
import {privateKeyToAccount} from 'viem/accounts';
import {address,uintString} from './protocol.mjs';
import {ProductError,requireValue} from './errors.mjs';
export const ROOT=path.resolve(import.meta.dirname,'../..');
export const SEPOLIA_USDC='0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238';
export const safeURL=z.string().url().refine(value=>{
 const url=new URL(value);return !url.username&&!url.password&&!url.hash&&(
 url.protocol==='https:'||(url.protocol==='http:'&&['127.0.0.1','localhost','[::1]'].includes(url.hostname)));
});
export const httpsURL=safeURL.refine(value=>new URL(value).protocol==='https:');
export const ensName=z.string().max(253).regex(/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\.eth$/).refine(value=>value.split('.').every(label=>label.length<=63));
export const secretKey=z.string().regex(/^0x[0-9a-fA-F]{64}$/);
export const providerSchema=z.object({id:z.string().max(100).regex(/^11155111:[0-9]+$/),service:z.number().int().min(0).max(1),
 price:uintString.refine(v=>/^[1-9][0-9]*$/.test(v)),owner:address,recipient:address,ensName,
 endpoint:httpsURL,bearerToken:z.string().min(32).max(256)}).strict();
export function configuration(e=process.env){
 const required=['SEPOLIA_RPC_URL','MATE_VAULT_ADDRESS','MATE_ATTESTOR_PRIVATE_KEY','MATE_RELAYER_PRIVATE_KEY','MATE_API_TOKEN','MATE_JOURNAL_KEY'];
 const missing=required.filter(name=>!e[name]);
 if(missing.length)throw new ProductError('configuration_required',`未設定: ${missing.join(', ')}`,503);
 try{
  const parsed=z.object({rpcURL:httpsURL,vault:address,attestorKey:secretKey,relayerKey:secretKey,
   apiToken:z.string().min(32).max(256),journalKey:z.string().regex(/^[\da-fA-F]{64}$/),
   host:z.enum(['127.0.0.1','::1','0.0.0.0']),port:z.coerce.number().int().min(1).max(65535),
   graphApiKey:z.string().max(512),graphSubgraphId:z.string().regex(/^[a-zA-Z0-9_-]{1,128}$/),
   ensParent:ensName.or(z.literal('')),ensRegistry:address.or(z.literal('')),ensKey:secretKey.or(z.literal('')),
   ensFactory:address.or(z.literal('')),
  }).parse({rpcURL:e.SEPOLIA_RPC_URL,vault:e.MATE_VAULT_ADDRESS,attestorKey:e.MATE_ATTESTOR_PRIVATE_KEY,relayerKey:e.MATE_RELAYER_PRIVATE_KEY,
   apiToken:e.MATE_API_TOKEN,journalKey:e.MATE_JOURNAL_KEY,host:e.MATE_BIND_HOST||'127.0.0.1',port:e.MATE_PORT||8787,
   graphApiKey:e.GRAPH_API_KEY||'',graphSubgraphId:e.GRAPH_SUBGRAPH_ID||'6wQRC7geo9XYAhckfmfo8kbMRLeWU8KQd3XsJqFKmZLT',
   ensParent:e.ENS_PARENT_NAME||'',ensRegistry:e.ENS_SUBREGISTRY_ADDRESS||'',ensKey:e.ENS_OPERATOR_PRIVATE_KEY||'',ensFactory:e.ENS_RESOLVER_FACTORY||''});
  const providers=z.array(providerSchema).max(50).parse(JSON.parse(e.MATE_PROVIDERS_JSON||'[]'));
  requireValue(new Set(providers.map(p=>`${p.id}:${p.service}`)).size===providers.length,'provider_ids','提供者IDが重複しています。',503);
  const keys=[parsed.attestorKey,parsed.relayerKey,parsed.ensKey].filter(Boolean);
  requireValue(new Set(keys.map(k=>privateKeyToAccount(k).address)).size===keys.length,'key_separation','中継・証明検証・ENSには別々のキーを使ってください。',503);
  return {...parsed,providers,chainId:11155111,token:SEPOLIA_USDC,
   dataDirectory:path.resolve(e.MATE_DATA_DIRECTORY||path.join(ROOT,'.data')),
   verifierBinary:path.resolve(e.MATE_VERIFIER_BINARY||path.join(ROOT,'services/verifier/target/release/mate-verify')),
   verifierKey:path.join(ROOT,'.build/proofs/mate_policy.pkv'),manifest:path.join(ROOT,'.build/proofs/manifest.json'),
  };
 }catch(error){if(error instanceof ProductError)throw error;throw new ProductError('invalid_configuration','接続設定の形式を確認してください。',503);}
}
export function loadArtifact(name){
 requireValue(['MateVault','MateResolverFactory'].includes(name),'artifact_name','未対応のコントラクトです。',503);
 return JSON.parse(fs.readFileSync(path.join(ROOT,'.build/contracts',`${name}.json`),'utf8'));
}
