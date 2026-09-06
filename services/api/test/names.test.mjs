import {test} from 'node:test';
import assert from 'node:assert/strict';
import {nameMessage,nameClaimSchema,Names} from '../names.mjs';
import {zeroAddress} from 'viem';
const claim={label:'my-mate',owner:'0x'+'11'.repeat(20),agent:'0x'+'22'.repeat(20),nonce:'0x'+'33'.repeat(32),expiresAt:2_000_000_000,signature:'0x1234'};
test('name approval binds the full parent name, owner, agent, domain and expiry',()=>{
  const config={vault:'0x'+'44'.repeat(20),ensParent:'mates.eth'};
  const original=nameMessage(config,claim);
  assert.ok(original.includes('name:my-mate.mates.eth'));
  assert.notEqual(original,nameMessage({...config,ensParent:'other.eth'},claim));
  for(const [field,value] of Object.entries({label:'other',agent:claim.owner,owner:claim.agent,expiresAt:2_000_000_001,nonce:'0x'+'55'.repeat(32)}))
    assert.notEqual(original,nameMessage(config,{...claim,[field]:value}),field);
  for(const label of ['Aname','ab','-mate','mate-','a.b','あいう']) assert.throws(()=>nameClaimSchema.parse({...claim,label}));
});
test('missing ENSv2 registry remains unresolved and can never invent an address',async()=>{
  const names=new Names({}, {public:{readContract:async()=>zeroAddress}},null);
  await assert.rejects(names.resolve('mate.example.eth'),{code:'ens_unresolved'});
  await assert.rejects(names.claim(claim),{code:'ens_unconfigured'});
});
