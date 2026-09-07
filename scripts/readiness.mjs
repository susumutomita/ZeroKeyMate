import fs from 'node:fs';
import path from 'node:path';
const ROOT=path.resolve(import.meta.dirname,'..');
const e=process.env;
const present=names=>names.every(name=>Boolean(e[name]));
const exists=file=>fs.existsSync(path.join(ROOT,file));
console.log(JSON.stringify({
  readiness:'not-release-verified',
  configuration:{
    privy:present(['PRIVY_APP_ID','PRIVY_IOS_CLIENT_ID']),
    execution:present(['SEPOLIA_RPC_URL','MATE_VAULT_ADDRESS','MATE_ATTESTOR_PRIVATE_KEY','MATE_RELAYER_PRIVATE_KEY','MATE_API_TOKEN','MATE_JOURNAL_KEY']),
    graph:present(['GRAPH_API_KEY']),
    ens:present(['ENS_PARENT_NAME','ENS_SUBREGISTRY_ADDRESS','ENS_OPERATOR_PRIVATE_KEY','ENS_RESOLVER_FACTORY']),
    specialist:present(['OLLAMA_MODEL','PROVIDER_API_TOKEN','PROVIDER_RECIPIENT','PROVIDER_JOURNAL_KEY','MATE_ATTESTOR_ADDRESS']),
  },
  artifacts:{
    api:exists('services/api/server.mjs'),specialist:exists('services/provider/server.mjs'),
    verifier:exists('services/verifier/target/release/mate-verify'),
    proofSetup:exists('apps/ios/ZeroKeyMate/Resources/Proofs/manifest.json'),
    nativeRuntime:exists('.tools/verity/output/Verity.xcframework/mate-runtime.json'),
  },
  requiresIndependentEvidence:[
    'Physical iPhone / DockKit capture, tracking and stop behavior',
    'On-device speech, continuous conversation and Foundation Models',
    'Live Privy, Sepolia, ENSv2 and The Graph acceptance',
    'Proof generated on the target iPhone through payment to actual specialist result',
    'Device layout, accessibility, latency and memory',
  ],
  note:'Presence of configuration or files never counts as integration verification. No secrets are printed.',
},null,2));
process.exitCode=1;
