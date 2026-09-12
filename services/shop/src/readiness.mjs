import {NETWORK, configuration} from './protocol.mjs';
import {EMPTY_AGE_ARGUMENTS} from './age.mjs';
import {checkedAgeCall} from './age-rpc.mjs';
export const MAX_ORDERS=1000;

// Read-only discovery has its own short deadline and response-size bound. It
// never sends a payment, a capability, card data, or wallet credentials.
export async function supportedNetworks() {
  const response=await fetch('https://x402.org/facilitator/supported',{
    signal:AbortSignal.timeout(3000),redirect:'error',headers:{Accept:'application/json'}
  });
  if(!response.ok || !response.body)throw new Error('facilitator_unavailable');
  const reader=response.body.getReader(),decoder=new TextDecoder();
  let text='',size=0;
  try {
    while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;
      if(size>32768)throw new Error('facilitator_response_too_large');text+=decoder.decode(value,{stream:true});}
    return JSON.parse(text+decoder.decode());
  } finally {await reader.cancel();}
}

export async function checkoutReady(env,rpc,supported= supportedNetworks,secondary) {
  if(!configuration(env) || !env.API_LIMIT || !env.ORDER_CREATION_LIMIT || !secondary)return false;
  try {
    const results=await Promise.allSettled([
      checkedAgeCall(env,[rpc,secondary],EMPTY_AGE_ARGUMENTS,false),
      env.ORDERS.prepare('SELECT count(*) AS count FROM orders').first(),supported()
    ]);
    if(results.some(result=>result.status!=='fulfilled'))return false;
    const [networkChecked,capacity,facilitator]=results.map(result=>result.value);
    return networkChecked && Number.isSafeInteger(capacity?.count) && capacity.count<MAX_ORDERS
      && Array.isArray(facilitator?.kinds) && facilitator.kinds.some(kind=>kind.x402Version===2 && kind.scheme==='exact' && kind.network===NETWORK);
  } catch {return false;}
}
