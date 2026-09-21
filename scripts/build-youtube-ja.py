#!/usr/bin/env python3
"""Build the Japanese YouTube explainer with a local VOICEVOX engine.

Requires Pillow, ffmpeg, ffprobe, and official VOICEVOX on localhost:50021.
Never uploads media. Existing submission media is read-only; exports go to output/.
"""
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import urllib.parse
import urllib.request
import wave

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/youtube-ja"
OUT.mkdir(parents=True, exist_ok=True)
DATA = json.loads((ROOT / "docs/presentation/youtube-ja.json").read_text())
FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"
REGULAR = "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"
BG, INK, GREEN, MUTED = "#f6f4ed", "#173e32", "#2e725c", "#61726a"
BASE = "http://127.0.0.1:50021"


def run(args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)


def request(path, data=None):
    headers = {"Content-Type": "application/json"} if data is not None else {}
    req = urllib.request.Request(BASE + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=120) as response:
        return response.read()


version = json.loads(request("/version"))
speakers = json.loads(request("/speakers"))
speaker = next(s for s in speakers if s["name"] == "ずんだもん")
speaker_id = next(s["id"] for s in speaker["styles"] if s["name"] == "ノーマル")


def synthesize(text):
    assert len(text) <= 140, "Split long narration before synthesis"
    key = hashlib.sha256(f"{version}|{speaker_id}|1.08|{text}".encode()).hexdigest()[:20]
    dest = OUT / f"voice-{key}.wav"
    if not dest.exists():
        query = json.loads(request("/audio_query?" + urllib.parse.urlencode({"text": text, "speaker": speaker_id}), b""))
        query.update(speedScale=1.08, outputSamplingRate=48000, outputStereo=True,
                     prePhonemeLength=0.12, postPhonemeLength=0.20)
        audio = request(f"/synthesis?speaker={speaker_id}", json.dumps(query).encode())
        dest.write_bytes(audio)
    with wave.open(str(dest)) as wav:
        seconds = wav.getnframes() / wav.getframerate()
    return dest, seconds


def split(text):
    sentences = re.findall(r"[^。！？]+[。！？]?", text)
    result = []
    for sentence in sentences:
        if len(sentence) <= 100:
            result.append(sentence)
        else:
            current = ""
            for piece in re.findall(r"[^、]+、?", sentence):
                if current and len(current + piece) > 100:
                    result.append(current)
                    current = ""
                current += piece
            if current:
                result.append(current)
    return result


def wrapped(draw, text, font, maxwidth):
    lines, line = [], ""
    for char in text:
        if char == "\n" or (line and draw.textlength(line + char, font=font) > maxwidth):
            lines.append(line)
            line = "" if char == "\n" else char
        else:
            line += char
    if line:
        lines.append(line)
    return lines


def render(scene, caption, index):
    img = Image.new("RGB", (1920, 1080), BG)
    d = ImageDraw.Draw(img)
    def text(x, y, value, size=40, color=INK, width=1700, regular=False, spacing=14):
        font = ImageFont.truetype(REGULAR if regular else FONT, size)
        lines = wrapped(d, value, font, width)
        for line in lines:
            d.text((x, y), line, font=font, fill=color)
            y += size + spacing
        return y
    text(100, 52, scene["eyebrow"], 29, GREEN)
    d.line((100, 120, 1820, 120), fill="#c9d7cf", width=2)
    width = 1030 if scene.get("image") else 1600
    if scene.get("video"):
        width = 1000
    size = 76
    while any(d.textlength(line, font=ImageFont.truetype(FONT, size)) > width for line in scene["title"].split("\n")):
        size -= 2
    text(100, 182, scene["title"], size, width=width)
    y = 455
    for point in scene["points"]:
        d.ellipse((105, y + 18, 117, y + 30), fill=GREEN)
        y = text(142, y, point, 36, MUTED, width=1000 if scene.get("video") or scene.get("image") else 1600, regular=True) + 26
    if scene.get("image"):
        cover = Image.open(ROOT / scene["image"]).convert("RGB")
        cover.thumbnail((665, 600))
        img.paste(cover, (1160, 245))
    d.rounded_rectangle((80, 862, 1840, 1025), radius=24, fill=INK)
    f = ImageFont.truetype(REGULAR, 40)
    lines = wrapped(d, caption, f, 1650)
    assert len(lines) <= 3, caption
    top = 942 - len(lines) * 49 / 2
    for line in lines:
        d.text(((1920 - d.textlength(line, font=f)) / 2, top), line, font=f, fill="white")
        top += 49
    text(100, 1037, DATA["credit"], 19, MUTED)
    text(1575, 1037, f"{index + 1:02d} / {len(DATA['scenes']):02d}", 19, MUTED)
    dest = OUT / f"frame-{hashlib.sha256((scene['id'] + caption).encode()).hexdigest()[:16]}.png"
    img.save(dest)
    return dest


