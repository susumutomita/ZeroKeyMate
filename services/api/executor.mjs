import {z} from 'zod';
import {actionSchema, grantSchema, signatureSchema, sha256, actionDigest} from './protocol.mjs';
import {requireValue, SerialQueue} from './errors.mjs';

export const executeSchema=z.object({action:actionSchema,agentSignature:signatureSchema,
  proof:z.string().min(4).max(11_184_812),payload:z.string().min(1).refine(value=>Buffer.byteLength(value)<=8_000),
  providerId:z.string().regex(/^11155111:[0-9]+$/).max(100)}).strict();
const registrationSchema=z.object({grant:grantSchema,signature:signatureSchema}).strict();
export class Executor {
  #queue=new SerialQueue();
  constructor({config,chain,verifier,discovery,journal}){Object.assign(this,{config,chain,verifier,discovery,journal});}
  register(input){return this.#queue.run(async()=>{
    const {grant,signature}=registrationSchema.parse(input);
    requireValue(await this.chain.verifyOwner(grant,signature),'owner_signature','所有者の署名が無効です。',403);
    return this.chain.register(grant,signature);
  });}
  execute(input){return this.#queue.run(async()=>{
    const request=executeSchema.parse(input);
    const actionHash=actionDigest(11155111,this.config.vault,request.action);
    requireValue(sha256(Buffer.from(request.payload)).toLowerCase()===request.action.requestHash.toLowerCase(),
      'payload_hash','承認した文章から内容が変わっています。',409);
    const id=`execution:${actionHash}`;
    let existing=this.journal.get(id);
    if(existing){
      const saved=existing.value.request;
      requireValue(saved.providerId===request.providerId && saved.payload===request.payload
        && saved.agentSignature.toLowerCase()===request.agentSignature.toLowerCase()
        && saved.proof===request.proof,'execution_conflict','同じ依頼識別子の内容が変わっています。',409);
      return this.#advance(id,existing);
    }
    const state=await this.chain.state(request.action.mandateId);
    const now=Math.floor(Date.now()/1000);
    requireValue(!state.revoked && state.validUntil>now && request.action.expiresAt>now+10
      && request.action.expiresAt<=state.validUntil && state.spent===request.action.spentBefore,
      'stale_mandate','委任または利用状態が変わりました。新たに確認してください。',409);
    requireValue(await this.chain.verifyAgent(request.action,request.agentSignature,state),'agent_signature','実行キーの署名が無効です。',403);
    const {provider,indexedBlock}=await this.discovery.choose(request.providerId,request.action);
    const verified=await this.verifier.verify(request.proof,{policyHash:state.policyHash,actionHash,action:request.action});
    const value={request,proofHash:verified.proofHash,indexedBlock,provider};
    // No secret policy is stored. This journal contains only the explicitly approved
    // disclosure, cryptographic proof and execution metadata, encrypted at rest.
    this.journal.put(id,'authorized',value);
    return this.#advance(id,{state:'authorized',value});
  });}
  receipt(actionHash){return this.#queue.run(async()=>{
    const id=`execution:${actionHash.toLowerCase()}`;
    const existing=this.journal.get(id);
    requireValue(existing,'execution_not_found','依頼がまだ届いていません。同じ依頼を再送してください。',404);
    return this.#advance(id,existing);
  });}
  async #advance(id,entry){
    let {state,value}=entry;
    if(state==='complete')return value.receipt;
    const {request,provider,proofHash}=value;
    if(state==='authorized'){
      // Prepare actual work before money moves. Provider withholds the result until payment.
      const prepared=await this.discovery.call(provider,'/v1/prepare',{
        action:request.action,agentSignature:request.agentSignature,payload:request.payload,proofHash,
      });
      requireValue(prepared.actionHash===actionDigest(11155111,this.config.vault,request.action) && prepared.status==='ready',
        'provider_not_ready','提供者の実行準備を確認できません。支払いは開始していません。',503);
      this.journal.put(id,'ready',value);state='ready';
    }
    if(state==='ready'){
      const payment=await this.chain.pay(request.action,request.agentSignature,proofHash);
      value={...value,payment};this.journal.put(id,'paid',value);state='paid';
    }
    requireValue(state==='paid','execution_state','実行記録が不正です。',503);
    const released=await this.discovery.call(provider,'/v1/release',{
      actionHash:value.payment.actionHash,transactionHash:value.payment.transactionHash,proofHash,
    });
    requireValue(released.actionHash===value.payment.actionHash && typeof released.result==='string'
      && released.result.trim() && Buffer.byteLength(released.result)<=100_000,'provider_result','結果を確認できません。支払い済みの依頼として再照会してください。',503);
    const receipt={...value.payment,result:released.result};
    this.journal.put(id,'complete',{...value,receipt});
    return receipt;
  }
}
