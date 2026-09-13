# Arc purchase-history index

This builds a real The Graph Subgraph for the Arc Testnet USDC token's
six-decimal `Transfer` events. It is not deployed or connected to the iPhone
yet and is not evidence that the Graph prize requirement is satisfied.
No endpoint, account, deploy credential or API key is fabricated or bundled.

```sh
cd integrations/graph-arc
npm ci --ignore-scripts
npm test
npm run build
```

`Account.sent` records gross outgoing token units since block **61850901**,
the public age-verifier deployment. It includes transfers made by other
applications. Minting is excluded; incoming funds do not undo spending and
self-transfers still count. This does not cover native-USDC gas or the
wallet's earlier history. `Spend` records do not prove merchant fulfillment.

The intended decision is an explicitly started private spending period:
the phone records a fresh confirmed `sent` baseline when the user sets an
allowance, then obtains subsequent totals from this deployment. The local
agent can propose deferring a 0.10 purchase when only 0.05 remains. The
private limit remains on the phone. This is application-level accounting,
not an on-chain cumulative-budget guarantee or the existing age proof.

Before enabling that flow, implement and validate all of these boundaries:

- Pin the actual Studio deployment ID, HTTPS query endpoint and start block.
- Reject indexing errors, changed deployments, missing/stale coverage and
  decreasing totals. A missing account means zero only inside known coverage.
- Match the query's block hash against both fixed Arc RPCs. Account for
  outgoing transfers since the indexed block and pending local authorizations;
  an index can lag and another application can spend concurrently.
- Give the model only the validated remaining amount and proposed price;
  deterministic checks must also reject an over-budget order.
- Show actual live query evidence and a changed purchase decision. Building
  this mapping, querying fixtures or printing history is insufficient.

Deployment requires the entrant's [Studio wallet connection and a deployment
credential](https://thegraph.com/docs/en/subgraphs/quick-start/). Do not read
existing wallet keys or Graph credentials. Prepare the project in Studio,
then separately authorize its specific credential storage/use. A free Studio
test endpoint is sufficient for development; publishing to the decentralized
network is a separate on-chain action with its own authorization.

Sources: [Graph Arc network identifier](https://thegraph.com/docs/en/supported-networks/arc-testnet/),
[Graph mappings](https://thegraph.com/docs/en/subgraphs/developing/creating/assemblyscript-mappings/),
[Arc USDC event emitters](https://docs.arc.io/arc/references/usdc-system-events).
The original mapping uses `@graphprotocol/graph-cli` 0.98.1 and `graph-ts`
0.38.2 from the public [graph-tooling repository](https://github.com/graphprotocol/graph-tooling).
The repository's [MIT license](https://github.com/graphprotocol/graph-tooling/blob/main/LICENSE-MIT)
was reviewed (Graph CLI also offers Apache-2.0). These are development tools,
not an iPhone binary dependency. Preserve dependency notices if redistributing.

The initially resolved CLI tree had 16 audit findings. Transitive versions
are fixed through explicit overrides; Jayson 4.1.3 keeps the CLI's JSON-RPC
client interface without the affected streaming parser. Gluegun's CommonJS
archive call is bridged to the MIT-licensed maintained
[`@xhmikosr/decompress` 11.1.4](https://github.com/XhmikosR/decompress).
The adapter test extracts a synthetic ordinary archive and rejects writes
outside its extraction directory. `npm audit` reports zero findings after
these changes, and the compiled mapping's SHA-256 is unchanged:
`9139950df63388f5e199af5f64043afd8fc71614b8ea41ab8f0982acefd100df`.
No credential was supplied and no deployment command was run.
