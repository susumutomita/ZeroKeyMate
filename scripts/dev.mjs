import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {startAPI} from '../services/api/server.mjs';
import {startProvider,providerConfiguration} from '../services/provider/server.mjs';
import {configuration} from '../services/api/config.mjs';

// Foreground ownership: Ctrl+C closes only the servers started by this invocation.
let api,provider,launcher,closing=false;
async function close() {
  closing=true;
  launcher?.kill('SIGTERM');
  await Promise.all([api,provider].filter(Boolean).map(server=>new Promise(resolve=>server.close(resolve))));
}
for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>{void close();});
try {
  configuration();providerConfiguration(); // Fail before launching apps or listening when setup is incomplete.
  provider=await startProvider();
  if(closing){await close();process.exit(0);}
  const started=await startAPI();api=started.server;
  if(closing){await close();process.exit(0);}
  if(!started.health.ready)throw started.configurationError||new Error('The real proof verifier is unavailable.');
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
