#!/usr/bin/env python3
"""Build review_music_v2.html — round-2 listening page.

Differences from `build_review_music.py` (round 1):

  1. The six takes the user approved are LOCKED at the top, so the new
     material is judged against what already passed rather than in a vacuum.
  2. There is no rank column. Round 1 ranked by structural proxies and the
     user's favourite (`dark_hybrid_take2`) came LAST on that ordering — flat
     arc, bright centroid, all the things the heuristic marks down. The
     metrics are still printed because they are cheap and occasionally
     diagnostic, but ordering by them was actively misleading, so candidates
     are grouped by family and left alone.
  3. Every row shows the canonical ship name and the context it feeds, so a
     rejection is actionable: it names the slot that needs a replacement.

Same controls as before: tick, "copy selected list", one
`style<TAB>path-relative-to-tools/audio` per line.
"""

from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "review_music_v2.html"

APPROVED = [
    "orchestral_cinematic_take1", "orchestral_cinematic_take2",
    "dark_hybrid_take1", "dark_hybrid_take2",
    "ambient_downtempo_take1", "ambient_lofi_take1",
]

# Presentation grouping for the round-2 block: family -> (heading, blurb).
GROUPS = [
    ("orchestral_cinematic", "ORCHESTRAL CINEMATIC — five ways to be cinematic",
     "The approved family, deepened and lengthened. Percussion-forward, "
     "strings-only slow burn, brass peaks, restrained/noble, and a darker "
     "minor-key take (plus the playoff variant)."),
    ("dark_hybrid", "DARK HYBRID — pulse tempo as the axis",
     "The other approved family. Slow half-time pulse, fast arpeggio drive, "
     "atmospheric, aggressive, and the crossover the brief asked for: "
     "orchestral strings sitting on top of the synth pulse."),
    ("menu_theme", "MENU", "One more title-screen theme to widen the rotation."),
    ("cue_draft", "DRAFT ROOM CUES — 90-120 s",
     "Tense, ticking, restrained percussion. Deliberately without a big "
     "climax: the drama is the clock, not the music."),
    ("cue_championship", "CHAMPIONSHIP CUE — 90-120 s",
     "Triumphant peak variant of the cinematic family."),
    ("ambient_downtempo", "AMBIENT — DOWNTEMPO LANE", "Approved lane, more takes."),
    ("ambient_lofi", "AMBIENT — LO-FI LANE", "Approved lane, more takes."),
]

CSS = """
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;background:#0b1020;color:#e8ecf1}
header{position:sticky;top:0;background:#070b16;border-bottom:1px solid #1c2740;padding:14px 20px;z-index:10}
h1{margin:0 0 4px;font-size:19px;letter-spacing:.04em}
h1 b{color:#e0b050}
.sub{color:#8b97a8;font-size:12px;line-height:1.5}
button{background:#c9a227;color:#0b1020;border:0;border-radius:6px;padding:8px 14px;font-size:13px;
cursor:pointer;margin-right:8px;font-weight:600}
button:hover{background:#e0b050}
h2{margin:26px 20px 4px;font-size:14px;color:#e0b050;border-bottom:1px solid #1c2740;padding-bottom:6px}
h2.locked{color:#7fd4a0;border-color:#1d3a2b}
.blurb{margin:6px 20px 8px;color:#8b97a8;font-size:11.5px;line-height:1.5;max-width:1000px}
table{width:calc(100% - 40px);margin:0 20px;border-collapse:collapse;font-size:12px}
th{text-align:left;color:#5f6b80;font-weight:500;font-size:10px;text-transform:uppercase;
letter-spacing:.06em;padding:6px 8px;border-bottom:1px solid #1c2740}
td{padding:7px 8px;border-bottom:1px solid #141b2c;vertical-align:middle}
tr:hover{background:#111829}
tr.lock{background:#0d1a14}
tr.lock:hover{background:#122317}
.fn{font-family:ui-monospace,Menlo,monospace;color:#dfe6ee;white-space:nowrap;font-weight:600}
.ship{font-family:ui-monospace,Menlo,monospace;color:#e0b050;white-space:nowrap;font-size:11px}
.ctx{font-family:ui-monospace,Menlo,monospace;color:#6fa8dc;white-space:nowrap;font-size:11px}
.pr{color:#8b97a8;max-width:380px;overflow-wrap:anywhere;font-size:11px;line-height:1.45}
.kw{color:#e0b050;font-family:ui-monospace,Menlo,monospace;font-size:11px;white-space:nowrap}
.num{color:#8b97a8;text-align:right;white-space:nowrap;font-family:ui-monospace,Menlo,monospace;font-size:11px}
.lufs{color:#6fa8dc;text-align:right;white-space:nowrap;font-family:ui-monospace,Menlo,monospace;font-size:11px}
.ok{color:#7fd4a0;font-family:ui-monospace,Menlo,monospace;font-size:11px}
.bad{color:#e0806a;font-family:ui-monospace,Menlo,monospace;font-size:11px}
.tag{background:#1d3a2b;color:#7fd4a0;border-radius:4px;padding:1px 6px;font-size:10px;
font-weight:600;letter-spacing:.04em}
audio{height:30px;vertical-align:middle}
.note{margin:10px 20px;color:#8b97a8;font-size:12px;line-height:1.6;max-width:1100px}
.note b{color:#cfd8e3}
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
function stopOthers(el){
 document.querySelectorAll('audio').forEach(a=>{if(a!==el)a.pause();});
}
document.addEventListener('play',e=>stopOthers(e.target),true);
count();
"""


