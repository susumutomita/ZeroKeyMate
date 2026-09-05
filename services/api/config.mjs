import fs from 'node:fs';
import path from 'node:path';
import {z} from 'zod';
import {address, uintString} from './protocol.mjs';
import {ProductError} from './errors.mjs';

export const ROOT = path.resolve(import.meta.dirname, '../..');
export const SEPOLIA_USDC = '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238';
const key = z.string().regex(/^0x[0-9a-fA-F]{64}$/);
export const providerSchema = z.object({
  id: z.string().regex(/^11155111:[0-9]+$/),
  service: z.number().int().min(0).max(1),
  price: uintString.refine(v => BigInt(v) > 0n),
  owner: address,
  recipient: address,
  ensName: z.string().regex(/^[a-z0-9-]+(?:\.[a-z0-9-]+)+\.eth$/),
  endpoint: z.string().url().refine(v => new URL(v).protocol === 'https:'),
  bearerToken: z.string().min(24),
}).strict();
export function configuration(environment = process.env) {
  const missing = [];
  function need(name) {const value=environment[name];if (!value) missing.push(name);return value;}
  const rpcURL = need('SEPOLIA_RPC_URL');
  const vault = need('MATE_VAULT_ADDRESS');
  const attestorKey = need('MATE_ATTESTOR_PRIVATE_KEY');
  const relayerKey = need('MATE_RELAYER_PRIVATE_KEY');
  const apiToken = need('MATE_API_TOKEN');
  const journalKey = need('MATE_JOURNAL_KEY');
  if (missing.length) throw new ProductError('configuration_required', `未設定: ${missing.join(', ')}`, 503);
  const parsed = z.object({rpcURL:z.string().url().refine(v=>new URL(v).protocol==='https:'),vault:address,
    attestorKey:key,relayerKey:key,apiToken:z.string().min(32),journalKey:z.string().regex(/^[0-9a-fA-F]{64}$/)})
    .parse({rpcURL,vault,attestorKey,relayerKey,apiToken,journalKey});
  const providers = z.array(providerSchema).max(50).parse(JSON.parse(environment.MATE_PROVIDERS_JSON || '[]'));
  if (new Set(providers.map(p=>p.id)).size !== providers.length) throw new Error('Duplicate provider ID');
  return {...parsed,chainId:11155111,token:SEPOLIA_USDC,providers,
    dataDirectory:path.resolve(environment.MATE_DATA_DIRECTORY || path.join(ROOT,'.data')),
    verifierBinary:path.resolve(environment.MATE_VERIFIER_BINARY || path.join(ROOT,'services/verifier/target/release/mate-verify')),
    verifierKey:path.join(ROOT,'.build/proofs/mate_policy.pkv'),manifest:path.join(ROOT,'.build/proofs/manifest.json'),
    graphApiKey:environment.GRAPH_API_KEY || '',
    graphSubgraphId:environment.GRAPH_SUBGRAPH_ID || '6wQRC7geo9XYAhckfmfo8kbMRLeWU8KQd3XsJqFKmZLT',
    ensParent:environment.ENS_PARENT_NAME || '',ensRegistry:environment.ENS_SUBREGISTRY_ADDRESS || '',
    ensKey:environment.ENS_OPERATOR_PRIVATE_KEY || '',
    host:environment.MATE_BIND_HOST || '127.0.0.1',port:Number(environment.MATE_PORT || 8787),
  };
}
export function loadArtifact(name) {
  return JSON.parse(fs.readFileSync(path.join(ROOT,'.build/contracts',`${name}.json`),'utf8'));
}
