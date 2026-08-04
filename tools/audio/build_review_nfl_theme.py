#!/usr/bin/env python3
"""Listen page for the whole NFL-broadcast wave — both rounds, one page.

`build_review_nfl_menu.py` covered the 8 menu takes off their RAW returns,
before there was a master or a score. This supersedes it: 16 candidates
(8 menu + 8 dashboard), each played from its MASTER preview so what you hear
is what would ship, with the round score, the reasons behind it, the seed and
the exact prompt. The 6 that went into the bundle carry a SHIPPED badge.

The two rounds are judged on opposite briefs and so get opposite chips:

  MENU      wants an arc. Green = peaks late, builds, opens quietly, has brass
            body between 200-2000 Hz, came back near the ordered tempo.
  DASHBOARD wants no arc at all. Green = flat, dark, constant, nothing that
            pulls the eye off the roster. The same +4 dB build that is a
            virtue upstairs is a defect here.

Every number is a filter, not a ranking. Round 3 of generate_music.py settled
that: the take the metrics liked least was the one that got approved. Reasons
are printed so a low score can be overruled by an ear — which is the whole
point of the page.

Paths are relative, so the page only works from inside tools/audio/.

    python3 build_review_nfl_theme.py && open review_nfl_theme.html
"""

from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MENU = ROOT / "gen_nfl_menu"
DASH = ROOT / "gen_nfl_dash"
PAGE = ROOT / "review_nfl_theme.html"
SHIPPED_JSON = ROOT / "shipped_nfl_theme.json"
MUSIC_MANIFEST = ROOT / "gen_music" / "manifest.json"
SHIPPED_REL = "../../dynasty/dynasty/Resources/Audio/Music"

MENU_LANES = {
    "orchestral": ("Orchestral", "Brass, strings, percussion — no synths"),
    "hybrid": ("Hybrid", "Fanfare over a modern synth floor"),
    "march": ("March", "Drumline forward, quickest pulse"),
    "slowburn": ("Slow burn", "Quiet statement first, fanfare arrives late"),
}
DASH_LANES = {
    "ambient": ("Ambient", "Drone and texture, almost no percussion"),
    "strings": ("Strings", "Ostinato underscore, forward motion without drama"),
    "lowbrass": ("Low brass", "Trombone/tuba pedal, dark and serious"),
    "fanfare": ("Restrained fanfare", "The broadcast motif played held-back"),
}

CSS = """
:root { color-scheme: dark; }
body { background:#0f1216; color:#e8eaed; font:14px/1.5 -apple-system,system-ui,sans-serif;
       margin:0; padding:32px 32px 64px; }
h1 { font-size:22px; margin:0 0 4px; }
h2 { font-size:17px; margin:40px 0 6px; color:#dfe6ee; font-weight:600; }
h3 { font-size:14px; margin:26px 0 10px; color:#9db4d0; font-weight:600;
     border-bottom:1px solid #253040; padding-bottom:6px; }
h3 em { color:#6f7b89; font-style:normal; font-weight:400; }
.sub { color:#8b97a6; margin:0 0 20px; max-width:74ch; }
.card { background:#161b22; border:1px solid #253040; border-radius:10px;
        padding:14px 16px; margin:0 0 12px; }
.card.ship { border-color:#3f6b46; background:#131d16; }
.card.base { border-color:#3d4f2f; background:#141a14; }
.top { display:flex; align-items:baseline; gap:10px; flex-wrap:wrap; }
.stem { font-weight:600; font-size:15px; }
.meta { color:#7d8794; font-size:12px; }
.badge { font-size:11px; font-weight:700; letter-spacing:.06em; border-radius:4px;
         padding:2px 7px; text-transform:uppercase; }
.badge.ship { background:#2c5a35; color:#c8f0cf; }
.badge.ref { background:#3d4f2f; color:#d6e8c4; }
.score { margin-left:auto; font-size:13px; font-weight:700; border-radius:5px;
         padding:2px 9px; background:#1d2530; border:1px solid #2b3646; }
.score.s5 { background:#13210f; border-color:#2f5233; color:#a8d99a; }
.score.s4 { background:#1c2412; border-color:#41552b; color:#cbe0a8; }
.score.s3 { background:#241d10; border-color:#5a4520; color:#e8c98a; }
.score.s2 { background:#2a1614; border-color:#5f2f2a; color:#eda79c; }
audio { width:100%; margin:10px 0 8px; }
.m { display:flex; flex-wrap:wrap; gap:6px; margin-top:6px; }
.m span { background:#1d2530; border:1px solid #2b3646; border-radius:5px;
          padding:2px 8px; font-size:12px; color:#b6c2d0; }
.m span b { color:#e8eaed; font-weight:600; }
.warn { border-color:#5a4520 !important; background:#241d10 !important; color:#e8c98a !important; }
.good { border-color:#2f5233 !important; background:#13210f !important; color:#a8d99a !important; }
.why { color:#c2a45f; font-size:12.5px; margin-top:8px; }
.why.clean { color:#8fbf85; }
.prompt { color:#6f7b89; font-size:12px; margin-top:8px; font-family:ui-monospace,monospace;
          word-break:break-word; }
.foot { color:#6f7b89; font-size:12px; margin-top:40px; border-top:1px solid #253040;
        padding-top:14px; max-width:74ch; }
"""


