import {after, before, test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {randomBytes} from 'node:crypto';
import fs from 'node:fs';
import {createPublicClient, createWalletClient, http, hashTypedData, keccak256, toHex} from 'viem';
import {foundry} from 'viem/chains';
import {mnemonicToAccount} from 'viem/accounts';

// Deterministic SIGNER ACTORS, not live AI. Disposable local token, not USDC.
// No .env, user key, public RPC, deployed shop or external payment is accessed.
const phrase = 'test test test test test test test test test test test junk';
const accounts = Array.from({length: 8}, (_, addressIndex) => mnemonicToAccount(phrase, {addressIndex}));
const [owner, agentA, agentB, merchantA, merchantB, relayerA, relayerB, stranger] = accounts;
const artifact = name => JSON.parse(fs.readFileSync(new URL(`../../.build/contracts/${name}.json`, import.meta.url), 'utf8'));
const budgetArtifact = artifact('MateSharedBudget');
const tokenArtifact = artifact('SharedBudgetTestToken');
const paymentTypes = {Payment: [
  {name: 'agent', type: 'address'}, {name: 'token', type: 'address'},
  {name: 'recipient', type: 'address'}, {name: 'amount', type: 'uint256'},
  {name: 'nonce', type: 'bytes32'}, {name: 'expiresAt', type: 'uint64'},
  {name: 'requestHash', type: 'bytes32'}
]};
const nonce = () => `0x${randomBytes(32).toString('hex')}`;
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let anvil;
let client;
let wallets;

async function start() {
  const reservation = createServer();
  await new Promise((resolve, reject) => {
    reservation.once('error', reject);
    reservation.listen(0, '127.0.0.1', resolve);
  });
  const port = reservation.address().port;
  await new Promise((resolve, reject) => reservation.close(error => error ? reject(error) : resolve()));
  let startupError;
  anvil = spawn('anvil', ['--host', '127.0.0.1', '--port', String(port), '--chain-id', '31337',
    '--mnemonic', phrase, '--accounts', '8', '--silent'], {stdio: 'ignore'});
  anvil.on('error', error => { startupError = error; });
  const transport = http(`http://127.0.0.1:${port}`, {timeout: 2_000, retryCount: 0});
  client = createPublicClient({chain: foundry, transport, pollingInterval: 50});
  wallets = accounts.map(account => createWalletClient({account, chain: foundry, transport}));
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    if (startupError) throw new Error('Install Anvil; no test is skipped or replaced with a fake result.', {cause: startupError});
    if (anvil.exitCode !== null) throw new Error(`Owned Anvil process exited: ${anvil.exitCode}`);
    try {
      assert.equal(await client.getChainId(), 31337);
      assert.match(await client.request({method: 'web3_clientVersion'}), /anvil/i);
      return;
    } catch { await pause(100); }
  }
  throw new Error('Owned local Anvil did not become ready within 20 seconds.');
}
async function stop() {
  if (!anvil || anvil.exitCode !== null || !anvil.pid) return;
  await new Promise(resolve => {
    const timer = setTimeout(() => { anvil.kill('SIGKILL'); resolve(); }, 3_000);
    anvil.once('exit', () => { clearTimeout(timer); resolve(); });
    anvil.kill('SIGTERM');
  });
}
async function receipt(hash, status = 'success') {
  const value = await client.waitForTransactionReceipt({hash, timeout: 20_000});
  assert.equal(value.status, status);
  return value;
}
const read = (f, name, args = []) => client.readContract({address: f.budget, abi: budgetArtifact.abi, functionName: name, args});
const balance = (f, address) => client.readContract({address: f.token, abi: tokenArtifact.abi, functionName: 'balanceOf', args: [address]});
async function call(f, functionName, args = [], wallet = wallets[0]) {
  const {request} = await client.simulateContract({address: f.budget, abi: budgetArtifact.abi, functionName, args, account: wallet.account});
  return receipt(await wallet.writeContract(request));
}
async function tokenCall(f, functionName, args, wallet = wallets[0]) {
  return receipt(await wallet.writeContract({address: f.token, abi: tokenArtifact.abi, functionName, args}));
}
async function fixture(options = {}) {
  const token = (await receipt(await wallets[0].deployContract({abi: tokenArtifact.abi, bytecode: tokenArtifact.bytecode}))).contractAddress;
  assert.ok(token);
  const now = (await client.getBlock()).timestamp;
  const validUntil = now + 3600n;
  const constructorArgs = [token, [agentA.address, agentB.address], [merchantA.address, merchantB.address],
    10_000_000n, 6_000_000n, validUntil];
  const budget = (await receipt(await wallets[0].deployContract({abi: budgetArtifact.abi,
    bytecode: budgetArtifact.bytecode, args: constructorArgs}))).contractAddress;
  assert.ok(budget);
  const f = {token, budget, validUntil, constructorArgs,
    domain: {name: 'ZeroKey Mate Shared Budget', version: '1', chainId: 31337, verifyingContract: budget}};
  // Deliberately fund MORE than the budget: rejection must not be just insolvency.
  if (options.fund !== false) await tokenCall(f, 'mint', [budget, 20_000_000n]);
  return f;
}
function payment(f, signer = agentA, changes = {}) {
  return {agent: signer.address, token: f.token, recipient: merchantA.address, amount: 2_000_000n,
    nonce: nonce(), expiresAt: f.validUntil, requestHash: keccak256(toHex('local test order')), ...changes};
}
async function signed(f, value, signer = agentA, domain = f.domain) {
  return [value, await signer.signTypedData({domain, types: paymentTypes, primaryType: 'Payment', message: value})];
}
async function rejects(f, args, errorName) {
  await assert.rejects(() => call(f, 'execute', args, wallets[5]), error => {
    assert.ok(error.message.includes(errorName), error.message);
    return true;
  });
}
const send = (f, args, wallet = wallets[5]) => wallet.writeContract({address: f.budget,
  abi: budgetArtifact.abi, functionName: 'execute', args, gas: 700_000n});

