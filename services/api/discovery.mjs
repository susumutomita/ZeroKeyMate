import {z} from 'zod';
import {boundedJSON} from './http.mjs';
import {requireValue} from './errors.mjs';

const quoteSchema=z.object({service:z.number().int().min(0).max(1),price:z.string().regex(/^[1-9][0-9]*$/),
  recipient:z.string().regex(/^0x[\da-fA-F]{40}$/),expiresAt:z.number().int(),ready:z.literal(true)}).strict();
/** Config pins known integrations; The Graph's live data, not that config, supplies candidates. */
export class Discovery {
  constructor(config,names){this.config=config;this.names=names;}
  async list(service){
    const {graphApiKey,graphSubgraphId}=this.config;
    requireValue(graphApiKey,'graph_unconfigured','The Graph APIキーが設定されていません。',503);
    const candidates=this.config.providers.filter(provider=>provider.service===service);
    if(!candidates.length) return {providers:[],indexedBlock:'not-queried',observedAt:new Date().toISOString()};
    const query=`query MateProviders($ids:[ID!]!){
      _meta { block { number } hasIndexingErrors }
      agents(first:50,where:{id_in:$ids}){
        id chainId owner agentWallet totalFeedback
        registrationFile {name active ens webEndpoint supportedTrusts}
      }
    }`;
    const response=await boundedJSON(`https://gateway.thegraph.com/api/${encodeURIComponent(graphApiKey)}/subgraphs/id/${graphSubgraphId}`,{
      method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({query,variables:{ids:candidates.map(provider=>provider.id)}}),
    });
    requireValue(!response.errors?.length && Array.isArray(response.data?.agents) && response.data?._meta?.hasIndexingErrors===false
      && Number.isSafeInteger(response.data._meta.block.number),'graph_response','インデックスの状態を検証できません。',503);
    const providers=[];
    for(const indexed of response.data.agents){
      const configured=candidates.find(provider=>provider.id===indexed.id);
      const registration=indexed.registrationFile;
      if(!configured || String(indexed.chainId)!=='11155111' || indexed.owner?.toLowerCase()!==configured.owner.toLowerCase()
        || !registration?.active || registration.ens!==configured.ensName
        || registration.webEndpoint!==configured.endpoint) continue;
      // The ENS recipient is re-resolved on every request, not cached as authorization.
      try {
        const identity=await this.names.resolve(configured.ensName);
        if(identity.address.toLowerCase()!==configured.recipient.toLowerCase()) continue;
        const quote=quoteSchema.parse(await this.call(configured,`/v1/quote?service=${service}`));
        const now=Math.floor(Date.now()/1000);
        if(quote.service!==service || quote.price!==configured.price || quote.recipient.toLowerCase()!==configured.recipient.toLowerCase()
          || quote.expiresAt<=now+10 || quote.expiresAt>now+600) continue;
        const feedback=BigInt(indexed.totalFeedback);
        if(feedback<0n) continue;
        providers.push({id:indexed.id,name:String(registration.name||configured.ensName).slice(0,120),service,
          price:quote.price,recipient:configured.recipient,ensName:configured.ensName,
          feedback:Number(feedback>BigInt(Number.MAX_SAFE_INTEGER)?BigInt(Number.MAX_SAFE_INTEGER):feedback)});
      } catch { /* Unreachable or mismatched providers are not replaced with invented candidates. */ }
    }
    providers.sort((a,b)=>b.feedback-a.feedback || (BigInt(a.price)<BigInt(b.price)?-1:BigInt(a.price)>BigInt(b.price)?1:a.id.localeCompare(b.id)));
    return {providers,indexedBlock:String(response.data._meta.block.number),observedAt:new Date().toISOString()};
  }
  async choose(id,action){
    const live=await this.list(action.service);
    const selected=live.providers.find(provider=>provider.id===id);
    requireValue(selected && selected.price===action.amount && selected.recipient.toLowerCase()===action.recipient.toLowerCase(),
      'provider_changed','提供者・料金・宛先が変わりました。送信前に再確認してください。',409);
    return {provider:this.config.providers.find(provider=>provider.id===id&&provider.service===action.service),indexedBlock:live.indexedBlock};
  }
  call(provider,path,body){
    const base=new URL(provider.endpoint);
    const url=new URL(base.toString().replace(/\/$/,'')+path);
    requireValue(url.origin===base.origin,'provider_origin','提供者の接続先が一致しません。',503);
    return boundedJSON(url,{method:body?'POST':'GET',headers:{'content-type':'application/json',authorization:`Bearer ${provider.bearerToken}`},
      ...(body?{body:JSON.stringify(body)}:{})},1_000_000);
  }
}
