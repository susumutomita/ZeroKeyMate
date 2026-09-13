import {DatabaseSync} from 'node:sqlite';
import {randomBytes,createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {ProductError} from './errors.mjs';

const digest=value=>createHash('sha256').update(value).digest('hex');
export const PAIRING_CODE_SECONDS=600,SESSION_SECONDS=3600,SESSION_REQUESTS=500;

/** Only hashes and bounded capability metadata are persisted, never bearer secrets. */
export class PairingStore {
  #db;#scope;#closed=false;
  constructor(filename,scope) {
    if(typeof scope!=='string' || !scope || scope.length>300)throw new Error('Invalid pairing scope');
    this.#scope=scope;
    if(filename!==':memory:') {
      fs.mkdirSync(path.dirname(filename),{recursive:true,mode:0o700});
      if(fs.existsSync(filename) && fs.lstatSync(filename).isSymbolicLink())throw new Error('Pairing store must not be a symlink');
    }
    this.#db=new DatabaseSync(filename);
    if(filename!==':memory:')fs.chmodSync(filename,0o600);
    this.#db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS pairing_codes(hash TEXT PRIMARY KEY,scope TEXT NOT NULL,expires INTEGER NOT NULL) STRICT;
      CREATE TABLE IF NOT EXISTS client_sessions(hash TEXT PRIMARY KEY,scope TEXT NOT NULL,purpose TEXT NOT NULL,expires INTEGER NOT NULL,remaining INTEGER NOT NULL) STRICT;`);
  }
  #transaction(work) {
    this.#db.exec('BEGIN IMMEDIATE');
    try{const result=work();this.#db.exec('COMMIT');return result;}
    catch(error){this.#db.exec('ROLLBACK');throw error;}
  }
  #prune(now) {
    this.#db.prepare('DELETE FROM pairing_codes WHERE expires<=?').run(now);
    this.#db.prepare('DELETE FROM client_sessions WHERE expires<=? OR remaining<=0').run(now);
  }
  issue(now=Math.floor(Date.now()/1000)) {
    return this.#transaction(()=>{
      this.#prune(now);
      this.#db.prepare('DELETE FROM pairing_codes WHERE scope=?').run(this.#scope);
      const code='pair_'+randomBytes(32).toString('hex'),expiresAt=now+PAIRING_CODE_SECONDS;
      this.#db.prepare('INSERT INTO pairing_codes VALUES(?,?,?)').run(digest(code),this.#scope,expiresAt);
      return {code,expiresAt};
    });
  }
  exchange(code,now=Math.floor(Date.now()/1000)) {
    if(typeof code!=='string' || !/^pair_[a-f0-9]{64}$/.test(code))throw new ProductError('pairing_invalid','Create a new one-time pairing code on your Mac.',401);
    return this.#transaction(()=>{
      this.#prune(now);
      const found=this.#db.prepare('DELETE FROM pairing_codes WHERE hash=? AND scope=? AND expires>? RETURNING hash').get(digest(code),this.#scope,now);
      if(!found)throw new ProductError('pairing_invalid','This pairing code is expired or already used. Create a new code on your Mac.',401);
      const active=this.#db.prepare('SELECT count(*) AS count FROM client_sessions WHERE scope=?').get(this.#scope).count;
      if(active>=16)throw new ProductError('pairing_capacity','Revoke old pairing sessions on your Mac before pairing another device.',409);
      const token='session_'+randomBytes(32).toString('hex'),expiresAt=now+SESSION_SECONDS;
      this.#db.prepare('INSERT INTO client_sessions VALUES(?,?,?,?,?)').run(digest(token),this.#scope,'mate-api',expiresAt,SESSION_REQUESTS);
      return {token,expiresAt,remainingRequests:SESSION_REQUESTS};
    });
  }
  authorize(token,now=Math.floor(Date.now()/1000)) {
    if(typeof token!=='string' || !/^session_[a-f0-9]{64}$/.test(token))return false;
    return !!this.#db.prepare(`UPDATE client_sessions SET remaining=remaining-1
      WHERE hash=? AND scope=? AND purpose='mate-api' AND expires>? AND remaining>0 RETURNING remaining`)
      .get(digest(token),this.#scope,now);
  }
  revoke() {
    this.#transaction(()=>{
      this.#db.prepare('DELETE FROM pairing_codes WHERE scope=?').run(this.#scope);
      this.#db.prepare('DELETE FROM client_sessions WHERE scope=?').run(this.#scope);
    });
  }
  close(){if(!this.#closed){this.#closed=true;this.#db.close();}}
}
