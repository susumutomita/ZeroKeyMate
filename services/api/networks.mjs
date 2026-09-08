import path from 'node:path';
import {defineChain} from 'viem';
import {sepolia} from 'viem/chains';
import {ProductError} from './errors.mjs';

// Public Arc documentation: docs.arc.io/arc/references/contract-addresses
// Gas is native USDC at 18 decimals; vault accounting uses its 6-decimal ERC-20 interface.
const arc = defineChain({id:5042002,name:'Arc Testnet',nativeCurrency:{name:'USDC',symbol:'USDC',decimals:18},
  rpcUrls:{default:{http:['https://rpc.testnet.arc.network']}},
  blockExplorers:{default:{name:'Arcscan',url:'https://testnet.arcscan.app'}}});
const networks = new Map([
  [11155111,{chain:sepolia,name:'Sepolia testnet',token:'0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238'}],
  [5042002,{chain:arc,name:'Arc Testnet',token:'0x3600000000000000000000000000000000000000'}],
]);
export function settlementNetwork(chainId=11155111) {
  const network=networks.get(Number(chainId));
  if(!network)throw new ProductError('wrong_chain','Only Arc Testnet and Sepolia testnet are supported.',503);
  return network;
}
export function networkConfiguration(e=process.env) {
  const chainId=Number(e.MATE_CHAIN_ID||(e.SEPOLIA_RPC_URL?11155111:5042002));
  const network=settlementNetwork(chainId);
  return {chainId,token:network.token,rpcURL:e.MATE_RPC_URL || (chainId===11155111?e.SEPOLIA_RPC_URL:e.ARC_RPC_URL) || network.chain.rpcUrls.default.http[0]};
}

export function stateDirectory(kind,e=process.env) {
  const {chainId}=networkConfiguration(e);
  const root=path.resolve(import.meta.dirname,'../..');
  return path.resolve(kind==='api' ? e.MATE_DATA_DIRECTORY||path.join(root,'.data',chainId===11155111?'':String(chainId))
    : e.PROVIDER_DATA_DIRECTORY||path.join(root,'.data/provider',chainId===11155111?'':String(chainId)));
}
