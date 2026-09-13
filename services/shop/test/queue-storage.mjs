// Snapshot/restore models durable storage and atomic commits, not chain results.
export class QueueStorage {
 constructor(values=[]) {this.values=new Map(values);this.failCommit=false;}
 async get(key) {return structuredClone(this.values.get(key));}
 async put(values) {for(const [key,value] of Object.entries(values))this.values.set(key,structuredClone(value));}
 async delete(key) {this.values.delete(key);}
 async setAlarm(value) {this.values.set('alarm',value);}
 async deleteAlarm() {this.values.delete('alarm');}
 async transaction(action) {
  const tx=new QueueStorage(structuredClone([...this.values]));await action(tx);
  if(this.failCommit)throw Error('storage failed');this.values=tx.values;
 }
}
