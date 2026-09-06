import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {root} from './environment.mjs';
const e=process.env;
const groups={
 'Native app': ['PRIVY_APP_ID','PRIVY_IOS_CLIENT_ID'],
 'Execution API': ['SEPOLIA_RPC_URL','MATE_VAULT_ADDRESS','MATE_ATTESTOR_PRIVATE_KEY','MATE_RELAYER_PRIVATE_KEY','MATE_API_TOKEN','MATE_JOURNAL_KEY'],
 'ENSv2 naming': ['ENS_PARENT_NAME','ENS_OPERATOR_PRIVATE_KEY','ENS_SUBREGISTRY_ADDRESS','ENS_RESOLVER_FACTORY'],
 'Live discovery': ['GRAPH_API_KEY','MATE_PROVIDERS_JSON'],
 'Actual specialist': ['PROVIDER_RECIPIENT_ADDRESS','PROVIDER_API_TOKEN','PROVIDER_JOURNAL_KEY'],
 'Physical-device installation': ['MATE_DEVELOPMENT_TEAM'],
};
const report={kind:'configuration-report-not-runtime-verification',groups:{},sources:{},warnings:[]};
for(const[name,keys]of Object.entries(groups))report.groups[name]={missing:keys.filter(key=>!e[key]||(key==='MATE_PROVIDERS_JSON'&&e[key]==='[]'))};
for(const file of ['services/api/server.mjs','services/provider/server.mjs','apps/ios/ZeroKeyMate/Resources/Proofs/manifest.json','.tools/verity/output/Verity.xcframework/mate-runtime.json'])
 report.sources[file]=fs.existsSync(path.join(root,file));
if((e.MATE_API_URL||'').startsWith('http:'))report.warnings.push('Physical iPhone requires HTTPS for the execution API; localhost HTTP is Simulator-only.');
report.warnings.push('Apple provisioning, biometric consent, account login, funded testnet wallets and a real ENSv2 parent cannot be fabricated by a launch command.');
console.log(JSON.stringify(report,null,2));
