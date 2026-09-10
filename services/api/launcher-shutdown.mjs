/** Startup can still acquire a server while a stop request is in flight. */
export function launcherShutdown(startupSettled,resources) {
  let shutdown;
  return ()=>shutdown ??= (async()=>{
    // Stop a build before awaiting startup, which may itself await that build.
    const build=resources().launcher?.stop().then(()=>null,error=>error);
    await startupSettled;
    const {api,provider,claim,control}=resources();
    const stops=[api,provider].filter(Boolean).map(server=>new Promise(resolve=>{
      const timer=setTimeout(()=>server.closeAllConnections(),5_000);
      server.whenDrained.then(()=>{clearTimeout(timer);resolve();});
      server.close();server.closeIdleConnections();
    }));
    if(build)stops.push(build.then(error=>{if(error)throw error;}));
    const results=await Promise.allSettled(stops);
    if(results.some(result=>result.status==='rejected'))throw new Error('Shutdown could not be confirmed. Launcher ownership was retained.');
    claim?.release?.();control?.close();
  })();
}
