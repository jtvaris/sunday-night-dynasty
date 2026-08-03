#!/usr/bin/env python3
"""Emit the machine-checkable parts of the LICENSES.md music sections.

Seeds, prompts, durations, loudness and loop measurements for 30+ files are
exactly the kind of thing that rots when transcribed by hand. The prose in
LICENSES.md stays hand-written; these tables are printed from
gen_music/manifest.json + shipped_music.json so they cannot drift from what
was actually generated and shipped.

Usage:  python3 music_licenses_block.py > /tmp/block.md
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RATE = 0.000975   # Replicate Nvidia L40S, $/s — both models run on it


def esc(s: str) -> str:
    return s.replace("|", "\\|")


def main() -> None:
    man = json.loads((ROOT / "gen_music" / "manifest.json").read_text())
    ship = json.loads((ROOT / "shipped_music.json").read_text())
    by_stem = {m["stem"]: m for m in man}

    r2 = [m for m in man if m.get("round") == 2]
    ace = [m for m in r2 if m["kind"] == "menu_theme"]
    sao = [m for m in r2 if m["kind"] == "ambient_loop"]

    gpu_ace = sum(m.get("predict_time") or 0 for m in ace)
    gpu_sao = sum(m.get("predict_time") or 0 for m in sao)

    print("#### Round-2 cost\n")
    print("| Model | Takes | GPU time | Cost @ $0.000975/s |")
    print("|---|---|---|---|")
    print(f"| `lucataco/ace-step` | {len(ace)} | {gpu_ace:.1f} s | ${gpu_ace*RATE:.3f} |")
    print(f"| `stackadoc/stable-audio-open-1.0` | {len(sao)} | {gpu_sao:.1f} s | ${gpu_sao*RATE:.3f} |")
    tot = gpu_ace + gpu_sao
    print(f"| **Total** | **{len(r2)}** | **{tot:.1f} s** | **≈ ${tot*RATE:.2f}** |")

    print("\n#### Round-2 themes — `lucataco/ace-step`\n")
    print("| File | Seed | Requested | Duration | LUFS | Prompt tags |")
    print("|---|---|---|---|---|---|")
    for m in sorted(ace, key=lambda x: x["stem"]):
        req = json.loads(
            (ROOT / "gen_music_raw" / m["style"] / f"{m['stem']}.json").read_text()
        ).get("requested_duration")
        print(f"| `{m['stem']}` | {m['seed']} | {req} s | {m['duration']:.1f} s | "
              f"{m['LUFS']} | {esc(m['prompt'])} |")

    print("\n#### Round-2 loops — `stackadoc/stable-audio-open-1.0`\n")
    print("| File | Seed | Duration | LUFS | Fold (xfade/tail-cut) | Seam | Head−tail | Prompt |")
    print("|---|---|---|---|---|---|---|---|")
    for m in sorted(sao, key=lambda x: x["stem"]):
        lp = m["loop"]
        a = lp["seam_after"]
        print(f"| `{m['stem']}` | {m['seed']} | {m['duration']:.1f} s | {m['LUFS']} | "
              f"{lp['xfade_s']:.1f} / {lp.get('tail_cut_s', 0):.1f} s | "
              f"{a['verdict']} ({a['headroom_db']:+.1f} dB) | "
              f"{a['level_match_db']:+.1f} dB | {esc(m['prompt'])} |")

    print("\n#### All loops — head-vs-tail level after the round-2 fix\n")
    print("| Loop | Round | Baseline fold Δ | Chosen fold | Chosen Δ | Re-pointed |")
    print("|---|---|---|---|---|---|")
    for m in sorted([x for x in man if x["kind"] == "ambient_loop"],
                    key=lambda x: (x.get("round", 1), x["stem"])):
        lp = m["loop"]
        base = lp.get("baseline")
        bd = f"{base['level_match_db']:+.1f} dB" if base else "--"
        print(f"| `{m['stem']}` | r{m.get('round',1)} | {bd} | "
              f"{lp['xfade_s']:.1f} / {lp.get('tail_cut_s',0):.1f} s | "
              f"{lp['seam_after']['level_match_db']:+.1f} dB | "
              f"{'**yes**' if lp.get('repointed') else 'no'} |")

    print("\n#### Shipped music — `dynasty/dynasty/Resources/Audio/Music/`\n")
    total = sum(s["bytes"] for s in ship)
    secs = sum(s["duration"] for s in ship)
    print(f"{len(ship)} files, {secs/60:.1f} min, **{total/1e6:.1f} MB** "
          f"(AAC-LC 160 kbps, 48 kHz stereo).\n")
    print("| Ship name | Context | Source take | Round | Model | Seed | Dur | LUFS | Size |")
    print("|---|---|---|---|---|---|---|---|---|")
    for s in ship:
        short = "ace-step" if "ace-step" in s["model"] else "stable-audio-open"
        print(f"| `{s['name']}.m4a` | {s['context']} | `{s['source_stem']}` | "
              f"r{s['round']} | {short} | {s['seed']} | {s['duration']:.0f} s | "
              f"{s['LUFS']} | {s['bytes']/1e6:.2f} MB |")

    unshipped = sorted({m["stem"] for m in r2}
                       - {s["source_stem"] for s in ship})
    if unshipped:
        print("\n**Generated but not shipped:** "
              + ", ".join(f"`{u}`" for u in unshipped)
              + " — kept in `gen_music/` as candidates.")


if __name__ == "__main__":
    main()
