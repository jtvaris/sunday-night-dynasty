#!/usr/bin/env python3
"""Stage-2 Job 1 — master the user-approved Sonniss crowd files.

Reads selections_round1.tsv, and for each approved source:

  * downmixes 5.1 -> stereo with an EXPLICIT pan matrix. These files carry a
    "_5.1 LCRLsRsLf" suffix, i.e. channel order L C R Ls Rs LFE, which is NOT
    ffmpeg's default FL FR FC LFE BL BR — a plain `-ac 2` would fold the centre
    channel into the right speaker and treat the left surround as LFE. Verified
    per-channel before trusting the filename: ch5 measures -54 dB RMS against
    ~-25 dB on the others, which is the LFE, so the suffix is accurate.
  * normalises to -18 LUFS with a -1.5 dBTP ceiling using one linear gain
    (see audio_common.gain_plan) — no compression, the beds keep their dynamics.
  * keeps full duration (beds/swells; ducking is AudioDirector's job).
  * writes 48 kHz stereo ship-wav / master-wav / preview-m4a.

Emits approved/manifest.json.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

import audio_common as ac

ROOT = Path(__file__).resolve().parent
OUT_ROOT = ROOT / "approved"

# c0=L c1=C c2=R c3=Ls c4=Rs c5=LFE -> ITU-R BS.775 stereo fold-down.
# LFE is dropped: it is redundant sub energy and measures ~-54 dB RMS here.
PAN_51 = ("pan=stereo"
          "|c0=c0+0.707*c1+0.707*c3"
          "|c1=c2+0.707*c1+0.707*c4")

NAMES = {
    "Crowd Cheering Interior Short Swell 2, The Forum Stadium, Applause _STEREO.wav":
        "crowd_cheer_forum_swell",
    "Crowd Cheering Exterior, Big Surge, Rose Bowl Stadium, Applause _5.1 LCRLsRsLf.wav":
        "crowd_cheer_rosebowl_surge",
    "Crowd Cheering Exterior, Close Cheers, Encore Call, Rose Bowl Stadium, Applause _5.1 LCRLsRsLf.wav":
        "crowd_cheer_rosebowl_encore",
    "SBssa_Crowd Booing 002.wav": "crowd_boo_stadium",
    "SBssa_Crowd Chanting 019.wav": "crowd_chant_stadium",
    "CROWD Reaction, Small Applause 03, 20 People, Bali, Indonesia.wav":
        "crowd_gasp_reaction",
    "SBssa_Crowd Talking 010.wav": "crowd_bed_talking",
}

# Source library per file, for the licence ledger.
LIBRARY = {
    "crowd_cheer_forum_swell": ("2496SoundEffects - Surround At The Show 1 5.1", "Sonniss GDC 2019 part 7of8"),
    "crowd_cheer_rosebowl_surge": ("2496SoundEffects - Surround At The Show 1 5.1", "Sonniss GDC 2019 part 7of8"),
    "crowd_cheer_rosebowl_encore": ("2496SoundEffects - Surround At The Show 1 5.1", "Sonniss GDC 2019 part 7of8"),
    "crowd_boo_stadium": ("Sonic Bat - Soccer Stadium Ambience", "Sonniss GDC 2020 part 11of14"),
    "crowd_chant_stadium": ("Sonic Bat - Soccer Stadium Ambience", "Sonniss GDC 2020 part 11of14"),
    "crowd_gasp_reaction": ("Articulated Sounds - Bali Ubud Village Ambiences", "Sonniss GDC 2020 part 1of14"),
    "crowd_bed_talking": ("Sonic Bat - Soccer Stadium Ambience", "Sonniss GDC 2020 part 11of14"),
}


def main() -> None:
    rows = []
    with (ROOT / "selections_round1.tsv").open() as fh:
        for cat, rel in csv.reader(fh, delimiter="\t"):
            rows.append((cat, ROOT / rel))

    manifest = []
    for cat, src in rows:
        if not src.exists():
            print(f"!! MISSING {src}")
            continue
        name = NAMES[src.name]
        info = ac.probe(src)
        pre = PAN_51 if info["channels"] == 6 else None

        raw_meas = ac.measure(src)                 # untouched source
        folded = ac.measure(src, pre)              # after the downmix
        plan = ac.master_chain(src, pre)           # loudnorm + corrective trim

        files = ac.encode_set(src, OUT_ROOT / cat, name, plan["chain"])

        ship = Path(files["ship_wav_16bit"])
        after = ac.measure(ship)
        out_info = ac.probe(ship)
        lib, bundle = LIBRARY[name]

        manifest.append({
            "category": cat, "name": name,
            "source_rel": str(src.relative_to(ROOT)),
            "source_file": src.name,
            "source_library": lib, "source_bundle": bundle,
            "source": info,
            "downmix": ("5.1 (L C R Ls Rs LFE) -> stereo, ITU-R BS.775, LFE dropped"
                        if pre else "native stereo, no downmix"),
            "in_LUFS": raw_meas.get("I"), "in_TP_dBTP": raw_meas.get("TP"),
            "downmixed_LUFS": folded.get("I"), "downmixed_TP_dBTP": folded.get("TP"),
            "correction_db": plan["correction_db"],
            "out_LUFS": after.get("I"), "out_TP_dBTP": after.get("TP"),
            "out_LRA": after.get("LRA"), "out": out_info,
            "files": {k: str(Path(v).relative_to(ROOT)) for k, v in files.items()},
        })
        print(f"[ok] {cat:12s} {name:28s} {info['channels']}ch/{info['sample_rate']//1000}k "
              f"{info['duration']:7.2f}s  {raw_meas.get('I')} -> {after.get('I')} LUFS  "
              f"TP {after.get('TP')} dBTP  (corr {plan['correction_db']:+.2f} dB)")

    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"\nwrote {OUT_ROOT/'manifest.json'} ({len(manifest)} files)")


if __name__ == "__main__":
    main()
