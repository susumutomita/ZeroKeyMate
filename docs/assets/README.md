# Screenshot provenance

These PNGs are unmodified screenshots exported from this repository's XCTest result bundle. They show the real app UI in Japanese, without injected wallets, model replies, proofs or payments.

| Asset | XCTest attachment | Device/runtime |
| --- | --- | --- |
| [home-simulator.png](home-simulator.png) | `01-home-portrait`, UUID `864DD995-F1A9-46DB-98FE-DB198B1CB4CE` | iPhone 17 Pro, iOS Simulator 26.2 |
| [rest-simulator.png](rest-simulator.png) | `02-resting`, UUID `4CC7F4C8-58AB-4972-9FC1-782907599862` | iPhone 17 Pro, iOS Simulator 26.2 |
| [conversation-simulator.png](conversation-simulator.png) | `03-conversation-empty`, UUID `9D272A44-EAEA-4620-A29B-6BDB5CE71726` | iPhone 17 Pro, iOS Simulator 26.2 |
| [settings-simulator.png](settings-simulator.png) | `04-settings`, UUID `35ABCA6C-7959-47D5-BD3B-C32835E64C0F` | iPhone 17 Pro, iOS Simulator 26.2 |

Source: [CI run 34072016837](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34072016837), commit [`5bbe0f6`](https://github.com/susumutomita/ZeroKeyMate/commit/5bbe0f6). Five tests passed and two native proof tests were explicitly skipped in the source-only build. All three UI tests passed. See the [validation record](../validation.md).

Artifact: `baseline-native-acceptance`, ID `10000887957`, bundle `acceptance-20260907T011042Z.xcresult`. Downloaded ZIP SHA-256: `dfc95d4f6dbdc775673e58d92775db246d37789777c25571edb938a3ae4fbd74`.

The images demonstrate presentation and the tested home-to-Rest UI transition. They do not establish physical camera/microphone state, Foundation Models availability, DockKit tracking, native proof generation or a live payment. No synthetic screenshots, generated product imagery or altered result text are used.
