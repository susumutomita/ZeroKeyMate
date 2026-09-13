# Submission film: human narration and editing notes

Final export: **3:27.38**, H.264/AAC, 1920×1080 at 30 fps, with the creator's recorded narration and 50 English captions. It uses the first **50 seconds** of the supplied **58.5-second edited demo** at its original speed. Use slides 1–2, the real clip in place of slide 3, then slides 4–9. Slides 10–11 are for questions and the downloadable deck. The main video gives about two minutes to **how it works and the technology stack**.

The recording combines successful takes. Introduce it as edited footage; do not imply that it is one continuous order. The submitted film and public walkthrough are committed; the untouched original file and private editing workspace stay outside version control. The 12.0-second figure is the first documented physical-card proof-processing observation, not a timing benchmark or a claim that every take took the same time.

Open the [slides](presentation/index.html) and the [large-text reading guide](presentation/narration.html). The guide has no AI speech or audio upload. It shows one short paragraph at a time; read it in your own voice. Record a sentence or section at a time on the Mac, leave a short pause, and record a correction when needed. Keep the best original human take of each sentence. Ordinary cuts and level adjustment can preserve intelligibility without generating replacement speech. Do not accelerate narration or proving footage to fit the limit.

## Read in your own voice

The English below is the recording script; timestamps are the original rehearsal plan. In the final edit, the creator's spoken headings were removed and pauses were aligned to the real device footage. Final chapters start at 0:00, 0:13.8, 0:24.4 (device footage), 1:14.4 (local agent), 1:36.45 (local ZK), 2:08.3 (privacy), 2:24.6 (payment), 2:50.75 (stack) and 3:08.85 (close). The final soundtrack uses only the creator's recorded narration; noisy device audio is omitted. Section titles, timestamps and Japanese hints are not part of the final voiceover.

### 01 · Introduction · 0:00–0:15

Visual: Slide 1.

This is ZeroKey Mate.
It turns my iPhone into a companion.
I can ask it for a beer, prove my age privately, and pay on Arc.

Reading hint: 最初はゆっくり。Mate は「メイト」、Arc は「アーク」。

### 02 · The problem · 0:15–0:28

Visual: Slide 2.

The shop only needs to know that I am twenty or older.
It does not need my name, address, or full date of birth.

Reading hint: twenty or older は「トゥエンティ・オア・オウルダー」。

### 03 · Recorded demo · 0:28–1:27

Visual: Actual edited demo · 58.5 seconds.

Here is the real app.
These are edited takes from the physical device.

I ask Mate to buy a beer.
I enter the card password privately, then tap my card.
The phone creates the age proof here.

After the store verifies it, I approve this exact payment.
The purchase completes on Arc Testnet.
I can open the receipt in the explorer.

This uses test funds. No real beer is delivered.

Reading hint: 映像に合わせて読む。Mate が話す場面は一息待つ。カードのパスワードは読まない。

### 04 · How it works: local agent · 1:27–1:52

Visual: Slide 4.

How does it work?
Speech recognition and the language model run on the iPhone.
Apple Foundation Models turns my request into a small, structured plan.
Mate checks the item, shop, and amount.
The model cannot access my card data or sign a payment.

Reading hint: structured plan は「ストラクチャード・プラン」。難しければ一文ずつ録音する。

### 05 · How it works: local ZK · 1:52–2:28

Visual: Slide 5.

The proof is the key part.
Our Noir circuit checks the government signature, the card signature for this order, and that I am at least twenty.
It also checks the time limits.

ProveKit, from World Foundation, runs the prover on the iPhone.
The private card data becomes an age proof for this order.
We use My Number card identity here. World ID login is not connected.

Reading hint: Noir は「ノワール」、ProveKit は「プルーヴ・キット」、prover は「プルーヴァー」。ここは一文ずつ。

### 06 · How it works: privacy · 2:28–2:46

Visual: Slide 6.

My birth date and card data stay on the phone.
The shop receives the proof and public order inputs.
Payment addresses are still public.
The privacy boundary is specific and verifiable.

Reading hint: birth date は「バース・デイト」。verifiable は「ヴェリファイアブル」。

### 07 · How it works: payment · 2:46–3:15

Visual: Slide 7.

