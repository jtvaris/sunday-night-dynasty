# Game Audio — source bundles & licensing

This file is the **audio provenance ledger** for Sunday Night Dynasty.

> **Rule: every audio file shipped in the app must be listed in this file.**
> If a sound is in `dynasty/dynasty/Resources/` (or any shipped bundle) and it is
> not recorded here with its source library and license, it does not ship.
> Add the entry in the same commit that adds the asset.

**Download date:** 2026-07-31
**Total downloaded:** 28.80 GB across 13 zips (all verified with `unzip -t`)
**Licensor for everything below:** Sonniss Ltd. — https://sonniss.com/
**License text:** https://sonniss.com/gdc-bundle-license/

---

## Bundle 1 — Sonniss #GameAudioGDC 2026 (the current bundle)

Complete: all 5 of 5 parts, 6.92 GB. Nothing skipped — the bundle came in well
under the 40 GB download cap.

| Part | Bytes | Verified |
|---|---:|---|
| `Sonniss.com-GDC2026-GameAudioBundle1of5.zip` | 1,301,592,146 | size + `unzip -t` |
| `Sonniss.com-GDC2026-GameAudioBundle2of5.zip` | 1,418,237,636 | size + `unzip -t` |
| `Sonniss.com-GDC2026-GameAudioBundle3of5.zip` | 1,490,753,131 | size + `unzip -t` |
| `Sonniss.com-GDC2026-GameAudioBundle4of5.zip` | 1,853,924,113 | size + `unzip -t` |
| `Sonniss.com-GDC2026-GameAudioBundle5of5.zip` | 856,448,992 | size + `unzip -t` |

## Bundle 2 — supplemental Sonniss GDC archive years

The 2026 bundle alone produced **zero** candidates for crowd_boo, chant, kick and
catch, and only one crowd_cheer — it is heavy on vehicles, industrial and glitch
libraries. To fill those gaps I listed the contents of all 78 archived Sonniss
zips *remotely* (without downloading them), sieved the filenames, and pulled only
the 8 highest-value parts. Same licensor, same license as Bundle 1.

| Zip | Bytes | Pulled for |
|---|---:|---|
| `Sonniss.com - GDC - Game Audio Bundle 2of5.zip` (2015) | 2,063,874,022 | catch |
| `Sonniss.com - GDC - Game Audio Bundle 3of5.zip` (2015) | 2,035,602,886 | whoosh, impacts |
| `Sonniss.com - GDC - Game Audio Bundle 4of5.zip` (2015) | 1,759,988,269 | crowd cheer, whistle |
| `Sonniss.com - GDC 2016- Game Audio Bundle Part 1of6.zip` | 2,162,829,410 | kick, impacts, gasp |
| `Sonniss.com - GDC 2017 - Game Audio Bundle Part 7of9.zip` | 2,425,417,848 | boo, chant |
| `Sonniss.com - GDC 2019 - Game Audio Bundle Part 7of8.zip` | 3,796,478,954 | crowd cheer, chant |
| `Sonniss.com - GDC 2020 - Game Audio Bundle Part1of14.zip` | 3,898,252,486 | gasp, shouts, whistle |
| `Sonniss.com - GDC 2020 - Game Audio Bundle Part11of14.zip` | 3,735,542,443 | boo, chant, cheer, beds |

## Note on the download source

