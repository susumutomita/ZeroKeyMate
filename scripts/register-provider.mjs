import fs from 'node:fs';
import path from 'node:path';
import {createPublicClient,http} from 'viem';
import {sepolia} from 'viem/chains';
import {privateKeyToAccount} from 'viem/accounts';
import {ROOT,secretKey,httpsURL} from '../services/api/config.mjs';
import {ProductError} from '../services/api/errors.mjs';
import {TransactionLane} from '../services/api/chain.mjs';
import {Journal} from '../services/api/journal.mjs';
import {processLock} from '../services/api/process-lock.mjs';
import {REGISTRY,REGISTRATION_CHAIN,registrationConfiguration,registerProvider} from '../services/api/provider-registration.mjs';
const e=process.env;
let journal,release;
try {
  const args=process.argv.slice(2);
  if(new Set(args).size!==args.length || args.some(arg=>!['--submit','--renew-wallet-authorization'].includes(arg)) || (args.includes('--renew-wallet-authorization') && !args.includes('--submit')))throw new ProductError('registration_arguments','Usage: npm run register-provider [-- --submit [--renew-wallet-authorization]]');
  const key=e.PROVIDER_REGISTRATION_PRIVATE_KEY?secretKey.parse(e.PROVIDER_REGISTRATION_PRIVATE_KEY):null;
  const signer=key?privateKeyToAccount(key):null;
  const config=registrationConfiguration(e,e.PROVIDER_REGISTRATION_OWNER||signer?.address);
  if(!args.includes('--submit')) {
    console.log(JSON.stringify({mode:'preview-only',chainId:REGISTRATION_CHAIN,registry:REGISTRY,...config},null,2));
    console.log('No transaction signed or sent. Review public metadata, owner and payout wallet before using --submit.');
  } else {
    if(!key)throw new ProductError('registration_key','Configure the registration owner key privately before submitting.');
    const recipientSigner=e.PROVIDER_REGISTRATION_RECIPIENT_PRIVATE_KEY?privateKeyToAccount(secretKey.parse(e.PROVIDER_REGISTRATION_RECIPIENT_PRIVATE_KEY)):signer;
    const rpcURL=httpsURL.parse(e.SEPOLIA_RPC_URL||sepolia.rpcUrls.default.http[0]);
    const client=createPublicClient({chain:sepolia,transport:http(rpcURL,{timeout:20_000,retryCount:0})});
    const directory=path.join(ROOT,'.data/provider-registration',config.owner.toLowerCase());
    release=processLock(path.join(directory,'registration.lock'));
    journal=new Journal(path.join(directory,'registration.sqlite'),e.MATE_JOURNAL_KEY);
    const lane=new TransactionLane({publicClient:client,rpcURL,key,journal,chainId:REGISTRATION_CHAIN});
    const result=await registerProvider({config,client,lane,journal,recipientSigner,renewWalletAuthorization:args.includes('--renew-wallet-authorization')});
    fs.mkdirSync(path.join(ROOT,'.build/registrations'),{recursive:true});
    fs.writeFileSync(path.join(ROOT,'.build/registrations','provider.json'),JSON.stringify(result,null,2)+'\n',{mode:0o600});
    console.log(JSON.stringify(result,null,2));
    console.log('On-chain registration confirmed. Graph indexing and a matching live specialist quote still need verification.');
  }
} catch(error) {
  console.error(error instanceof ProductError?error.message:'Provider registration could not be confirmed. Check configuration and retain the registration journal before retrying; raw SDK errors are withheld.');
  process.exitCode=1;
} finally {journal?.close();release?.();}
