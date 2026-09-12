import {parseAbi} from 'viem';
import {hex32} from './protocol.mjs';

export const AGE_ABI = parseAbi(['function verifyOrderAge(bytes32 orderHash,bytes32 nonce,uint256 expiresAt,bytes proof,uint256[8] inputs) view returns (bool)']);
export const EMPTY_AGE_ARGUMENTS = ['0x'+'00'.repeat(32),'0x'+'00'.repeat(32),0n,'0x',Array(8).fill(0n)];

export function ageSubmission(input) {
  if (Object.keys(input).length !== 2 || !hex32(input.rootKeyHash)
      || typeof input.proof !== 'string' || !/^0x[0-9a-fA-F]{768}$/.test(input.proof)) {
    throw new Error('invalid_age_proof');
  }
  return {ageProof:input.proof.toLowerCase(),ageRootKeyHash:input.rootKeyHash.toLowerCase()};
}

export function ageArguments(order) {
  if (!order.ageProof || !order.ageRootKeyHash) return null;
  const split=value=>[BigInt('0x'+value.slice(2,34)),BigInt('0x'+value.slice(34))];
  return [order.orderHash,order.paymentNonce,BigInt(order.expiresAt),order.ageProof,
    [...split(order.orderHash),...split(order.paymentNonce),...split(order.ageRootKeyHash),BigInt(order.createdAt),BigInt(order.expiresAt)]];
}
