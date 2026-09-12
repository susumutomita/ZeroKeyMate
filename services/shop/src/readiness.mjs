import {NETWORK, configuration} from './protocol.mjs';
import {EMPTY_AGE_ARGUMENTS} from './age.mjs';
import {checkedAgeCall} from './age-rpc.mjs';
import {supportedSettlement} from './settlement.mjs';
export const MAX_ORDERS=1000;

// Readiness reads public gas balance/network state, never submits a payment.
export const supportedNetworks = supportedSettlement;

export async function checkoutReady(env,rpc,supported= supportedNetworks,secondary) {
  if(!configuration(env) || !env.API_LIMIT || !env.ORDER_CREATION_LIMIT || !secondary)return false;
  try {
    const results=await Promise.allSettled([
      checkedAgeCall(env,[rpc,secondary],EMPTY_AGE_ARGUMENTS,false),
      env.ORDERS.prepare('SELECT count(*) AS count FROM orders').first(),supported(env)
    ]);
    if(results.some(result=>result.status!=='fulfilled'))return false;
    const [networkChecked,capacity,facilitator]=results.map(result=>result.value);
    return networkChecked && Number.isSafeInteger(capacity?.count) && capacity.count<MAX_ORDERS
      && Array.isArray(facilitator?.kinds) && facilitator.kinds.some(kind=>kind.x402Version===2 && kind.scheme==='exact' && kind.network===NETWORK);
  } catch {return false;}
}
