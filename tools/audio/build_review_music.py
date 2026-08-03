#!/usr/bin/env python3
"""Build review_music.html — the music-experiment listening page.

Same controls as build_review_v2.py (tick + "copy selected list", one
`style<TAB>path-relative-to-tools/audio` per line). Two zones: the ACE-Step
menu themes and the Stable Audio Open ambient loops.

Every row carries what it takes to reproduce or reject the take: style, model,
duration, prompt, seed, LUFS — plus the structural read-out that stood in for
ears (see post_music.py `structure`) and, for loops, the measured wrap
discontinuity.
"""

from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "review_music.html"

CSS = """
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;background:#0b1020;color:#e8ecf1}
header{position:sticky;top:0;background:#070b16;border-bottom:1px solid #1c2740;padding:14px 20px;z-index:10}
h1{margin:0 0 4px;font-size:19px;letter-spacing:.04em}
h1 b{color:#e0b050}
.sub{color:#8b97a8;font-size:12px;line-height:1.5}
button{background:#c9a227;color:#0b1020;border:0;border-radius:6px;padding:8px 14px;font-size:13px;
cursor:pointer;margin-right:8px;font-weight:600}
button:hover{background:#e0b050}
h2{margin:26px 20px 6px;font-size:15px;color:#e0b050;border-bottom:1px solid #1c2740;padding-bottom:6px}
table{width:calc(100% - 40px);margin:0 20px;border-collapse:collapse;font-size:12px}
th{text-align:left;color:#5f6b80;font-weight:500;font-size:10px;text-transform:uppercase;
letter-spacing:.06em;padding:6px 8px;border-bottom:1px solid #1c2740}
td{padding:7px 8px;border-bottom:1px solid #141b2c;vertical-align:middle}
tr:hover{background:#111829}
.fn{font-family:ui-monospace,Menlo,monospace;color:#dfe6ee;white-space:nowrap;font-weight:600}
.pr{color:#8b97a8;max-width:400px;overflow-wrap:anywhere;font-size:11px;line-height:1.45}
.kw{color:#e0b050;font-family:ui-monospace,Menlo,monospace;font-size:11px;white-space:nowrap}
.num{color:#8b97a8;text-align:right;white-space:nowrap;font-family:ui-monospace,Menlo,monospace;font-size:11px}
.lufs{color:#6fa8dc;text-align:right;white-space:nowrap;font-family:ui-monospace,Menlo,monospace;font-size:11px}
.ok{color:#7fd4a0;font-family:ui-monospace,Menlo,monospace;font-size:11px}
.bad{color:#e0806a;font-family:ui-monospace,Menlo,monospace;font-size:11px}
audio{height:30px;vertical-align:middle}
.note{margin:8px 20px;color:#8b97a8;font-size:12px;line-height:1.6;max-width:1100px}
.note b{color:#cfd8e3}
.rank{color:#e0b050;font-weight:700;font-family:ui-monospace,Menlo,monospace}
#out{width:calc(100% - 40px);margin:10px 20px;height:120px;background:#060910;color:#9fe8b8;
border:1px solid #1c2740;border-radius:6px;font-family:ui-monospace,Menlo,monospace;font-size:11px;
display:none;padding:8px}
"""

JS = """
function count(){document.getElementById('n').textContent=
 document.querySelectorAll('input[type=checkbox]:checked').length+' selected';}
document.addEventListener('change',count);
function copySel(){
 const rows=[...document.querySelectorAll('input[type=checkbox]:checked')]
   .map(c=>c.dataset.style+'\\t'+c.value);
 const t=rows.join('\\n');
 const o=document.getElementById('out');o.style.display='block';o.value=t;
 navigator.clipboard.writeText(t).then(()=>{},()=>{o.select();});
 count();
}
count();
"""

# Ranking is structural/spectral only — see the honest-limits note on the page.
RANK = {
    "broadcast_anthem_take1": 1,
    "orchestral_cinematic_take1": 2,
    "dark_hybrid_take1": 3,
    "orchestral_cinematic_take2": 4,
    "broadcast_anthem_take2": 5,
    "dark_hybrid_take2": 6,
}

