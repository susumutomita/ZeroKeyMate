import {address,hex32} from './protocol.mjs';

// One coordinator per sponsor, not per order: the EVM account nonce is shared.
// Durable records survive eviction, and contain only a signed public USDC
// transaction until its sponsor nonce is finalized. No key/card data is stored.
export class SettlementQueue {
 constructor(storage,transaction,{clock=Date.now}={}) {
  this.storage=storage;this.transaction=transaction;this.clock=clock;this.tail=Promise.resolve();
 }
 exclusive(action) {
  const result=this.tail.then(action);this.tail=result.catch(()=>{});return result;
 }
 async progress() {
  const active=await this.storage.get('active');
  if(!active)return true;
  const record=await this.storage.get(active);
  if(!record || record.sponsor!==this.transaction.sponsor)throw new Error('settlement_configuration_changed');
  // Schedule before network I/O so an eviction or lost response resumes the
  // same bytes. Finalized nonce consumption frees the slot; it does NOT attest
  // to payment success. Worker/iPhone still verify both USDC events separately.
  await this.storage.setAlarm(this.clock()+60000);
  if(await this.transaction.nonce('finalized')>record.nonce) {
   const {raw,...retained}=record;
   await this.storage.transaction(async tx=>{
    await tx.put({[active]:retained,nonceFloor:record.nonce+1});
    await tx.delete('active');await tx.deleteAlarm();
   });
   return true;
  }
  // Lost submission responses and alarms can only rebroadcast this exact
  // transaction; they never allocate a replacement nonce or raise its fee.
  try {await this.transaction.broadcast(record);}catch {/* The durable alarm retries. */}
  return false;
 }
 settle(payload,required) {
  return this.exclusive(async()=>{
   const a=payload?.payload?.authorization;
   if(!address(a?.from) || !hex32(a?.nonce))throw new Error('invalid_payment');
   const key=`payment:${a.from.toLowerCase()}:${a.nonce.toLowerCase()}`;
   const previous=await this.storage.get(key);
   if(previous) {
    if(previous.sponsor!==this.transaction.sponsor)throw new Error('settlement_configuration_changed');
    if(await this.storage.get('active')===key)await this.progress();
    return previous.result;
   }
   if(!await this.progress())throw new Error('settlement_busy');
   const count=(await this.storage.get('count'))??0;
   if(count>=1000)throw new Error('settlement_capacity');
   const [latest,pending]=await Promise.all([this.transaction.nonce('latest'),this.transaction.nonce('pending')]);
   if(latest!==pending || latest<((await this.storage.get('nonceFloor'))??0))throw new Error('settlement_nonce_unconfirmed');
   const record=await this.transaction.prepare(payload,required,latest);
   // Commit the exact signed bytes AND alarm before the first broadcast.
   // No external I/O in this atomic storage transaction.
   await this.storage.transaction(async tx=>{
    await tx.put({[key]:record,active:key,count:count+1});
    await tx.setAlarm(this.clock()+60000);
   });
   try {await this.transaction.broadcast(record);}catch {/* Receipt remains unknown. */}
   return record.result;
  });
 }
 alarm() {return this.exclusive(()=>this.progress());}
}
