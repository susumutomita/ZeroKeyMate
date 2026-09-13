import {NETWORK, configuration} from './protocol.mjs';
import {EMPTY_AGE_ARGUMENTS} from './age.mjs';
import {checkedAgeCall} from './age-rpc.mjs';
import {supportedSettlement} from './settlement.mjs';
export const MAX_ORDERS=1000;

// Readiness reads public gas balance/network state, never submits a payment.
export const supportedNetworks = supportedSettlement;

export async function checkoutReady(env,rpc,supported= supportedNetworks,secondary) {
  return (await checkoutReadiness(env,rpc,supported,secondary)).available;
}

// Fixed categories only: no error text, RPC response, order, key or balance.
export async function checkoutReadiness(env,rpc,supported= supportedNetworks,secondary) {
  const unavailable=code=>({available:false,code});
  if(!configuration(env) || !env.API_LIMIT || !env.ORDER_CREATION_LIMIT || !secondary)return unavailable('configuration');
  try {
    const results=await Promise.allSettled([
      checkedAgeCall(env,[rpc,secondary],EMPTY_AGE_ARGUMENTS,false),
      env.ORDERS.prepare('SELECT count(*) AS count FROM orders').first(),supported(env)
    ]);
    const stages=['age_network','storage','settlement_network'];
    for(let i=0;i<results.length;i++)if(results[i].status!=='fulfilled')return unavailable(stages[i]);
    const [networkChecked,capacity,facilitator]=results.map(result=>result.value);
    if(!networkChecked)return unavailable('age_network');
    if(!Number.isSafeInteger(capacity?.count) || capacity.count<0)return unavailable('storage');
    if(capacity.count>=MAX_ORDERS)return unavailable('capacity');
    if(!Array.isArray(facilitator?.kinds) || !facilitator.kinds.some(kind=>kind.x402Version===2 && kind.scheme==='exact' && kind.network===NETWORK))return unavailable('settlement');
    return {available:true,code:'ready'};
  } catch {return unavailable('configuration');}
}
