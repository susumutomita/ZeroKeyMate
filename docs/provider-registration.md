# Register a real specialist

Registration is on Sepolia (11155111); paid requests still settle on the configured Arc/Sepolia MateVault. This command does not deploy a registry, fund a wallet, or claim Graph indexing is complete.

## Prepare and review

Configure a reachable `PROVIDER_PUBLIC_URL` over HTTPS, the public `PROVIDER_REGISTRATION_OWNER` and `PROVIDER_RECIPIENT` addresses, and public name/description/image fields from `.env.example`. No credential belongs in those URLs or metadata. Keep the owner key in `PROVIDER_REGISTRATION_PRIVATE_KEY` and, for a different payout wallet, its key in `PROVIDER_REGISTRATION_RECIPIENT_PRIVATE_KEY`. This CLI currently signs with operator-controlled EOA keys; it does not impersonate a hosted or smart-contract wallet.

Run `npm run register-provider`. This previews only the public owner, recipient, registry and metadata; it neither signs nor submits. Review these concrete values before continuing. The registration owner needs Sepolia test ETH for gas. Do not reuse a production wallet or publish these private configuration files.

## Submit and recover

With an encrypted-journal key (`MATE_JOURNAL_KEY`) configured, run:

```sh
npm run register-provider -- --submit
```

The command verifies Sepolia, registry bytecode and the expected EIP-712 domain, mints an identity, verifies its owner, sets the payout wallet when needed, publishes the registration data URI, and reads back owner/wallet/URI. The wallet signature binds the registry, chain, identity, owner, recipient and a short deadline. Public result evidence is saved under `.build/registrations/provider.json`; it reports indexing as unverified.

Signed transactions are encrypted in `.data/provider-registration/<owner>/registration.sqlite` before broadcast. Repeating the same command recovers the same operations. Keep the journal and original settings after timeouts; changing metadata mid-recovery is refused. Do not remove a journal to resolve an unknown outcome.

Only after a wallet-authorization transaction is confirmed reverted, renew that signature explicitly:

```sh
npm run register-provider -- --submit --renew-wallet-authorization
```

Unknown or successful wallet transactions cannot take that renewal path. A reverted mint or metadata transaction requires operator investigation; the CLI does not silently mint a replacement identity or change an already signed operation. Registry upgrades and external identity transfers may require renewed integration review.

## Verify discovery

Add the returned `11155111:AGENT_ID`, owner, payout recipient and exact HTTPS endpoint to the private `MATE_PROVIDERS_JSON`, together with the service, price and provider bearer. Configure the Graph key/subgraph and the API's normal deployment settings. Start the real specialist with its verifier/model ready, then run:

```sh
npm run check-provider -- 11155111:AGENT_ID
```

This uses Mate's actual discovery path: indexed owner/wallet/endpoint must match the pin, and a live quote must match chain/vault/token/recipient/service/price. Only success is reported ready. Indexing delay, missing metadata, an unavailable model or a mismatched quote stays unavailable. Configuration and local fixture tests do not prove live registration, indexing or payment.

## Protocol references and validation boundary

Reviewed 2026-09-10 against the [ERC-8004 specification](https://eips.ethereum.org/EIPS/eip-8004), the [reference registry at b9e466c](https://github.com/erc-8004/erc-8004-contracts/blob/b9e466c250744a7e06b13dff9d3c2844ed64f825/contracts/IdentityRegistryUpgradeable.sol), and [Agent0's indexed Sepolia configuration at 909a9d4](https://github.com/agent0lab/subgraph/blob/909a9d4518432c641e06fdb731b480fb0e9340dd/subgraph.yaml). The reference registry declares MIT licensing; it is not vendored or added as a dependency. This implementation uses independently authored calls to its public interface.

The inspected indexer supports IPFS and base64 registration data URIs in its [identity mapping](https://github.com/agent0lab/subgraph/blob/909a9d4518432c641e06fdb731b480fb0e9340dd/src/identity-registry.ts). The CLI uses a data URI; it does not assume arbitrary hosted HTTPS metadata is fetched. Confirm the deployed subgraph's behavior through the live check. [The Graph's Agent0 documentation](https://thegraph.com/docs/en/subgraphs/existing-subgraphs/agent0/) describes the discovery schema and API-key setup.

Tests use an explicitly synthetic chain adapter to cover lost-response recovery, stable registration operations, changed-environment refusal, separate-wallet signatures and confirmed-revert renewal. Public testnet registration and Graph/quote acceptance remain unverified until the commands succeed against configured real services.

A read-only public Sepolia RPC check on 2026-09-10 confirmed the configured registry has bytecode and the expected signature domain. No registration transaction was signed or sent during that check; it is not live registration or Graph acceptance.
