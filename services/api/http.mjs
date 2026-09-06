import http from 'node:http';
import {timingSafeEqual} from 'node:crypto';
import {TextDecoder} from 'node:util';
import {ProductError, requireValue} from './errors.mjs';

const decoder = new TextDecoder('utf-8', {fatal: true});
export function authenticated(request, token) {
  const expected = Buffer.from(`Bearer ${token}`);
  const supplied = Buffer.from(request.headers.authorization ?? '');
  return token.length >= 32 && supplied.length === expected.length && timingSafeEqual(supplied, expected);
}
export async function readJSON(request, limit = 12 * 1024 * 1024) {
  requireValue(/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers['content-type'] ?? ''),
    'content_type', 'JSON形式で送信してください。', 415);
  requireValue(!request.headers['content-encoding'], 'content_encoding', '圧縮リクエストは受け付けません。', 415);
  const length = request.headers['content-length'];
  requireValue(length === undefined || (/^\d+$/.test(length) && Number(length) <= limit),
    'body_too_large', 'リクエストの上限を超えました。', 413);
  const chunks = []; let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    requireValue(size <= limit, 'body_too_large', 'リクエストの上限を超えました。', 413);
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(decoder.decode(Buffer.concat(chunks)));
    requireValue(value && typeof value === 'object' && !Array.isArray(value), 'invalid_json', 'JSONオブジェクトが必要です。');
    return value;
  } catch (error) {
    if (error instanceof ProductError) throw error;
    throw new ProductError('invalid_json', 'JSONを読み取れませんでした。');
  }
}
export function respond(response, status, value) {
  const bytes = Buffer.from(JSON.stringify(value));
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8', 'Content-Length': bytes.length,
    'Cache-Control': 'no-store, private', 'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'",
  });
  response.end(bytes);
}
/** Pairing capability is installation-scoped, never a public anonymous API. */
export function jsonServer({token, handler, publicHandler, maxConcurrent = 4}) {
  if (typeof token !== 'string' || token.length < 32) throw new Error('A random pairing token of at least 32 characters is required');
  let active = 0, period = Date.now(), count = 0;
  const server = http.createServer(async (request, response) => {
    let admitted = false;
    try {
      requireValue(request.url?.startsWith('/') && !request.url.startsWith('//') && request.url.length <= 2048,
        'invalid_path', '無効なリクエストです。');
      const url = new URL(request.url, 'http://localhost');
      if (request.method === 'GET' && publicHandler) {
        const value = publicHandler(url.pathname);
        if (value !== undefined) { respond(response, 200, value); return; }
      }
      requireValue(authenticated(request, token), 'unauthorized', '接続を承認できません。', 401);
      requireValue(!request.headers.origin, 'browser_origin', 'ブラウザからの操作は許可していません。', 403);
      requireValue(['GET','POST'].includes(request.method), 'method', '未対応の操作です。', 405);
      if (Date.now() - period > 60_000) { period = Date.now(); count = 0; }
      requireValue(++count <= 120 && active < maxConcurrent, 'busy', '別の操作が実行中です。', 429);
      active++; admitted = true;
      const value = await handler(request, url);
      if (!response.destroyed) respond(response, 200, value);
    } catch (error) {
      if (!response.destroyed && !response.headersSent) {
        const known = error instanceof ProductError;
        const malformed = error?.name === 'ZodError';
        respond(response, known ? error.status : malformed ? 400 : 503, {
          error: known ? error.code : malformed ? 'invalid_request' : 'operation_pending',
          message: known ? error.message : malformed ? '入力の形式を確認してください。' : '完了を確認できませんでした。確認待ちの依頼から同じ操作を照会してください。',
        });
      }
      // Deliberately do not log request bodies, RPC URLs, signatures, credentials or raw SDK errors.
    } finally { if (admitted) active--; }
  });
  server.requestTimeout = 30_000; server.headersTimeout = 10_000;
  server.keepAliveTimeout = 5_000; server.maxRequestsPerSocket = 100;
  return server;
}
export async function boundedJSON(url, options = {}, limit = 1_000_000) {
  const response = await fetch(url, {...options, redirect:'error', signal:options.signal ?? AbortSignal.timeout(90_000)});
  requireValue(response.ok, 'upstream_unavailable', `外部サービスが応答できませんでした（HTTP ${response.status}）。`, 503);
  requireValue(response.body && Number(response.headers.get('content-length') ?? 0) <= limit,
    'upstream_response', '外部サービスの応答が大きすぎます。', 502);
  const reader = response.body.getReader(); const chunks=[]; let size=0;
  try {
    while (true) {
      const {done,value}=await reader.read(); if (done) break;
      size+=value.byteLength;
      requireValue(size<=limit,'upstream_response','応答の上限を超えました。',502);
      chunks.push(Buffer.from(value));
    }
    return JSON.parse(decoder.decode(Buffer.concat(chunks)));
  } catch (error) {
    await reader.cancel().catch(()=>{});
    if (error instanceof ProductError) throw error;
    throw new ProductError('upstream_response','外部サービスの応答を検証できません。',502);
  } finally { reader.releaseLock(); }
}
