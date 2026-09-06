import fs from 'node:fs';
import path from 'node:path';
import {toFunctionSelector} from 'viem';
import {SEPOLIA_USDC} from '../services/api/config.mjs';
const root=path.resolve(import.meta.dirname,'..');
const directory=path.join(root,'apps/ios/ZeroKeyMate/Resources');fs.mkdirSync(directory,{recursive:true});
const names=['approve(address,uint256)','deposit(uint256)','withdraw(uint256)','revoke(bytes32)',
 'setText(bytes32,string,string)','authorizeTextRoles(bytes,string,address,bool)'];
fs.writeFileSync(path.join(directory,'Selectors.json'),JSON.stringify(Object.fromEntries(names.map(name=>[name,toFunctionSelector(name)])),null,2)+'\n');
const e=process.env;
const config={apiURL:e.MATE_API_URL||'http://127.0.0.1:8787',apiToken:e.MATE_API_TOKEN||'',
 privyAppID:e.PRIVY_APP_ID||'',privyClientID:e.PRIVY_IOS_CLIENT_ID||'',
 rpcURL:e.SEPOLIA_RPC_URL||'https://ethereum-sepolia-rpc.publicnode.com',vault:e.MATE_VAULT_ADDRESS||'',
 token:SEPOLIA_USDC,ensParent:e.ENS_PARENT_NAME||'',chainID:11155111};
fs.writeFileSync(path.join(directory,'Configuration.json'),JSON.stringify(config,null,2)+'\n',{mode:0o600});
console.log('Native configuration written. Attestor, relayer, ENS, Graph and provider secrets are not bundled.');
