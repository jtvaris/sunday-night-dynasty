#!/usr/bin/env python3
"""Regenerate the provenance tables in LICENSES.md from the two manifests.

Replaces everything from the "## Approved & mastered" marker onward, so it is
safe to re-run after another mastering pass.
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LIC = ROOT / "LICENSES.md"
# Everything from here down is regenerated; the stale "nothing shipped yet"
# and "bespoke pending" tables it replaces are superseded by these manifests.
MARK = "## Shipped files"

approved = json.loads((ROOT / "approved" / "manifest.json").read_text())
gen = [g for g in json.loads((ROOT / "gen" / "manifest.json").read_text())
       if g["status"] == "ok"]

raw_meta = [json.loads(p.read_text()) for p in (ROOT / "gen_raw").glob("*/*.json")]
total_predict = sum(m.get("predict_time") or 0 for m in raw_meta)
RATE = 0.000975  # Nvidia L40S, per second, as billed by Replicate
cost = total_predict * RATE

L: list[str] = []
A = L.append

A("## Shipped files")
A("")
A("**Still nothing in `dynasty/dynasty/Resources/`.** Stage 2 masters candidates")
A("into `approved/` and `gen/` only; the copy into the app bundle happens after")
A("the user picks takes from `review_audio_v2.html`. Update this section in the")
A("same commit that adds the assets.")
A("")
A("| Shipped path | Category | Source | Licence |")
A("|---|---|---|---|")
A("| _(none yet)_ | | | |")
A("")
A("---")
A("")
A("## Approved & mastered (round 1)")
A("")
A("These are the seven files the user approved from `review_audio.html`. All are")
A("Sonniss GDC bundle content, so the umbrella licence above applies verbatim:")
A("**royalty-free commercial use, no attribution required, no reselling as sound**")
A("**packs, no AI-training use.**")
A("")
A("Mastering applied (`process_approved.py`): 5.1 sources folded to stereo with an")
A("explicit ITU-R BS.775 pan matrix, EBU R128 two-pass loudnorm to **-18 LUFS /**")
A("**-1.5 dBTP**, 48 kHz stereo, full duration preserved. Each ships as 16-bit PCM")
A("wav (the format `AudioDirector` already loads) with a 24-bit `.master.wav`")
A("archive and an `.m4a` review preview alongside.")
A("")
A("> **5.1 channel-order note.** The two Rose Bowl files are tagged")
A("> `_5.1 LCRLsRsLf`, i.e. **L C R Ls Rs LFE** — *not* ffmpeg's default")
A("> `FL FR FC LFE BL BR`. A plain `-ac 2` would fold the centre channel into the")
A("> right speaker and treat left-surround as LFE. Verified before trusting the")
A("> filename: channel 5 measures ~-54 dB RMS against ~-25 dB on the others, which")
A("> is unmistakably the LFE. The pan matrix in `process_approved.py` is correct;")
A("> do not 'simplify' it back to `-ac 2`.")
A("")
A("| Mastered file | Category | Source library | Bundle | Source | LUFS in → out | True peak |")
A("|---|---|---|---|---|---|---|")
for a in sorted(approved, key=lambda x: (x["category"], x["name"])):
    src = f"{a['source']['channels']}ch / {a['source']['sample_rate']//1000} kHz / {a['source']['duration']:.1f}s"
    A(f"| `{a['files']['ship_wav_16bit']}` | `{a['category']}` | {a['source_library']} "
      f"| {a['source_bundle']} | {src} | {a['in_LUFS']} → {a['out_LUFS']} LUFS | {a['out_TP_dBTP']} dBTP |")
A("")
A("Original filenames (for tracing back into `extracted/`):")
A("")
for a in sorted(approved, key=lambda x: x["name"]):
    A(f"- `{a['name']}` ← `{a['source_file']}`")
A("")
A("---")
A("")
A("## Generated SFX")
A("")
A("Everything the Sonniss archive could not serve was generated from scratch with")
A("a text-to-audio model. **No bundle audio was used as input**, which keeps us")
A("clear of the Sonniss no-AI-training clause quoted above.")
A("")
A("| Field | Value |")
A("|---|---|")
A("| Model | `stackadoc/stable-audio-open-1.0` (Replicate) |")
A("| Version pinned | `9aff84a639f96d0f7e6081cdea002d15133d0043727f849c40abdd166b7c75a8` |")
A("| Upstream weights | `stabilityai/stable-audio-open-1.0` (Hugging Face) |")
A("| Licence | **Stability AI Community License** |")
A("| Licence text | https://stability.ai/community-license-agreement |")
A("| Hardware / rate | Nvidia L40S, $0.000975 / sec |")
A(f"| Takes generated | {len(raw_meta)} ({len(gen)} kept for review, rest are pilots) |")
A(f"| Total GPU time | {total_predict:.1f} s |")
A(f"| Total cost | ~${cost:.2f} |")
A("| Date | 2026-08-03 |")
A("")
A("### ⚠ Licence caveat — the $1M annual-revenue cap")
A("")
A("The Stability AI Community License permits **commercial use, royalty-free,")
A("only while you or your affiliates generate under USD $1,000,000 in annual")
A("revenue** (any revenue, not just revenue derived from the model). Verbatim:")
A("")
A("> *If at any time You or Your Affiliate(s), either individually or in")
A("> aggregate, generate more than USD $1,000,000 in annual revenue (or the")
A("> equivalent thereof in Your local currency), regardless of whether that")
A("> revenue is generated directly or indirectly from the Stability AI Materials")
A("> or Derivative Works, any licenses granted to You under this Agreement shall")
A("> terminate as of such date.*")
A("")
A("**→ If Sunday Night Dynasty (or Brew Crow as a whole) ever crosses $1M annual")
A("revenue, an Enterprise licence must be obtained from Stability AI, or these")
A("generated files must be replaced.** Register at https://stability.ai/license.")
A("This is a live obligation, not a one-off check — re-read it at each funding or")
A("revenue milestone.")
A("")
A("**Also recorded, because it is a genuine trap:** the Replicate wrapper repo")
A("`github.com/stackadoc/cog-stable-audio` still ships a `LICENSE_MODEL` file")
A("containing the *older* **Stability AI NON-COMMERCIAL Research Community**")
A("**License** (dated 2024-06-05), under which shipping these sounds in a paid")
A("game would **not** be permitted. That file is a stale snapshot of the terms at")
A("the model's launch. Stability subsequently relicensed the upstream weights:")
A("`stabilityai/stable-audio-open-1.0` on Hugging Face declares")
A("`license_name: stable-audio-community` (model card last modified 2025-06-19),")
A("and the same applies to `stable-audio-open-small`. **We rely on the upstream")
A("Community License, not the wrapper repo's stale file.** If this is ever")
A("challenged, the evidence is the Hugging Face model-card metadata.")
A("")
A("Model outputs themselves are not claimed by Stability — the licence covers the")
A("Materials and Derivative Works, and explicitly excludes model output from the")
A("definition of a Derivative Work. Shipping the generated `.wav` files inside the")
A("game is distribution of *output*, not of the model.")
A("")
A("### Generated categories")
A("")
A("Prompts, seeds and per-take loudness live in `gen/manifest.json`; the raw")
A("47 s model returns plus a JSON sidecar per take are in `gen_raw/` so any take")
A("is reproducible from its seed. Nothing here is shipped until the user picks")
A("takes from `review_audio_v2.html`.")
A("")
A("| Category | Takes | Why generated rather than sourced |")
A("|---|---|---|")
WHY = {
    "kick_punt": "Only 2 keyword hits archive-wide, both motorcycle kick-starts. No ball-kick recording in any Sonniss year.",
    "kick_place": "Same gap as `kick_punt` — no placekick/tee impact exists in the archive.",
    "catch": "3 hits, all apparel foley (bracelet, leather jacket). No ball-into-hands catch.",
    "throw_whoosh": "Generic whooshes exist but none read as a short QB release; cheaper to generate than to sift.",
    "tackle_impact": "Archive impacts are all melee/weapon or vehicle; no pad-on-pad body collision.",
    "whistle": "Archive whistles are train/kettle/sports-hall; no clean isolated referee pea whistle.",
    "shouts": "Male-voice hits were announcer VO or animal grunts; no snap-cadence or lineman effort.",
    "crowd_boo_extra": "Only 2 usable boo files archive-wide — not enough variation for a season.",
    "crowd_gasp_extra": "The one approved gasp is a 20-person village reaction, far too small for a stadium.",
    "crowd_chant_extra": "Only 3 chant files, none football-specific (protest / basketball).",
}
cnt = Counter(g["category"] for g in gen)
for cat in sorted(cnt):
    A(f"| `{cat}` | {cnt[cat]} | {WHY.get(cat, '')} |")
A("")
A("Two categories needed a prompt-iteration wave (takes suffixed `_v2`), driven by")
A("measured spectral analysis rather than guesswork (`analyze_gen.py`):")
A("")
A("- **`kick_place`** — round 1 returned a median spectral centroid of 4.5-6.2 kHz:")
A("  thin, clicky, no ball behind it (one take was effectively DC). Re-prompted to")
A("  lead with low-end body and a *heavy* ball; round 2 landed 143-2145 Hz.")
A("- **`catch`** — round 1 was weak and sparse (-26 to -31 LUFS after normalisation).")
A("  Re-prompted for a *loud, hard* slap; round 2 landed -18 to -20 LUFS.")
A("- **`shouts`** grunts were also re-prompted deeper (3.3 kHz → ~2.1 kHz centroid).")
A("")
A("Both waves are kept in the review page so the user can A/B them.")
A("")

text = LIC.read_text()
head = text.split(MARK)[0].rstrip() if MARK in text else text.rstrip()
LIC.write_text(head + "\n\n" + "\n".join(L))
print(f"updated {LIC}: {len(approved)} approved rows, {len(gen)} generated takes, ~${cost:.2f}")
