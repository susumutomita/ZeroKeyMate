import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {ProofVerifier} from '../verifier.mjs';
import {ROOT} from '../config.mjs';
import {sha256} from '../protocol.mjs';

// Requires make proofs and the real Rust verifier. Never replaced with a mock.
const directory=path.join(ROOT,'.build/proofs');
const verifier=new ProofVerifier({binary:path.join(ROOT,'services/verifier/target/release/mate-verify'),
  verifier:path.join(directory,'mate_policy.pkv'),manifest:path.join(directory,'manifest.json')});
const statement=JSON.parse(fs.readFileSync(path.join(directory,'statement.json'),'utf8'));
const bytes=fs.readFileSync(path.join(directory,'valid.np'));
const expected={policyHash:statement.policyHash,actionHash:statement.actionHash,
  action:{spentBefore:statement.spent,amount:statement.amount,service:statement.service}};
test('real ProveKit proof is verified and its extracted statement matches execution',async()=>{
  const result=await verifier.verify(bytes.toString('base64'),expected);
  assert.deepEqual(result.statement,statement);assert.equal(result.proofHash,sha256(bytes));
});
test('real verifier rejects a tampered proof',async()=>{
  const changed=Buffer.from(bytes);changed[Math.floor(changed.length/2)]^=1;
  await assert.rejects(verifier.verify(changed.toString('base64'),expected),{code:'proof_rejected'});
});
test('a valid proof never authorizes a substituted public statement',async()=>{
  await assert.rejects(verifier.verify(bytes.toString('base64'),{...expected,actionHash:sha256('substitution')}),{code:'proof_rejected'});
});