def chip(label: str, val, fmt="{}", cls="") -> str:
    return f'<span class="{cls}">{label} <b>{fmt.format(val)}</b></span>'


def menu_chips(r: dict) -> str:
    peak = r.get("peak_pos") or 0
    build = r.get("build_db") or 0
    intro = r.get("intro_vs_body_db") or 0
    mid = r.get("band_mid_pct") or 0
    low = r.get("band_low_pct") or 0
    err = r.get("bpm_err")
    out = [
        chip("len", r.get("duration") or 0, "{:.0f}s"),
        chip("peak@", peak, "{:.0%}", "good" if peak > 0.45 else "warn"),
        chip("build", build, "{:+.1f}dB", "good" if build > 0 else "warn"),
        chip("intro", intro, "{:+.1f}dB", "good" if intro < -1 else "warn"),
        chip("mid", mid, "{:.0f}%", "good" if mid >= 35 else "warn"),
        chip("low", low, "{:.0f}%", "warn" if low >= 75 else ""),
        chip("high", r.get("band_high_pct") or 0, "{:.1f}%",
             "warn" if (r.get("band_high_pct") or 0) > 15 else ""),
        chip("BPM", r.get("bpm_octave_fit") or 0, "{:.0f}"),
        chip("want", r.get("bpm_want") or 0, "{:.0f}"),
    ]
    if err is not None:
        out.append(chip("±", err, "{:.0f}", "good" if err <= 8 else "warn"))
    out += [chip("arc", r.get("arc_db") or 0, "{:.1f}dB"),
            chip("LUFS", r.get("LUFS") or 0, "{}")]
    return '<div class="m">' + "".join(out) + "</div>"


def dash_chips(r: dict) -> str:
    build = abs(r.get("build_db") or 0)
    arc = r.get("arc_db") or 0
    cent = r.get("centroid_hz") or 0
    lra = r.get("LRA") or 0
    out = [
        chip("len", r.get("duration") or 0, "{:.0f}s"),
        chip("build", r.get("build_db") or 0, "{:+.1f}dB", "good" if build <= 3 else "warn"),
        chip("arc", arc, "{:.1f}dB", "good" if arc <= 12 else "warn"),
        chip("centroid", cent, "{:.0f}Hz", "good" if cent <= 2200 else "warn"),
        chip("LRA", lra, "{:.1f}", "good" if lra <= 7 else "warn"),
        chip("peak@", r.get("peak_pos") or 0, "{:.0%}"),
        chip("LUFS", r.get("LUFS") or 0, "{}"),
    ]
    tail = r.get("tail_silence_s") or 0
    if tail > 0.5:
        out.append(chip("tail trimmed", tail, "{:.2f}s"))
    return '<div class="m">' + "".join(out) + "</div>"


def score_cls(s: float | None) -> str:
    if s is None:
        return ""
    return f"s{min(5, max(2, int(s)))}"


def card(r: dict, src: str, chips, shipped: bool) -> str:
    s = r.get("score")
    why = "; ".join(r.get("reasons") or [])
    badge = '<span class="badge ship">shipped</span>' if shipped else ""
    return (f'<div class="card{" ship" if shipped else ""}">'
            f'<div class="top"><span class="stem">{html.escape(r["stem"])}</span>'
            f'{badge}'
            f'<span class="meta">seed {r.get("seed", "—")} · '
            f'{html.escape(str(r.get("model", "")))}</span>'
            + (f'<span class="score {score_cls(s)}">{s:.1f}</span>' if s is not None else "")
            + "</div>"
            f'<audio controls preload="none" src="{html.escape(src)}"></audio>'
            f'{chips(r)}'
            + (f'<div class="why">{html.escape(why)}</div>' if why else
               '<div class="why clean">no measured objection</div>')
            + f'<div class="prompt">{html.escape(r.get("prompt", ""))}</div>'
            + "</div>")


def ref_card(stem: str, src: str, note: str, bits: list[str]) -> str:
    return ('<div class="card base"><div class="top">'
            f'<span class="stem">{html.escape(stem)}</span>'
            '<span class="badge ref">in the game today</span>'
            f'<span class="meta">{html.escape(note)}</span></div>'
            f'<audio controls preload="none" src="{html.escape(src)}"></audio>'
            '<div class="m">' + "".join(bits) + "</div></div>")


