import {configuration} from '../services/api/config.mjs';
import {Discovery} from '../services/api/discovery.mjs';
import {ProductError} from '../services/api/errors.mjs';
try {
  const config=configuration();
  const requested=process.argv[2];
  if(process.argv.length!==3 || !/^11155111:[0-9]+$/.test(requested??''))throw new ProductError('provider_id','Usage: npm run check-provider -- 11155111:AGENT_ID');
  const pinned=config.providers.filter(provider=>provider.id===requested);
  if(!pinned.length)throw new ProductError('provider_pin','Add this registered provider to private MATE_PROVIDERS_JSON before checking it.');
  const discovery=new Discovery(config,null);
  const results=[];
  for(const provider of pinned) {
    const live=await discovery.list(provider.service);
    const found=live.providers.find(candidate=>candidate.id===requested);
    if(!found)throw new ProductError('provider_unavailable','The provider is not discoverable with a matching live quote. Check Graph indexing, owner, payout wallet, endpoint, model readiness and price.');
    results.push({id:found.id,service:found.service,indexedBlock:live.indexedBlock,observedAt:live.observedAt,ready:true});
  }
  console.log(JSON.stringify(results,null,2));
} catch(error) {
  console.error(error instanceof ProductError?error.message:'Provider discovery could not be verified. Raw SDK errors and credentials are withheld.');process.exitCode=1;
}
