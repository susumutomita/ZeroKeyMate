import {createHash, randomBytes} from 'node:crypto';
import {z} from 'zod';

export const MAX_U64 = (1n << 64n) - 1n;
export const uintString = z.string().regex(/^(0|[1-9][0-9]*)$/).refine(v => BigInt(v) <= MAX_U64, 'uint64 overflow');
export const address = z.string().regex(/^0x[0-9a-fA-F]{40}$/);
export const hash32 = z.string().regex(/^0x[0-9a-fA-F]{64}$/);
export const actionSchema = z.object({
  mandateId: hash32, recipient: address, amount: uintString.refine(v => BigInt(v) > 0n),
  service: z.number().int().min(0).max(1), nonce: hash32,
  expiresAt: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
  requestHash: hash32, spentBefore: uintString,
}).strict();
export const grantSchema = z.object({
  owner: address, agent: address, policyHash: hash32,
  validUntil: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
  nonce: z.string().regex(/^(0|[1-9][0-9]*)$/).refine(v => BigInt(v) < (1n << 256n)),
}).strict();
export const signatureSchema = z.string().regex(/^0x(?:[0-9a-fA-F]{2})+$/).max(16386);
export const grantTypes = { Grant: [
  {name:'owner',type:'address'}, {name:'agent',type:'address'}, {name:'policyHash',type:'bytes32'},
  {name:'validUntil',type:'uint64'}, {name:'nonce',type:'uint256'},
]};
export const executionTypes = {Execution: [{name:'actionHash',type:'bytes32'}]};
export const proofTypes = {ProofApproval: [{name:'actionHash',type:'bytes32'},{name:'proofHash',type:'bytes32'}]};
export function domain(chainId, vault) { return {name:'ZeroKey Mate',version:'1',chainId,verifyingContract:vault}; }
export function sha256(bytes) { return `0x${createHash('sha256').update(bytes).digest('hex')}`; }
export function hexBytes(value, length) {
  if (typeof value !== 'string' || !new RegExp(`^0x[0-9a-fA-F]{${length*2}}$`).test(value)) throw new Error(`Expected ${length} bytes`);
  return Buffer.from(value.slice(2), 'hex');
}
export function u64(value) {
  const n = BigInt(value);
  if (n < 0n || n > MAX_U64) throw new RangeError('uint64 out of range');
  const out = Buffer.alloc(8); out.writeBigUInt64BE(n); return out;
}
export function actionPreimage(chainId, vault, rawAction) {
  const a = actionSchema.parse(rawAction);
  return Buffer.concat([Buffer.from('ZKM-ACT1'),u64(chainId),hexBytes(vault,20),
    hexBytes(a.mandateId,32),hexBytes(a.recipient,20),hexBytes(a.nonce,32),u64(a.expiresAt),
    hexBytes(a.requestHash,32),u64(a.spentBefore),u64(a.amount),Buffer.from([a.service])]);
}
export function actionDigest(chainId, vault, action) { return sha256(actionPreimage(chainId,vault,action)); }
export function contractAction(action) {
  const a = actionSchema.parse(action);
  return {...a, amount:BigInt(a.amount),spentBefore:BigInt(a.spentBefore),expiresAt:BigInt(a.expiresAt)};
}
export function contractGrant(grant) {
  const g = grantSchema.parse(grant);
  return {...g, validUntil:BigInt(g.validUntil),nonce:BigInt(g.nonce)};
}
export function newNonce() { return `0x${randomBytes(32).toString('hex')}`; }

/** Match the statement extracted AFTER cryptographic verification, not a client assertion. */
export function assertStatement(statement, {policyHash, actionHash, action}) {
  const parsed = z.object({policyHash:hash32, actionHash:hash32, spent:uintString,
    amount:uintString, service:z.number().int().min(0).max(1)}).strict().parse(statement);
  if (parsed.policyHash.toLowerCase() !== policyHash.toLowerCase()
      || parsed.actionHash.toLowerCase() !== actionHash.toLowerCase()
      || BigInt(parsed.spent) !== BigInt(action.spentBefore)
      || BigInt(parsed.amount) !== BigInt(action.amount)
      || parsed.service !== action.service) throw new Error('Verified statement does not authorize this action');
  return parsed;
}
