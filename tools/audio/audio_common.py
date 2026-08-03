#!/usr/bin/env python3
"""Shared mastering helpers for the stage-2 audio pipeline.

Loudness policy (used by BOTH the approved-Sonniss job and the generated SFX):

    gain = min( TARGET_I - measured_I ,  TARGET_TP - measured_TP )

i.e. normalise to -18 LUFS but never let true peak pass -1.5 dBTP. It is a
single linear gain: no compression, no limiter, so the crowd beds keep their
dynamics and the one-shot transients keep their snap. Whichever constraint
binds is recorded per file, so "why is this one -20 LUFS" is always answerable.

(ffmpeg's own two-pass `loudnorm` was tried first and silently fell back to
its dynamic mode on the short cheer files, landing them 1 LU *above* target;
this explicit approach hits the target exactly and is fully transparent.)
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

TARGET_I = -18.0
TARGET_TP = -1.5
RATE = 48000
# EBU R128 gating uses 400 ms blocks — a file shorter than that has no valid
# integrated loudness, so one-shots get padded out to this before measuring.
MIN_MEASURE_S = 0.6


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def probe(path: Path) -> dict:
    p = run(["ffprobe", "-v", "error", "-select_streams", "a:0",
             "-show_entries", "stream=codec_name,sample_rate,channels,bits_per_sample",
             "-show_entries", "format=duration", "-of", "json", str(path)])
    d = json.loads(p.stdout)
    st = d["streams"][0]
    return {"codec": st.get("codec_name"),
            "sample_rate": int(st.get("sample_rate", 0)),
            "channels": int(st.get("channels", 0)),
            "bits": st.get("bits_per_sample"),
            "duration": round(float(d["format"]["duration"]), 3)}


def measure(path: Path, pre_filter: str | None = None) -> dict:
    """Integrated loudness + true peak via ebur128."""
    af = (pre_filter + "," if pre_filter else "") + "ebur128=peak=true:framelog=quiet"
    p = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
             "-map", "0:a:0", "-af", af, "-f", "null", "-"])
    tail = p.stderr[-4000:]
    out: dict = {"I": None, "TP": None, "LRA": None}
    m = re.search(r"I:\s*(-?[\d.]+|-inf)\s*LUFS", tail)
    if m:
        out["I"] = None if "inf" in m.group(1) else float(m.group(1))
    m = re.search(r"LRA:\s*(-?[\d.]+)\s*LU", tail)
    if m:
        out["LRA"] = float(m.group(1))
    tp = re.findall(r"True peak:.*?Peak:\s*(-?[\d.]+|-inf)\s*dBFS", tail, re.S)
    if tp:
        out["TP"] = None if "inf" in tp[-1] else float(tp[-1])
    return out


def envelope(path: Path, frame_ms: int = 10, limit_s: float | None = None,
             pre_filter: str | None = None) -> tuple[list[float], float]:
    """Per-frame RMS level in dB (silence -> -120). Returns (levels, frame_s)."""
    info = probe(path)
    n = max(1, int(info["sample_rate"] * frame_ms / 1000))
    af = (pre_filter + "," if pre_filter else "")
    af += (f"aformat=channel_layouts=mono,asetnsamples={n},"
           "astats=metadata=1:reset=1,"
           "ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-")
    cmd = ["ffmpeg", "-hide_banner", "-nostats"]
    if limit_s:
        cmd += ["-t", str(limit_s)]
    cmd += ["-i", str(path), "-map", "0:a:0", "-af", af, "-f", "null", "-"]
    p = run(cmd)
    vals: list[float] = []
    for line in p.stdout.splitlines():
        if "RMS_level=" in line:
            v = line.split("=", 1)[1].strip()
            vals.append(-120.0 if "inf" in v else float(v))
    return vals, frame_ms / 1000.0


def gain_plan(meas: dict) -> dict:
    """Decide the single linear gain and record which target bound it."""
    I, TP = meas.get("I"), meas.get("TP")
    if I is None or TP is None:
        return {"gain_db": None, "bound_by": "silent", "ok": False}
    need_i = TARGET_I - I
    head_tp = TARGET_TP - TP
    gain = min(need_i, head_tp)
    return {"gain_db": round(gain, 2),
            "bound_by": "loudness" if need_i <= head_tp else "true-peak",
            "ok": True}


TARGET_LRA = 11.0


def loudnorm_measure(path: Path, pre_filter: str | None = None) -> dict:
    """loudnorm pass 1 — analysis over the same chain pass 2 will see."""
    ln = f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}:print_format=json"
    af = (pre_filter + "," if pre_filter else "") + ln
    p = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
             "-map", "0:a:0", "-af", af, "-f", "null", "-"])
    blob = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", p.stderr, re.S)
    if not blob:
        raise RuntimeError(f"loudnorm pass1 failed for {path.name}:\n{p.stderr[-1200:]}")
    return json.loads(blob.group(0))


def loudnorm_chain(m: dict) -> str:
    """loudnorm pass 2. `linear=true` keeps it a transparent single gain when
    the material allows, and falls back to its true-peak limiter only when the
    peaks would otherwise breach the ceiling — which is what high-crest crowd
    recordings need to reach -18 LUFS at all."""
    return (f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}"
            f":measured_I={m['input_i']}:measured_TP={m['input_tp']}"
            f":measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}"
            f":offset={m['target_offset']}:linear=true:print_format=summary")


def master_chain(src: Path, pre_filter: str | None = None) -> dict:
    """Full loudness stage: two-pass loudnorm plus a corrective linear trim.

    loudnorm alone lands short files ~1 LU off target (its gating sees too few
    400 ms blocks), so the result is re-measured and a residual gain folded in.
    The correction is clamped so true peak can never pass the ceiling.
    """
    m = loudnorm_measure(src, pre_filter)
    base = (pre_filter + "," if pre_filter else "") + loudnorm_chain(m)

    tmp = src.parent / f".{src.stem}.probe.wav"
    try:
        p = run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                 "-i", str(src), "-map", "0:a:0", "-af", base,
                 "-ar", str(RATE), "-ac", "2", "-c:a", "pcm_f32le", str(tmp)])
        if p.returncode != 0:
            raise RuntimeError(p.stderr[-800:])
        mid = measure(tmp)
    finally:
        tmp.unlink(missing_ok=True)

    correction = 0.0
    if mid.get("I") is not None and mid.get("TP") is not None:
        want = TARGET_I - mid["I"]
        head = TARGET_TP - mid["TP"]
        correction = round(min(want, head), 2)
        if abs(correction) < 0.1:
            correction = 0.0

    chain = base + (f",volume={correction}dB" if correction else "")
    return {"chain": chain, "after_loudnorm": mid, "correction_db": correction}


def encode_set(src: Path, outdir: Path, name: str, af_chain: str) -> dict:
    """Write the three delivery flavours from one filter chain.

    <name>.wav        16-bit PCM 48k stereo -> ship format (AudioDirector
                      loads .wav via AVAudioPlayer; existing assets are
                      pcm_s16le, so this matches what the app already reads)
    <name>.master.wav 24-bit PCM 48k stereo -> mastering archive
    <name>.m4a        AAC 192k              -> review-page preview
    """
    outdir.mkdir(parents=True, exist_ok=True)
    targets = {
        "ship_wav_16bit": (outdir / f"{name}.wav", ["-c:a", "pcm_s16le"]),
        "master_wav_24bit": (outdir / f"{name}.master.wav", ["-c:a", "pcm_s24le"]),
        "preview_m4a": (outdir / f"{name}.m4a", ["-c:a", "aac", "-b:a", "192k"]),
    }
    for key, (dst, extra) in targets.items():
        p = run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                 "-i", str(src), "-map", "0:a:0", "-vn",
                 "-af", af_chain, "-ar", str(RATE), "-ac", "2",
                 *extra, str(dst)])
        if p.returncode != 0:
            raise RuntimeError(f"encode failed {dst.name}: {p.stderr[-800:]}")
    return {k: str(v[0]) for k, v in targets.items()}
