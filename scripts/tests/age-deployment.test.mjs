import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {keccak256} from 'viem';
import {loadAgeDeployment} from '../age-deployment.mjs';

test('a deployer cannot authorize an always-success verifier using copied setup pins and recomputed hashes',async()=>{
 const directory=await mkdtemp(path.join(os.tmpdir(),'mate-forged-deployment-'));
 try {
  const publicSetup=JSON.parse(await readFile(new URL('../../config/age-runtime-pins.json',import.meta.url)));
  // Valid EVM returning true. The old loader accepted this self-consistent package.
  const runtimeTemplate='0x600160005260206000f3';
  const verifier={runtimeTemplate,runtimeCodeHash:keccak256(runtimeTemplate),immutableReferences:{}};
  const pkg={format:1,chainId:5042002,testnetOnly:true,publicSetup,verifier,
   gate:{...verifier,immutableNames:{}}};
  await writeFile(path.join(directory,'deployment.json'),JSON.stringify(pkg));
  await assert.rejects(()=>loadAgeDeployment(directory),/independently reviewed build/);
 } finally {await rm(directory,{recursive:true,force:true});}
});
