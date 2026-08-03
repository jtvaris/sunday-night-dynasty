#!/usr/bin/env python3
"""Build review_audio_v2.html — round-2 listening page.

Same controls as v1 (tick + "copy selected list", output is
`category<TAB>path-relative-to-tools/audio` per line, ready to save as
selections_round2.tsv). Two zones:

  1. APPROVED — the seven Sonniss crowd files, already mastered. Locked:
     shown for reference and level-matching, no checkboxes.
  2. GENERATED — every Stable Audio Open take, grouped by category, with the
     prompt/seed/loudness that produced it so a good take is reproducible.
"""

from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "review_audio_v2.html"

CSS = """
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;background:#12151a;color:#e8ecf1}
header{position:sticky;top:0;background:#0d1014;border-bottom:1px solid #2a3140;padding:14px 20px;z-index:10}
h1{margin:0 0 4px;font-size:19px}
.sub{color:#8b97a8;font-size:12px}
button{background:#2d6cdf;color:#fff;border:0;border-radius:6px;padding:8px 14px;font-size:13px;cursor:pointer;margin-right:8px}
button:hover{background:#3d7cef}
h2{margin:26px 20px 8px;font-size:15px;color:#7fd4a0;border-bottom:1px solid #2a3140;padding-bottom:6px}
h2.locked{color:#e0b050}
table{width:calc(100% - 40px);margin:0 20px;border-collapse:collapse;font-size:12px}
td{padding:5px 8px;border-bottom:1px solid #1e242e;vertical-align:middle}
tr:hover{background:#181d25}
.fn{font-family:ui-monospace,Menlo,monospace;color:#dfe6ee;white-space:nowrap}
.pr{color:#8b97a8;max-width:430px;overflow-wrap:anywhere;font-size:11px}
.kw{color:#e0b050;font-family:ui-monospace,Menlo,monospace;font-size:11px;white-space:nowrap}
.dur{color:#8b97a8;text-align:right;white-space:nowrap;font-family:ui-monospace,Menlo,monospace}
.lufs{color:#6fa8dc;text-align:right;white-space:nowrap;font-family:ui-monospace,Menlo,monospace;font-size:11px}
audio{height:30px;vertical-align:middle}
.note{margin:8px 20px;color:#8b97a8;font-size:12px;line-height:1.5}
.warn{margin:8px 20px;color:#e0806a;font-size:12px}
#out{width:calc(100% - 40px);margin:10px 20px;height:130px;background:#0b0e12;color:#9fe8b8;
border:1px solid #2a3140;border-radius:6px;font-family:ui-monospace,Menlo,monospace;font-size:11px;display:none;padding:8px}
"""

JS = """
function count(){document.getElementById('n').textContent=
 document.querySelectorAll('input[type=checkbox]:checked').length+' selected';}
document.addEventListener('change',count);
function copySel(){
 const rows=[...document.querySelectorAll('input[type=checkbox]:checked')].map(c=>{
   const cat=c.closest('table').previousElementSibling.textContent.split('\\u2014')[0].trim();
   return cat+'\\t'+c.value;});
 const t=rows.join('\\n');
 const o=document.getElementById('out');o.style.display='block';o.value=t;
 navigator.clipboard.writeText(t).then(()=>{},()=>{o.select();});
 count();
}
count();
"""


def fmt(v, suffix="", nd=1):
    return f"{v:.{nd}f}{suffix}" if isinstance(v, (int, float)) else "--"


def main() -> None:
    approved = json.loads((ROOT / "approved" / "manifest.json").read_text())
    gen_p = ROOT / "gen" / "manifest.json"
    gen = json.loads(gen_p.read_text()) if gen_p.exists() else []
    gen_ok = [g for g in gen if g["status"] == "ok"]
    bad = [g for g in gen if g["status"] != "ok"]

    parts: list[str] = []
    A = parts.append
    A('<meta charset="utf-8"><title>Dynasty — audio round 2 (generated SFX)</title>')
    A(f"<style>{CSS}</style>")
    A('<header><h1>Dynasty — audio round 2</h1>')
    A(f'<div class="sub">{len(approved)} approved Sonniss crowd files (mastered, locked) '
      f'&middot; {len(gen_ok)} generated takes across {len({g["category"] for g in gen_ok})} categories '
      '&middot; everything normalised to &minus;18 LUFS / &minus;1.5 dBTP, 48 kHz stereo<br>'
      'tick the takes you want to keep, then copy the list (category + path per line) '
      'and save it as <code>selections_round2.tsv</code></div>')
    A('<div style="margin-top:10px">'
      '<button onclick="copySel()">Copy selected list</button>'
      '<button onclick="document.querySelectorAll(\'input[type=checkbox]\').forEach(c=>c.checked=false);count()">Clear all</button>'
      '<span id="n" class="sub"></span></div></header>')
    A('<textarea id="out" readonly></textarea>')

    # ---- locked approved section ----
    A('<h2 class="locked">APPROVED — Sonniss crowd beds (locked reference)</h2>')
    A('<div class="note">Already selected and mastered in job 1 &mdash; listed here so you can '
      'level-match the generated one-shots against them. Not selectable.</div>')
    A("<table>")
    for a in sorted(approved, key=lambda x: (x["category"], x["name"])):
        A("<tr>"
          f'<td class="kw">{html.escape(a["category"])}</td>'
          f'<td class="fn">{html.escape(a["name"])}</td>'
          f'<td class="dur">{fmt(a["out"]["duration"], "s", 2)}</td>'
          f'<td class="lufs">{fmt(a["out_LUFS"])} LUFS / {fmt(a["out_TP_dBTP"])} dBTP</td>'
          f'<td class="pr">{html.escape(a["source_library"])}</td>'
          f'<td><audio controls preload="none" src="{a["files"]["preview_m4a"]}"></audio></td>'
          "</tr>")
    A("</table>")

    # ---- generated ----
    cats: dict[str, list] = {}
    for g in gen_ok:
        cats.setdefault(g["category"], []).append(g)

    if bad:
        A(f'<div class="warn">{len(bad)} take(s) came back unusable/silent: '
          + html.escape(", ".join(b["stem"] for b in bad)) + "</div>")

    for cat in sorted(cats):
        takes = sorted(cats[cat], key=lambda x: x["stem"])
        A(f'<h2>{html.escape(cat)} &mdash; {len(takes)} takes</h2>')
        A("<table>")
        for g in takes:
            A("<tr>"
              f'<td><input type="checkbox" value="{html.escape(g["files"]["ship_wav_16bit"])}"></td>'
              f'<td class="fn">{html.escape(g["stem"])}</td>'
              f'<td class="dur">{fmt(g["out"]["duration"], "s", 2)}</td>'
              f'<td class="lufs">{fmt(g["out_LUFS"])} / {fmt(g["out_TP_dBTP"])}</td>'
              f'<td class="kw">seed {g.get("seed")}</td>'
              f'<td class="pr">{html.escape(g.get("prompt") or "")}</td>'
              f'<td><audio controls preload="none" src="{g["files"]["preview_m4a"]}"></audio></td>'
              "</tr>")
        A("</table>")

    A(f"<script>{JS}</script>")
    OUT.write_text("\n".join(parts))
    print(f"wrote {OUT}  ({len(approved)} approved, {len(gen_ok)} generated, {len(bad)} bad)")


if __name__ == "__main__":
    main()