def section(title: str, blurb: str, rows: list[dict], lanes: dict,
            chips, shipped: set[str], rel: str) -> list[str]:
    out = [f"<h2>{html.escape(title)}</h2>", f'<p class="sub">{blurb}</p>']
    for lane, (name, desc) in lanes.items():
        got = [r for r in rows if r["lane"] == lane]
        if not got:
            continue
        out.append(f"<h3>{html.escape(name)} — <em>{html.escape(desc)}</em></h3>")
        for r in sorted(got, key=lambda x: (-(x.get("score") or 0), x["stem"])):
            out.append(card(r, f'{rel}/{r["stem"]}.m4a', chips,
                            r["stem"] in shipped))
    return out


def main() -> None:
    menu = json.loads((MENU / "metrics.json").read_text())
    dash = json.loads((DASH / "metrics.json").read_text())
    shipped = {s["name"] for s in json.loads(SHIPPED_JSON.read_text())} \
        if SHIPPED_JSON.exists() else set()

    spend = (menu.get("spend_usd") or 0) + (dash.get("spend_usd") or 0)
    gpu = (menu.get("gpu_seconds") or 0) + (dash.get("gpu_seconds") or 0)

    parts = [f"<style>{CSS}</style>",
             "<h1>NFL broadcast wave — 16 candidates, 6 shipped</h1>",
             '<p class="sub">Heroic brass, snare march, timpani, Americana '
             'grandeur. Two rounds off the same DNA pulling in opposite '
             'directions: the menu round wants an anthem that arcs, the '
             'dashboard round wants an underscore that never does. Every take '
             'plays from its 192 kbps master preview, so this is what would '
             'ship — the bundled files are the same masters at 160 kbps AAC. '
             'Scores are a filter, not a ranking; the reasons under each take '
             'are there to be overruled by an ear.</p>']

    base = MENU / "baseline.json"
    if base.exists():
        parts.append("<h3>Reference — the two menu themes in the game today</h3>")
        for r in json.loads(base.read_text()):
            parts.append(ref_card(
                r["stem"], f'{SHIPPED_REL}/{r["file"]}', "round 3 synth anthem",
                [chip("len", r.get("actual_s") or 0, "{:.0f}s"),
                 chip("BPM", r.get("bpm_octave_fit") or 0, "{:.0f}"),
                 chip("mid", r.get("band_mid_pct") or 0, "{:.0f}%"),
                 chip("low", r.get("band_low_pct") or 0, "{:.0f}%")]))

    if MUSIC_MANIFEST.exists():
        beds = {"dashboard_dark_r3_ember": "music_dashboard_bed_a",
                "dashboard_dark_r3_late": "music_dashboard_bed_b",
                "dashboard_dark_r3_slowpulse": "music_dashboard_bed_c"}
        man = [m for m in json.loads(MUSIC_MANIFEST.read_text()) if m["stem"] in beds]
        if man:
            parts.append("<h3>Reference — the dashboard beds in the game today</h3>")
            for m in man:
                parts.append(ref_card(
                    beds[m["stem"]], f'{SHIPPED_REL}/{beds[m["stem"]]}.m4a',
                    "round 3 dark downtempo",
                    [chip("len", m.get("duration") or 0, "{:.0f}s"),
                     chip("build", m.get("build_db") or 0, "{:+.1f}dB"),
                     chip("arc", m.get("arc_db") or 0, "{:.1f}dB"),
                     chip("centroid", m.get("centroid_hz") or 0, "{:.0f}Hz"),
                     chip("LRA", m.get("LRA") or 0, "{:.1f}")]))

    parts += section(
        "Menu round — 8 takes, 3 shipped",
        "Title screen. The brief: heroic brass fanfare, military snare, "
        "timpani, ~90-125 BPM, a quiet open that builds to a late peak. Green "
        "chips mean the take does that; amber means it does the opposite.",
        menu["takes"], MENU_LANES, menu_chips, shipped, "gen_nfl_menu")

    parts += section(
        "Dashboard round — 8 takes, 3 shipped",
        "The screen a player stares at longest. Same broadcast DNA, held back: "
        "it has to sit behind reading a roster. Green chips mean flat, dark and "
        "constant — here a build, a wide arc or a bright centroid is the defect.",
        dash["takes"], DASH_LANES, dash_chips, shipped, "gen_nfl_dash")

    parts.append(
        f'<div class="foot">Both rounds: ACE-Step on Replicate '
        f'(Apache-2.0, no revenue cap), {gpu:.0f} GPU-seconds at '
        f'$0.000975/s = <b>${spend:.4f}</b> for all 16 takes. Masters at '
        f'-16 LUFS / -1.5 dBTP, dead air trimmed off a measured RMS envelope. '
        f'Shipped files land in dynasty/dynasty/Resources/Audio/Music/ and are '
        f'wired into MusicDirector\'s <code>menu</code> and '
        f'<code>dashboard</code> playlists.</div>')

    PAGE.write_text("\n".join(parts))
    print(f"wrote {PAGE.name}  ({len(menu['takes']) + len(dash['takes'])} "
          f"candidates, {len(shipped)} shipped)")


if __name__ == "__main__":
    main()
