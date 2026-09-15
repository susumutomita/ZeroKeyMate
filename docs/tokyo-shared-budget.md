# ZeroKey Mate: many agents, one allowance, one stop

Status: a **local-chain enforcement prototype**, separate from the submitted physical-card beer purchase. This is not an improved ETHOnline submission, a live AI shopping flow, an Arc deployment or a claim of Tokyo eligibility. The submitted README, movie, age circuit and working shop remain unchanged.

## Product decision

Lead with **one allowance shared across independently signing agents**. Do not lead with a companion buying beer, a collection of SDK names or private age verification.

Proposed user: a person delegating small purchases to more than one assistant. Their problem is a combined spending limit: granting each assistant a separate allowance does not automatically create one shared ceiling. This need is a hypothesis to validate, not established demand. The implementation's guarantee is one budget contract, not all of the person's external wallets or accounts.

The demonstration must show that the account has sufficient money and STILL refuses an over-budget payment. Otherwise it demonstrates an empty wallet, not permission enforcement.

### First 30 seconds of the future pitch

> I gave two assistants one shared allowance of ten. Both tried to spend six at the same time. The account held twenty, so lack of funds was not the problem. One payment settled and the other was rejected by the contract. Then I stopped both assistants with one transaction, including an already-signed payment. The rules are enforced where the money moves, not in an AI prompt.

Use this wording only with the relevant recorded evidence. Today's demo uses **deterministic signer actors**, not AI agents. Do not call them autonomous shopping agents until actual agent integrations are recorded.

## Run the actual local EVM demo

Prerequisites: the repository's pinned npm dependencies, Node 22.16+ on 22.x or 24.x, Make, and Anvil (the existing CI uses Foundry v1.3.1). No iPhone, My Number card, private configuration, API key or testnet funding is required.

From the repository root:

```sh
make demo-budget
```

Make installs the lockfile dependencies if absent, compiles the contracts and starts a fresh Anvil on an available loopback port. It deploys a clearly named LOCAL test token and the real `MateSharedBudget` Solidity contract. It uses disposable development signing keys, shuts down its Anvil process, and never reads `.env` or accepts an external RPC. Missing Anvil or a failed assertion is an error, not a skipped or simulated success.

The demo runs two pre-signed payments in the **same mined block** with automatic mining temporarily disabled. Exactly one must succeed. It then confirms owner revocation, mines another pre-signed payment which must revert, and withdraws the remainder to the owner. This proves the deterministic spending boundary, not parallel AI reasoning.

Receipts, deployed bytecode hash, balances and explicit local-only labels are saved to a new `.build/shared-budget-evidence/*.json` file. Those hashes belong to the disposable local chain; they are not Arc explorer evidence.

```sh
make test-budget       # Only the new contract suite
make test-contracts    # Existing and new contract suites
make test             # Existing Swift/API/launcher regressions
```

The existing `CI / enforcement` job invokes `make test-contracts`, which includes the new suite. iPhone/Xcode checks remain separate; passing EVM tests is not a physical-device acceptance result.

## What is enforced

An owner deployment transaction fixes the token, shared lifetime budget, per-payment maximum, allowed agent addresses, allowed merchant addresses and expiration (at most one day). There are at most sixteen agents and sixteen merchants. The account is not upgradeable and has no methods to widen these terms or reset spending. Funding is a separate token transfer.

`execute` accepts an EIP-712 payment signed by an allowed agent. Its domain binds the chain and this specific contract. The signed message explicitly binds agent, token, recipient, amount, nonce, expiry and request hash. The shared spent counter, per-agent replay nonce and exact token transfer update atomically. A transfer failure rolls all of them back. Additional funds do not replenish authorization.

Anyone may relay a valid payment, but cannot change its fields. There is no arbitrary-call function, approval function, owner-signature fallback or ERC-1271 path that bypasses the counter. Owner-only `revokeAll` permanently stops all agent signatures. Owner-only `withdraw` also stops all agents and returns funds only to the owner.

Revocation takes effect **when mined**. It cannot reverse payments already included in a block or guarantee winning a transaction-ordering race. Semantic duplicate orders are not deduplicated across agents: the nonce protects replay per agent; an order service needs its own invoice/idempotency protocol.

## Acceptance evidence, not just a successful path

The tests cover same-block competition with excess funding; exact typed-data hashing and transfer amounts; combined spending by two keys; top-ups not resetting the cap; replay; unauthorized revocation and withdrawal; both agents' previously signed payments after revocation; exact expiry; signature field/domain substitutions; unapproved merchants and agents; per-payment limits; token transfer failure rollback; fee-on-transfer rejection; insufficient funding and retry; direct allowance bypass attempts; and invalid policy construction.

## Boundaries that must stay visible

- Constructor is intentionally limited to chain **31337**. This prototype must not be deployed on Arc or mainnet merely by removing that guard; token compatibility, deployment controls and a security review are separate work.
- The token used by the demo is an explicit test double. The existing Privy/x402/Arc payment is not connected to this shared account. USDC compatibility and gas sponsorship for this new route are not established.
- Budget, recipients, agent addresses and payments are public. There is no ZK privacy claim, attestor, age proof or World ID integration in this path.
- The immutable token must have reviewed, ordinary exact-transfer behavior. Balance checks reject the tested fee behavior; they do not make arbitrary malicious or rebasing tokens safe.
- There is no new native iPhone permission screen or actual multi-agent shopping orchestration in this change. The harness deliberately isolates the enforcement core so another reviewer can verify it without device access.
- This is unaudited research code, not protection suitable for real funds. Test success does not establish mainnet security, product-market fit or prize eligibility.

## Next product gate, before more integrations

Show the shared-limit and stop scenarios to people already using multiple assistants for paid tasks. Ask whether a single shared authorization solves a problem their current wallet controls cannot solve. Compare against existing wallet policy products; do not claim shared counters or spending limits are novel by themselves.

Only after that distinction is demonstrated, connect two real agent adapters and a native owner approval/stop screen to this enforcement path. Record an uncut same-budget flow, including a rejected payment and an already-signed action after confirmed revocation. Choose any future ZK component from a concrete confidentiality need rather than reusing it just because it exists. Preserve the current physical-card proof as an optional, separate capability.
