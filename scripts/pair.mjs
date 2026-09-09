import fs from 'node:fs';
import path from 'node:path';
import {PairingStore} from '../services/api/pairing.mjs';
import {networkConfiguration,stateDirectory} from '../services/api/networks.mjs';
const e=process.env;
let store;
try {
  if(!/^0x[0-9a-fA-F]{40}$/.test(e.MATE_VAULT_ADDRESS ?? '') || /^0x0{40}$/.test(e.MATE_VAULT_ADDRESS))throw new Error('Configure MATE_VAULT_ADDRESS first.');
  const args=process.argv.slice(2);
  if(args.length>1 || (args.length && args[0]!=='--revoke'))throw new Error('Usage: npm run pair [-- --revoke]');
  const directory=stateDirectory('api',e),{chainId}=networkConfiguration(e);
  store=new PairingStore(path.join(directory,'pairing.sqlite'),`${chainId}:${e.MATE_VAULT_ADDRESS.toLowerCase()}`);
  const filename=path.join(directory,'pairing-code.txt');
  if(args[0]==='--revoke') {
    store.revoke();fs.rmSync(filename,{force:true});
    console.log('Revoked device sessions and outstanding pairing codes for this deployment.');
  } else {
    const {code,expiresAt}=store.issue();
    // Exclusive creation prevents following a pre-existing symlink. Never log the secret.
    fs.rmSync(filename,{force:true});
    fs.writeFileSync(filename,`${code}\n`,{mode:0o600,flag:'wx'});
    console.log(`One-time code saved privately to ${filename}. Expires ${new Date(expiresAt*1000).toISOString()}. Enter it in Mate > Connection. Sessions last one hour or 500 requests.`);
  }
} catch(error) {console.error(error.message);process.exitCode=1;}
finally{store?.close();}
