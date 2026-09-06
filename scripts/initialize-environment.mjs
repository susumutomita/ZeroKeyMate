import fs from 'node:fs';
import {randomBytes} from 'node:crypto';
import {generatePrivateKey} from 'viem/accounts';
import {root,loadEnvironment,saveEnvironment} from './environment.mjs';
import path from 'node:path';
process.umask(0o077);
const filename=path.join(root,'.env');
if(!fs.existsSync(filename))fs.copyFileSync(path.join(root,'.env.example'),filename);
const e=loadEnvironment(),changes={};
for(const key of ['MATE_API_TOKEN','MATE_JOURNAL_KEY','PROVIDER_API_TOKEN','PROVIDER_JOURNAL_KEY'])
 if(!e[key])changes[key]=randomBytes(32).toString('hex');
for(const key of ['MATE_RELAYER_PRIVATE_KEY','MATE_ATTESTOR_PRIVATE_KEY'])
 if(!e[key])changes[key]=generatePrivateKey();
saveEnvironment(changes);
console.log('Local pairing and testnet-service keys initialized in .env (mode 0600). Existing keys were preserved.');
console.log('No funds were sent, no accounts were logged into, and no API credentials were invented.');
