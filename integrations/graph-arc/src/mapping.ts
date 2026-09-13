import { BigInt } from '@graphprotocol/graph-ts';
import { Transfer } from '../generated/ArcUSDC/USDC';
import { Account, Spend } from '../generated/schema';

export function handleTransfer(event: Transfer): void {
  // Minting does not spend a buyer's budget. Self-transfers still count as
  // outflow; incoming transfers never increase the private spending allowance.
  if (event.params.from.toHexString() == '0x0000000000000000000000000000000000000000') return;
  let account = Account.load(event.params.from);
  if (account == null) {
    account = new Account(event.params.from);
    account.sent = BigInt.zero();
    account.transferCount = BigInt.zero();
  }
  account.sent = account.sent.plus(event.params.value);
  account.transferCount = account.transferCount.plus(BigInt.fromI32(1));
  account.lastUpdatedBlock = event.block.number;
  account.save();

  const spend = new Spend(event.transaction.hash.concatI32(event.logIndex.toI32()));
  spend.payer = event.params.from;
  spend.recipient = event.params.to;
  spend.amount = event.params.value;
  spend.transactionHash = event.transaction.hash;
  spend.logIndex = event.logIndex;
  spend.blockNumber = event.block.number;
  spend.timestamp = event.block.timestamp;
  spend.save();
}
