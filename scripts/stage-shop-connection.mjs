// Public deployment coordinates only. No .env, credential, wallet or signing.
import {parseArgs} from 'node:util';
import {writeFile,mkdir} from 'node:fs/promises';
import {createPublicClient,http,keccak256,isAddress} from 'viem';
import {baseSepolia} from 'viem/chains';
const {values}=parseArgs({options:{origin:{type:'string'},recipient:{type:'string'},'age-gate':{type:'string'},'age-gate-code-hash':{type:'string'}}});
const origin=new URL(values.origin);
if(origin.protocol!=='https:' || origin.username || origin.password || origin.search || origin.hash || origin.pathname!=='/' || origin.port)throw new Error('Use only the public HTTPS store origin');
for(const key of ['recipient','age-gate'])if(!isAddress(values[key]??'',{strict:false}) || /^0x0{40}$/i.test(values[key]))throw new Error(`Invalid public ${key}`);
if(!/^0x[0-9a-fA-F]{64}$/.test(values['age-gate-code-hash']??''))throw new Error('Expected reviewed public gate code hash');
const clients=['https://sepolia.base.org','https://base-sepolia-rpc.publicnode.com'].map(url=>createPublicClient({chain:baseSepolia,transport:http(url,{timeout:5000,retryCount:0})}));
await Promise.all(clients.map(async client=>{
  if(await client.getChainId()!==84532)throw new Error('Wrong testnet');
  const code=await client.getCode({address:values['age-gate']});
  if(!code || code==='0x' || keccak256(code).toLowerCase()!==values['age-gate-code-hash'].toLowerCase())throw new Error('Deployed gate does not match the reviewed hash');
}));
const connection={origin:origin.origin,recipient:values.recipient.toLowerCase(),ageGate:values['age-gate'].toLowerCase(),ageGateCodeHash:values['age-gate-code-hash'].toLowerCase()};
const destination=new URL('../apps/ios/ZeroKeyMate/Resources/ShopConnection.json',import.meta.url);
await mkdir(new URL('.',destination),{recursive:true});
await writeFile(destination,JSON.stringify(connection,null,2)+'\n',{flag:'wx'});
console.log('Staged public shop connection after two-provider code checks. Rebuild the app; no order, signing or payment performed.');
