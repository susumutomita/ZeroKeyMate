import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {root} from './environment.mjs';
import {boundedJSON} from '../services/api/http.mjs';
const mode=process.argv[2]||'services';
const directory=path.join(root,'.data');fs.mkdirSync(directory,{recursive:true,mode:0o700});
const stateFile=path.join(directory,'service-processes.json');
if(mode==='stop'){
 // Do not kill unrelated processes after a PID has been reused: a parent launcher
 // owns its children and receives a single termination signal.
 if(fs.existsSync(stateFile)){
  const state=JSON.parse(fs.readFileSync(stateFile,'utf8'));
  const {execFileSync}=await import('node:child_process');
  try{
   const command=execFileSync('ps',['-p',String(state.pid),'-o','command='],{encoding:'utf8'});
   if(command.includes('scripts/services.mjs')&&command.includes(state.marker))process.kill(state.pid,'SIGTERM');
   else console.log('Recorded process no longer matches this launcher; no signal sent.');
  }catch{console.log('No matching services process is running.');}
 }
 process.exit(0);
}
if(!['services','provider'].includes(mode))throw new Error('Unsupported service mode');
const marker=process.argv[3];
if(!marker){
 const child=spawn(process.execPath,['--env-file-if-exists=.env','scripts/services.mjs',mode,root],{cwd:root,env:process.env,stdio:'inherit'});
 for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>child.kill(signal));
 child.once('exit',code=>process.exit(code??1));
}else{
 const {acquireProcessLock}=await import('../services/api/process-lock.mjs');
 const unlock=acquireProcessLock(path.join(directory,'launcher.lock'));
 fs.writeFileSync(stateFile,JSON.stringify({pid:process.pid,marker:root}),{mode:0o600});
 const children=[];let closing=false;
 const spawnOwned=(command,args)=>{const child=spawn(command,args,{cwd:root,env:process.env,stdio:'inherit'});children.push(child);child.once('error',()=>cleanup(1));return child;};
 const cleanup=(code=0)=>{
  if(closing)return;closing=true;
  for(const child of children)child.kill('SIGTERM');
  try{fs.unlinkSync(stateFile);}catch{}unlock();
  setTimeout(()=>process.exit(code),1000).unref();
 };
 for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>cleanup(0));
 try{
  const modelBase=(process.env.PROVIDER_MODEL_URL||'http://127.0.0.1:11434').replace(/\/$/,'');
  const location=new URL(modelBase);
  if(!['127.0.0.1','localhost','[::1]'].includes(location.hostname))throw new Error('The bundled specialist requires local Ollama.');
  let tags;
  try{tags=await boundedJSON(modelBase+'/api/tags',{signal:AbortSignal.timeout(1500)});}catch{
   if(modelBase!=='http://127.0.0.1:11434')throw new Error('Start the configured local Ollama instance first.');
   const ollama=spawnOwned('ollama',['serve']);
   for(let attempt=0;attempt<30;attempt++){
    try{tags=await boundedJSON(modelBase+'/api/tags',{signal:AbortSignal.timeout(1000)});break;}catch{await new Promise(r=>setTimeout(r,1000));}
   }
   if(!tags)throw new Error('Ollama did not become ready.');
  }
  const model=process.env.PROVIDER_MODEL||'gemma3:4b';
  if(!tags.models?.some(item=>item.name===model||item.model===model)){
   const pull=spawnOwned('ollama',['pull',model]);
   await new Promise((resolve,reject)=>{pull.once('error',reject);pull.once('exit',code=>code===0?resolve():reject(new Error('Model download failed.')));});
  }
  const provider=spawnOwned(process.execPath,['--env-file-if-exists=.env','services/provider/server.mjs']);
  provider.once('error',()=>cleanup(1));provider.once('exit',code=>{if(!closing)cleanup(code||1);});
  if(mode==='services'){
   const api=spawnOwned(process.execPath,['--env-file-if-exists=.env','services/api/server.mjs']);
   api.once('error',()=>cleanup(1));api.once('exit',code=>{if(!closing)cleanup(code||1);});
  }
  console.log('Service processes launched; readiness is checked by each server. Keep this terminal open; Ctrl-C stops these processes.');
 }catch(error){console.error(error.message);cleanup(1);}
}
