# Resume external-request setup

Open **Controls → Set up external requests**, or the same action in Settings. Local conversation and **Try private rules on this device** remain usable independently.

The setup screen restores pending state before selecting a step. A pending execution or grant takes priority over new setup. Otherwise it validates the configured deployment and RPC network, restores the Privy session and wallet roles, refreshes the account and mandate, and then offers the next action:

1. Configure the connection and public Privy identifiers.
2. Sign in to the existing wallet account.
3. Prepare owner/Mate wallet roles if missing.
4. Check balances and add test funds when the execution account is empty.
5. Review the permitted services, budget and expiry.
6. Review an external translation request.

Each action opens an existing screen. Login, deposit approval, deposit, mandate approval and disclosure remain separate user actions. No payment, registration or microphone/camera start is triggered by advancing setup. Use Back to return from a detail screen, or **Do this later** to return to the face.

A checkpoint scoped to the connection is stored only to offer Resume. The stage itself is recomputed from restored and freshly checked state, so restart does not repeat a successful registration or trust an earlier balance. Changed connections invalidate account observations. Failed checks retain the existing connection and show the failure.

Validation: core state transitions cover restoration, pending-operation priority, missing account observations, drained balance and missing/expired mandate. A Simulator UI test opens connection setup, returns, defers, and resumes while camera remains off. Live login, funding, phone HTTPS and a real order remain acceptance work under #8/#16/#17.

Runtime pairing uses a one-time 10-minute code and a one-hour/500-request session. Same-environment renewal preserves pending operations. Failed validation keeps the previous saved configuration. See the README pairing instructions.
