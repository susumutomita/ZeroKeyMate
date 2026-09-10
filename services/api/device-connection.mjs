import {networkConfiguration} from './networks.mjs';
import {boundedJSON} from './http.mjs';

export async function checkDeviceConnection(e,fetchJSON=boundedJSON) {
  let url;
  try{url=new URL(e.MATE_API_URL);}catch{throw new Error('Set MATE_API_URL to the reachable HTTPS origin described in docs/arc-setup.md before full-stack iPhone launch.');}
  if(url.protocol!=='https:' || url.username || url.password || url.search || url.hash || !['','/'].includes(url.pathname)
    || ['localhost','127.0.0.1','[::1]'].includes(url.hostname))
    throw new Error('A physical iPhone needs a reachable HTTPS API origin without embedded credentials or query parameters.');
  if(!/^0x[0-9a-fA-F]{40}$/.test(e.MATE_VAULT_ADDRESS ?? '') || /^0x0{40}$/.test(e.MATE_VAULT_ADDRESS))
    throw new Error('Configure the confirmed MateVault address before full-stack iPhone launch.');
  const expected=networkConfiguration(e);
  let health;
  try{health=await fetchJSON(new URL('/health',url),{signal:AbortSignal.timeout(10_000)},10_000);}
  catch{throw new Error('The HTTPS API could not be verified. Check its certificate, reachability and proxy configuration; TLS verification remains enabled.');}
  if(health?.service!=='ZeroKey Mate API' || health.ready!==true || health.proofVerification!=='available'
    || health.chainId!==expected.chainId || typeof health.vault!=='string' || typeof health.token!=='string'
    || health.vault.toLowerCase()!==e.MATE_VAULT_ADDRESS.toLowerCase()
    || health.token.toLowerCase()!==expected.token.toLowerCase())
    throw new Error('The HTTPS API is not ready or belongs to a different chain, vault or token. App launch stopped.');
  return {apiURL:url.origin,chainId:expected.chainId};
}
