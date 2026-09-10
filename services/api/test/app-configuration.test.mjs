import {test} from 'node:test';
import assert from 'node:assert/strict';
import {publicAppConfiguration} from '../../../scripts/app-configuration.mjs';
test('bundled configuration excludes server bearer and private RPC credentials',()=>{
  const config=publicAppConfiguration({MATE_CHAIN_ID:'5042002',MATE_API_URL:'https://mate.example.com',MATE_API_TOKEN:'private-api-secret',
    MATE_RPC_URL:'https://rpc.example.com/private-rpc-secret',MATE_RELAYER_PRIVATE_KEY:'private-relayer-secret'});
  assert.equal(config.apiToken,'');
  assert.equal(config.rpcURL,'https://rpc.testnet.arc.network');
  assert.equal(JSON.stringify(config).includes('private-'),false);
  for(const url of ['https://user:secret@example.com','https://example.com?key=secret','https://example.com/secret','http://192.168.1.2'])
    assert.throws(()=>publicAppConfiguration({MATE_API_URL:url}));
});
