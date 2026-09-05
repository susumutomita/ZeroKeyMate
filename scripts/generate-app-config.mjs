import fs from 'node:fs';
import path from 'node:path';
import {toFunctionSelector} from 'viem';
const root=path.resolve(import.meta.dirname,'..');
const directory=path.join(root,'apps/ios/ZeroKeyMate/Resources');
fs.mkdirSync(directory,{recursive:true});
const names=['approve(address,uint256)','deposit(uint256)','withdraw(uint256)','revoke(bytes32)'];
fs.writeFileSync(path.join(directory,'Selectors.json'),JSON.stringify(Object.fromEntries(names.map(n=>[n,toFunctionSelector(n)])),null,2)+'\n');
// Only public app identifiers and this installation's local pairing token belong
// in the app. Attestor, deployment, ENS, Graph and model provider secrets do NOT.
const e=process.env;
const config={apiURL:e.MATE_API_URL??'http://127.0.0.1:8787',apiToken:e.MATE_API_TOKEN??'',
  privyAppID:e.PRIVY_APP_ID??'',privyClientID:e.PRIVY_IOS_CLIENT_ID??'',
  rpcURL:e.SEPOLIA_RPC_URL??'https://ethereum-sepolia-rpc.publicnode.com',
  vault:e.MATE_VAULT_ADDRESS??'',token:e.MATE_TOKEN_ADDRESS??'',chainID:11155111};
fs.writeFileSync(path.join(directory,'Configuration.json'),JSON.stringify(config,null,2)+'\n',{mode:0o600});
console.log('Generated native selectors and installation configuration; no server signing keys are embedded.');
