import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Readable} from 'node:stream';
import http from 'node:http';
import {once} from 'node:events';
import {apiHandler} from '../server.mjs';
import {authenticated,readJSON,jsonServer} from '../http.mjs';

const token='a'.repeat(64),owner='0x'+'11'.repeat(20);
test('authentication rejects absent, short and substituted pairing tokens',()=>{
  assert.equal(authenticated({headers:{}},token),false);
  assert.equal(authenticated({headers:{authorization:`Bearer ${token}`}},token),true);
  assert.equal(authenticated({headers:{authorization:`Bearer ${'b'.repeat(64)}`}},token),false);
  assert.equal(authenticated({headers:{authorization:'Bearer short'}},'short'),false);
});
test('HTTP route validation rejects duplicate, unknown and malformed query parameters',async()=>{
  let reads=0;
  const handler=apiHandler({chain:{account:async address=>{reads++;return {owner:address};}}});
  const get=path=>handler({method:'GET'},new URL(path,'http://localhost'));
  assert.deepEqual(await get(`/v1/account?owner=${owner}`),{owner});
  await assert.rejects(get(`/v1/account?owner=${owner}&owner=${owner}`),{code:'duplicate_parameter'});
  await assert.rejects(get(`/v1/account?owner=${owner}&unused=1`));
  await assert.rejects(get('/v1/account?owner=invalid'));
  await assert.rejects(get('/missing'),{code:'not_found'});
  assert.equal(reads,1);
});
test('body parser rejects arrays, invalid UTF-8, compression and oversized input',async()=>{
  const parse=(bytes,headers={},limit=100)=>{
    const request=Readable.from([Buffer.from(bytes)]);request.headers={'content-type':'application/json',...headers};
    return readJSON(request,limit);
  };
  assert.deepEqual(await parse('{"ok":true}'),{ok:true});
  await assert.rejects(parse('[]'),{code:'invalid_json'});
  await assert.rejects(parse(Buffer.from([0xff])),{code:'invalid_json'});
  await assert.rejects(parse('{}',{'content-encoding':'gzip'}),{code:'content_encoding'});
  await assert.rejects(parse('{"long":"payload"}',{},5),{code:'body_too_large'});
});
test('real HTTP server has authenticated routes and truthful public health',async t=>{
  const server=jsonServer({token,handler:async()=>({received:true}),publicHandler:p=>p==='/health'?{ready:false}:undefined});
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  const base=`http://127.0.0.1:${server.address().port}`;
  const health=await fetch(base+'/health');assert.deepEqual(await health.json(),{ready:false});
  assert.equal((await fetch(base+'/v1/state')).status,401);
  assert.equal((await fetch(base+'/v1/state',{headers:{authorization:`Bearer ${token}`,origin:'https://example.com'}})).status,403);
  const accepted=await fetch(base+'/v1/state',{headers:{authorization:`Bearer ${token}`}});
  assert.equal(accepted.status,200);assert.match(accepted.headers.get('cache-control'),/no-store/);
});

test('shutdown retains journal ownership until disconnected handlers finish',async t=>{
  let finishWork,startedWork,finished=false,released=false;
  const started=new Promise(resolve=>{startedWork=resolve;});
  const work=new Promise(resolve=>{finishWork=resolve;});
  const server=jsonServer({token,handler:async()=>{
    startedWork();await work;
    assert.equal(released,false,'journal must still be owned while persisting the result');
    finished=true;return {finished};
  }});
  server.once('drained',()=>{released=true;});
  t.after(()=>{finishWork();server.closeAllConnections();server.close();});
  server.listen(0,'127.0.0.1');await once(server,'listening');
  const request=http.get(`http://127.0.0.1:${server.address().port}/v1/state`,{
    headers:{authorization:`Bearer ${token}`}
  });
  request.on('error',()=>{});
  await started;
  const closed=once(server,'close');
  request.destroy();server.close();server.closeAllConnections();
  await closed;
  assert.equal(finished,false);assert.equal(released,false);
  finishWork();await server.whenDrained;
  assert.equal(finished,true);assert.equal(released,true);
  // A second shutdown observer can await an already-drained server.
  await server.whenDrained;
});
