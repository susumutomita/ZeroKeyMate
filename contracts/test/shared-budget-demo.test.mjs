import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Run the published command, not a second implementation of the budget model.
test('CLI demo executes real local transactions and emits matching evidence', {timeout: 100_000}, async () => {
  const script = fileURLToPath(new URL('./shared-budget.test.mjs', import.meta.url));
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const stdout = await new Promise((resolve, reject) => {
    const grouped = process.platform !== 'win32';
    const child = spawn(process.execPath, [script, '--demo'], {
      cwd: root, detached: grouped, stdio: ['ignore', 'pipe', 'pipe']
    });
    let output = '';
    let errors = '';
    let settled = false;
    function killOwnedProcesses() {
      if (!child.pid) return;
      try {
        // On Linux/macOS, also stop this demo's Anvil if the CLI hangs.
        if (grouped) process.kill(-child.pid, 'SIGKILL');
        else child.kill('SIGKILL');
      } catch (error) { if (error.code !== 'ESRCH') errors += String(error); }
    }
    function finish(error) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) { killOwnedProcesses(); reject(error); }
      else resolve(output);
    }
    const timer = setTimeout(() => finish(new Error('Local budget CLI exceeded 90 seconds.')), 90_000);
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => {
      output += chunk;
      if (output.length > 256_000) finish(new Error('Unexpectedly large CLI output.'));
    });
    child.stderr.on('data', chunk => {
      errors += chunk;
      if (errors.length > 256_000) finish(new Error('Unexpectedly large CLI error output.'));
    });
    child.once('error', finish);
    child.once('close', code => finish(code === 0 ? null : new Error(`CLI failed (${code}): ${errors}\n${output}`)));
  });
  assert.match(stdout, /All assertions passed\./);
  const match = stdout.match(/^Local receipts and deployed-code hash: (.+)$/m);
  assert.ok(match, stdout);
  const evidencePath = path.resolve(match[1]);
  assert.equal(path.dirname(evidencePath), path.join(root, '.build', 'shared-budget-evidence'));
  const report = JSON.parse(fs.readFileSync(evidencePath, 'utf8'));
  assert.equal(report.schema, 'zerokey-shared-budget-local-evidence-v1');
  assert.equal(report.initialBalanceUnits, '20000000');
  assert.equal(report.sharedLimitUnits, '10000000');
  assert.equal(report.balanceAfterRaceUnits, '14000000');
  assert.equal(report.remainingBudgetUnits, '4000000');
  assert.deepEqual(report.competingPayments.map(value => value.status).sort(), ['reverted', 'success']);
  assert.equal(report.competingPayments[0].blockNumber, report.competingPayments[1].blockNumber);
  assert.equal(report.revocation.status, 'success');
  assert.equal(report.preSignedPaymentAfterRevocation.status, 'reverted');
  assert.equal(report.withdrawal.status, 'success');
  assert.equal(report.ownerRecoveredUnits, '14000000');
  assert.equal(report.finalBudgetTokenBalanceUnits, '0');
  assert.match(report.deployedCodeHash, /^0x[0-9a-f]{64}$/);
  console.log(`Verified LOCAL demo evidence: ${JSON.stringify(report)}`);
});
