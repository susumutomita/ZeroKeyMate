# Physical-device acceptance

Not executed by CI. Record the actual iPhone model, iOS version, stand model/firmware, commit SHA and result for each check. Do not mark these complete without the hardware.

1. Launch on a physical iPhone without a stand. Eyes are closed and camera is OFF. No camera prompt occurs until Start; no microphone prompt occurs at all.
2. Tap Start and allow camera access. Eyes open and blink; the iOS camera indicator is visible. The app states camera ON. No microphone indicator appears.
3. Tap Stop. The app displays stopping until AVCaptureSession stops, then OFF. The camera indicator disappears. Repeat rapidly, including stopping while authorization/startup is pending; capture must not restart from a late completion.
4. Deny camera access on a fresh install. Explain the denial; do not animate success. Allow access in Settings and retry explicitly.
5. Pair the Belkin stand using its normal procedure, attach the phone, and enable its tracking button. The app reports a real connection. Start the front camera and verify the stand follows the user in portrait and landscape. Merely docking must not start capture.
6. Disable the stand's tracking button. The app reports no enabled tracking. Camera and tracking are separate states: the camera remains on until Stop or lifecycle shutdown.
7. Detach a connected phone while capturing. Capture stops. Reattach: it stays stopped until Start.
8. Background/lock while capturing and return. Capture must not restart automatically. Test a background transition while the camera-permission request is pending as well.
9. Trigger an interruption (another camera use or call) and verify capture does not resume without Start. Check the explanatory message.
10. Inspect network traffic for the app and confirm no frame/audio upload or third-party requests. No wallet, ENS, ZK proof or payment success may be shown in this slice.

The simulator is useful for layout, denial/error handling and initial face display only. It does not validate the physical stand connection, camera framing, motion, or device power use. No identity-card reading or signing code is present.
