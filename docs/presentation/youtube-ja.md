# Japanese YouTube explainer

This is a separate Japanese explainer with **VOICEVOX:ずんだもん** narration. It does not replace the human-narrated ETHOnline submission.

- Script: [youtube-ja.json](youtube-ja.json)
- Renderer: [build-youtube-ja.py](../../scripts/build-youtube-ja.py)
- Export: `output/youtube-ja/ZeroKeyMate-ja-zundamon.mp4`
- Captions: `output/youtube-ja/ZeroKeyMate-ja.srt`
- Reproducibility evidence: `output/youtube-ja/build-evidence.json`
- Release scope and trust boundaries: [release direction](../release-direction-2026-09-15.md)

The rendered video was uploaded to YouTube on September 15 as video `deIP60_RYoM`. Japanese SRT captions, chapter timestamps, the existing cover, VOICEVOX credit and synthesized-content disclosure were saved. YouTube reported no copyright issues at upload time; this is not a guarantee against later claims. The upload was saved privately pending the creator's publication confirmation.

The September 15 export is 264.23 seconds, 1920×1080 H.264 with 48 kHz AAC. It uses VOICEVOX Engine 0.25.2, Zundamon normal (speaker 3), Japanese explanation graphics, and the existing edited physical-device walkthrough at its original speed. The original recording's audio is not mixed into this version. The ten chapter frames, subtitle layout, full-file decoding, audio peak (-1.5 dBFS) and credit were checked; this does not claim human listening acceptance or a new device purchase.

Future third-party x402, MynaWallet and mobile My Number card connections are explicitly labeled unimplemented. Twelve seconds is one observation of local proof processing, not a benchmark. The experimental Groth16 backend, testnet money and separate age/payment verification are disclosed.

## Generate locally

On macOS, install Pillow, FFmpeg and FFprobe. Use the official VOICEVOX Engine with port 50021 bound only to localhost:

```sh
docker run --rm -p 127.0.0.1:50021:50021 voicevox/voicevox_engine:cpu-latest
python3 scripts/build-youtube-ja.py
```

The script checks the running engine's version and speaker list. Speech files are cached by text, version, voice and speed. The renderer uses the macOS Hiragino fonts and writes generated assets to the ignored `output/` directory. It makes requests only to the local engine and does not upload files. Running against a different engine version can change pronunciation and timing; the demo cue overlap guard must still pass.

## Credits

音声：VOICEVOX:ずんだもん

- [VOICEVOX terms](https://voicevox.hiroshiba.jp/term/)
- [Zundamon audio terms](https://zunko.jp/con_ongen_kiyaku.html)
- The cover is the project's previously generated illustration; [artwork prompts](artwork-prompts.md).
- The edited device recording is the creator-supplied footage already used in the submission. No new claims of an uninterrupted recording or automated payment approval are added.
