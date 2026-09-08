import fs from 'node:fs';
import {randomBytes} from 'node:crypto';
const filename=new URL('../.env',import.meta.url);
if(fs.existsSync(filename)){console.log('.env already exists; it was preserved.');}
else {
  const secret=()=>randomBytes(32).toString('hex');
  let content=fs.readFileSync(new URL('../.env.example',import.meta.url),'utf8');
  for(const name of ['MATE_API_TOKEN','MATE_JOURNAL_KEY','PROVIDER_API_TOKEN','PROVIDER_JOURNAL_KEY'])
    content=content.replace(new RegExp(`^${name}=$`,'m'),`${name}=${secret()}`);
  fs.writeFileSync(filename,content,{flag:'wx',mode:0o600});
  console.log('Created private .env with local pairing and journal keys. Configure external services separately; no signing keys were generated.');
}
