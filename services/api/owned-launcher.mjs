import {spawn} from 'node:child_process';

// The group ID comes only from this spawn, never a persisted PID/lock file.
export function startOwnedLauncher(command,args,{stdout=process.stdout,stderr=process.stderr,stdin='inherit',env=process.env,graceMs=2_000}={}) {
  if(process.platform==='win32')throw new Error('The native launcher requires POSIX process groups.');
  const child=spawn(command,args,{detached:true,env,stdio:[stdin,'pipe','pipe']});
  child.stdout.pipe(stdout,{end:false});child.stderr.pipe(stderr,{end:false});
  let settled=false,failure,stopping;
  child.once('error',error=>{failure=error;});
  const completion=new Promise(resolve=>child.once('close',(code,signal)=>{
    settled=true;resolve({code,signal,error:failure});
  }));
  // Keep output pipes open until the shell's children close them too.
  const signalGroup=signal=>{
    if(settled || !child.pid)return;
    try{process.kill(-child.pid,signal);}catch(error){if(error.code!=='ESRCH')throw error;}
  };
  async function waitForClose(milliseconds) {
    let timer;
    try{return await Promise.race([completion.then(()=>true),new Promise(resolve=>{timer=setTimeout(()=>resolve(false),milliseconds);})]);}
    finally{clearTimeout(timer);}
  }
  return {completion,stop(){
    return stopping ??= (async()=>{
      if(settled)return;
      signalGroup('SIGTERM');
      if(await waitForClose(graceMs))return;
      signalGroup('SIGKILL');
      if(!await waitForClose(graceMs))throw new Error('The app launcher did not stop. Its ownership was retained.');
    })();
  }};
}
