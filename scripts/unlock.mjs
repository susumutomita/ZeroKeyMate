import fs from 'node:fs';
import path from 'node:path';
import {ROOT} from '../services/api/config.mjs';
const kind=process.argv[2];
if(!['api','provider'].includes(kind))throw new Error('Usage: npm run unlock -- api|provider');
const directory=kind==='api' ? process.env.MATE_DATA_DIRECTORY||path.join(ROOT,'.data')
  :process.env.PROVIDER_DATA_DIRECTORY||path.join(ROOT,'.data/provider');
const filename=path.join(directory,`${kind}.lock`);
if(!fs.existsSync(filename)){console.log('No lock exists.');}
else {
  const metadata=fs.lstatSync(filename),lock=JSON.parse(fs.readFileSync(filename,'utf8'));
  if(metadata.isSymbolicLink() || !Number.isSafeInteger(lock.pid) || lock.pid<=0)throw new Error('Cannot safely identify this lock.');
  let alive=true;
  try{process.kill(lock.pid,0);}catch(error){if(error.code==='ESRCH')alive=false;else throw error;}
  if(alive)throw new Error('The process still exists. Stop it before unlocking; transactions may be in flight.');
  if(fs.lstatSync(filename).ino!==metadata.ino)throw new Error('The lock changed. No action taken.');
  fs.unlinkSync(filename);console.log('Removed the stopped process lock. The encrypted journal and pending transaction bytes were preserved.');
}
