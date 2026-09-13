import fs from 'node:fs';
import {publicAppConfiguration} from './app-configuration.mjs';
import path from 'node:path';
import {toFunctionSelector} from 'viem';
const root=path.resolve(import.meta.dirname,'..');
const directory=path.join(root,'apps/ios/ZeroKeyMate/Resources');
fs.mkdirSync(directory,{recursive:true});
const names=['approve(address,uint256)','deposit(uint256)','withdraw(uint256)','revoke(bytes32)'];
fs.writeFileSync(path.join(directory,'Selectors.json'),JSON.stringify(Object.fromEntries(names.map(n=>[n,toFunctionSelector(n)])),null,2)+'\n');
// Bundles contain public identifiers only. Pairing credentials are exchanged at runtime.
const config=publicAppConfiguration(process.env);
fs.writeFileSync(path.join(directory,'Configuration.json'),JSON.stringify(config,null,2)+'\n',{mode:0o600});
console.log('Generated native selectors and installation configuration; no server signing keys are embedded.');
