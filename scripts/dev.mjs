import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import {SpecialistModel} from '../services/provider/model.mjs';
import {startAPI} from '../services/api/server.mjs';
import {startProvider,providerConfiguration} from '../services/provider/server.mjs';
import {configuration} from '../services/api/config.mjs';
import {claimLauncherOwnership} from '../services/api/launcher-ownership.mjs';

// Foreground ownership: Ctrl+C closes only the servers started by this invocation.
let api,provider,launcher,claim,closing=false;
async function close() {
  closing=true;
  launcher?.kill('SIGTERM');
  await Promise.all([api,provider].filter(Boolean).map(server=>new Promise(resolve=>{
    const timer=setTimeout(()=>{server.closeAllConnections();resolve();},5_000);
    server.close(()=>{clearTimeout(timer);resolve();});
    server.closeIdleConnections();
  })));
  claim?.release?.();
}
for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>{void close();});
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
    console.log('[2/5] Checking the real specialist model');
    await new SpecialistModel(providerConfig).ready();
    if(closing){await close();process.exit(0);}
    provider=await startProvider();
    if(closing){await close();process.exit(0);}
    console.log('[3/5] Preparing the API and real proof verifier');
    const started=await startAPI();api=started.server;
    if(closing){await close();process.exit(0);}
    if(!started.health.ready)throw started.configurationError||new Error('The real proof verifier is unavailable.');
  }
  console.log('[4/5] Checking the specialist quote and verifier');
  const quoteResponse=await fetch(`http://127.0.0.1:${providerPort}/v1/quote?service=${providerConfig.service}`,{
    headers:{authorization:`Bearer ${providerConfig.apiToken}`},signal:AbortSignal.timeout(30_000)});
  if(!quoteResponse.ok)throw new Error(`Specialist quote unavailable (HTTP ${quoteResponse.status}). Check model, vault and verifier configuration.`);
  const quote=await quoteResponse.json();
  if(!quote.ready || quote.chainId!==apiConfig.chainId || quote.vault?.toLowerCase()!==apiConfig.vault.toLowerCase() || quote.recipient?.toLowerCase()!==providerConfig.recipient.toLowerCase() || quote.price!==providerConfig.price)throw new Error('Specialist quote does not match this environment.');
  if(closing){await close();process.exit(0);}
  if(!process.argv.includes('--services-only')) {
    console.log('[5/5] Launching Mate');
    const mode=process.argv.includes('--device')?['--device','auto']:process.argv.includes('--simulator')?['--simulator']:['--choose'];
    launcher=spawn('./mate',mode,{stdio:'inherit'});
    const [code]=await once(launcher,'exit');launcher=null;
    if(code!==0)throw new Error('App launch did not complete. Services are being stopped.');
  }
  console.log('API and specialist are running. Press Ctrl+C to stop; pending executions remain recoverable.');
} catch(error) {
  console.error(error.message);await close();process.exitCode=1;
}
