import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {PairingStore} from '../pairing.mjs';
import {jsonServer} from '../http.mjs';
import {apiHandler,pairingHandler} from '../server.mjs';

test('HTTP pairing exchanges a single code, rejects browser requests and requires bounded sessions',async()=>{
  const store=new PairingStore(':memory:','test:deployment');
  const server=jsonServer({authorize:req=>store.authorize(/^Bearer (session_[a-f0-9]{64})$/.exec(req.headers.authorization ?? '')?.[1]),
    handler:apiHandler({}),pairHandler:pairingHandler(()=>store,()=>true)});
  server.once('drained',()=>store.close());
  server.listen(0,'127.0.0.1');await once(server,'listening');
  const base=`http://127.0.0.1:${server.address().port}`;
  const post=(code,headers={})=>fetch(base+'/v1/pair',{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify({code})});
  try {
    const code=store.issue().code;
    assert.equal((await post(code,{Origin:'https://example.com'})).status,403);
    assert.equal((await fetch(base+'/v1/session',{headers:{Authorization:`Bearer ${code}`}})).status,401);
    const invalid=await fetch(base+'/v1/pair?extra=1',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code})});
    assert.equal(invalid.status,400);
    const response=await post(code);assert.equal(response.status,200);
    const session=await response.json();
    assert.equal((await post(code)).status,401);
    assert.equal((await fetch(base+'/v1/session')).status,401);
    const request=()=>fetch(base+'/v1/session',{headers:{Authorization:`Bearer ${session.token}`}});
    assert.deepEqual(await (await request()).json(),{paired:true});
    store.revoke();assert.equal((await request()).status,401);
  }finally{server.close();server.closeAllConnections();await server.whenDrained;}
});
