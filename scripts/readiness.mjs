import fs from 'node:fs';
import {networkConfiguration} from '../services/api/networks.mjs';
import path from 'node:path';
const ROOT=path.resolve(import.meta.dirname,'..');
const e=process.env;
const present=names=>names.every(name=>Boolean(e[name]));
const exists=file=>fs.existsSync(path.join(ROOT,file));
console.log(JSON.stringify({
  readiness:'not-release-verified',
  chainId:networkConfiguration(e).chainId,
  configuration:{
    privy:present(['PRIVY_APP_ID','PRIVY_IOS_CLIENT_ID']),
    execution:present(['MATE_VAULT_ADDRESS','MATE_RELAYER_PRIVATE_KEY','MATE_API_TOKEN','MATE_JOURNAL_KEY']) && (e.MATE_ATTESTOR_MODE==='circle'?present(['CIRCLE_ATTESTOR_ADDRESS']):present(['MATE_ATTESTOR_PRIVATE_KEY'])),
    graph:present(['GRAPH_API_KEY']),
    circleAgentWallet: e.MATE_ATTESTOR_MODE==='circle' && present(['CIRCLE_ATTESTOR_ADDRESS']),
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
    'Live Privy, Arc, Circle Agent Wallet and The Graph acceptance',
    'Proof generated on the target iPhone through payment to actual specialist result',
    'Device layout, accessibility, latency and memory',
  ],
  note:'Presence of configuration or files never counts as integration verification. No secrets are printed.',
},null,2));
process.exitCode=1;
