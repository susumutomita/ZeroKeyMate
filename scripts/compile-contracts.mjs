import fs from 'node:fs';
import path from 'node:path';
import solc from 'solc';

const root = path.resolve(import.meta.dirname, '..');
const inputFiles = ['contracts/src/MateVault.sol', 'contracts/src/MateNaming.sol'];
if (process.argv.includes('--tests')) inputFiles.push('contracts/test/TestToken.sol');
const sources = Object.fromEntries(inputFiles.map(p => [p, {content: fs.readFileSync(path.join(root, p), 'utf8')}]));
const output = JSON.parse(solc.compile(JSON.stringify({
  language: 'Solidity', sources,
  settings: { optimizer: {enabled: true, runs: 200}, evmVersion: 'cancun', viaIR: true,
    outputSelection: {'*': {'*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object']}} }
}), {import: name => {
  const resolved = path.resolve(root, 'node_modules', name);
  if (!resolved.startsWith(path.join(root, 'node_modules') + path.sep)) return {error: 'Import outside dependencies'};
  try {return {contents: fs.readFileSync(resolved, 'utf8')};} catch {return {error: `Missing import ${name}`};}
}}));
for (const error of output.errors ?? []) console.error(error.formattedMessage);
if ((output.errors ?? []).some(e => e.severity === 'error')) process.exit(1);
fs.mkdirSync(path.join(root, '.build/contracts'), {recursive: true});
for (const file of inputFiles) for (const [name, artifact] of Object.entries(output.contracts[file])) {
  fs.writeFileSync(path.join(root, '.build/contracts', `${name}.json`), JSON.stringify({
    contractName: name, compiler: solc.version(), abi: artifact.abi,
    bytecode: `0x${artifact.evm.bytecode.object}`, deployedBytecode: `0x${artifact.evm.deployedBytecode.object}`
  }, null, 2));
  console.log(`Compiled ${name}`);
}
