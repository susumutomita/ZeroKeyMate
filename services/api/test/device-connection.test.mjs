import {test} from 'node:test';
import assert from 'node:assert/strict';
import {checkDeviceConnection} from '../device-connection.mjs';
const env={MATE_API_URL:'https://mate.example.com',MATE_CHAIN_ID:'5042002',MATE_VAULT_ADDRESS:'0x'+'11'.repeat(20)};
const health={service:'ZeroKey Mate API',chainId:5042002,vault:env.MATE_VAULT_ADDRESS,token:'0x3600000000000000000000000000000000000000',ready:true,proofVerification:'available'};
test('physical connection preflight accepts only the ready matching HTTPS deployment and sends no bearer',async()=>{
  let called=false;
  const result=await checkDeviceConnection({...env,MATE_API_TOKEN:'must-not-be-sent'},async(url,options,limit)=>{
    called=true;assert.equal(url.href,'https://mate.example.com/health');assert.equal(options.headers,undefined);assert.equal(limit,10_000);return health;
  });
  assert.equal(called,true);assert.equal(result.apiURL,env.MATE_API_URL);
  for(const changes of [{vault:42},{token:null},{ready:false},{proofVerification:'unavailable'},{chainId:11155111},{vault:'0x'+'22'.repeat(20)},{token:'0x'+'33'.repeat(20)}])
    await assert.rejects(checkDeviceConnection(env,async()=>({...health,...changes})),/not ready or belongs/);
});
test('invalid phone URLs fail before network access and transport failure cannot become readiness',async()=>{
  for(const url of ['','http://192.168.1.1','https://localhost','https://user:secret@example.com','https://example.com?token=private','https://example.com/private'])
    await assert.rejects(checkDeviceConnection({...env,MATE_API_URL:url},async()=>{assert.fail('must not contact invalid origin');}));
  await assert.rejects(checkDeviceConnection(env,async()=>{throw new Error('private upstream detail');}),/HTTPS API could not be verified/);
});
