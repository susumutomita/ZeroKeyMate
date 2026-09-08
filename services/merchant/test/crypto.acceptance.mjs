import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {ROOT} from '../../api/config.mjs';
import {ProofVerifier} from '../../api/verifier.mjs';
import {Journal} from '../../api/journal.mjs';
import {sha256} from '../../api/protocol.mjs';
import {Specialist} from '../../provider/server.mjs';

// Real cryptographic proof and binary. Chain/model adapters below are test doubles;
// this acceptance proves merchant ZK verification, not live payment or delivery.
test('merchant accepts a real matching ProveKit proof and rejects a modified copy before work',async t=>{
  const directory=path.join(ROOT,'.build/proofs');
  const statement=JSON.parse(fs.readFileSync(path.join(directory,'statement.json'),'utf8'));
  const bytes=fs.readFileSync(path.join(directory,'valid.np'));
  const verifier=new ProofVerifier({binary:path.join(ROOT,'services/verifier/target/release/mate-verify'),
    verifier:path.join(directory,'mate_policy.pkv'),manifest:path.join(directory,'manifest.json')});
  const config={chainId:11155111,vault:'0x'+'11'.repeat(20),recipient:'0x'+'33'.repeat(20),price:'3000000',service:0};
  const action={mandateId:'0x'+'22'.repeat(32),recipient:config.recipient,amount:config.price,service:0,
    nonce:'0x'+'44'.repeat(32),expiresAt:2000000000,requestHash:sha256('Hello, Mate.'),spentBefore:'0'};
  const journal=new Journal(':memory:','ab'.repeat(32));t.after(()=>journal.close());let runs=0;
  const specialist=new Specialist({config,journal,verifier,
    chain:{state:async()=>({policyHash:statement.policyHash,spent:'0',revoked:false,validUntil:2000000100}),verifyAgent:async()=>true},
    model:{run:async()=>{runs++;return 'Explicit model test double';}}});
  const request={action,payload:'Hello, Mate.',agentSignature:'0x1234',proof:bytes.toString('base64'),proofHash:sha256(bytes)};
  const changed=Buffer.from(bytes);changed[Math.floor(changed.length/2)]^=1;
  await assert.rejects(specialist.prepare({...request,proof:changed.toString('base64'),proofHash:sha256(changed)}),{code:'proof_rejected'});
  assert.equal(runs,0);assert.equal(journal.recentWork().length,0);
  const ready=await specialist.prepare(request);
  assert.equal(ready.actionHash,statement.actionHash);assert.equal(runs,1);
  assert.equal(journal.get(`work:${ready.actionHash}`).value.proofVerified,true);
});
