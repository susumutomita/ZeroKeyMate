import {test} from 'node:test';
import assert from 'node:assert/strict';
import {launcherShutdown} from '../launcher-shutdown.mjs';
const deferred=()=>{let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};};
test('shutdown stops builds first, waits for late startup and handler drain, then releases once',async()=>{
  const startup=deferred(),drain=deferred(),state={},events=[];
  state.launcher={stop:async()=>{events.push('build-stopped');}};
  state.claim={release:()=>events.push('released')};
  const stop=launcherShutdown(startup.promise,()=>state);
  const closing=stop();assert.equal(closing,stop());
  await Promise.resolve();assert.deepEqual(events,['build-stopped']);
  state.api={whenDrained:drain.promise,close:()=>events.push('server-closed'),closeIdleConnections(){},closeAllConnections(){}};
  startup.resolve();await Promise.resolve();await Promise.resolve();
  assert.deepEqual(events,['build-stopped','server-closed']);
  drain.resolve();await closing;
  assert.deepEqual(events,['build-stopped','server-closed','released']);
});
test('unconfirmed child termination retains ownership after server drain',async()=>{
  let released=false;
  const stop=launcherShutdown(Promise.resolve(),()=>({launcher:{stop:async()=>{throw new Error('still alive');}},claim:{release:()=>{released=true;}}}));
  await assert.rejects(stop(),/ownership was retained/);assert.equal(released,false);
});
