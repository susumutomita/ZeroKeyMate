import {DurableObject} from 'cloudflare:workers';
import {createArcTransaction} from './settlement.mjs';
import {SettlementQueue} from './settlement-queue.mjs';
export {default} from './worker.mjs';

export class ArcSettlementQueue extends DurableObject {
 constructor(ctx,env) {super(ctx,env);this.queue=new SettlementQueue(ctx.storage,createArcTransaction(env));}
 async settle(payload,required) {
  try {return await this.queue.settle(payload,required);}
  catch {throw new Error('settlement_pending');} // Never expose SDK arguments or secrets.
 }
 async alarm() {
  try {await this.queue.alarm();}
  catch {await this.ctx.storage.setAlarm(Date.now()+60000);}
 }
}
