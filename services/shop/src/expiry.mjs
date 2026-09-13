import {parseAbi} from 'viem';
import {CHAIN_ID,USDC,hex32} from './protocol.mjs';
const ABI=parseAbi(['function authorizationState(address authorizer,bytes32 nonce) view returns (bool)']);

// An absent receipt/log is not proof of non-payment. Close only after both
// providers agree that the original nonce is unused at a finalized block whose
// timestamp has passed the exact signature's validBefore. No new nonce is made.
export async function expiredUnusedPayment(order,clients) {
  const end=order.paymentValidBefore;
  if(clients.length!==2 || !Number.isSafeInteger(end) || end<=order.createdAt || end>order.expiresAt)return null;
  try {
    const finalized=await Promise.all(clients.map(async rpc=>{
      if(await rpc.getChainId()!==CHAIN_ID)throw new Error('wrong_chain');
      return rpc.getBlock({blockTag:'finalized'});
    }));
    if(finalized.some(block=>typeof block.number!=='bigint'))return null;
    const number=finalized[0].number<finalized[1].number?finalized[0].number:finalized[1].number;
    const blocks=await Promise.all(clients.map(rpc=>rpc.getBlock({blockNumber:number})));
    if(blocks.some(block=>block.number!==number || !hex32(block.hash) || typeof block.timestamp!=='bigint' || block.timestamp<BigInt(end))
       || blocks[0].hash!==blocks[1].hash || blocks[0].timestamp!==blocks[1].timestamp)return null;
    const used=await Promise.all(clients.map(rpc=>rpc.readContract({address:USDC,abi:ABI,functionName:'authorizationState',args:[order.payer,order.paymentNonce],blockNumber:number})));
    if(used.some(value=>value!==false))return null;
    return {blockNumber:number.toString(),blockHash:blocks[0].hash,timestamp:blocks[0].timestamp.toString()};
  } catch { return null; }
}
