# Arc age-verified checkout

The beer purchase path targets **Arc Testnet, 5042002** throughout: order
commitment, iPhone EIP-712 signature, government-root age gate, merchant
settlement and receipt recovery. This replaces the unfinished Base Sepolia
checkout. It does not enable mainnet or perform a public deployment.

## Architecture and data

```mermaid
sequenceDiagram
    participant User
    participant Mate as iPhone / local AI and prover
    participant Shop as Workers + D1
    participant Arc as Arc Testnet / two RPC providers
    User->>Mate: Ask for one beer
    Mate->>Shop: Create exact 0.10 USDC order
    Shop-->>Mate: Order, nonce, expiry
    User->>Mate: Tap card and enter signing PIN
    Note over Mate: Authenticate card and generate local age proof
    Mate->>Shop: Order-bound proof (no card fields)
    Shop->>Arc: eth_call to pinned age gate and verifier
    Arc-->>Shop: Matching verification results
    Shop-->>Mate: x402 PAYMENT-REQUIRED
    User->>Mate: Approve this purchase
    Mate->>Shop: Exact signed USDC authorization
    Note over Shop: Reserve order; verify signature; simulate USDC
    Shop->>Arc: Sponsor gas for transferWithAuthorization
    Shop->>Arc: Confirm Transfer and AuthorizationUsed
    Shop-->>Mate: Persisted completed order
    Mate->>Arc: Independently confirm receipt
```

The sponsor key belongs to a new testnet-only wallet, configured only after
explicit approval as a Cloudflare Worker secret. The buyer signs through the iPhone's Privy embedded-wallet SDK; the merchant
does not receive the buyer key. Privy wallet authentication/signing is a separate
integration and is not claimed to work wholly offline. Neither the local model nor the shop receives the card PIN, certificate,
signature, birth date, name or address. Public proof inputs and payment metadata
are visible to the RPC providers. Certificate revocation remains unchecked; this
is an experimental narrow JPKI profile, not a completed eKYC service.

## Public-source review, 2026-09-13

- [Arc network settings](https://docs.arc.io/arc/references/connect-to-arc):
  chain 5042002, primary `rpc.testnet.arc.io`, separate dRPC endpoint
  `rpc.drpc.testnet.arc.io`, explorer `testnet.arcscan.app`.
- [Arc contract addresses](https://docs.arc.io/arc/references/contract-addresses)
  and [stablecoin model](https://docs.arc.io/arc/concepts/stablecoin-native-model):
  native USDC uses 18 decimals; the same balance's ERC-20 interface at
  `0x3600000000000000000000000000000000000000` uses six.
- [EVM differences](https://docs.arc.io/arc/references/evm-differences): current
  Arc targets Osaka, has deterministic finality, and rejects fees below its
  20-gwei minimum. The two-provider, two-block receipt check is retained.
- [USDC events](https://docs.arc.io/arc/references/usdc-system-events): the
  native system-emitter event is distinct from the six-decimal token event.
  The checkout filters the official ERC-20 emitter and authorization nonce.
- [x402 network support](https://docs.x402.org/core-concepts/network-and-token-support):
  protocol support for an EVM network does not supply a working facilitator.
  The live `x402.org/facilitator/supported` response did not include Arc.
- [Circle's Gateway example](https://www.circle.com/blog/turn-your-api-into-a-storefront-for-agents)
  uses Gateway balances and later settlement/withdrawal. It is not a drop-in
  replacement for a direct USDC authorization and receipt.
- [ETHOnline Arc prizes](https://ethglobal.com/events/ethonline2026/prizes):
  a functional frontend/backend, architecture diagram, video/presentation,
  documentation and repository are expected. The Agentic Economy category
  calls for Circle Agent Stack use. A separate Continuity category requires
  Continuity registration. Portions of the awards have a September 30 mainnet
  condition; this code and current authorization remain testnet-only.

A separate ChatGPT research session was collected and checked against these
sources. Its claim that current Arc requires Paris/no PUSH0 contradicted the
current Arc documentation and the actual Cancun verifier RPC test. Its
Continuity requirement conflated separate categories. Its suggested Arcon
facilitator URL did not resolve in a direct network check. None of those claims
was adopted. Public wallet/API credentials were not used for research.

## Observed acceptance and remaining boundary

The actual native prover, direct EVM verifier, production settlement adapter,
signed x402 authorization, persisted completion and duplicate-submit recovery
passed on isolated Anvil with fresh synthetic card and wallet keys. Standard
Anvil uses a synthetic ERC-20 and does not model Arc's native-USDC semantics.

Both public Arc RPC endpoints accepted a real synthetic proof using the exact
Cancun verifier runtime supplied as an ephemeral `eth_call` code override;
changing a public input was rejected. Both returned the expected `USDC` / `2`
EIP-712 domain separator and supported finalized-block reads. This is **not a
deployment or public payment**. No real card data or private key was sent.

Both endpoints estimated 1,325,921 gas for the verifier and 331,202 for the gate.
At the reviewed 25-gwei ceiling this is 0.041428075 native test USDC before any
gas-limit margin. Estimates may change. Public deployment still needs approval
of a dedicated deployer and total budget, plus receipt/code checks afterwards.
Merchant settlement separately caps each submission at 0.00375 test USDC gas.

The reviewed Arc package SHA-256 is
`b525f26df035c15670ba891fbdea8121691400a8375bdb498e64c82179712d81`.
Compared with the previous package, only the gate, chain ID and gate source hash
change. The compiler, verifier and original mobile proving parameters match.
Fresh export from the pinned verifier key reproduced this whole-package digest.

Remaining: authorized public contract deployment, dedicated sponsor secret and
funding, Cloudflare publishing, configured physical iPhone installation, actual
card touch and full card-to-USDC acceptance. A meaningful Circle Agent Stack
integration into this checkout is also outstanding for that specific category;
the existing separate API attestor adapter does not satisfy it by itself.