async function competingPayments(f) {
  const actions = [payment(f, agentA, {amount: 6_000_000n}),
    payment(f, agentB, {amount: 6_000_000n, recipient: merchantB.address})];
  const args = [await signed(f, actions[0], agentA), await signed(f, actions[1], agentB)];
  // Both proposals individually pass before either is mined.
  for (const action of args) await client.simulateContract({address: f.budget, abi: budgetArtifact.abi,
    functionName: 'execute', args: action, account: relayerA});
  let hashes;
  await client.request({method: 'evm_setAutomine', params: [false]});
  try {
    // Independent relayer transaction nonces; both transactions enter one block.
    hashes = await Promise.all([send(f, args[0], wallets[5]), send(f, args[1], wallets[6])]);
    await client.request({method: 'evm_mine', params: []});
  } finally {
    await client.request({method: 'evm_setAutomine', params: [true]});
  }
  const receipts = await Promise.all(hashes.map(hash => client.waitForTransactionReceipt({hash, timeout: 20_000})));
  assert.equal(receipts[0].blockNumber, receipts[1].blockNumber);
  assert.equal(receipts.filter(value => value.status === 'success').length, 1);
  assert.equal(receipts.filter(value => value.status === 'reverted').length, 1);
  assert.equal(await read(f, 'spent'), 6_000_000n);
  assert.equal(await read(f, 'remainingBudget'), 4_000_000n);
  assert.equal(await balance(f, f.budget), 14_000_000n);
  assert.equal(await balance(f, merchantA.address) + await balance(f, merchantB.address), 6_000_000n);
  const loser = receipts.findIndex(value => value.status === 'reverted');
  await rejects(f, args[loser], 'SharedBudgetExceeded');
  assert.equal(await read(f, 'usedNonces', [actions[loser].agent, actions[loser].nonce]), false);
  return {actions, args, receipts, loser};
}

