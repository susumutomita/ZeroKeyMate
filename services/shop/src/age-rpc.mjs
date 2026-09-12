import {keccak256} from 'viem';
import {CHAIN_ID, hex32, nowSeconds} from './protocol.mjs';
import {AGE_ABI} from './age.mjs';

// A 2-of-2 independent-provider trust boundary, NOT an Ethereum light client.
// A single fabricated RPC approval, fork, timeout or stale head cannot unlock
// checkout. Both providers colluding remains an explicit deployment assumption.
export async function checkedAgeCall(env,rpcs,args,expected) {
  if(rpcs.length!==2 || rpcs[0]===rpcs[1])return false;
  try {
    const heads=await Promise.all(rpcs.map(async rpc=>{
      if(await rpc.getChainId()!==CHAIN_ID)throw new Error('wrong_chain');
      return rpc.getBlock({blockTag:'latest'});
    }));
    if(heads.some(head=>typeof head.number!=='bigint' || head.number<0n))return false;
    const blockNumber=heads[0].number<heads[1].number?heads[0].number:heads[1].number;
    const snapshots=await Promise.all(rpcs.map(async rpc=>{
      const [block,code]=await Promise.all([
        rpc.getBlock({blockNumber}),rpc.getCode({address:env.AGE_GATE_ADDRESS,blockNumber})
      ]);
      const age=BigInt(nowSeconds())-block.timestamp;
      if(block.number!==blockNumber || !hex32(block.hash) || age< -30n || age>120n
        || !code || code==='0x' || keccak256(code).toLowerCase()!==env.AGE_GATE_CODE_HASH.toLowerCase())throw new Error('untrusted_snapshot');
      return {rpc,block};
    }));
    if(snapshots[0].block.hash.toLowerCase()!==snapshots[1].block.hash.toLowerCase()
      || snapshots[0].block.timestamp!==snapshots[1].block.timestamp)return false;
    const answers=await Promise.all(snapshots.map(({rpc})=>rpc.readContract({
      address:env.AGE_GATE_ADDRESS,abi:AGE_ABI,functionName:'verifyOrderAge',args,blockNumber,gas:1000000n
    })));
    return answers.every(answer=>answer===expected);
  } catch {return false;}
}
