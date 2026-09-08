import http from 'node:http';
import path from 'node:path';
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {authenticated,respond} from '../api/http.mjs';
import {startProvider} from '../provider/server.mjs';
import {networkConfiguration,settlementNetwork} from '../api/networks.mjs';

const assets=new Map([
  ['/', ['index.html','text/html; charset=utf-8']],
  ['/app.css',['app.css','text/css; charset=utf-8']],
  ['/app.js',['app.js','text/javascript; charset=utf-8']],
]);

// The operator UI is a loopback-only, read-only view. Payment and provider
// credentials are never embedded in HTML, URLs, browser storage or order rows.
export function merchantServer({token,catalog,readiness,orders}) {
  return http.createServer(async(req,res)=>{
    try {
      const port=res.socket.localPort;
      const allowed=new Set([`127.0.0.1:${port}`,`localhost:${port}`]);
      if(!allowed.has(req.headers.host) || (req.headers.origin && !allowed.has(new URL(req.headers.origin).host))) {
        respond(res,403,{error:'origin_rejected',message:'Open this shop on localhost.'});return;
      }
      if(req.method!=='GET') {respond(res,405,{error:'read_only',message:'The operator screen cannot authorize payments.'});return;}
      const url=new URL(req.url,'http://localhost');
      if(url.search) {respond(res,400,{error:'invalid_request'});return;}
      const asset=assets.get(url.pathname);
      if(asset) {
        const bytes=await fs.readFile(new URL(`./public/${asset[0]}`,import.meta.url));
        res.writeHead(200,{'Content-Type':asset[1],'Content-Length':bytes.length,'Cache-Control':'no-store',
          'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer',
          'Content-Security-Policy':"default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"});
        res.end(bytes);return;
      }
      if(url.pathname==='/api/shop') {respond(res,200,{...catalog,...await readiness()});return;}
      if(url.pathname==='/api/orders') {
        if(!authenticated(req,token)) {respond(res,401,{error:'unauthorized',message:'Enter the shop operator token to view orders.'});return;}
        respond(res,200,{orders:await orders()});return;
      }
      respond(res,404,{error:'not_found'});
    } catch {if(!res.headersSent)respond(res,503,{error:'unavailable',message:'The shop could not load this view. Retry shortly.'});}
  });
}

export function orderSummaries(specialist) {
  if(!specialist)return [];
  return specialist.journal.recentWork().map(({id,state,value,updatedAt})=>({
    id:id.slice(5),status:state,amount:value.request.action.amount,service:value.request.action.service,
    proofVerified:value.proofVerified===true,proofHash:value.request.proofHash,
    transactionHash:value.transactionHash??null,updatedAt,
  }));
}

export async function startMerchant(e=process.env) {
  const network=networkConfiguration(e);
  let provider,connection='unavailable';
  try {provider=await startProvider(e);connection='connected';} catch { /* Show honest setup state without exposing configuration secrets. */ }
  const specialist=provider?.specialist;
  let lastCheck=0,cached;
  const readiness=async()=>{
    if(Date.now()-lastCheck<5000 && cached)return cached;
    let ready=false;
    if(specialist) {try {await specialist.quote(specialist.config.service);ready=true;}catch{}}
    cached={ready,connection,message:ready?'Accepting requests from paired Mate clients.'
      :specialist?'The model or ZK verifier is unavailable. Orders are paused.'
      :'Connect the vault, verifier and provider configuration to open the shop.'};
    lastCheck=Date.now();return cached;
  };
  const server=merchantServer({token:e.PROVIDER_API_TOKEN||'',
    catalog:{name:'Mate Atelier',product:Number(e.PROVIDER_SERVICE||0)===0?'Personal translation':'Clear summary',
      description:Number(e.PROVIDER_SERVICE||0)===0?'Your words, naturally translated between English and Japanese.':'A concise summary that keeps the meaning of your text.',
      price:specialist?.config.price??null,network:settlementNetwork(network.chainId).name,
      chainId:network.chainId,recipient:specialist?.config.recipient??null},readiness,
    orders:()=>orderSummaries(specialist)});
  const port=Number(e.MERCHANT_PORT||8790);
  if(!Number.isInteger(port)||port<1||port>65535){provider?.close();throw new Error('Invalid merchant port');}
  try {await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve);});}
  catch(error){provider?.close();throw error;}
  server.once('close',()=>provider?.close());
  return server;
}
if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const server=await startMerchant();
    console.log(`Mate shop: http://127.0.0.1:${server.address().port}`);
    for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>server.close());
  }catch {console.error('Could not start the shop. Check configuration and port availability.');process.exitCode=1;}
}
