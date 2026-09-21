# Optional Circle CLI

This lockfile installs an external proof-attestation CLI. The deployed iPhone shop
uses its own x402 payment path and does not depend on this CLI.

```sh
npm ci --ignore-scripts --prefix config/circle-cli
npm test --prefix config/circle-cli
npm audit --audit-level=moderate --prefix config/circle-cli
```

The tests require Node 24+ and use a temporary, isolated CLI profile. Node's
permission model prevents the help subprocess from reading wallet configuration
elsewhere or using the network. Compatibility RPC/WebSocket tests use loopback
fixtures only. No wallet authentication or signing is performed.

Security overrides are documented in [SOURCES](../../docs/SOURCES.md). Recheck
the compatibility suite when removing an override after an upstream update.
Low-severity elliptic findings inherited through ethers 5 remain; the moderate
audit threshold is explicit and does not mean the dependency tree is risk-free.
