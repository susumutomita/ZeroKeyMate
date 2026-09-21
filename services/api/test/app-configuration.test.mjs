import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
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
test('a configured shop survives rebuild with only its existing public IDs',()=>{
  const previous={chainID:5042002,privyAppID:'public-app',privyClientID:'public-client',
    apiToken:'private-old-token',rpcURL:'https://rpc.example.com/private-key',vault:'private-old-vault'};
  const env={SEPOLIA_RPC_URL:'https://rpc.example.com/private-sepolia',MATE_RELAYER_PRIVATE_KEY:'private-relayer'};
  const config=publicAppConfiguration(env,{shopConfigured:true,previous});
  assert.equal(config.chainID,5042002);assert.equal(config.privyAppID,'public-app');assert.equal(config.privyClientID,'public-client');
  assert.equal(config.rpcURL,'https://rpc.testnet.arc.network');assert.equal(config.token,'0x3600000000000000000000000000000000000000');
  assert.equal(config.apiToken,'');assert.equal(config.vault,'');assert.equal(JSON.stringify(config).includes('private-'),false);
  assert.equal(env.MATE_CHAIN_ID,undefined,'Do not mutate the caller environment');
});
test('explicit identifiers override prior setup and an explicit different chain fails closed',()=>{
  const options={shopConfigured:true,previous:{privyAppID:'old-app',privyClientID:'old-client'}};
  const updated=publicAppConfiguration({MATE_CHAIN_ID:'5042002',PRIVY_APP_ID:'new-app',PRIVY_IOS_CLIENT_ID:'new-client'},options);
  assert.equal(updated.privyAppID,'new-app');assert.equal(updated.privyClientID,'new-client');
  const cleared=publicAppConfiguration({PRIVY_APP_ID:'',PRIVY_IOS_CLIENT_ID:''},options);
  assert.equal(cleared.privyAppID,'');assert.equal(cleared.privyClientID,'');
  for(const MATE_CHAIN_ID of ['11155111','1','','5042002 '])
    assert.throws(()=>publicAppConfiguration({MATE_CHAIN_ID},options),/configured shop build/);
});
test('companion-only builds never inherit another installation or change the legacy chain selection',()=>{
  const config=publicAppConfiguration({SEPOLIA_RPC_URL:'https://rpc.example.com'},
    {previous:{chainID:5042002,privyAppID:'old-app',privyClientID:'old-client'}});
  assert.equal(config.chainID,11155111);assert.equal(config.privyAppID,'');assert.equal(config.privyClientID,'');
  const absent=publicAppConfiguration({}, {shopConfigured:true,previous:null});
  assert.equal(absent.chainID,5042002);assert.equal(absent.privyAppID,'');
});
test('the real generator reads existing public shop setup and leaves it intact on a conflicting chain',()=>{
  const root=path.resolve(import.meta.dirname,'../../..');
  const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'mate-public-config-'));
  try {
    for(const file of ['scripts/app-configuration.mjs','scripts/generate-app-config.mjs','services/api/networks.mjs','services/api/errors.mjs']) {
      fs.mkdirSync(path.dirname(path.join(fixture,file)),{recursive:true});fs.copyFileSync(path.join(root,file),path.join(fixture,file));
    }
    fs.symlinkSync(path.join(root,'node_modules'),path.join(fixture,'node_modules'),'dir');
    const resources=path.join(fixture,'apps/ios/ZeroKeyMate/Resources');fs.mkdirSync(resources,{recursive:true});
    const config=path.join(resources,'Configuration.json');
    fs.writeFileSync(config,JSON.stringify({privyAppID:'fixture-app',privyClientID:'fixture-client',apiToken:'private-fixture'}));
    fs.writeFileSync(path.join(resources,'ShopConnection.json'),'{}');
    const env={PATH:process.env.PATH,SEPOLIA_RPC_URL:'https://sepolia.example.com'};
    const first=spawnSync(process.execPath,['scripts/generate-app-config.mjs'],{cwd:fixture,env,encoding:'utf8'});
    assert.equal(first.status,0,first.stderr);
    const saved=fs.readFileSync(config,'utf8'),value=JSON.parse(saved);
    assert.equal(value.chainID,5042002);assert.equal(value.privyAppID,'fixture-app');assert.equal(value.privyClientID,'fixture-client');
    assert.equal(saved.includes('private-fixture'),false);
    const conflict=spawnSync(process.execPath,['scripts/generate-app-config.mjs'],{cwd:fixture,
      env:{...env,MATE_CHAIN_ID:'11155111'},encoding:'utf8'});
    assert.notEqual(conflict.status,0);assert.match(conflict.stderr,/configured shop build/);
    assert.equal(fs.readFileSync(config,'utf8'),saved);
  }finally{fs.rmSync(fixture,{recursive:true,force:true})}
});
