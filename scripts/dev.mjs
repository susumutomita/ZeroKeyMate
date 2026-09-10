import {launcherShutdown} from '../services/api/launcher-shutdown.mjs';
import {startLauncherControl} from '../services/api/launcher-control.mjs';
import {startOwnedLauncher} from '../services/api/owned-launcher.mjs';
import {createHash} from 'node:crypto';
import {SpecialistModel} from '../services/provider/model.mjs';
import {startAPI} from '../services/api/server.mjs';
import {startProvider,providerConfiguration} from '../services/provider/server.mjs';
import {configuration} from '../services/api/config.mjs';
import {claimLauncherOwnership} from '../services/api/launcher-ownership.mjs';

// Foreground ownership: Ctrl+C closes only the servers started by this invocation.
let api,provider,launcher,claim,control,closing=false;
let startupFinished;
const startupSettled=new Promise(resolve=>{startupFinished=resolve;});
const shutdown=launcherShutdown(startupSettled,()=>({api,provider,launcher,claim,control}));
function close() {
  closing=true;
  return shutdown().catch(error=>{console.error(error.message);process.exitCode=1;throw error;});
}
for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>{void close().catch(()=>{});});
async function run() {
try {
  // Fail before launching apps or listening when setup is incomplete.
  console.log('[1/5] Checking connection settings');
  const apiConfig=configuration(),providerConfig=providerConfiguration();
  if(apiConfig.chainId!==providerConfig.chainId || apiConfig.vault.toLowerCase()!==providerConfig.vault.toLowerCase())throw new Error('API and specialist must use the same chain and vault.');
  const providerPort=Number(process.env.PROVIDER_PORT||8788);
  const environment=createHash('sha256').update(JSON.stringify({apiConfig,providerConfig})).digest('hex');
  claim=claimLauncherOwnership({apiPort:apiConfig.port,providerPort,environment});
  if(claim.reuse) {
    console.log(`Reusing services already started by pid ${claim.record.pid} at ${claim.record.startedAt}. Not starting a second copy.`);
    const health=await fetch(`http://127.0.0.1:${claim.record.apiPort}/health`,{signal:AbortSignal.timeout(10_000)}).then(r=>r.ok?r.json():null);
    if(!health?.ready || health.chainId!==apiConfig.chainId || health.vault?.toLowerCase()!==apiConfig.vault.toLowerCase())throw new Error('The recorded API is unavailable or belongs to another environment. Inspect the owning launcher before retrying.');
    claim=null; // This invocation does not own the reused services; nothing to release.
  } else {
    control=await startLauncherControl(claim.record,close);
    if(closing)return;
    console.log('[2/5] Checking the real specialist model');
    await new SpecialistModel(providerConfig).ready();
    if(closing)return;
    provider=await startProvider();
    if(closing)return;
    console.log('[3/5] Preparing the API and real proof verifier');
    const started=await startAPI();api=started.server;
    if(closing)return;
    if(!started.health.ready)throw started.configurationError||new Error('The real proof verifier is unavailable.');
  }
  console.log('[4/5] Checking the specialist quote and verifier');
  const quoteResponse=await fetch(`http://127.0.0.1:${providerPort}/v1/quote?service=${providerConfig.service}`,{
    headers:{authorization:`Bearer ${providerConfig.apiToken}`},signal:AbortSignal.timeout(30_000)});
  if(!quoteResponse.ok)throw new Error(`Specialist quote unavailable (HTTP ${quoteResponse.status}). Check model, vault and verifier configuration.`);
  const quote=await quoteResponse.json();
  if(!quote.ready || quote.chainId!==apiConfig.chainId || quote.vault?.toLowerCase()!==apiConfig.vault.toLowerCase() || quote.recipient?.toLowerCase()!==providerConfig.recipient.toLowerCase() || quote.price!==providerConfig.price)throw new Error('Specialist quote does not match this environment.');
  if(closing)return;
  if(!process.argv.includes('--services-only')) {
    console.log('[5/5] Launching Mate');
    const mode=process.argv.includes('--device')?['--device','auto']:process.argv.includes('--simulator')?['--simulator']:['--choose'];
    launcher=startOwnedLauncher('./mate',mode);
    const {code,error}=await launcher.completion;launcher=null;
    if(!closing && (error || code!==0))throw new Error('App launch did not complete. Services are being stopped.');
  }
  if(!closing)console.log('API and specialist are running. Press Ctrl+C or run ./mate stop to stop; pending executions remain recoverable.');
} catch(error) {
  if(!closing){console.error(error.message);process.exitCode=1;}
  closing=true;
} finally {
  startupFinished();
  if(closing)await close().catch(()=>{});
}
}
await run();
