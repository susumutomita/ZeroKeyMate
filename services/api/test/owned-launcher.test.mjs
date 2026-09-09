import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PassThrough} from 'node:stream';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {startOwnedLauncher} from '../owned-launcher.mjs';

test('cancellation stops owned shell children but leaves unrelated work running',{skip:process.platform==='win32',timeout:10_000},async t=>{
  const unrelated=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'});
  t.after(async()=>{const closed=once(unrelated,'close');unrelated.kill();await closed;});
  for(const stubborn of [false,true]) {
    const output=new PassThrough();let text='';let ready;
    const started=new Promise(resolve=>{ready=resolve;});
    output.on('data',chunk=>{text+=chunk;if(text.includes('ready'))ready();});
    const fixture=`${stubborn ? "process.on('SIGTERM',()=>{});" : ''}console.log('ready');setInterval(()=>{},1000);`;
    const parent=`const {spawn}=require('node:child_process');${stubborn ? "process.on('SIGTERM',()=>{});" : ''}spawn(process.execPath,['-e',${JSON.stringify(fixture)}],{stdio:'inherit'});setInterval(()=>{},1000);`;
    const owned=startOwnedLauncher(process.execPath,['-e',parent],{stdin:'ignore',stdout:output,stderr:output,graceMs:300});
    t.after(()=>owned.stop());
    await started;
    await Promise.all([owned.stop(),owned.stop()]);
    const result=await owned.completion;
    assert.notEqual(result.signal,null);
    assert.doesNotThrow(()=>process.kill(unrelated.pid,0));
  }
});

test('failed spawn closes cleanly and repeated stop is harmless',async()=>{
  const output=new PassThrough();output.resume();
  const owned=startOwnedLauncher('/nonexistent-mate-launcher',[],{stdout:output,stderr:output,stdin:'ignore'});
  const result=await owned.completion;assert.equal(result.error.code,'ENOENT');
  await owned.stop();await owned.stop();
});
