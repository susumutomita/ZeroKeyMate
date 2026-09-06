import fs from 'node:fs';
import path from 'node:path';
import {parseEnv} from 'node:util';
export const root=path.resolve(import.meta.dirname,'..');
export function loadEnvironment(){
 const filename=path.join(root,'.env');
 return fs.existsSync(filename)?parseEnv(fs.readFileSync(filename,'utf8')):{};
}
/** Replace only named settings, preserve comments and do not display secrets. */
export function saveEnvironment(changes){
 const filename=path.join(root,'.env');
 const old=fs.existsSync(filename)?fs.readFileSync(filename,'utf8'):'';
 const outstanding=new Map(Object.entries(changes));
 const lines=old.split('\n').map(line=>{
  const key=/^\s*([A-Z][A-Z0-9_]*)\s*=/.exec(line)?.[1];
  if(!key||!outstanding.has(key))return line;
  const value=outstanding.get(key);outstanding.delete(key);return encode(key,value);
 });
 for(const [key,value]of outstanding)lines.push(encode(key,value));
 const temporary=filename+'.new';
 fs.writeFileSync(temporary,lines.join('\n').replace(/\n+$/,'')+'\n',{mode:0o600});
 fs.renameSync(temporary,filename);fs.chmodSync(filename,0o600);
}
function encode(key,value){
 if(!/^[A-Z][A-Z0-9_]*$/.test(key)||typeof value!=='string'||/[\r\n']/.test(value))throw new Error('Invalid configuration value');
 return `${key}='${value}'`;
}