if (process.argv.includes('--demo')) {
  try {
    await start();
    const f = await fixture();
    const race = await competingPayments(f);
    const pending = await signed(f, payment(f, agentB, {amount: 4_000_000n}), agentB);
    await client.simulateContract({address: f.budget, abi: budgetArtifact.abi,
      functionName: 'execute', args: pending, account: relayerA});
    const revocation = await call(f, 'revokeAll');
    await rejects(f, pending, 'BudgetStopped');
    const stoppedPayment = await receipt(await send(f, pending), 'reverted');
    assert.equal(await read(f, 'spent'), 6_000_000n);
    const withdrawal = await call(f, 'withdraw', [14_000_000n]);
    assert.equal(await balance(f, owner.address), 14_000_000n);
    assert.equal(await balance(f, f.budget), 0n);
    const brief = value => ({transactionHash: value.transactionHash,
      blockNumber: value.blockNumber.toString(), status: value.status});
    const report = {schema: 'zerokey-shared-budget-local-evidence-v1',
      network: 'Fresh loopback Anvil, chain 31337', token: 'LOCAL test double, 6 decimals; NOT USDC',
      actors: 'Two deterministic signers; NOT live AI agents',
      generatedAt: new Date().toISOString(), budgetAddress: f.budget, tokenAddress: f.token,
      deployedCodeHash: keccak256(await client.getBytecode({address: f.budget})),
      initialBalanceUnits: '20000000', sharedLimitUnits: '10000000', perPaymentLimitUnits: '6000000',
      competingPayments: race.receipts.map(brief), spentAfterRaceUnits: '6000000', remainingBudgetUnits: '4000000',
      balanceAfterRaceUnits: '14000000', revocation: brief(revocation),
      preSignedPaymentAfterRevocation: brief(stoppedPayment), withdrawal: brief(withdrawal),
      finalBudgetTokenBalanceUnits: '0', ownerRecoveredUnits: '14000000'};
    const directory = new URL('../../.build/shared-budget-evidence/', import.meta.url);
    fs.mkdirSync(directory, {recursive: true});
    const target = new URL(`${Date.now()}-${randomBytes(4).toString('hex')}.json`, directory);
    fs.writeFileSync(target, JSON.stringify(report, null, 2) + '\n', {flag: 'wx', mode: 0o600});
    console.log('LOCAL EVM DEMO — test token and deterministic signer actors, not a live purchase.');
    console.log('Funded 20; authorized a SHARED budget of 10 and a per-payment maximum of 6.');
    console.log('Two pre-signed payments of 6 mined together: exactly one succeeded, one reverted.');
    console.log('14 remained in the account, but only 4 remained in the authorization.');
    console.log('Owner revoked all agents. An already-signed, otherwise-valid payment of 4 reverted.');
    console.log('Owner recovered the remaining 14. All assertions passed.');
    console.log(`Local receipts and deployed-code hash: ${target.pathname}`);
  } finally { await stop(); }
} else {
  before(start);
  after(stop);

  test('two funded agents compete in one block without exceeding the shared cap', {timeout: 60_000}, async () => {
    await competingPayments(await fixture());
  });
  test('onchain and offchain typed digests agree; payment transfers the exact amount', async () => {
    const f = await fixture(); const p = payment(f); const args = await signed(f, p);
    assert.equal(await read(f, 'paymentDigest', [p]), hashTypedData({domain: f.domain,
      types: paymentTypes, primaryType: 'Payment', message: p}));
    await receipt(await send(f, args));
    assert.equal(await balance(f, merchantA.address), p.amount);
    assert.equal(await read(f, 'spent'), p.amount);
  });
  test('both agents consume one counter; a top-up cannot reset the authorization', async () => {
    const f = await fixture();
    await call(f, 'execute', await signed(f, payment(f, agentA, {amount: 6_000_000n})));
    await call(f, 'execute', await signed(f, payment(f, agentB, {amount: 4_000_000n}), agentB));
    await tokenCall(f, 'mint', [f.budget, 20_000_000n]);
    assert.equal(await read(f, 'spent'), 10_000_000n);
    assert.equal(await balance(f, f.budget), 30_000_000n);
    await rejects(f, await signed(f, payment(f, agentA, {amount: 1n})), 'SharedBudgetExceeded');
  });
  test('replay cannot transfer twice, even with a changed request or another relayer', async () => {
    const f = await fixture(); const p = payment(f); const args = await signed(f, p);
    await call(f, 'execute', args, wallets[6]);
    await rejects(f, args, 'PaymentReplayed');
    await rejects(f, await signed(f, {...p, requestHash: nonce()}), 'PaymentReplayed');
    assert.equal(await read(f, 'spent'), p.amount);
  });
  test('one confirmed owner revocation blocks both previously signed agents', async () => {
    const f = await fixture();
    const actions = [await signed(f, payment(f)), await signed(f, payment(f, agentB), agentB)];
    await assert.rejects(() => call(f, 'revokeAll', [], wallets[7]), /Unauthorized/);
    await call(f, 'revokeAll');
    for (const args of actions) {
      await rejects(f, args, 'BudgetStopped');
      await receipt(await send(f, args), 'reverted');
    }
    await tokenCall(f, 'mint', [f.budget, 1n]);
    assert.equal(await read(f, 'stopped'), true);
    assert.equal(await read(f, 'spent'), 0n);
  });
  test('withdrawal is owner-only and permanently disables spending', async () => {
    const f = await fixture(); const args = await signed(f, payment(f));
    await assert.rejects(() => call(f, 'withdraw', [1n], wallets[7]), /Unauthorized/);
    await call(f, 'withdraw', [20_000_000n]);
    assert.equal(await balance(f, owner.address), 20_000_000n);
    assert.equal(await read(f, 'stopped'), true);
    await rejects(f, args, 'BudgetStopped');
  });
  test('exact payment expiry and policy expiry are enforced', async () => {
    const f = await fixture();
    const expiresAt = (await client.getBlock()).timestamp + 30n;
    const args = await signed(f, payment(f, agentA, {expiresAt}));
    await client.request({method: 'evm_setNextBlockTimestamp', params: [Number(expiresAt)]});
    await client.request({method: 'evm_mine', params: []});
    await rejects(f, args, 'PaymentExpired');
    await rejects(f, await signed(f, payment(f, agentA, {expiresAt: f.validUntil + 1n})), 'PaymentExpired');
    await client.request({method: 'evm_setNextBlockTimestamp', params: [Number(f.validUntil)]});
    await client.request({method: 'evm_mine', params: []});
    await rejects(f, await signed(f, payment(f)), 'PaymentExpired');
  });
  test('recipient, amount, nonce, expiry, agent and request are signature-bound', async () => {
    const f = await fixture(); const p = payment(f); const args = await signed(f, p);
    for (const change of [{recipient: merchantB.address}, {amount: 1n}, {nonce: nonce()},
      {expiresAt: p.expiresAt - 1n}, {agent: agentB.address}, {requestHash: nonce()}]) {
      await rejects(f, [{...p, ...change}, args[1]], 'InvalidSignature');
    }
    await rejects(f, [{...p, token: stranger.address}, args[1]], 'InvalidPayment');
    await rejects(f, [p, '0x1234'], 'InvalidSignature');
  });
  test('chain and budget address prevent signature transplantation', async () => {
    const f = await fixture(); const p = payment(f);
    await rejects(f, await signed(f, p, agentA, {...f.domain, chainId: 1}), 'InvalidSignature');
    await rejects(f, await signed(f, p, agentA, {...f.domain, verifyingContract: stranger.address}), 'InvalidSignature');
  });
  test('unknown agents, unapproved merchants, empty actions and oversized payments fail', async () => {
    const f = await fixture();
    await rejects(f, await signed(f, payment(f, stranger), stranger), 'UnknownAgent');
    await rejects(f, await signed(f, payment(f, agentA, {recipient: stranger.address})), 'RecipientNotAllowed');
    await rejects(f, await signed(f, payment(f, agentA, {amount: 7_000_000n})), 'PerPaymentLimitExceeded');
    for (const change of [{amount: 0n}, {nonce: `0x${'0'.repeat(64)}`}, {requestHash: `0x${'0'.repeat(64)}`}]) {
      await rejects(f, await signed(f, payment(f, agentA, change)), 'InvalidPayment');
    }
  });
  test('failed token transfer rolls back the shared counter AND replay state', async () => {
    const f = await fixture(); const p = payment(f); const args = await signed(f, p);
    await tokenCall(f, 'configure', [true, false]);
    await receipt(await send(f, args), 'reverted');
    assert.equal(await read(f, 'spent'), 0n);
    assert.equal(await read(f, 'usedNonces', [p.agent, p.nonce]), false);
    assert.equal(await balance(f, merchantA.address), 0n);
    await tokenCall(f, 'configure', [false, false]);
    await receipt(await send(f, args));
    assert.equal(await read(f, 'spent'), p.amount);
  });
  test('fee-on-transfer tokens fail closed and roll back balances and accounting', async () => {
    const f = await fixture(); const p = payment(f); const args = await signed(f, p);
    await tokenCall(f, 'configure', [false, true]);
    await rejects(f, args, 'UnsupportedTokenBehavior');
    await receipt(await send(f, args), 'reverted');
    assert.equal(await read(f, 'spent'), 0n);
    assert.equal(await balance(f, f.budget), 20_000_000n);
    assert.equal(await balance(f, merchantA.address), 0n);
    assert.equal(await read(f, 'usedNonces', [p.agent, p.nonce]), false);
  });
  test('insufficient funding does not consume authorization and can be retried after funding', async () => {
    const f = await fixture({fund: false}); const p = payment(f); const args = await signed(f, p);
    await rejects(f, args, 'InsufficientFunds');
    await receipt(await send(f, args), 'reverted');
    assert.equal(await read(f, 'spent'), 0n);
    assert.equal(await read(f, 'usedNonces', [p.agent, p.nonce]), false);
    await tokenCall(f, 'mint', [f.budget, p.amount]);
    await receipt(await send(f, args));
  });
  test('an agent cannot bypass execute using a token allowance', async () => {
    const f = await fixture();
    await assert.rejects(() => client.simulateContract({address: f.token, abi: tokenArtifact.abi,
      functionName: 'transferFrom', args: [f.budget, stranger.address, 1n], account: agentA}), /ERC20InsufficientAllowance/);
    assert.equal(await read(f, 'spent'), 0n);
    assert.equal(await balance(f, f.budget), 20_000_000n);
  });
  test('invalid or duplicate immutable policy terms cannot be deployed', async () => {
    const f = await fixture();
    const variants = [[0, stranger.address], [1, []], [1, [agentA.address, agentA.address]],
      [1, [owner.address]], [2, []], [2, [merchantA.address, merchantA.address]],
      [3, 0n], [4, 0n], [4, 11_000_000n], [5, 0n]];
    for (const [index, value] of variants) {
      const args = [...f.constructorArgs]; args[index] = value;
      // Fixed gas forces a mined constructor revert rather than only estimation.
      const hash = await wallets[0].deployContract({abi: budgetArtifact.abi,
        bytecode: budgetArtifact.bytecode, args, gas: 5_000_000n});
      await receipt(hash, 'reverted');
    }
  });
}
