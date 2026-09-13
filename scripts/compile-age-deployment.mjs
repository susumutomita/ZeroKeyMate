// Offline compiler helper. Receives only public source from prepare-age-deployment.py.
import assert from 'node:assert/strict';
import solc from 'solc';
import {keccak256} from 'viem';
let input='';for await(const chunk of process.stdin){input+=chunk;assert.ok(input.length<1000000);}
const sources=JSON.parse(input);
assert.deepEqual(Object.keys(sources).sort(),['MateAgeGate.sol','Verifier.sol']);
const settings={optimizer:{enabled:true,runs:200},evmVersion:'cancun',viaIR:true,
 outputSelection:{'*':{'':['ast'],'*':['abi','evm.bytecode.object','evm.deployedBytecode.object','evm.deployedBytecode.immutableReferences']}}};
const output=JSON.parse(solc.compile(JSON.stringify({language:'Solidity',sources,settings})));
assert.equal((output.errors??[]).filter(e=>e.severity==='error').length,0,'Contract compilation failed');
const record=(file,name)=>{
 const c=output.contracts[file][name],runtime='0x'+c.evm.deployedBytecode.object;
 assert.match(runtime,/^0x[0-9a-f]+$/);assert.ok(runtime.length/2-1<=24576);
 return {abi:c.abi,bytecode:'0x'+c.evm.bytecode.object,runtimeTemplate:runtime,
  runtimeCodeHash:keccak256(runtime),immutableReferences:c.evm.deployedBytecode.immutableReferences};
};
const gate=record('MateAgeGate.sol','MateAgeGate');
const definition=output.sources['MateAgeGate.sol'].ast.nodes.find(n=>n.nodeType==='ContractDefinition'&&n.name==='MateAgeGate');
gate.immutableNames=Object.fromEntries(definition.nodes.filter(n=>n.nodeType==='VariableDeclaration'&&n.mutability==='immutable').map(n=>[String(n.id),n.name]));
assert.deepEqual(Object.values(gate.immutableNames).sort(),['verifier','verifierCodeHash']);
assert.deepEqual(Object.keys(gate.immutableReferences).sort(),Object.keys(gate.immutableNames).sort());
process.stdout.write(JSON.stringify({compiler:solc.version(),settings,verifier:record('Verifier.sol','ProvekitGroth16Verifier'),gate}));
