# Experimental bounded purchase account

`MatePurchaseAccount` and its factory are an opt-in contract experiment. They are not deployed, funded or connected to the native beer checkout in v0.3.0. The demonstrated purchase still requires explicit approval through the existing Privy wallet.

An owner signs an EIP-712 permission containing the agent, merchant, maximum purchase count, expiry and salt. The factory creates and initializes an ERC-1167 account atomically. Each payment is fixed at 100,000 token units (0.10 USDC); at most 100 slots can be authorized and a permission lasts at most one day. The token address, chain and account are bound into the transfer digest. Only Arc Testnet and local Anvil are accepted at deployment.

The account accepts only exact EIP-3009 transfer signatures from its assigned agent. A slot has a deterministic nonce; the configured token must enforce nonce consumption atomically, so topping up an account cannot reset its spending cap. A short-lived owner signature can revoke or withdraw only to the owner; withdrawal also revokes future purchases.

## Validation and trust

Local contract tests exercise payment caps, replay and top-ups, tampered authorization fields, initialization, factory/account/chain domain binding, admin replay and expiry, malformed ABI data, revocation and insufficient-funds rollback. The fixture is a local test token, not live Arc USDC. It follows the signature-check-before-nonce-consumption ordering in [Circle's public EIP-3009 implementation](https://github.com/circlefin/stablecoin-evm/blob/master/contracts/v2/EIP3009.sol).

This is not a security audit. Live USDC compatibility, shop bytes-signature handling, durable nonce reservation, explicit iPhone delegation UX and physical-device acceptance remain required before enabling it. The account does not verify age: age verification remains the separate order-bound shop protocol. No automatic payment capability is enabled by merging this source.
