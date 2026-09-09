import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {startAPI} from '../services/api/server.mjs';
import {startProvider,providerConfiguration} from '../services/provider/server.mjs';
import {configuration} from '../services/api/config.mjs';
import {claimLauncherOwnership} from '../services/api/launcher-ownership.mjs';

// Foreground ownership: Ctrl+C closes only the servers started by this invocation.
let api,provider,launcher,claim,closing=false;
async function close() {
  closing=true;
  launcher?.kill('SIGTERM');
  await Promise.all([api,provider].filter(Boolean).map(server=>new Promise(resolve=>server.close(resolve))));
  claim?.release();
}
for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>{void close();});
try {
  // Fail before launching apps or listening when setup is incomplete.
  const apiConfig=configuration();providerConfiguration();
  const providerPort=Number(process.env.PROVIDER_PORT||8788);
  claim=claimLauncherOwnership({apiPort:apiConfig.port,providerPort});
  if(claim.reuse) {
    console.log(`Reusing services already started by pid ${claim.record.pid} at ${claim.record.startedAt}. Not starting a second copy.`);
    const health=await fetch(`http://127.0.0.1:${claim.record.apiPort}/health`).then(r=>r.ok?r.json():null).catch(()=>null);
    if(!health)throw new Error(`pid ${claim.record.pid} owns this checkout's services, but the API on port ${claim.record.apiPort} did not answer. Stop that process, or remove .data/launcher-owner.json if it is no longer running, then try again.`);
    claim=null; // This invocation does not own the reused services; nothing to release.
  } else {
    provider=await startProvider();
    if(closing){await close();process.exit(0);}
    const started=await startAPI();api=started.server;
    if(closing){await close();process.exit(0);}
    if(!started.health.ready)throw started.configurationError||new Error('The real proof verifier is unavailable.');
  }
  if(!process.argv.includes('--services-only')) {
    const mode=process.argv.includes('--device')?['--device','auto']:process.argv.includes('--simulator')?['--simulator']:['--choose'];
    launcher=spawn('./mate',mode,{stdio:'inherit'});
    const [code]=await once(launcher,'exit');launcher=null;
    if(code!==0)throw new Error('App launch did not complete. Services are being stopped.');
  }
  console.log('API and specialist are running. Press Ctrl+C to stop; pending executions remain recoverable.');
} catch(error) {
  console.error(error.message);await close();process.exitCode=1;
}
