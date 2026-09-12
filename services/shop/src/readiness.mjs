import {keccak256, parseAbi} from 'viem';
import {CHAIN_ID, NETWORK, configuration, nowSeconds} from './protocol.mjs';

const ageABI=parseAbi(['function isOrderAgeVerified(bytes32 orderHash,address payer,uint256 minimumAge,uint256 expiresAt) view returns (bool)']);
const zeroHash='0x'+'00'.repeat(32), zeroAddress='0x'+'00'.repeat(20);
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

export async function checkoutReady(env,rpc,supported= supportedNetworks) {
  if(!configuration(env) || !env.API_LIMIT || !env.ORDER_CREATION_LIMIT)return false;
  try {
    const results=await Promise.allSettled([
      rpc.getChainId(),rpc.getBlock({blockTag:'latest'}),rpc.getCode({address:env.AGE_GATE_ADDRESS}),
      rpc.readContract({address:env.AGE_GATE_ADDRESS,abi:ageABI,functionName:'isOrderAgeVerified',args:[zeroHash,zeroAddress,20n,0n]}),
      env.ORDERS.prepare('SELECT count(*) AS count FROM orders').first(),supported()
    ]);
    if(results.some(result=>result.status!=='fulfilled'))return false;
    const [chain,block,code,invalidOrderApproved,capacity,facilitator]=results.map(result=>result.value);
    const age=BigInt(nowSeconds())-block.timestamp;
    return chain===CHAIN_ID && age>=-30n && age<=120n && Boolean(code) && code!=='0x'
      && keccak256(code).toLowerCase()===env.AGE_GATE_CODE_HASH.toLowerCase()
      && invalidOrderApproved===false && Number.isSafeInteger(capacity?.count) && capacity.count<MAX_ORDERS
      && Array.isArray(facilitator?.kinds) && facilitator.kinds.some(kind=>kind.x402Version===2 && kind.scheme==='exact' && kind.network===NETWORK);
  } catch {return false;}
}
