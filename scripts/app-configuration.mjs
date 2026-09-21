import {networkConfiguration,settlementNetwork} from '../services/api/networks.mjs';
export function publicAppConfiguration(e={}, {shopConfigured=false,previous={}}={}) {
  if(shopConfigured) {
    if(e.MATE_CHAIN_ID!==undefined && e.MATE_CHAIN_ID!=='5042002')
      throw new Error('A configured shop build requires MATE_CHAIN_ID=5042002 (Arc Testnet).');
    // ShopConnection is an explicit local installation choice. A legacy
    // SEPOLIA_RPC_URL must not switch that app back to Sepolia on rebuild.
    // Only these public IDs can be reused, never a pairing token or RPC URL.
    const prior=previous && typeof previous==='object' ? previous : {};
    e={...e,MATE_CHAIN_ID:'5042002',
      PRIVY_APP_ID:e.PRIVY_APP_ID??(typeof prior.privyAppID==='string'?prior.privyAppID:''),
      PRIVY_IOS_CLIENT_ID:e.PRIVY_IOS_CLIENT_ID??(typeof prior.privyClientID==='string'?prior.privyClientID:'')};
  }
  const network=networkConfiguration(e);
  const apiURL=e.MATE_API_URL??'http://127.0.0.1:8787',api=new URL(apiURL);
  if(api.username||api.password||api.search||api.hash||!['','/'].includes(api.pathname)
    || !(api.protocol==='https:' || (api.protocol==='http:' && ['127.0.0.1','localhost','[::1]'].includes(api.hostname))))
    throw new Error('MATE_API_URL must be an HTTPS origin without credentials or query parameters (localhost is allowed for Simulator).');
  return {apiURL,apiToken:'',privyAppID:e.PRIVY_APP_ID??'',privyClientID:e.PRIVY_IOS_CLIENT_ID??'',
    rpcURL:settlementNetwork(network.chainId).chain.rpcUrls.default.http[0],
    vault:e.MATE_VAULT_ADDRESS??'',token:network.token,
    ensParent:network.chainId===11155111?(e.ENS_PARENT_NAME||''):'',chainID:network.chainId};
}