STYLE_BRIEF = {
    "broadcast_anthem": "heroic brass stabs, drumline, stadium-sized, builds to a peak",
    "dark_hybrid": "pulsing synth bass, cinematic percussion, tension-and-release",
    "orchestral_cinematic": "strings + horns, slow-burn epic, championship gravitas",
    "ambient_lofi": "lo-fi pads + brushed percussion",
    "ambient_broadcast": "broadcast underscore, muted keys, distant crowd",
    "ambient_downtempo": "downtempo lo-fi beat, dusty keys, vinyl",
    "ambient_cinematic": "sustained string pad, restrained, pre-game calm",
}


def f(v, nd=1, suf=""):
    return f"{v:.{nd}f}{suf}" if isinstance(v, (int, float)) else "--"


def main() -> None:
    man = json.loads((ROOT / "gen_music" / "manifest.json").read_text())
    themes = [m for m in man if m["kind"] == "menu_theme"]
    loops = [m for m in man if m["kind"] == "ambient_loop"]
    themes.sort(key=lambda m: RANK.get(m["stem"], 99))
    loops.sort(key=lambda m: m["stem"])

    P: list[str] = []
    A = P.append
    A('<meta charset="utf-8"><title>Sunday Night Dynasty — music candidates</title>')
    A(f"<style>{CSS}</style>")
    A('<header><h1>SUNDAY NIGHT <b>DYNASTY</b> — music candidates</h1>')
    A(f'<div class="sub">{len(themes)} menu themes '
      '(<code>lucataco/ace-step</code>, Apache-2.0) &middot; '
      f'{len(loops)} ambient loops (<code>stackadoc/stable-audio-open-1.0</code>, '
      'Stability Community Licence) &middot; all instrumental, '
      '&minus;16 LUFS / &minus;1.5 dBTP, 48 kHz stereo<br>'
      'tick what is worth keeping, then copy the list and save it as '
      '<code>selections_music.tsv</code></div>')
    A('<div style="margin-top:10px">'
      '<button onclick="copySel()">Copy selected list</button>'
      '<button onclick="document.querySelectorAll(\'input[type=checkbox]\')'
      '.forEach(c=>c.checked=false);count()">Clear all</button>'
      '<span id="n" class="sub"></span></div></header>')
    A('<textarea id="out" readonly></textarea>')

    A('<div class="note"><b>Read this before trusting the order.</b> Nobody in the '
      'generation loop could hear these files. The <span class="rank">#</span> rank '
      'is derived only from measurable proxies for the brief: <b>peak @</b> is where '
      'the loudest moment falls (0 = opens loudest, 1 = ends loudest), <b>build</b> is '
      'the last third minus the first third in dB, <b>arc</b> is the spread between the '
      'quiet and loud sections, <b>cent</b> is the median spectral centroid (low = dark '
      'and bass-led, high = bright and thin) and <b>LRA</b> is loudness range. '
      'A theme that "builds to a peak" should show a late peak, a positive build and a '
      'wide arc. None of that can tell you whether the melody is any good, whether the '
      'brass sounds synthetic, or whether the model hallucinated wordless vocal pads '
      '&mdash; <b>that judgement is yours, by ear</b>.</div>')

    # ---- menu themes ----
    A(f'<h2>MENU THEMES &mdash; ACE-Step, 90 s requested, instrumental marker forced</h2>')
    A('<table><tr><th></th><th>#</th><th>take</th><th>dur</th><th>LUFS / dBTP</th>'
      '<th>LRA</th><th>cent</th><th>peak@</th><th>build</th><th>arc</th>'
      '<th>seed</th><th>prompt tags</th><th>preview</th></tr>')
    for m in themes:
        r = RANK.get(m["stem"], "")
        A("<tr>"
          f'<td><input type="checkbox" data-style="{html.escape(m["style"])}" '
          f'value="{html.escape(m["files"]["master_wav"])}"></td>'
          f'<td class="rank">{r}</td>'
          f'<td class="fn">{html.escape(m["stem"])}</td>'
          f'<td class="num">{f(m["duration"],1,"s")}</td>'
          f'<td class="lufs">{f(m["LUFS"])} / {f(m["dBTP"])}</td>'
          f'<td class="num">{f(m["LRA"])}</td>'
          f'<td class="num">{m.get("centroid_hz")}</td>'
          f'<td class="num">{f(m.get("peak_pos"),2)}</td>'
          f'<td class="num">{f(m.get("build_db"),1)}</td>'
          f'<td class="num">{f(m.get("arc_db"),1)}</td>'
          f'<td class="kw">{m["seed"]}</td>'
          f'<td class="pr">{html.escape(m["prompt"])}</td>'
          f'<td><audio controls preload="none" src="{m["files"]["preview_m4a"]}"></audio></td>'
          "</tr>")
    A("</table>")

    # ---- ambient loops ----
    A('<h2>DASHBOARD / AMBIENT LOOPS &mdash; Stable Audio Open, 47 s requested, '
      'seamless-wrap edited</h2>')
    A('<div class="note">Each file has had its tail folded back onto its head with a '
      f'2.0 s equal-power crossfade, so it wraps on <code>numberOfLoops = -1</code>. '
      '<b>seam</b> is the measured wrap discontinuity: the sample jump across the wrap '
      'minus the 99.9th-percentile jump the waveform already makes on its own. '
      'Negative = the wrap moves the signal <i>less</i> than the music does anyway, '
      'i.e. no click is physically present. <b>lvl</b> is the level match across the '
      'wrap (tail minus head, dB) &mdash; a big number there can still be audible as a '
      'jump in level even with a click-free seam.</div>')
    A('<table><tr><th></th><th>take</th><th>dur</th><th>LUFS / dBTP</th><th>LRA</th>'
      '<th>cent</th><th>arc</th><th>seam before</th><th>seam after</th><th>lvl</th>'
      '<th>seed</th><th>prompt</th><th>preview</th></tr>')
    for m in loops:
        lp = m["loop"]
        b, a = lp["seam_before"], lp["seam_after"]
        cls = "ok" if a["verdict"] == "clean" else "bad"
        bcls = "ok" if b["verdict"] == "clean" else "bad"
        lvl = a["level_match_db"]
        lcls = "ok" if abs(lvl) <= 3 else "bad"
        A("<tr>"
          f'<td><input type="checkbox" data-style="{html.escape(m["style"])}" '
          f'value="{html.escape(m["files"]["master_wav"])}"></td>'
          f'<td class="fn">{html.escape(m["stem"])}</td>'
          f'<td class="num">{f(m["duration"],1,"s")}</td>'
          f'<td class="lufs">{f(m["LUFS"])} / {f(m["dBTP"])}</td>'
          f'<td class="num">{f(m["LRA"])}</td>'
          f'<td class="num">{m.get("centroid_hz")}</td>'
          f'<td class="num">{f(m.get("arc_db"),1)}</td>'
          f'<td class="{bcls}">{f(b["headroom_db"],1)} dB</td>'
          f'<td class="{cls}">{f(a["headroom_db"],1)} dB {a["verdict"]}</td>'
          f'<td class="{lcls}">{f(lvl,1)}</td>'
          f'<td class="kw">{m["seed"]}</td>'
          f'<td class="pr">{html.escape(m["prompt"])}</td>'
          f'<td><audio controls preload="none" src="{m["files"]["preview_m4a"]}"></audio></td>'
          "</tr>")
    A("</table>")

    A('<div class="note" style="margin-bottom:40px"><b>Licensing, short version.</b> '
      'ACE-Step weights are Apache-2.0 &mdash; commercial use, no revenue cap, no '
      'attribution burden. Stable Audio Open is the Stability AI Community Licence, '
      'which is royalty-free commercial <i>only under $1M annual revenue</i>. If the '
      'ambient loops ship and Brew Crow ever crosses that line, they must be '
      'relicensed or replaced; the menu themes have no such string attached. '
      'MusicGen and everything else built on <code>audiocraft</code> was rejected '
      'outright: its weights are CC-BY-NC 4.0. Full detail in '
      '<code>LICENSES.md</code>.</div>')

    A(f"<script>{JS}</script>")
    OUT.write_text("\n".join(P))
    print(f"wrote {OUT}  ({len(themes)} themes, {len(loops)} loops)")


if __name__ == "__main__":
    main()
