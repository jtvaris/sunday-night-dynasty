#!/usr/bin/env python3
"""Listen page for the gen_nfl_menu round.

Same job as build_review_music_v2.py does for rounds 1-3: put every take of a
round on one page with a player and its measurements, because the ear is the
gate and the metrics are only there to explain what the ear hears. The two
menu themes already in the app are embedded at the top as a reference — the
question for each candidate is not "is this good" in the abstract, it is "is
this better than what is on the menu screen right now".

Paths are relative, so the page only works from inside tools/audio/.

    python3 build_review_nfl_menu.py && open review_nfl_menu.html
"""

from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "gen_nfl_menu"
PAGE = ROOT / "review_nfl_menu.html"
SHIPPED_REL = "../../dynasty/dynasty/Resources/Audio/Music"

LANES = {
    "orchestral": "Pure orchestral — brass, strings, percussion, no synths",
    "hybrid": "Brass + synth hybrid — fanfare over a modern synth floor",
    "slowburn": "Slow burn — quiet statement first, fanfare arrives late",
    "march": "Uptempo march — drumline forward, quickest pulse",
}

CSS = """
:root { color-scheme: dark; }
body { background:#0f1216; color:#e8eaed; font:14px/1.5 -apple-system,system-ui,sans-serif;
       margin:0; padding:32px; }
h1 { font-size:22px; margin:0 0 4px; }
h2 { font-size:15px; margin:32px 0 10px; color:#9db4d0; font-weight:600;
     border-bottom:1px solid #253040; padding-bottom:6px; }
.sub { color:#8b97a6; margin:0 0 24px; max-width:70ch; }
.card { background:#161b22; border:1px solid #253040; border-radius:10px;
        padding:14px 16px; margin:0 0 12px; }
.card.base { border-color:#3d4f2f; background:#141a14; }
.top { display:flex; align-items:baseline; gap:12px; flex-wrap:wrap; }
.stem { font-weight:600; font-size:15px; }
.meta { color:#7d8794; font-size:12px; }
audio { width:100%; margin:10px 0 8px; }
.m { display:flex; flex-wrap:wrap; gap:6px; margin-top:6px; }
.m span { background:#1d2530; border:1px solid #2b3646; border-radius:5px;
          padding:2px 8px; font-size:12px; color:#b6c2d0; }
.m span b { color:#e8eaed; font-weight:600; }
.warn { border-color:#5a4520 !important; background:#241d10 !important; color:#e8c98a !important; }
.good { border-color:#2f5233 !important; background:#13210f !important; color:#a8d99a !important; }
.prompt { color:#6f7b89; font-size:12px; margin-top:8px; font-family:ui-monospace,monospace;
          word-break:break-word; }
"""


def chip(label: str, val, fmt="{}", cls="") -> str:
    return f'<span class="{cls}">{label} <b>{fmt.format(val)}</b></span>'


def metrics(r: dict) -> str:
    peak = r.get("peak_pos") or 0
    build = r.get("build_db") or 0
    intro = r.get("intro_vs_body_db") or 0
    out = [
        chip("len", r.get("actual_s", 0), "{:.0f}s"),
        chip("peak@", peak, "{:.0%}", "good" if peak > 0.45 else "warn"),
        chip("build", build, "{:+.1f}dB", "good" if build > 0 else "warn"),
        chip("arc", r.get("arc_db") or 0, "{:.1f}dB"),
        chip("intro", intro, "{:+.1f}dB", "good" if intro < -1 else "warn"),
        chip("BPM", r.get("bpm_octave_fit") or 0, "{:.0f}"),
        chip("want", r.get("bpm_want") or 0, "{:.0f}"),
        chip("onsets", r.get("onsets_per_min") or 0, "{:.0f}/min"),
        chip("mid", r.get("band_mid_pct") or 0, "{:.0f}%",
             "good" if (r.get("band_mid_pct") or 0) >= 35 else "warn"),
        chip("low", r.get("band_low_pct") or 0, "{:.0f}%",
             "warn" if (r.get("band_low_pct") or 0) >= 70 else ""),
        chip("high", r.get("band_high_pct") or 0, "{:.1f}%"),
        chip("LUFS", r.get("lufs") or 0, "{:.1f}"),
    ]
    dead = (r.get("head_dead_s") or 0) + (r.get("tail_dead_s") or 0)
    if dead > 0.5:
        out.append(chip("dead air", dead, "{:.2f}s", "warn"))
        out.append(chip("trim", tuple(r.get("trim", [])), "{}"))
    return '<div class="m">' + "".join(out) + "</div>"


def card(r: dict, src: str, base: bool = False) -> str:
    p = r.get("prompt", "")
    return (f'<div class="card{" base" if base else ""}">'
            f'<div class="top"><span class="stem">{html.escape(r["stem"])}</span>'
            f'<span class="meta">seed {r.get("seed", "—")}</span></div>'
            f'<audio controls preload="none" src="{html.escape(src)}"></audio>'
            f'{metrics(r)}'
            + (f'<div class="prompt">{html.escape(p)}</div>' if p else "")
            + "</div>")


def main() -> None:
    rows = json.loads((OUT / "analysis.json").read_text())
    base = json.loads((OUT / "baseline.json").read_text())

    parts = [f"<style>{CSS}</style>",
             "<h1>NFL broadcast menu round — 8 candidates</h1>",
             '<p class="sub">Heroic brass fanfare / snare march / timpani, '
             '~90-120 BPM, clean intro. Green chips mean the take does what a '
             'menu anthem should (peaks late, builds, opens quietly, has brass '
             'body); amber means it does the opposite. Metrics rank nothing on '
             'their own — round 3 proved the take the metrics liked least was '
             'the one that got approved. Listen first, read second.</p>',
             "<h2>Reference — what is on the menu screen today</h2>"]
    for r in base:
        parts.append(card(r, f'{SHIPPED_REL}/{r["file"]}', base=True))

    for lane, blurb in LANES.items():
        got = [r for r in rows if r["lane"] == lane]
        if not got:
            continue
        parts.append(f"<h2>{html.escape(blurb)}</h2>")
        for r in got:
            parts.append(card(r, r["file"]))

    PAGE.write_text("\n".join(parts))
    print(f"wrote {PAGE.name}  ({len(rows)} candidates + {len(base)} reference)")


if __name__ == "__main__":
    main()