def f(v, nd=1, suf=""):
    return f"{v:.{nd}f}{suf}" if isinstance(v, (int, float)) else "--"


def main() -> None:
    man = json.loads((ROOT / "gen_music" / "manifest.json").read_text())
    by_stem = {m["stem"]: m for m in man}

    ship_path = ROOT / "shipped_music.json"
    ship = {}
    if ship_path.exists():
        for s in json.loads(ship_path.read_text()):
            ship[s["source_stem"]] = (s["name"], s["context"])

    approved = [by_stem[s] for s in APPROVED if s in by_stem]
    r2 = [m for m in man if m.get("round") == 2]

    P: list[str] = []
    A = P.append
    A('<meta charset="utf-8"><title>Sunday Night Dynasty — music round 2</title>')
    A(f"<style>{CSS}</style>")
    A('<header><h1>SUNDAY NIGHT <b>DYNASTY</b> — music, round 2</h1>')
    A(f'<div class="sub">{len(approved)} approved (locked, top) &middot; '
      f'{len(r2)} new candidates &middot; '
      'themes <code>lucataco/ace-step</code> (Apache-2.0), loops '
      '<code>stackadoc/stable-audio-open-1.0</code> (Stability Community) '
      '&middot; all instrumental, &minus;16 LUFS / &minus;1.5 dBTP, 48 kHz<br>'
      'tick anything that should NOT ship, or that you want more of, then copy '
      'the list</div>')
    A('<div style="margin-top:10px">'
      '<button onclick="copySel()">Copy selected list</button>'
      '<button onclick="document.querySelectorAll(\'input[type=checkbox]\')'
      '.forEach(c=>c.checked=false);count()">Clear all</button>'
      '<span id="n" class="sub"></span></div></header>')
    A('<textarea id="out" readonly></textarea>')

    A('<div class="note"><b>There is no rank column this time, on purpose.</b> '
      'Round 1 ordered the candidates by structural proxies &mdash; late peak, '
      'wide dynamic arc, dark centroid. Your favourite, '
      '<code>dark_hybrid_take2</code>, came <b>last</b> on that ordering: flat '
      'arc, brightest centroid in the set, peak in the first eighth. So the '
      'heuristic was not measuring what you were listening for, and round 2 '
      'does not filter or sort by it. The numbers are still printed '
      '(<b>cent</b> = median spectral centroid, <b>arc</b> = quiet-to-loud '
      'spread, <b>peak@</b> = where the loudest moment falls, 0 = opens '
      'loudest) but they are diagnostics, not a verdict. '
      '<b>ship</b> names the file the take becomes in the app and the playlist '
      'it feeds &mdash; a rejection therefore names the slot that needs a '
      'replacement.</div>')

    # ---- locked approved set ----
    A('<h2 class="locked">APPROVED — ROUND 1 <span class="tag">SHIPPING</span></h2>')
    A('<div class="blurb">Already passed your ear. Listed so the new material '
      'is judged against them rather than in isolation. The downtempo loop was '
      're-pointed &mdash; see the loop table note.</div>')
    A('<table><tr><th></th><th>take</th><th>ship as</th><th>context</th>'
      '<th>dur</th><th>LUFS</th><th>cent</th><th>arc</th><th>seed</th>'
      '<th>preview</th></tr>')
    for m in approved:
        sn, sc = ship.get(m["stem"], ("--", "--"))
        A('<tr class="lock">'
          f'<td><input type="checkbox" data-style="{html.escape(m["style"])}" '
          f'value="{html.escape(m["files"]["master_wav"])}"></td>'
          f'<td class="fn">{html.escape(m["stem"])}</td>'
          f'<td class="ship">{html.escape(sn)}</td>'
          f'<td class="ctx">{html.escape(sc)}</td>'
          f'<td class="num">{f(m["duration"],1,"s")}</td>'
          f'<td class="lufs">{f(m["LUFS"])}</td>'
          f'<td class="num">{m.get("centroid_hz")}</td>'
          f'<td class="num">{f(m.get("arc_db"),1)}</td>'
          f'<td class="kw">{m["seed"]}</td>'
          f'<td><audio controls preload="none" src="{m["files"]["preview_m4a"]}"></audio></td>'
          "</tr>")
    A("</table>")

    # ---- round-2 candidates, grouped, unranked ----
    for style, heading, blurb in GROUPS:
        rows = [m for m in r2 if m["style"] == style]
        if not rows:
            continue
        rows.sort(key=lambda m: m["stem"])
        is_loop = rows[0]["kind"] == "ambient_loop"
        A(f"<h2>{html.escape(heading)}</h2>")
        A(f'<div class="blurb">{html.escape(blurb)}</div>')
        if is_loop:
            A('<table><tr><th></th><th>take</th><th>ship as</th><th>context</th>'
              '<th>dur</th><th>LUFS</th><th>cent</th><th>seam</th><th>head/tail</th>'
              '<th>fold</th><th>seed</th><th>prompt</th><th>preview</th></tr>')
        else:
            A('<table><tr><th></th><th>take</th><th>ship as</th><th>context</th>'
              '<th>dur</th><th>LUFS</th><th>LRA</th><th>cent</th><th>peak@</th>'
              '<th>arc</th><th>seed</th><th>prompt</th><th>preview</th></tr>')
        for m in rows:
            sn, sc = ship.get(m["stem"], ("(not shipped)", "--"))
            cells = [
                f'<td><input type="checkbox" data-style="{html.escape(m["style"])}" '
                f'value="{html.escape(m["files"]["master_wav"])}"></td>',
                f'<td class="fn">{html.escape(m["stem"])}</td>',
                f'<td class="ship">{html.escape(sn)}</td>',
                f'<td class="ctx">{html.escape(sc)}</td>',
                f'<td class="num">{f(m["duration"],1,"s")}</td>',
                f'<td class="lufs">{f(m["LUFS"])}</td>',
            ]
            if is_loop:
                lp = m["loop"]
                a = lp["seam_after"]
                lvl = a["level_match_db"]
                lcls = "ok" if abs(lvl) < 3 else "bad"
                scls = "ok" if a["verdict"] == "clean" else "bad"
                cells += [
                    f'<td class="num">{m.get("centroid_hz")}</td>',
                    f'<td class="{scls}">{a["verdict"]}</td>',
                    f'<td class="{lcls}">{f(lvl,1,"dB")}</td>',
                    f'<td class="num">{f(lp["xfade_s"],1)}/{f(lp.get("tail_cut_s",0),1)}</td>',
                ]
            else:
                cells += [
                    f'<td class="num">{f(m.get("LRA"))}</td>',
                    f'<td class="num">{m.get("centroid_hz")}</td>',
                    f'<td class="num">{f(m.get("peak_pos"),2)}</td>',
                    f'<td class="num">{f(m.get("arc_db"),1)}</td>',
                ]
            cells += [
                f'<td class="kw">{m["seed"]}</td>',
                f'<td class="pr">{html.escape(m["prompt"])}</td>',
                f'<td><audio controls preload="none" src="{m["files"]["preview_m4a"]}"></audio></td>',
            ]
            A("<tr>" + "".join(cells) + "</tr>")
        A("</table>")

    A('<div class="note"><b>Loops.</b> <code>seam</code> is the wrap '
      'discontinuity: the sample jump across the wrap minus the 99.9th-'
      'percentile jump the waveform already makes on its own, so "clean" means '
      'no click is physically present. <code>head/tail</code> is the new check '
      '&mdash; the RMS of the last 200 ms minus the first 200 ms. Round 1 '
      'shipped <code>ambient_downtempo_take1</code> at <b>+7.8 dB</b> there: '
      'click-free, but it would audibly drop in level on every wrap. Round 2 '
      'searches the fold point (<code>fold</code> = crossfade seconds / tail '
      'cut seconds) until the delta is under 3 dB, trying the round-1 fold '
      'first so loops that were already fine are untouched.</div>')

    A('<div class="note" style="margin-bottom:40px"><b>Licensing.</b> ACE-Step '
      'weights are Apache-2.0 &mdash; commercial use, no revenue cap. Stable '
      'Audio Open is the Stability AI Community Licence: royalty-free '
      'commercial <i>only under $1M annual revenue</i>, so the ambient loops '
      'carry a live obligation the themes do not. ACE-Step returns 320 kbps '
      'MP3, not WAV, so those masters are lossy at source; the ship encode is '
      'AAC 160 kbps either way. Full detail in <code>LICENSES.md</code>.</div>')

    A(f"<script>{JS}</script>")
    OUT.write_text("\n".join(P))
    print(f"wrote {OUT}  ({len(approved)} approved, {len(r2)} new)")


if __name__ == "__main__":
    main()
