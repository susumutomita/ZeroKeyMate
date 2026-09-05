import {test} from 'node:test';
import assert from 'node:assert/strict';
import {actionDigest,actionPreimage,actionSchema,assertStatement,sha256,u64,MAX_U64} from '../protocol.mjs';
const vault='0x'+'11'.repeat(20);
const action={mandateId:'0x'+'22'.repeat(32),recipient:'0x'+'33'.repeat(20),nonce:'0x'+'44'.repeat(32),
  expiresAt:2_000_000_000,requestHash:sha256(Buffer.from('Hello, Mate.')),spentBefore:'0',amount:'3000000',service:0};

test('canonical preimage is exactly 177 bytes with fixed domain and field offsets',()=>{
  const p=actionPreimage(11155111,vault,action);
  assert.equal(p.length,177); assert.equal(p.subarray(0,8).toString(),'ZKM-ACT1');
  assert.equal(p.readBigUInt64BE(8),11155111n); assert.equal(p.readBigUInt64BE(160),0n);
  assert.equal(p.readBigUInt64BE(168),3000000n); assert.equal(p[176],0);
});
test('every security-sensitive field changes the action hash',()=>{
  const original=actionDigest(11155111,vault,action);
  const changes={mandateId:'0x'+'55'.repeat(32),recipient:'0x'+'66'.repeat(20),nonce:'0x'+'77'.repeat(32),
    expiresAt:2000000001,requestHash:sha256('other'),spentBefore:'1',amount:'3000001',service:1};
  for(const [key,value] of Object.entries(changes)) assert.notEqual(actionDigest(11155111,vault,{...action,[key]:value}),original,key);
  assert.notEqual(actionDigest(1,vault,action),original);
  assert.notEqual(actionDigest(11155111,'0x'+'88'.repeat(20),action),original);
});
test('integers never accept rounding, signed values, exponent notation, or overflow',()=>{
  for(const amount of ['1e6','-1','01','1.0',(MAX_U64+1n).toString()]) assert.throws(()=>actionSchema.parse({...action,amount}));
  assert.throws(()=>u64(-1)); assert.throws(()=>u64(MAX_U64+1n));
  assert.equal(u64(MAX_U64).toString('hex'),'ffffffffffffffff');
});
test('proof statement must match all public execution fields',()=>{
  const context={policyHash:'0x'+'99'.repeat(32),actionHash:actionDigest(11155111,vault,action),action};
  const statement={policyHash:context.policyHash,actionHash:context.actionHash,spent:'0',amount:'3000000',service:0};
  assert.deepEqual(assertStatement(statement,context),statement);
  for(const [key,value] of Object.entries({policyHash:'0x'+'00'.repeat(32),actionHash:'0x'+'00'.repeat(32),spent:'1',amount:'1',service:1})) {
    assert.throws(()=>assertStatement({...statement,[key]:value},context),undefined,key);
  }
  assert.throws(()=>assertStatement({...statement,valid:true},context));
});
test('malformed addresses and unknown action fields fail closed',()=>{
  assert.throws(()=>actionPreimage(11155111,'0x1234',action));
  assert.throws(()=>actionSchema.parse({...action,service:2}));
  assert.throws(()=>actionSchema.parse({...action,budget:'99999'}));
});
