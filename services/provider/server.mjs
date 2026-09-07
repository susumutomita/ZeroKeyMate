import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {z} from 'zod';
import {jsonServer,readJSON} from '../api/http.mjs';
import {ROOT,httpsURL,safeURL,SEPOLIA_USDC} from '../api/config.mjs';
import {actionSchema,signatureSchema,address,hash32,uintString,actionDigest,sha256} from '../api/protocol.mjs';
import {requireValue,ProductError,SerialQueue} from '../api/errors.mjs';
import {Chain} from '../api/chain.mjs';
import {Journal} from '../api/journal.mjs';
import {processLock} from '../api/process-lock.mjs';
import {SpecialistModel} from './model.mjs';

const prepareSchema=z.object({action:actionSchema,agentSignature:signatureSchema,
  payload:z.string().min(1).refine(v=>Buffer.byteLength(v)<=8_000),proofHash:hash32}).strict();
const releaseSchema=z.object({actionHash:hash32,transactionHash:hash32,proofHash:hash32}).strict();
export class Specialist {
  #queue=new SerialQueue();
  constructor({config,chain,journal,model}){Object.assign(this,{config,chain,journal,model});}
  async quote(service) {
    requireValue(service===this.config.service,'service_unavailable','この専門サービスは未対応です。',404);
    await this.model.ready();
    return {service,price:this.config.price,recipient:this.config.recipient,expiresAt:Math.floor(Date.now()/1000)+120,ready:true};
  }
  prepare(input){return this.#queue.run(async()=>{
    const request=prepareSchema.parse(input),{action}=request;
    const actionHash=actionDigest(11155111,this.config.vault,action);
    requireValue(action.service===this.config.service && action.amount===this.config.price
      && action.recipient.toLowerCase()===this.config.recipient.toLowerCase()
      && sha256(request.payload).toLowerCase()===action.requestHash.toLowerCase(),
      'request_mismatch','承認された文章・料金・宛先と依頼が一致しません。',409);
    const id=`work:${actionHash}`,previous=this.journal.get(id);
    if(previous) {
      requireValue(previous.value.request.proofHash===request.proofHash
        && previous.value.request.agentSignature===request.agentSignature,'work_conflict','同じ依頼の証明・署名が変わっています。',409);
      return {actionHash,status:'ready'};
    }
    const state=await this.chain.state(action.mandateId),now=Math.floor(Date.now()/1000);
    requireValue(!state.revoked && state.validUntil>=action.expiresAt && action.expiresAt>now+10 && state.spent===action.spentBefore,
      'stale_mandate','委任が失効したか、利用状態が変わっています。',409);
    requireValue(await this.chain.verifyAgent(action,request.agentSignature,state),'agent_signature','実行キーの署名が無効です。',403);
    const result=await this.model.run(action.service,request.payload);
    this.journal.put(id,'ready',{request,result});
    return {actionHash,status:'ready'};
  });}
  release(input){return this.#queue.run(async()=>{
    const request=releaseSchema.parse(input),id=`work:${request.actionHash.toLowerCase()}`,entry=this.journal.get(id);
    requireValue(entry,'work_missing','準備済みの依頼がありません。',404);
    requireValue(entry.value.request.proofHash.toLowerCase()===request.proofHash.toLowerCase(),
      'proof_mismatch','支払いの証明ハッシュが一致しません。',409);
    // Independently read the canonical vault event before disclosing any result,
    // including retries. The API's assertion of payment is not evidence.
    await this.chain.executionEvent(request.transactionHash,entry.value.request.action,request.proofHash);
    this.journal.put(id,'complete',{...entry.value,transactionHash:request.transactionHash});
    return {actionHash:request.actionHash.toLowerCase(),result:entry.value.result};
  });}
}
export function providerHandler(specialist) {
  return async(request,url)=>{
    if(request.method==='GET' && url.pathname==='/v1/quote') {
      requireValue([...url.searchParams.keys()].join(',')==='service' && /^[01]$/.test(url.searchParams.get('service')||''),
        'invalid_request','専門サービスを指定してください。');
      return specialist.quote(Number(url.searchParams.get('service')));
    }
    requireValue(!url.search,'invalid_request','この操作はクエリを受け付けません。');
    if(request.method==='POST' && url.pathname==='/v1/prepare')return specialist.prepare(await readJSON(request,32_000));
    if(request.method==='POST' && url.pathname==='/v1/release')return specialist.release(await readJSON(request,2_000));
    throw new ProductError('not_found','この操作はありません。',404);
  };
}
export function providerConfiguration(e=process.env) {
  return z.object({rpcURL:httpsURL,vault:address,attestorAddress:address,token:address,
    recipient:address,service:z.coerce.number().int().min(0).max(1),price:uintString.refine(v=>BigInt(v)>0n),
    modelURL:safeURL,model:z.string().min(1).max(200),apiToken:z.string().min(32).max(256),
    journalKey:z.string().regex(/^[a-fA-F0-9]{64}$/)}).parse({
    rpcURL:e.SEPOLIA_RPC_URL,vault:e.MATE_VAULT_ADDRESS,attestorAddress:e.MATE_ATTESTOR_ADDRESS,token:SEPOLIA_USDC,
    recipient:e.PROVIDER_RECIPIENT,service:e.PROVIDER_SERVICE,price:e.PROVIDER_PRICE,
    modelURL:e.OLLAMA_URL||'http://127.0.0.1:11434',model:e.OLLAMA_MODEL,
    apiToken:e.PROVIDER_API_TOKEN,journalKey:e.PROVIDER_JOURNAL_KEY,
  });
}
export async function startProvider(e=process.env) {
  const config=providerConfiguration(e);
  const directory=path.resolve(e.PROVIDER_DATA_DIRECTORY||path.join(ROOT,'.data/provider'));
  const release=processLock(path.join(directory,'provider.lock'));
  let journal;
  try {
    journal=new Journal(path.join(directory,'provider.sqlite'),config.journalKey);
    const chain=new Chain(config,journal);await chain.prepare();
    const specialist=new Specialist({config,chain,journal,model:new SpecialistModel(config)});
    const server=jsonServer({token:config.apiToken,handler:providerHandler(specialist),
      publicHandler:route=>route==='/health'?{service:'ZeroKey Mate specialist',network:'sepolia',modelReadiness:'checked-per-quote'}:undefined});
    server.once('close',()=>{journal.close();release();});
    await new Promise((resolve,reject)=>{
      server.once('error',reject);
      server.listen(z.coerce.number().int().min(1).max(65535).parse(e.PROVIDER_PORT||8788),
        z.enum(['127.0.0.1','::1','0.0.0.0']).parse(e.PROVIDER_BIND_HOST||'127.0.0.1'),resolve);
    });
    return server;
  }catch(error){journal?.close();release();throw error;}
}
if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const server=await startProvider();console.log(`Specialist listening on port ${server.address().port}.`);
    for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>server.close());
  }catch{console.error('専門サービスを起動できません。Sepolia・提供者・Ollamaの設定を確認してください。');process.exitCode=1;}
}
