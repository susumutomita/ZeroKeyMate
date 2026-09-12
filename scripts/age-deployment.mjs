// PUBLIC deployment artifacts and read-only code checks. No wallet or credentials.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {keccak256,isAddress} from 'viem';
const root=path.resolve(import.meta.dirname,'..');
export async function loadAgeDeployment(directory) {
 const file=await readFile(path.join(directory,'deployment.json'));
 assert.ok(file.length<1000000,'Unexpected deployment package size');
 // This digest belongs to the reviewed repository, never to the supplied package.
 // It authenticates creation/runtime code, ABI, compiler settings and immutable
 // positions together; a deployer cannot authorize new code by hashing it again.
 const artifactPins=JSON.parse(await readFile(path.join(root,'config/age-deployment-pins.json')));
 assert.equal(artifactPins.format,1);
 assert.equal(createHash('sha256').update(file).digest('hex'),artifactPins.deploymentSHA256,
  'Deployment package is not the independently reviewed build');
 const pkg=JSON.parse(file);
 const pins=JSON.parse(await readFile(path.join(root,'config/age-runtime-pins.json')));
 assert.equal(pkg.format,1);assert.equal(pkg.chainId,5042002);assert.equal(pkg.testnetOnly,true);
 assert.deepEqual(pkg.publicSetup,pins,'Package does not match the reviewed iPhone setup');
 assert.match(pkg.verifier.runtimeTemplate,/^0x[0-9a-f]+$/);
 assert.equal(keccak256(pkg.verifier.runtimeTemplate),pkg.verifier.runtimeCodeHash);
 assert.deepEqual(pkg.verifier.immutableReferences,{});
 return pkg;
}
export function expectedGateRuntime(pkg,verifier) {
 assert.ok(isAddress(verifier,{strict:false})&&!/^0x0{40}$/i.test(verifier),'Invalid public verifier address');
 const gate=pkg.gate;
 assert.match(gate.runtimeTemplate,/^0x[0-9a-f]+$/);
 assert.equal(keccak256(gate.runtimeTemplate),gate.runtimeCodeHash);
 assert.deepEqual(Object.values(gate.immutableNames).sort(),['verifier','verifierCodeHash']);
 assert.deepEqual(Object.keys(gate.immutableReferences).sort(),Object.keys(gate.immutableNames).sort());
 const code=Buffer.from(gate.runtimeTemplate.slice(2),'hex');
 for(const [id,refs] of Object.entries(gate.immutableReferences)) {
  const name=gate.immutableNames[id];
  const value=name==='verifier'?verifier.slice(2).toLowerCase().padStart(64,'0'):pkg.verifier.runtimeCodeHash.slice(2);
  assert.match(value,/^[0-9a-f]{64}$/);assert.ok(refs.length>0);
  for(const {start,length} of refs){assert.equal(length,32);assert.ok(Number.isSafeInteger(start)&&start>=0&&start+length<=code.length);Buffer.from(value,'hex').copy(code,start);}
 }
 return '0x'+code.toString('hex');
}
export async function checkAgeDeployment(pkg,{verifier,gate},rpcs,now=Math.floor(Date.now()/1000)) {
 assert.equal(rpcs.length,2);assert.notEqual(rpcs[0],rpcs[1]);
 assert.ok(isAddress(gate,{strict:false})&&!/^0x0{40}$/i.test(gate));
 const expected=expectedGateRuntime(pkg,verifier),gateCodeHash=keccak256(expected);
 const heads=await Promise.all(rpcs.map(async rpc=>{assert.equal(await rpc.getChainId(),5042002);return rpc.getBlock({blockTag:'latest'});}));
 assert.ok(heads.every(head=>typeof head.number==='bigint'&&head.number>=0n));
 const blockNumber=heads[0].number<heads[1].number?heads[0].number:heads[1].number;
 const hashes=await Promise.all(rpcs.map(async rpc=>{
  const [block,verifierCode,gateCode]=await Promise.all([rpc.getBlock({blockNumber}),rpc.getCode({address:verifier,blockNumber}),rpc.getCode({address:gate,blockNumber})]);
  assert.equal(block.number,blockNumber);assert.match(block.hash,/^0x[0-9a-fA-F]{64}$/);
  assert.ok(block.timestamp<=BigInt(now+30)&&block.timestamp>=BigInt(now-120),'Stale or future chain snapshot');
  assert.equal(verifierCode?.toLowerCase(),pkg.verifier.runtimeTemplate,'Verifier does not match iPhone parameters');
  assert.equal(gateCode?.toLowerCase(),expected,'Gate is not the prepared government-root verifier');
  return {hash:block.hash.toLowerCase(),timestamp:block.timestamp};
 }));
 assert.deepEqual(hashes[0],hashes[1],'RPC providers disagree');
 return {gateCodeHash,blockHash:hashes[0].hash,blockNumber:blockNumber.toString()};
}
