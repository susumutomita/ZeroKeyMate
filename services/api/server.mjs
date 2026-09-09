import path from 'node:path';
import {stateDirectory} from './networks.mjs';
import {pathToFileURL} from 'node:url';
import {z} from 'zod';
import {configuration,ROOT} from './config.mjs';
import {jsonServer,readJSON} from './http.mjs';
import {ProductError,requireValue} from './errors.mjs';
import {address,hash32} from './protocol.mjs';
import {Journal} from './journal.mjs';
import {Chain} from './chain.mjs';
import {ProofVerifier} from './verifier.mjs';
import {Discovery} from './discovery.mjs';
import {Names} from './names.mjs';
import {Executor} from './executor.mjs';
import {PairingStore} from './pairing.mjs';
import {processLock} from './process-lock.mjs';

function query(url,shape) {
  const values={};
  for (const [key,value] of url.searchParams) {
    requireValue(!(key in values),'duplicate_parameter','同じパラメーターは一度だけ指定してください。');
    values[key]=value;
  }
  return z.object(shape).strict().parse(values);
}
export function apiHandler({chain,names,discovery,executor}) {
  return async (request,url) => {
    const route=`${request.method} ${url.pathname}`;
    switch (route) {
    case 'GET /v1/session':query(url,{});return {paired:true};
    case 'GET /v1/configuration':query(url,{});return {chainId:chain.config.chainId,vault:chain.config.vault,token:chain.config.token,actionVersion:'ZKM-ACT1'};
    case 'GET /v1/account':return chain.account(query(url,{owner:address}).owner);
    case 'GET /v1/state':return chain.state(query(url,{mandateId:hash32}).mandateId);
    case 'GET /v1/providers':return discovery.list(Number(query(url,{service:z.enum(['0','1'])}).service));
    case 'GET /v1/receipts':return executor.receipt(query(url,{actionHash:hash32}).actionHash);
    case 'GET /v1/names/resolve':return names.resolve(query(url,{name:z.string().min(1).max(253)}).name);
    case 'POST /v1/grants':query(url,{});return executor.register(await readJSON(request,32_000));
    case 'POST /v1/execute':query(url,{});return executor.execute(await readJSON(request));
    case 'POST /v1/executions/cancel': {
      query(url,{});
      const {actionHash}=z.object({actionHash:hash32}).strict().parse(await readJSON(request,1_000));
      return executor.cancel(actionHash);
    }
    case 'POST /v1/names':query(url,{});return names.claim(await readJSON(request,32_000));
    default:throw new ProductError('not_found','この操作はありません。',404);
    }
  };
}

export function pairingHandler(store,ready) {
  return async(request,url)=>{
    requireValue(ready(),'integration_unavailable','Configure the deployment and proof verifier before pairing.',503);
    query(url,{});
    const {code}=z.object({code:z.string().max(80)}).strict().parse(await readJSON(request,512));
    return store().exchange(code);
  };
}

export async function startAPI(e=process.env) {
  const release=processLock(path.join(stateDirectory('api',e),'api.lock'));
  let journal,pairing,handler,configurationError;
  const health={service:'ZeroKey Mate API',chainId:null,vault:null,token:null,ready:false,proofVerification:'unavailable'};
  try {
    const config=configuration(e);
    Object.assign(health,{chainId:config.chainId,vault:config.vault,token:config.token});
    pairing=new PairingStore(path.join(config.dataDirectory,'pairing.sqlite'),`${config.chainId}:${config.vault.toLowerCase()}`);
    journal=new Journal(path.join(config.dataDirectory,'api.sqlite'),config.journalKey);
    const chain=new Chain(config,journal);
    await chain.prepare();
    const names=new Names(config,chain,journal);
    const discovery=new Discovery(config,names);
    const verifier=new ProofVerifier({binary:config.verifierBinary,verifier:config.verifierKey,manifest:config.manifest});
    try {await verifier.prepare();health.proofVerification='available';} catch { /* Execution still fails closed in verify(). */ }
    const executor=new Executor({config,chain,verifier,discovery,journal});
    handler=apiHandler({chain,names,discovery,executor});health.ready=health.proofVerification==='available';
  } catch (error) {
    configurationError=error instanceof ProductError ? error : new ProductError('integration_unavailable','ネットワーク・契約・検証ファイルの接続設定を確認してください。',503);
    handler=async()=>{throw configurationError;};
  }
  const server=jsonServer({handler,authorize:request=>pairing?.authorize(/^Bearer (session_[a-f0-9]{64})$/.exec(request.headers.authorization ?? '')?.[1]) ?? false,
    pairHandler:pairingHandler(()=>pairing,()=>health.ready),publicHandler:route=>{
      if(route==='/health')return health;
      if(route==='/v1/configuration'){
        requireValue(health.ready,'integration_unavailable','Configure the deployment and proof verifier before pairing.',503);
        return {chainId:health.chainId,vault:health.vault,token:health.token,actionVersion:'ZKM-ACT1'};
      }
    }});
  server.once('drained',()=>{journal?.close();pairing?.close();release();});
  try {
    const port=z.coerce.number().int().min(1).max(65535).parse(e.MATE_PORT||8787);
    const host=z.enum(['127.0.0.1','::1','0.0.0.0']).parse(e.MATE_BIND_HOST||'127.0.0.1');
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,host,resolve);});
    return {server,health,configurationError};
  } catch(error) {journal?.close();pairing?.close();release();throw error;}
}
if (process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const {server,health,configurationError}=await startAPI();
    console.log(`ZeroKey Mate API listening on port ${server.address().port}; API ${health.ready?'ready':'not ready'}, proof verifier ${health.proofVerification}. Provider availability is checked per request.`);
    if(configurationError)console.error(configurationError.message);
    for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>server.close());
  } catch(error) {console.error(error instanceof ProductError?error.message:'APIを起動できませんでした。設定とポートを確認してください。');process.exitCode=1;}
}
