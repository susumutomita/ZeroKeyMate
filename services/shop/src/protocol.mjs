import {encodeAbiParameters, keccak256, stringToHex, isAddress} from 'viem';
import {decodePaymentSignatureHeader} from '@x402/core/http';
import {PaymentPayloadSchema} from '@x402/core/schemas';

export const CHAIN_ID = 5042002;
export const NETWORK = 'eip155:5042002';
export const USDC = '0x3600000000000000000000000000000000000000';
export const PRODUCTS = Object.freeze([{id:'mate-lager', name:'Mate Lager', description:'A crisp, bright lager. Chosen by you, ordered by Mate.', size:'330 ml · 5% ABV', amount:'100000', currency:'test USDC', minimumAge:20}]);
export const nowSeconds = () => Math.floor(Date.now()/1000);
export const hex32 = value => typeof value === 'string' && /^0x[0-9a-fA-F]{64}$/.test(value);
export const address = value => typeof value === 'string' && isAddress(value, {strict:false}) && !/^0x0{40}$/i.test(value);
export const hashKey = key => keccak256(stringToHex(key));

export function configuration(env) {
  return Number(env.SHOP_CHAIN_ID) === CHAIN_ID && address(env.AGE_GATE_ADDRESS) && hex32(env.AGE_GATE_CODE_HASH)
    && address(env.PAYMENT_RECIPIENT) && Boolean(env.ORDERS);
}

export function newOrder(input, key, env, now = nowSeconds()) {
  const product = PRODUCTS.find(product => product.id === input.productId);
  if (!product || input.quantity !== 1 || !address(input.payer)) throw new Error('invalid_order');
  const order = {id:hashKey(key), productId:product.id, quantity:1, payer:input.payer.toLowerCase(),
    amount:product.amount, recipient:env.PAYMENT_RECIPIENT.toLowerCase(), chainId:CHAIN_ID, token:USDC,
    ageGate:env.AGE_GATE_ADDRESS.toLowerCase(), createdAt:now, expiresAt:now+900,
    minimumAge:20, state:'awaiting_age', paymentTransaction:null};
  order.paymentNonce = keccak256(encodeAbiParameters([{type:'string'},{type:'bytes32'}],['ZKM-X402-ORDER-1',order.id]));
  order.orderHash = orderHash(order);
  return order;
}

export function orderHash(order) {
  return keccak256(encodeAbiParameters(
    ['string','uint256','address','bytes32','string','uint256','address','address','address','uint256','uint256','bytes32','uint256'].map(type=>({type})),
    ['ZKM-AGE-ORDER-1',BigInt(order.chainId),order.ageGate,order.id,order.productId,BigInt(order.quantity),
      order.payer,order.recipient,order.token,BigInt(order.amount),BigInt(order.expiresAt),order.paymentNonce,BigInt(order.minimumAge)]));
}

export function requirements(order) {
  return {scheme:'exact', network:NETWORK, amount:order.amount, asset:USDC, payTo:order.recipient,
    maxTimeoutSeconds:300, extra:{name:'USDC',version:'2'}};
}

export function paymentPayload(header, order, now=nowSeconds()) {
  if (typeof header !== 'string' || header.length > 16384) throw new Error('invalid_payment');
  let decoded;
  try { decoded = decodePaymentSignatureHeader(header); } catch { throw new Error('invalid_payment'); }
  const result = PaymentPayloadSchema.safeParse(decoded);
  if (!result.success || result.data.x402Version !== 2) throw new Error('invalid_payment');
  const payload = result.data;
  const accepted = payload.accepted;
  const expected = requirements(order);
  for (const key of ['scheme','network','amount','asset','payTo']) {
    if (String(accepted[key]).toLowerCase() !== String(expected[key]).toLowerCase()) throw new Error('payment_mismatch');
  }
  const auth = payload.payload.authorization;
  if (!auth || !hex32(auth.nonce) || auth.nonce.toLowerCase() !== order.paymentNonce.toLowerCase()
    || String(auth.from).toLowerCase() !== order.payer || String(auth.to).toLowerCase() !== order.recipient
    || auth.value !== order.amount || !/^\d+$/.test(auth.validAfter) || !/^\d+$/.test(auth.validBefore)
    || BigInt(auth.validAfter) > BigInt(now) || BigInt(auth.validBefore) <= BigInt(now)
    || BigInt(auth.validBefore) > BigInt(order.expiresAt)) throw new Error('payment_mismatch');
  return payload;
}