`downloads.sonniss.com` is behind a Cloudflare JS challenge ("Just a moment...")
that a headless client cannot pass, and the Google Drive mirror linked from
gdc.sonniss.com returns *"Quota exceeded — too many users have viewed or
downloaded this file recently."* Everything was therefore pulled from the
Internet Archive item [`sonniss.com-gdc-game-audio-bundles`](https://archive.org/details/sonniss.com-gdc-game-audio-bundles),
which hosts the identical files over plain HTTP with byte-range resume.

**The 2026 part sizes were checked against the official Google Drive
`content-length` values and match exactly for all five parts**, so the payload is
bit-identical to the official release. Every zip additionally passes `unzip -t`.

`download_bundle.sh` in this folder reproduces the download.

### Known extraction gaps

Two folders failed to extract because their names contain non-UTF-8 bytes that
macOS `unzip` rejects (`Illegal byte sequence`). Neither is football-relevant, so
they were not chased down:

- `Blik Blinks - SIGNUM… Sci-fi Cinematic SFX Pack` (GDC 2016 part 1of6)
- `Sonic Bat … Ambisonics - Village` (GDC 2020 part 11of14)

---

## License summary (Sonniss GDC Bundle license)

Sonniss releases the GDC bundle under a **royalty-free commercial license**:

- **Commercial use is permitted.** "Licensee may use and modify the licensed
  sound effects for personal and commercial projects **without attribution** to
  the original creator."
- **Unlimited projects, perpetual.** "Licensee may use the licensed sound effects
  on an unlimited number of projects for the entirety of their life time."
- **Synchronization rights** for "games, films, television & interactive
  projects" — which covers shipping them inside Sunday Night Dynasty.
- **Royalty-free** — no ongoing fees, no revenue share.
- **No attribution required** (we keep this ledger anyway, for our own audit trail).

**Prohibited — read before shipping:**

- **No reselling the sounds as-is.** "Licensee may not sell any of the sound
  effects as they come." Shipping them *inside a game* is fine; shipping them as
  a sound pack is not.
- **No claiming authorship** of the original recordings.
- **No AI training.** "The Licensee is expressly prohibited from using any sound
  effects licensed under this Agreement for the purpose of training artificial
  intelligence technologies."
  **→ These files must never be fed to ElevenLabs (or any model) as training,
  cloning, or voice-conversion input.** Bespoke audio generated to fill the gaps
  below must be produced from scratch, not derived from bundle content.

Each publisher inside the bundle ships its own `LICENSE`/`README` in its folder
(plus `License - GDC Game Audio.pdf` at each bundle root). Those are consistent
with the umbrella license above; if we ever ship a file from a library with
unusual terms, record the exception in the table below.

---

## SHIPPED — `dynasty/dynasty/Resources/Audio/`

**Status: SHIPPED.** These are the exact files inside the app bundle. Every one
is rendered by `tools/audio/ship_audio.py`, which is the only thing allowed to
write this folder — delete a file and re-run the script to get it back
bit-identical. The `Window from source` column is the trim the script applies,
so any entry can be traced back to the mastered source in `approved/` or `gen/`
and from there to its Sonniss original or its generation seed.

Two licence families are in play, both already analysed in full below:

- **Sonniss GDC bundle** — royalty-free commercial use, no attribution
  required, no reselling as sound packs, no AI-training use. See
  *License summary* above.
- **Stability AI Community License** (Stable Audio Open 1.0) — free for
  commercial use under 1 M USD annual revenue; model **output** is explicitly
  not a Derivative Work. See *Generated SFX* below, including the note about
  the wrapper repo's stale non-commercial `LICENSE_MODEL` file.
- **Original work** — three procedural cues from
  `tools/asset-pipeline/generate_audio.sh` (ffmpeg sine/noise chains) that the
  recorded set had no replacement for. `snap` and `td_horn` are still
  triggered; `crowd_loop` is the bed fallback in `AudioDirector.preload()`.

### Format policy

16-bit PCM WAV at 48 kHz throughout (the three procedural leftovers stay at
their original 44.1 kHz — `AVAudioPlayer` makes no format assumption, see
`AudioDirector.assetURL` / `preload`). Channel count is chosen per role against
the 25 MB budget: **one-shot SFX mono** (point-source transients, stereo buys
nothing on a 0.3 s thud), **crowd reactions stereo** (the width is the whole
reason for using real stadium captures), **crowd bed mono** (biggest file by
far, plays at 15–60 % of master under everything, where centre placement is
inaudible — trading its width is what keeps the reactions stereo).

### Retired in this pass

`catch_pop.wav`, `hit_big.wav`, `hit_light.wav`, `kick_thump.wav`,
`whistle.wav` and `crowd_swell.wav` were procedural placeholders fully
superseded by recorded takes. `ship_audio.py` deletes them on every run.

| Shipped file | Dur | Ch | KB | Window from source | Source | Licence |
|---|---:|---:|---:|---|---|---|
| `sfx_catch_1.wav` | 0.35s | 1 | 33 | 0.00–0.35s | Stable Audio Open 1.0, seed `20316989` (`catch_take2_v2`) | Stability AI Community |
| `sfx_catch_2.wav` | 0.40s | 1 | 38 | 0.00–0.40s | Stable Audio Open 1.0, seed `20371669` (`catch_take3`) | Stability AI Community |
| `sfx_catch_3.wav` | 0.30s | 1 | 28 | 0.00–0.30s | Stable Audio Open 1.0, seed `20379588` (`catch_take4`) | Stability AI Community |
| `sfx_catch_4.wav` | 0.35s | 1 | 33 | 0.00–0.35s | Stable Audio Open 1.0, seed `20395426` (`catch_take6`) | Stability AI Community |
| `sfx_kick_place_1.wav` | 0.45s | 1 | 42 | 0.00–0.45s | Stable Audio Open 1.0, seed `20316236` (`kick_place_take2`) | Stability AI Community |
| `sfx_kick_place_2.wav` | 0.40s | 1 | 38 | 0.00–0.40s | Stable Audio Open 1.0, seed `20324155` (`kick_place_take3`) | Stability AI Community |
| `sfx_kick_place_3.wav` | 0.45s | 1 | 42 | 0.00–0.45s | Stable Audio Open 1.0, seed `20347912` (`kick_place_take6`) | Stability AI Community |
| `sfx_kick_punt_1.wav` | 0.45s | 1 | 42 | 0.00–0.45s | Stable Audio Open 1.0, seed `20260803` (`kick_punt_take1`) | Stability AI Community |
| `sfx_kick_punt_2.wav` | 0.35s | 1 | 33 | 0.00–0.35s | Stable Audio Open 1.0, seed `20276641` (`kick_punt_take3`) | Stability AI Community |
| `sfx_throw_1.wav` | 0.40s | 1 | 38 | 0.00–0.40s | Stable Audio Open 1.0, seed `20427102` (`throw_whoosh_take4`) | Stability AI Community |
| `sfx_throw_2.wav` | 0.30s | 1 | 28 | 0.00–0.30s | Stable Audio Open 1.0, seed `20442940` (`throw_whoosh_take6`) | Stability AI Community |
| `sfx_tackle_1.wav` | 0.45s | 1 | 42 | 0.00–0.45s | Stable Audio Open 1.0, seed `20450859` (`tackle_impact_take1`) | Stability AI Community |
| `sfx_tackle_2.wav` | 0.60s | 1 | 56 | 0.00–0.60s | Stable Audio Open 1.0, seed `20466697` (`tackle_impact_take3`) | Stability AI Community |
| `sfx_whistle_1.wav` | 0.95s | 1 | 89 | 0.00–0.95s | Stable Audio Open 1.0, seed `20545887` (`whistle_take5`) | Stability AI Community |
| `sfx_cadence_1.wav` | 3.05s | 1 | 286 | 0.00–3.05s | Stable Audio Open 1.0, seed `20577563` (`shouts_cadence1`) | Stability AI Community |
| `sfx_grunt_1.wav` | 0.40s | 1 | 38 | 0.00–0.40s | Stable Audio Open 1.0, seed `20601320` (`shouts_grunt1`) | Stability AI Community |
| `sfx_grunt_2.wav` | 0.30s | 1 | 28 | 0.00–0.30s | Stable Audio Open 1.0, seed `20617158` (`shouts_grunt3`) | Stability AI Community |
| `crowd_cheer_1.wav` | 5.60s | 2 | 1050 | 0.00–5.60s | Sonniss GDC 2019 p7of8 — 2496SoundEffects - Surround At The Show 1 — `Crowd Cheering Interior Short Swell 2, The Forum Stadium, Applause _STEREO.wav` | Sonniss GDC bundle |
| `crowd_cheer_2.wav` | 7.10s | 2 | 1332 | 0.45–7.55s | Sonniss GDC 2019 p7of8 — 2496SoundEffects - Surround At The Show 1 — `Crowd Cheering Exterior, Big Surge, Rose Bowl Stadium, Applause _5.1.wav` | Sonniss GDC bundle |
| `crowd_cheer_3.wav` | 5.80s | 2 | 1088 | 154.20–160.00s | Sonniss GDC 2019 p7of8 — 2496SoundEffects - Surround At The Show 1 — `Crowd Cheering Exterior, Close Cheers, Encore Call, Rose Bowl Stadium, Applause _5.1.wav` | Sonniss GDC bundle |
| `crowd_boo_1.wav` | 6.20s | 2 | 1163 | 11.60–17.80s | Sonniss GDC 2020 p11of14 — Sonic Bat - Soccer Stadium Ambience — `SBssa_Crowd Booing 002.wav` | Sonniss GDC bundle |
| `crowd_boo_2.wav` | 5.50s | 2 | 1031 | 1.20–6.70s | Stable Audio Open 1.0, seed `20625077` (`crowd_boo_extra_take1`) | Stability AI Community |
| `crowd_boo_3.wav` | 5.70s | 2 | 1069 | 0.30–6.00s | Stable Audio Open 1.0, seed `20632996` (`crowd_boo_extra_take2`) | Stability AI Community |
| `crowd_boo_4.wav` | 5.80s | 2 | 1088 | 0.70–6.50s | Stable Audio Open 1.0, seed `20640915` (`crowd_boo_extra_take3`) | Stability AI Community |
| `crowd_gasp_1.wav` | 4.20s | 2 | 788 | 0.20–4.40s | Sonniss GDC 2020 p1of14 — Articulated Sounds - Bali Ubud Village Ambiences — `CROWD Reaction, Small Applause 03, 20 People, Bali, Indonesia.wav` | Sonniss GDC bundle |
| `crowd_gasp_2.wav` | 2.80s | 2 | 525 | 0.25–3.05s | Stable Audio Open 1.0, seed `20656753` (`crowd_gasp_extra_take1`) | Stability AI Community |
| `crowd_gasp_3.wav` | 3.80s | 2 | 713 | 0.40–4.20s | Stable Audio Open 1.0, seed `20680510` (`crowd_gasp_extra_take4`) | Stability AI Community |
| `crowd_chant_1.wav` | 8.00s | 2 | 1500 | 8.00–16.00s | Sonniss GDC 2020 p11of14 — Sonic Bat - Soccer Stadium Ambience — `SBssa_Crowd Chanting 019.wav` | Sonniss GDC bundle |
| `crowd_chant_2.wav` | 5.20s | 2 | 975 | 1.80–7.00s | Stable Audio Open 1.0, seed `20696348` (`crowd_chant_extra_take2`) | Stability AI Community |
| `crowd_chant_3.wav` | 5.00s | 2 | 938 | 1.20–6.20s | Stable Audio Open 1.0, seed `20704267` (`crowd_chant_extra_take3`) | Stability AI Community |
| `crowd_bed_talking.wav` | 80.00s | 1 | 7500 | 32.00–112.00s + 3s loop x-fade | Sonniss GDC 2020 p11of14 — Sonic Bat - Soccer Stadium Ambience — `SBssa_Crowd Talking 010.wav` | Sonniss GDC bundle |
| `crowd_loop.wav` | 8.00s | 1 | 689 | — (unchanged) | Procedural — `tools/asset-pipeline/generate_audio.sh` (ffmpeg sine/noise) | Original work |
| `snap.wav` | 0.12s | 1 | 10 | — (unchanged) | Procedural — `tools/asset-pipeline/generate_audio.sh` (ffmpeg sine/noise) | Original work |
| `td_horn.wav` | 1.38s | 1 | 119 | — (unchanged) | Procedural — `tools/asset-pipeline/generate_audio.sh` (ffmpeg sine/noise) | Original work |

**Total shipped audio: 21.98 MB** across 34 files (budget 25 MB).

---

## Approved & mastered (round 1)

These are the seven files the user approved from `review_audio.html`. All are
Sonniss GDC bundle content, so the umbrella licence above applies verbatim:
**royalty-free commercial use, no attribution required, no reselling as sound**
**packs, no AI-training use.**

Mastering applied (`process_approved.py`): 5.1 sources folded to stereo with an
explicit ITU-R BS.775 pan matrix, EBU R128 two-pass loudnorm to **-18 LUFS /**
**-1.5 dBTP**, 48 kHz stereo, full duration preserved. Each ships as 16-bit PCM
wav (the format `AudioDirector` already loads) with a 24-bit `.master.wav`
archive and an `.m4a` review preview alongside.

> **5.1 channel-order note.** The two Rose Bowl files are tagged
> `_5.1 LCRLsRsLf`, i.e. **L C R Ls Rs LFE** — *not* ffmpeg's default
> `FL FR FC LFE BL BR`. A plain `-ac 2` would fold the centre channel into the
> right speaker and treat left-surround as LFE. Verified before trusting the
> filename: channel 5 measures ~-54 dB RMS against ~-25 dB on the others, which
> is unmistakably the LFE. The pan matrix in `process_approved.py` is correct;
> do not 'simplify' it back to `-ac 2`.

| Mastered file | Category | Source library | Bundle | Source | LUFS in → out | True peak |
|---|---|---|---|---|---|---|
| `approved/crowd_bed/crowd_bed_talking.wav` | `crowd_bed` | Sonic Bat - Soccer Stadium Ambience | Sonniss GDC 2020 part 11of14 | 2ch / 96 kHz / 128.0s | -41.3 → -18.0 LUFS | -1.5 dBTP |
| `approved/crowd_boo/crowd_boo_stadium.wav` | `crowd_boo` | Sonic Bat - Soccer Stadium Ambience | Sonniss GDC 2020 part 11of14 | 2ch / 96 kHz / 25.2s | -24.6 → -18.0 LUFS | -1.5 dBTP |
| `approved/crowd_chant/crowd_chant_stadium.wav` | `crowd_chant` | Sonic Bat - Soccer Stadium Ambience | Sonniss GDC 2020 part 11of14 | 2ch / 96 kHz / 67.0s | -26.2 → -18.0 LUFS | -1.5 dBTP |
| `approved/crowd_cheer/crowd_cheer_forum_swell.wav` | `crowd_cheer` | 2496SoundEffects - Surround At The Show 1 5.1 | Sonniss GDC 2019 part 7of8 | 2ch / 96 kHz / 6.3s | -21.7 → -18.0 LUFS | -3.2 dBTP |
| `approved/crowd_cheer/crowd_cheer_rosebowl_encore.wav` | `crowd_cheer` | 2496SoundEffects - Surround At The Show 1 5.1 | Sonniss GDC 2019 part 7of8 | 6ch / 96 kHz / 160.1s | -23.7 → -18.0 LUFS | -1.5 dBTP |
| `approved/crowd_cheer/crowd_cheer_rosebowl_surge.wav` | `crowd_cheer` | 2496SoundEffects - Surround At The Show 1 5.1 | Sonniss GDC 2019 part 7of8 | 6ch / 96 kHz / 10.9s | -18.3 → -18.0 LUFS | -6.5 dBTP |
| `approved/crowd_gasp/crowd_gasp_reaction.wav` | `crowd_gasp` | Articulated Sounds - Bali Ubud Village Ambiences | Sonniss GDC 2020 part 1of14 | 2ch / 96 kHz / 12.3s | -22.8 → -18.9 LUFS | -1.5 dBTP |

Original filenames (for tracing back into `extracted/`):

- `crowd_bed_talking` ← `SBssa_Crowd Talking 010.wav`
- `crowd_boo_stadium` ← `SBssa_Crowd Booing 002.wav`
- `crowd_chant_stadium` ← `SBssa_Crowd Chanting 019.wav`
- `crowd_cheer_forum_swell` ← `Crowd Cheering Interior Short Swell 2, The Forum Stadium, Applause _STEREO.wav`
- `crowd_cheer_rosebowl_encore` ← `Crowd Cheering Exterior, Close Cheers, Encore Call, Rose Bowl Stadium, Applause _5.1 LCRLsRsLf.wav`
- `crowd_cheer_rosebowl_surge` ← `Crowd Cheering Exterior, Big Surge, Rose Bowl Stadium, Applause _5.1 LCRLsRsLf.wav`
- `crowd_gasp_reaction` ← `CROWD Reaction, Small Applause 03, 20 People, Bali, Indonesia.wav`

---

## Generated SFX

Everything the Sonniss archive could not serve was generated from scratch with
a text-to-audio model. **No bundle audio was used as input**, which keeps us
clear of the Sonniss no-AI-training clause quoted above.

| Field | Value |
|---|---|
| Model | `stackadoc/stable-audio-open-1.0` (Replicate) |
| Version pinned | `9aff84a639f96d0f7e6081cdea002d15133d0043727f849c40abdd166b7c75a8` |
| Upstream weights | `stabilityai/stable-audio-open-1.0` (Hugging Face) |
| Licence | **Stability AI Community License** |
| Licence text | https://stability.ai/community-license-agreement |
| Hardware / rate | Nvidia L40S, $0.000975 / sec |
| Takes generated | 77 (73 kept for review, rest are pilots) |
| Total GPU time | 413.1 s |
| Total cost | ~$0.40 |
| Date | 2026-08-03 |

### ⚠ Licence caveat — the $1M annual-revenue cap

The Stability AI Community License permits **commercial use, royalty-free,
only while you or your affiliates generate under USD $1,000,000 in annual
revenue** (any revenue, not just revenue derived from the model). Verbatim:

> *If at any time You or Your Affiliate(s), either individually or in
> aggregate, generate more than USD $1,000,000 in annual revenue (or the
> equivalent thereof in Your local currency), regardless of whether that
> revenue is generated directly or indirectly from the Stability AI Materials
> or Derivative Works, any licenses granted to You under this Agreement shall
> terminate as of such date.*

**→ If Sunday Night Dynasty (or Brew Crow as a whole) ever crosses $1M annual
revenue, an Enterprise licence must be obtained from Stability AI, or these
generated files must be replaced.** Register at https://stability.ai/license.
This is a live obligation, not a one-off check — re-read it at each funding or
revenue milestone.

**Also recorded, because it is a genuine trap:** the Replicate wrapper repo
`github.com/stackadoc/cog-stable-audio` still ships a `LICENSE_MODEL` file
containing the *older* **Stability AI NON-COMMERCIAL Research Community**
**License** (dated 2024-06-05), under which shipping these sounds in a paid
game would **not** be permitted. That file is a stale snapshot of the terms at
the model's launch. Stability subsequently relicensed the upstream weights:
`stabilityai/stable-audio-open-1.0` on Hugging Face declares
`license_name: stable-audio-community` (model card last modified 2025-06-19),
and the same applies to `stable-audio-open-small`. **We rely on the upstream
Community License, not the wrapper repo's stale file.** If this is ever
challenged, the evidence is the Hugging Face model-card metadata.

Model outputs themselves are not claimed by Stability — the licence covers the
Materials and Derivative Works, and explicitly excludes model output from the
definition of a Derivative Work. Shipping the generated `.wav` files inside the
game is distribution of *output*, not of the model.

### Generated categories

Prompts, seeds and per-take loudness live in `gen/manifest.json`; the raw
47 s model returns plus a JSON sidecar per take are in `gen_raw/` so any take
is reproducible from its seed. The user picked 24 of these from
`review_audio_v2.html` (`selections_round2.tsv`); the ones that actually ship,
and the seed behind each, are listed in **SHIPPED** above.

| Category | Takes | Why generated rather than sourced |
|---|---|---|
| `catch` | 12 | 3 hits, all apparel foley (bracelet, leather jacket). No ball-into-hands catch. |
| `crowd_boo_extra` | 4 | Only 2 usable boo files archive-wide — not enough variation for a season. |
| `crowd_chant_extra` | 4 | Only 3 chant files, none football-specific (protest / basketball). |
| `crowd_gasp_extra` | 4 | The one approved gasp is a 20-person village reaction, far too small for a stadium. |
| `kick_place` | 12 | Same gap as `kick_punt` — no placekick/tee impact exists in the archive. |
| `kick_punt` | 6 | Only 2 keyword hits archive-wide, both motorcycle kick-starts. No ball-kick recording in any Sonniss year. |
| `shouts` | 9 | Male-voice hits were announcer VO or animal grunts; no snap-cadence or lineman effort. |
| `tackle_impact` | 8 | Archive impacts are all melee/weapon or vehicle; no pad-on-pad body collision. |
| `throw_whoosh` | 6 | Generic whooshes exist but none read as a short QB release; cheaper to generate than to sift. |
| `whistle` | 8 | Archive whistles are train/kettle/sports-hall; no clean isolated referee pea whistle. |

Two categories needed a prompt-iteration wave (takes suffixed `_v2`), driven by
measured spectral analysis rather than guesswork (`analyze_gen.py`):

- **`kick_place`** — round 1 returned a median spectral centroid of 4.5-6.2 kHz:
  thin, clicky, no ball behind it (one take was effectively DC). Re-prompted to
  lead with low-end body and a *heavy* ball; round 2 landed 143-2145 Hz.
- **`catch`** — round 1 was weak and sparse (-26 to -31 LUFS after normalisation).
  Re-prompted for a *loud, hard* slap; round 2 landed -18 to -20 LUFS.
- **`shouts`** grunts were also re-prompted deeper (3.3 kHz → ~2.1 kHz centroid).

Both waves are kept in the review page so the user can A/B them.
