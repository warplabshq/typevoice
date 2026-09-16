#!/usr/bin/env python3
"""Word error rate over Tools/clips/*.wav with matching *.txt references.

Transcribes each clip through the same FluidAudio CLI the app links against:
    swift run --package-path <FluidAudio checkout> fluidaudiocli transcribe clip.wav --model-version v2
Set FLUIDAUDIO=<path to checkout>. Prints per-clip and aggregate WER.
"""
import glob, os, re, subprocess, sys

FLUID = os.environ.get("FLUIDAUDIO")
if not FLUID:
    sys.exit("set FLUIDAUDIO=/path/to/FluidAudio checkout")

def norm(s):
    s = s.lower()
    s = re.sub(r"[^a-z0-9' ]+", " ", s)
    return s.split()

def wer(ref, hyp):
    d = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        prev, d[0] = d[0], i
        for j, h in enumerate(hyp, 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r != h))
            prev, d[j] = d[j], cur
    return d[len(hyp)] / max(len(ref), 1)

def transcribe(path):
    out = subprocess.run(
        ["swift", "run", "--package-path", FLUID, "-c", "release", "fluidaudiocli",
         "transcribe", path, "--model-version", "v2"],
        capture_output=True, text=True)
    m = re.search(r"Transcription:\s*(.*)", out.stdout)
    return m.group(1).strip() if m else out.stdout.strip().splitlines()[-1]

total_e = total_n = 0
for wav in sorted(glob.glob("Tools/clips/*.wav")):
    txt = wav[:-4] + ".txt"
    if not os.path.exists(txt):
        continue
    ref = norm(open(txt).read())
    hyp = norm(transcribe(wav))
    e = wer(ref, hyp)
    total_e += e * len(ref); total_n += len(ref)
    print(f"{os.path.basename(wav):32s} WER {e*100:5.1f}%")
print(f"{'aggregate':32s} WER {total_e / max(total_n,1) * 100:5.1f}%")
