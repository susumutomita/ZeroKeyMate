// Offline compatibility checks for the optional CLI's security overrides.
// No wallet login, user configuration, signing or public RPC is used.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createRequire } from 'node:module';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:http';

const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../../', import.meta.url));

test('CLI help retains the adapter commands with an isolated, offline profile', () => {
  const profile = mkdtempSync(resolve(tmpdir(), 'mate-circle-cli-'));
  try {
    for (const args of [['--help'], ['wallet', 'list', '--help'], ['wallet', 'sign', 'typed-data', '--help']]) {
      const result = spawnSync(process.execPath, [
        '--permission', `--allow-fs-read=${root}`, `--allow-fs-read=${profile}`,
        `--allow-fs-write=${profile}`, require.resolve('@circle-fin/cli'), ...args,
      ], { encoding: 'utf8', timeout: 15_000, env: {
        PATH: process.env.PATH, CIRCLE_CLI_HOME: profile, CIRCLE_VERSION_CHECK: 'off',
        DO_NOT_TRACK: '1', CI: 'true',
      } });
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stdout, /Usage: circle/);
      if (args[1] === 'list') assert.match(result.stdout, /--chain/);
      if (args[1] === 'sign') assert.match(result.stdout, /typed-data/);
    }
  } finally { rmSync(profile, { recursive: true, force: true }); }
});

test('Anchor TOML override accepts the Buffer input used by its workspace loader', () => {
  const result = require('toml').parse(Buffer.from('[workspace]\nmembers = ["programs/*"]\n[provider]\ncluster = "localnet"\n'));
  assert.deepEqual(result.workspace.members, ['programs/*']);
  assert.equal(result.provider.cluster, 'localnet');
  assert.throws(() => require('toml').parse('[workspace\n'));
});

test('Solana RPC keeps working through the Jayson override, including errors', async () => {
  const { Connection } = require('@solana/web3.js');
  const methods = [];
  const server = createServer(async (request, response) => {
    let body = ''; for await (const chunk of request) body += chunk;
    const input = JSON.parse(body); methods.push(input.method);
    const result = input.method === 'getVersion' ? { 'solana-core': 'test-fixture', 'feature-set': 1 } : 42;
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify(input.method === 'getBlockHeight'
      ? { jsonrpc: '2.0', id: input.id, error: { code: -32000, message: 'fixture rejection' } }
      : { jsonrpc: '2.0', id: input.id, result }));
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  try {
    const connection = new Connection(`http://127.0.0.1:${server.address().port}`);
    assert.equal((await connection.getVersion())['solana-core'], 'test-fixture');
    assert.equal(await connection.getSlot(), 42);
    await assert.rejects(connection.getBlockHeight(), /fixture rejection/);
    assert.deepEqual(methods, ['getVersion', 'getSlot', 'getBlockHeight']);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test('Jayson browser client preserves batch IDs and errors', async () => {
  const Client = require('jayson/lib/client/browser');
  const client = new Client((message, callback) => {
    callback(null, JSON.stringify(JSON.parse(message).map(request => request.method === 'ok'
      ? { jsonrpc: '2.0', id: request.id, result: 42 }
      : { jsonrpc: '2.0', id: request.id, error: { code: -32601, message: 'not found' } })));
  });
  const requests = [client.request('ok', []), client.request('missing', [])];
  assert.notEqual(requests[0].id, requests[1].id);
  const results = await new Promise((resolve, reject) => client.request(requests, (error, result) => error ? reject(error) : resolve(result)));
  assert.equal(results[0].id, requests[0].id); assert.equal(results[0].result, 42);
  assert.equal(results[1].id, requests[1].id); assert.equal(results[1].error.code, -32601);
});

test('WebSocket override exchanges frames on loopback', async () => {
  const { WebSocket, WebSocketServer } = require('ws');
  const server = new WebSocketServer({ host: '127.0.0.1', port: 0 });
  server.on('connection', socket => socket.on('message', message => socket.send(message)));
  await once(server, 'listening');
  const client = new WebSocket(`ws://127.0.0.1:${server.address().port}`);
  try {
    await once(client, 'open'); const response = once(client, 'message');
    client.send('public compatibility fixture');
    assert.equal((await response)[0].toString(), 'public compatibility fixture');
  } finally {
    client.terminate(); for (const socket of server.clients) socket.terminate();
    await new Promise(resolve => server.close(resolve));
  }
});