The store verifies the proof using our Age Gate contract on Arc.
Then Privy signs the exact payment I approve.
x402 carries that payment to the store, which pays the network fee.
We check the actual receipt before showing success.
Age verification and the token transfer are separate steps.

Reading hint: Privy は「プリヴィ」、x402 は「エックス・フォー・オー・トゥー」。receipt は「リシート」。

### 08 · Technology stack · 3:15–3:33

Visual: Slide 8.

Each layer has a clear job.
Apple powers the companion.
Noir and ProveKit handle the private proof.
Cloudflare runs the store and order recovery.
Privy, x402, and Arc complete the payment.

Reading hint: 4つの担当を順番に読む。略語を急いで全部説明しなくてよい。

### 09 · Result and close · 3:33–3:52

Visual: Slide 9.

One physical-card run showed twelve seconds of local proof processing.
We completed real test payments on Arc.
This is still an experimental testnet build.
Your companion. Your rules.
That is ZeroKey Mate.

Reading hint: 最後の2行は少し間を置く。12秒は実測1回の値で一般的な速度保証ではない。

## Pronunciation help

| Term | Reading aid | Meaning in this demo |
| --- | --- | --- |
| ZeroKey Mate | ゼロ・キー・メイト | The iPhone companion |
| on-device | オン・ディヴァイス | Runs on the phone |
| Noir | ノワール | Language of the age circuit |
| ProveKit | プルーヴ・キット | World Foundation's proving toolkit |
| zero-knowledge proof | ズィーロウ・ナリッジ・プルーフ | Proves the condition without revealing the private input |
| JPKI | ジェイ・ピー・ケイ・アイ | Japanese public identity infrastructure; use “My Number card” in the spoken script |
| Privy | プリヴィ | Embedded buyer wallet |
| x402 | エックス・フォー・オー・トゥー | Payment protocol |
| Arc | アーク | Settlement network |
| USDC | ユー・エス・ディー・シー | Token used for the test purchase |
| receipt | リシート | Confirmed payment record |

These are reading aids, not a requirement to erase a Japanese accent. Short phrases, steady volume and subtitles matter more than a native accent. Hard pauses are marked by separate lines in the reading guide. Do not clone the speaker's voice or regenerate pronunciation with AI for the submitted narration.

## What the diagrams establish

1. **Local agent:** on-device Speech → Foundation Models structured proposal → deterministic Mate workflow. Card fields and signing interfaces are never exposed to the model. The supported flow is one configured store and item.
2. **Local ZK:** authenticated JPKI certificate + card signature over the order and nonce are private witness inputs. The Noir circuit checks the trusted root, RSA signatures, age threshold, certificate validity and order expiry. ProveKit generates the proof on the physical iPhone. Self-entered age is not accepted as identity evidence.
3. **Privacy boundary:** private card inputs stay local; the proof, public order inputs, wallet authentication and payment information use network services. Payments remain linkable.
4. **Execution:** the Worker requires agreement from both Arc RPCs on the Age Gate contract call. After exact user approval, the Privy/x402 payment settles and receipt validation checks the actual transfer. Verification is not atomically part of the token transaction and this is not a permission validator.

See the [claim-to-code table](presentation/README.md) for precise evidence, trust assumptions and the status appendix. Use “ProveKit from World Foundation”; do not claim World ID authentication. The local prover uses a pinned experimental Groth16 branch with a single-party setup, and certificate revocation is not checked.

## Export and official format

The [official guide](https://ethglobal.com/events/ethonline2026/info/details), checked September 13, requires 2–4 minutes, at least 720p, human narration and no sped-up footage. It disallows AI/TTS voiceover and filming the submission with a mobile phone. Editing out waiting is allowed. The supplied physical-stand footage was filmed with another phone; no official hardware-shot exception has been confirmed. Keep that format question separate from the working purchase evidence. A Mac/webcam stand shot plus a direct screen capture follows the proposed replacement workflow; do not invent an organizer exemption.

Export H.264/AAC at 1920×1080. Play the whole final file, check cuts and audio, and inspect for passwords, card details, login codes or unrelated personal information. Keep the real timer at normal speed. Put the final tested video URL into [submission.md](submission.md), verify playback without uploader credentials, then submit and reload the Hacker Dashboard receipt. Slides and an edited visual clip without human narration are not a completed submission.