parts, captions, chapters = [], [], []
elapsed = 0.0
for index, scene in enumerate(DATA["scenes"]):
    chapters.append({"start": elapsed, "title": scene["eyebrow"], "id": scene["id"]})
    if "video" in scene:
        duration = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(ROOT / scene["video"])]))
        entries = []
        for number, cue in enumerate(scene["cues"]):
            end = scene["cues"][number + 1]["at"] if number + 1 < len(scene["cues"]) else duration
            entries.append((cue["text"], end - cue["at"], cue["at"]))
    else:
        entries = [(s, None, None) for line in scene["lines"] for s in split(line)]
    for text, fixed_duration, offset in entries:
        wav, speech_seconds = synthesize(text)
        if fixed_duration is not None and speech_seconds > fixed_duration - 0.05:
            raise ValueError(f"Narration overlaps next demo cue: {text} {speech_seconds:.2f}/{fixed_duration:.2f}")
        duration = fixed_duration or math.ceil((speech_seconds + 0.30) * 30) / 30
        frame = render(scene, text, index)
        output = OUT / f"part-{len(parts):03d}.mp4"
        args = ["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-framerate", "30", "-i", str(frame), "-i", str(wav)]
        if offset is not None:
            args += ["-ss", str(offset), "-i", str(ROOT / scene["video"]), "-filter_complex",
                     "[2:v]crop=640:1080:640:0,scale=440:742,setsar=1[phone];[0:v][phone]overlay=1310:125:eof_action=pass[v]", "-map", "[v]"]
        else:
            args += ["-map", "0:v"]
        args += ["-map", "1:a", "-af", "apad", "-t", str(duration), "-r", "30", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", str(output)]
        run(args)
        parts.append(output)
        captions.append({"start": elapsed, "end": elapsed + speech_seconds, "text": text})
        elapsed += duration
        print(f"{len(parts):02d} {scene['id']}: {elapsed:.1f}s", flush=True)

concat = OUT / "parts.txt"
concat.write_text("".join(f"file '{p.name}'\n" for p in parts))
final = OUT / "ZeroKeyMate-ja-zundamon.mp4"
run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(concat),
     "-map", "0:v", "-map", "0:a", "-c:v", "copy", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
     "-metadata", f"title={DATA['title']}", "-metadata", f"comment={DATA['credit']}; Edited physical testnet footage; future capabilities labeled.", "-movflags", "+faststart", str(final)])


def timestamp(value):
    ms = round(value * 1000)
    return f"{ms//3600000:02d}:{ms//60000%60:02d}:{ms//1000%60:02d},{ms%1000:03d}"


(OUT / "ZeroKeyMate-ja.srt").write_text("\n\n".join(f"{i+1}\n{timestamp(c['start'])} --> {timestamp(c['end'])}\n{c['text']}" for i, c in enumerate(captions)) + "\n")
(OUT / "chapters.json").write_text(json.dumps(chapters, ensure_ascii=False, indent=2))
(OUT / "build-evidence.json").write_text(json.dumps({"voicevox": version, "speaker": speaker_id, "voice_credit": DATA["credit"], "duration_timeline": elapsed,
    "sha256": hashlib.sha256(final.read_bytes()).hexdigest(), "source_sha256": hashlib.sha256((ROOT / "services/shop/public/demo/assets/device-walkthrough.mp4").read_bytes()).hexdigest(),
    "editing": "Existing edited real-device recording retained at original playback speed; Japanese synthesized narration; no original audio; no new device run claimed."}, ensure_ascii=False, indent=2))
print(final, flush=True)
