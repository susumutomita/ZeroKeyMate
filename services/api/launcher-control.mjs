import net from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createHash,timingSafeEqual} from 'node:crypto';
import {OWNERSHIP_PATH,readLauncherOwnership} from './launcher-ownership.mjs';

function socketPath(record,file) {
  return path.join(os.tmpdir(),'mate-'+createHash('sha256').update(path.resolve(file)+'\0'+record.instance).digest('hex').slice(0,20)+'.sock');
}
/** Local socket capability: no PID loaded from disk is ever signalled. */
export async function startLauncherControl(record,stop,file=OWNERSHIP_PATH) {
  const expected=Buffer.from(record.instance+'\n');
  const server=net.createServer(socket=>{
    let input=Buffer.alloc(0),accepted=false;
    socket.setTimeout(2_000,()=>socket.destroy());
    socket.on('error',()=>{});
    socket.on('data',chunk=>{
      if(accepted)return;
      input=Buffer.concat([input,chunk]);
      if(input.length>expected.length){socket.destroy();return;}
      if(!input.includes(10))return;
      if(input.length!==expected.length || !timingSafeEqual(input,expected)){socket.destroy();return;}
      accepted=true;socket.setTimeout(0);
      Promise.resolve().then(stop).then(()=>socket.end('stopped\n'),()=>socket.end('pending\n'));
    });
  });
  server.maxConnections=4;
  const endpoint=socketPath(record,file);
  // A collision fails closed; never unlink another process's socket.
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(endpoint,resolve);});
  fs.chmodSync(endpoint,0o600);
  return server;
}
export async function requestLauncherStop(file=OWNERSHIP_PATH,timeoutMs=30_000) {
  const record=readLauncherOwnership(file);
  if(!record)return {running:false};
  await new Promise((resolve,reject)=>{
    const socket=net.createConnection(socketPath(record,file));
    let answer='',settled=false;
    const finish=error=>{if(settled)return;settled=true;clearTimeout(timer);socket.destroy();error?reject(error):resolve();};
    const timer=setTimeout(()=>finish(new Error('Shutdown is still unconfirmed. The launcher may be draining pending work; inspect it before retrying.')),timeoutMs);
    socket.on('connect',()=>socket.write(record.instance+'\n'));
    socket.on('error',()=>finish(new Error('The recorded launcher could not be contacted. No process was signalled.')));
    socket.on('data',data=>{
      answer+=data.toString();
      if(answer==='stopped\n')finish();
      else if(answer.includes('\n') || answer.length>32)finish(new Error('Shutdown was not confirmed; ownership remains with the launcher.'));
    });
    socket.on('end',()=>{if(!settled)finish(new Error('The launcher disconnected before confirming shutdown.'));});
  });
  return {running:true};
}
