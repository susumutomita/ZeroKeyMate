import {networkConfiguration,settlementNetwork} from '../services/api/networks.mjs';
export function publicAppConfiguration(e={}) {
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
