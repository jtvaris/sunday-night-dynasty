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

---

## Music candidates

Exploratory only — **nothing in this section ships yet**. The question being
answered is whether open, commercially-licensed music models clear the
"SUNDAY NIGHT DYNASTY primetime broadcast" bar, or whether a paid service
(Suno Pro) is required. Review page: `review_music.html`. Generated
2026-08-03 by `generate_music.py`, mastered by `post_music.py`.

Everything is **instrumental** by construction — no vocals were requested and
ACE-Step was given its explicit `[instrumental]` lyrics marker.

### License gate

Every model in Replicate's `ai-music-generation` collection (17 entries) was
checked against one rule: **the weights must permit commercial use.** Verdicts
recorded 2026-08-03.

| Model | Weights licence | Verdict |
|---|---|---|
| `lucataco/ace-step` | Apache-2.0 | ✅ **USED** — no revenue cap, no attribution burden |
| `stackadoc/stable-audio-open-1.0` | Stability AI Community | ⚠️ **USED** — commercial only under $1M revenue (see caveat above) |
| `meta/musicgen` | CC-BY-NC 4.0 | ❌ rejected — non-commercial |
| `andreasjansson/musicgen-looper` | CC-BY-NC 4.0 | ❌ rejected — same `audiocraft` weights |
| `sakemin/musicgen-chord`, `-stereo-chord`, `-remixer` | CC-BY-NC 4.0 | ❌ rejected — same weights |
| `lucataco/magnet` | CC-BY-NC 4.0 | ❌ rejected — `audiocraft` weights, MIT code only |
| `google/lyria-2`, `minimax/music-*`, `elevenlabs/music`, `stability-ai/stable-audio-2.5` | closed weights, vendor ToS | ⊘ not evaluated — hosted paid services, not "open models"; revisit only if the open route fails |
| `zsxkib/flux-music`, `riffusion/riffusion` | — | ⊘ not evaluated — neither targets full-song broadcast music |

**The MusicGen family is disqualified as a class.** Its weights ship under
`LICENSE_weights` = *Creative Commons Attribution-NonCommercial 4.0*
(https://github.com/facebookresearch/audiocraft/blob/main/LICENSE_weights,
checked 2026-08-03). The MIT licence on the `audiocraft` *code* does not
extend to the weights — a genuinely easy trap, since the repo's headline
licence badge says MIT.

### ACE-Step — the full-song model

| Field | Value |
|---|---|
| Model | `lucataco/ace-step` (Replicate) |
| Version pinned | `280fc4f9ee507577f880a167f639c02622421d8fecf492454320311217b688f1` |
| Upstream weights | `ACE-Step/ACE-Step-v1-3.5B` (Hugging Face) |
| Licence | **Apache-2.0** |
| Evidence | HF model card metadata `license: apache-2.0` (card modified 2025-05-22); GitHub `ace-step/ACE-Step` LICENSE = Apache-2.0 (GitHub licence API, `spdx_id: Apache-2.0`) |
| Hardware / rate | Nvidia L40S, $0.000975 / sec |
| Takes | 6 (3 styles × 2) |
| GPU time | 45.2 s |
| Date checked | 2026-08-03 |

**No stale-licence trap here**, unlike the Stable Audio wrapper. The Replicate
model's `github_url` and `weights_url` point *directly* at the upstream
`ace-step/ACE-Step` repo and the `ACE-Step/ACE-Step-v1-3.5B` HF repo — there is
no intermediate cog wrapper carrying its own older licence file, so the
Apache-2.0 chain is unbroken from Replicate to weights.

Apache-2.0 is materially better than the Stable Audio position: **no revenue
cap**, so the menu themes carry no live obligation to re-check at funding
milestones. If only one of the two model families can ship, this is the one
with no strings.

**Output format caveat:** ACE-Step returns **MP3 (320 kbps)**, not WAV. Fine
for candidate review; if a take is chosen for the game it is a lossy master,
and it would be worth re-running the winning seed to see whether a WAV-capable
host or a local ACE-Step run can produce a lossless version of the same seed.

### Stable Audio Open — the ambient loops

Same model, version, licence and **$1M annual-revenue caveat** as the
Generated SFX section above — see *"⚠ Licence caveat"* there, it applies
verbatim to these loops. 4 takes, 22.4 s GPU.

### Cost

| Model | Takes | GPU time | Cost @ $0.000975/s |
|---|---|---|---|
| `lucataco/ace-step` | 6 | 45.2 s | $0.044 |
| `stackadoc/stable-audio-open-1.0` | 4 | 22.4 s | $0.022 |
| **Total** | **10** | **67.6 s** | **≈ $0.07** |

Replicate exposes no per-prediction cost field, so this is
`predict_time × published L40S rate`, summed over the 10 prediction IDs
recorded in `gen_music/manifest.json`. Budget was $3.

### Takes — seed and prompt

Reproducible from seed + prompt + the pinned version. Duration and LUFS are
measured on the mastered file (−16 LUFS / −1.5 dBTP, 48 kHz stereo).

**Menu themes — `lucataco/ace-step`, `duration=90`, `number_of_steps=60`,
`scheduler=euler`, `guidance_type=apg`, `guidance_scale=15`,
`tag_guidance_scale=5`, `lyrics="[instrumental]"`**

| File | Seed | Duration | LUFS | Prompt tags |
|---|---|---|---|---|
| `broadcast_anthem_take1` | 770101 | 87.5 s | −16.0 | epic sports broadcast theme, heroic brass fanfare, marching drumline, snare rolls, timpani, orchestral horns, cymbal swells, stadium anthem, triumphant, confident, building to a big finish, wide stereo, instrumental, no vocals, 140 BPM, D minor |
| `broadcast_anthem_take2` | 770102 | 88.8 s | −16.0 | primetime american football intro theme, bold brass stabs, military snare drumline, low brass ostinato, french horns, orchestral percussion, powerful, swaggering, broadcast package, crescendo to peak, instrumental, no vocals, 128 BPM, E minor |
| `dark_hybrid_take1` | 770201 | 89.9 s | −16.0 | dark hybrid cinematic, pulsing analog synth bass, taiko drums, cinematic percussion, tense string ostinato, brass swells, trailer tension and release, modern primetime sports, brooding, night game, instrumental, no vocals, 120 BPM, F minor |
| `dark_hybrid_take2` | 770202 | 88.7 s | −16.0 | hybrid orchestral electronic, driving synth bass pulse, industrial percussion hits, dark atmospheric pads, staccato strings, rising tension, epic drop, aggressive, sleek and modern, instrumental, no vocals, 130 BPM, A minor |
| `orchestral_cinematic_take1` | 770301 | 88.7 s | −16.0 | epic orchestral cinematic, sweeping legato strings, noble french horns, slow burn build, timpani, string ensemble, championship gravitas, majestic, emotional, film score, instrumental, no vocals, 90 BPM, C minor |
| `orchestral_cinematic_take2` | 770302 | 88.0 s | −16.0 | cinematic orchestral anthem, soaring string melody, heroic horn theme, deep low brass, orchestral timpani rolls, gradual crescendo to triumphant climax, legacy and dynasty, grand, sweeping, instrumental, no vocals, 100 BPM, G minor |

**Ambient loops — `stackadoc/stable-audio-open-1.0`, `seconds_total=47`,
`cfg_scale=7`, `steps=100`, `sampler_type=dpmpp-3m-sde`**, negative prompt
`vocals, singing, voice, lyrics, choir, speech, announcer, rapping, harsh,
distorted, clipping, sound effect, sudden silence`. Durations are post-trim
and post-loop-edit (a 2.0 s crossfade is folded back onto the head).

| File | Seed | Duration | LUFS | Prompt |
|---|---|---|---|---|
| `ambient_broadcast_take1` | 880201 | 45.5 s | −16.1 | ambient sports broadcast underscore, muted electric piano, soft pad wash, light brushed percussion, distant stadium crowd ambience, relaxed, professional, steady loop, instrumental |
| `ambient_cinematic_take1` | 880401 | 40.6 s | −16.2 | cinematic ambient bed, sustained warm string pad, slow pulse, subtle low percussion, restrained, moody, pre-game calm, evolving texture, steady loop, instrumental |
| `ambient_downtempo_take1` | 880301 | 44.7 s | −16.0 | downtempo lo-fi beat, dusty warm keys, soft kick and rim shot, vinyl texture, low-key confident, dark and moody, understated menu music, steady groove, instrumental |
| `ambient_lofi_take1` | 880101 | 45.5 s | −16.0 | lo-fi ambient underscore, soft warm synth pads, gentle brushed drums, subtle sub bass, mellow, understated, calm and spacious, steady unchanging loop, background music, instrumental |

### Loop-seam measurements

Wrap discontinuity = the sample-value jump between the last and first sample,
compared against the 99.9th-percentile jump the waveform already makes on its
own. Negative headroom means the wrap moves the signal *less* than the music
does anyway, i.e. no click is physically present. `lvl` is tail-minus-head RMS
over 200 ms.

| Loop | Headroom before | Headroom after | Verdict | lvl |
|---|---|---|---|---|
| `ambient_broadcast_take1` | +22.2 dB (click) | **−11.8 dB** | clean | +1.0 dB |
| `ambient_cinematic_take1` | +6.4 dB (click) | **−13.4 dB** | clean | −1.4 dB |
| `ambient_downtempo_take1` | −9.9 dB | **−33.4 dB** | clean | +7.8 dB ⚠ |
| `ambient_lofi_take1` | −4.8 dB | **−28.1 dB** | clean | −2.3 dB |

Two of the four had a genuine click at the raw wrap; the crossfade removed
both. `ambient_downtempo_take1` is click-free but its last 200 ms are 7.8 dB
**louder** than its first 200 ms — most likely a drum hit landing right on the
boundary. It will not tick, but it may audibly "drop" in level each time it
wraps, so it needs an ear before use.

---

## Music — round 2 (SHIPPED)

Round 1 was the experiment; this is the soundtrack. Generated 2026-08-03 by
`generate_music.py round2`, mastered by `post_music.py`, encoded and installed
by `ship_music.py`. Review page: `review_music_v2.html`.

**Licence position is unchanged from the round-1 section above** — same two
models, same pinned versions, same verdicts. ACE-Step is Apache-2.0 with no
revenue cap. Stable Audio Open is the Stability AI Community Licence and its
**$1M annual-revenue cap now applies to shipped game content**, not just to
experiments: seven of the 27 shipped files (the ambient loops) come from it.
That is a live obligation — see "⚠ Licence caveat" in the Generated SFX
section. The 20 ACE-Step files carry no such string.

### What round 2 set out to do

The user approved six of the ten round-1 takes by ear: both
`orchestral_cinematic`, both `dark_hybrid`, and the downtempo + lo-fi loops.
Round 2 therefore stopped exploring styles and deepened those two families at
broadcast length, added the situational cues the game was missing, and filled
each context to a depth where the rotation does not repeat inside a session.

**One calibration note is load-bearing.** Round 1 ranked its candidates by
structural proxies — late peak, wide dynamic arc, dark spectral centroid. The
take the user liked most, `dark_hybrid_take2`, ranked **last** on that
ordering: flattest arc in the set, brightest centroid, peak in the first
eighth. The heuristic was not measuring what the ear was listening for, so
round 2 does **not** prune or sort by it. It generates spread inside each
family and leaves the judgement to a listen. The metrics are still recorded
because they are nearly free and occasionally diagnose a real defect (a
runaway peak, a track that never moves), but they are no longer a gate.

| Model | Takes | GPU time | Cost @ $0.000975/s |
|---|---|---|---|
| `lucataco/ace-step` | 17 | 192.2 s | $0.187 |
| `stackadoc/stable-audio-open-1.0` | 5 | 26.5 s | $0.026 |
| **Total** | **22** | **218.7 s** | **≈ $0.21** |

Budget was $3; round 1 spent $0.07, so the two rounds together are ≈ $0.28.
Replicate exposes no per-prediction cost field, so this is
`predict_time × published L40S rate` summed over the prediction IDs recorded
in `gen_music/manifest.json`.

**Output format, recorded per the brief:** ACE-Step returns **320 kbps MP3**,
not WAV — the model offers no lossless output on this Replicate wrapper. Every
ACE-Step file in the shipped set is therefore lossy at source, and the AAC
ship encode is a second generation. This was accepted deliberately: the
material is background music played under UI at −16 LUFS, the artefacts of a
320 kbps source are not audible at that role, and the alternative was a paid
service. Stable Audio Open returns WAV, so the seven ambient loops are lossy
only once (at the ship encode). If a track is ever promoted to a foreground
role, re-run its seed on a WAV-capable host first.

### Round-2 takes — seed and prompt

Reproducible from seed + prompt + the pinned version. `Requested` is the
duration asked of the model; `Duration` is the mastered file after dead-air
trim. ACE-Step's own ceiling is 240 s (schema-verified), and nothing here sits
near it — every second costs ~20 KB of app bundle.

| File | Seed | Requested | Duration | LUFS | Prompt tags |
|---|---|---|---|---|---|
| `cue_championship_take1` | 970502 | 110 s | 106.5 s | -16.0 | triumphant orchestral climax, full brass fanfare, soaring string melody, timpani rolls and cymbal crashes, victory celebration, confetti and lifted trophy, majestic and joyous, peaks early and holds, instrumental, no vocals, 104 BPM, C major |
| `cue_draft_room_take1` | 970501 | 105 s | 104.8 s | -16.0 | tense underscore, ticking clock, restrained muted percussion, pizzicato strings, low sustained drone, sparse piano notes, nervous anticipation, deadline pressure, war room, minimal and taut, no big climax, instrumental, no vocals, 100 BPM, A minor |
| `cue_draft_room_take2` | 970503 | 100 s | 99.9 s | -16.0 | tense minimal underscore, metronome tick, muted staccato strings, soft heartbeat kick, cold synth drone, rising unease, clock winding down, restrained, no melody, instrumental, no vocals, 92 BPM, E minor |
| `cue_draft_room_take3` | 970504 | 98 s | 96.2 s | -16.0 | suspense underscore, ticking percussion, col legno strings, low piano ostinato, sparse marimba, held breath tension, decision under pressure, understated and nervous, instrumental, no vocals, 108 BPM, C sharp minor |
| `dark_hybrid_r2_aggro` | 970404 | 156 s | 155.9 s | -16.0 | aggressive hybrid trailer music, distorted synth bass, hard hitting industrial percussion, brass braams, metallic impacts, gritty and confrontational, relentless drive, epic drop, instrumental, no vocals, 135 BPM, A minor |
| `dark_hybrid_r2_atmos` | 970403 | 172 s | 171.2 s | -16.0 | dark ambient hybrid score, evolving synth pads, distant low drones, sparse sub bass pulse, occasional cinematic hit, spacious and atmospheric, slow drifting tension, minimal percussion, empty stadium at night, instrumental, no vocals, 76 BPM, D minor |
| `dark_hybrid_r2_crossover` | 970405 | 160 s | 159.9 s | -16.0 | hybrid orchestral electronic crossover, sweeping legato strings over a pulsing analog synth bass, cinematic taiko and timpani, noble french horns against electronic percussion, epic and modern, tension and release, primetime dynasty, instrumental, no vocals, 118 BPM, C minor |
| `dark_hybrid_r2_drive` | 970402 | 152 s | 151.2 s | -16.0 | hybrid orchestral electronic, fast driving synth arpeggio, tight electronic drums, propulsive sixteenth note bass pulse, staccato string stabs, urgent momentum, modern primetime sports, instrumental, no vocals, 145 BPM, G minor |
| `dark_hybrid_r2_slow` | 970401 | 166 s | 166.0 s | -16.0 | dark hybrid cinematic, slow pulsing analog synth bass, half-time cinematic drums, deep sub bass, sparse metallic percussion, patient tension build, brooding night game, wide reverb, instrumental, no vocals, 92 BPM, F minor |
| `gameday_build_take1` | 970701 | 150 s | 146.4 s | -16.0 | aggressive hybrid pregame build, pounding synth bass, stadium drumline over electronic drums, rising brass swell, hard impacts, adrenaline, walk out of the tunnel, builds relentlessly to kickoff, instrumental, no vocals, 128 BPM, D minor |
| `menu_theme_r2_take1` | 970601 | 92 s | 89.6 s | -16.0 | definitive sports management main menu theme, warm legato strings, noble horn statement, soft timpani, understated drumline, confident but calm, loops comfortably under a menu, never fatiguing, broadcast prestige, instrumental, no vocals, 86 BPM, F major |
| `orchestral_cinematic_r2_brass` | 970303 | 162 s | 160.6 s | -16.0 | epic orchestral cinematic, heroic french horn theme, trombone and tuba power chords, brass fanfare peaks, string bed underneath, timpani hits, triumphant summits and quiet valleys, stadium grandeur, instrumental, no vocals, 96 BPM, E flat major |
| `orchestral_cinematic_r2_dark` | 970305 | 152 s | 149.9 s | -16.0 | dark orchestral cinematic, brooding low strings, ominous cellos and double bass, muted brass, sparse timpani, minor key tension, cold and serious, rivalry week, foreboding build, instrumental, no vocals, 88 BPM, B minor |
| `orchestral_cinematic_r2_noble` | 970304 | 168 s | 164.8 s | -16.0 | noble restrained orchestral score, gentle string ensemble, solo french horn melody, soft woodwinds, sparse piano, dignified and understated, quiet confidence, never bombastic, hall of fame reverence, instrumental, no vocals, 80 BPM, A major |
| `orchestral_cinematic_r2_percussive` | 970301 | 158 s | 157.8 s | -16.0 | epic orchestral cinematic, driving orchestral percussion, taiko drums, timpani ostinato, snare rolls, staccato low strings, brass punctuation, relentless forward momentum, percussion forward mix, championship gravitas, instrumental, no vocals, 110 BPM, C minor |
| `orchestral_cinematic_r2_strings` | 970302 | 176 s | 173.3 s | -16.0 | cinematic string orchestra, no percussion, sustained legato violins, warm cello counter-melody, slow burn build, patient and emotional, film score, restrained opening then soaring, dynasty legacy, instrumental, no vocals, 72 BPM, D minor |
| `playoffs_dark_take1` | 970801 | 150 s | 147.6 s | -16.0 | dark tense cinematic, tremolo strings, low brass swells, sparse war drums, cold and high stakes, one game to survive, creeping dread with a defiant peak, january football, instrumental, no vocals, 84 BPM, F sharp minor |

| File | Seed | Duration | LUFS | Fold (xfade/tail-cut) | Seam | Head−tail | Prompt |
|---|---|---|---|---|---|---|---|
| `ambient_downtempo_r2_take2` | 980301 | 44.5 s | -16.0 | 2.0 / 0.0 s | clean (-44.9 dB) | +0.1 dB | downtempo lo-fi beat, dusty rhodes chords, soft kick and rim shot, warm tape saturation, vinyl crackle, low-key confident, steady unchanging groove, understated menu music, instrumental |
| `ambient_downtempo_r2_take3` | 980302 | 44.5 s | -16.0 | 3.0 / 0.0 s | clean (-16.5 dB) | +0.0 dB | downtempo instrumental underscore, muted upright bass, brushed drums, dark warm keys, subtle vinyl texture, moody and patient, constant level, no build, background loop, instrumental |
| `ambient_downtempo_r2_take4` | 980303 | 44.5 s | -16.1 | 2.0 / 0.0 s | clean (-14.4 dB) | +1.3 dB | slow downtempo underscore, mellow electric piano, soft brushed kick, deep warm bass, vinyl dust, unhurried and reflective, steady groove, background loop, instrumental |
| `ambient_lofi_r2_take2` | 980101 | 46.0 s | -16.0 | 1.5 / 0.0 s | clean (-11.8 dB) | -0.1 dB | lo-fi ambient underscore, soft warm analog pads, gentle brushed drums, mellow electric piano, subtle sub bass, calm and spacious, steady unchanging loop, no dynamic swells, background music, instrumental |
| `ambient_lofi_r2_take3` | 980102 | 45.0 s | -16.0 | 2.0 / 0.0 s | clean (-24.3 dB) | +1.8 dB | soft lo-fi ambient bed, hazy tape pads, very light percussion, warm muted guitar, slow and reflective, quiet offseason, steady unchanging loop, background music, instrumental |

### The loop head-vs-tail fix

Round 1 shipped `ambient_downtempo_take1` with a click-free wrap whose last
200 ms were **7.8 dB louder** than its first 200 ms — it would not tick, but
it would audibly *drop* in level on every wrap. A step-free seam is necessary
but not sufficient.

`post_music.py` now treats the crossfade point as a free parameter and
searches it. Where you fold the tail back decides which two moments of the
take end up adjacent, so if the default fold lands on a drum hit, another fold
will not. The search walks a grid of (crossfade length × tail cut), keeps the
smallest head-vs-tail delta that still has a clean seam and stays above the
40 s floor, and **tries the round-1 fold first** — so a loop that already
passed is left byte-identical rather than silently re-cut.

Every shipped loop is now under the 3 dB rule, including the approved round-1
downtempo bed, which was re-pointed from +7.8 dB to +2.7 dB. That file is the
same take and the same seed; only the loop start moved.

| Loop | Round | Baseline fold Δ | Chosen fold | Chosen Δ | Re-pointed |
|---|---|---|---|---|---|
| `ambient_broadcast_take1` | r1 | +1.0 dB | 2.0 / 0.0 s | +1.0 dB | no |
| `ambient_cinematic_take1` | r1 | -1.4 dB | 2.0 / 0.0 s | -1.4 dB | no |
| `ambient_downtempo_take1` | r1 | +7.8 dB | 1.0 / 1.5 s | +2.7 dB | **yes** |
| `ambient_lofi_take1` | r1 | -2.3 dB | 2.0 / 0.0 s | -2.3 dB | no |
| `ambient_downtempo_r2_take2` | r2 | +0.1 dB | 2.0 / 0.0 s | +0.1 dB | no |
| `ambient_downtempo_r2_take3` | r2 | +0.4 dB | 3.0 / 0.0 s | +0.0 dB | **yes** |
| `ambient_downtempo_r2_take4` | r2 | +1.3 dB | 2.0 / 0.0 s | +1.3 dB | no |
| `ambient_lofi_r2_take2` | r2 | +3.2 dB | 1.5 / 0.0 s | -0.1 dB | **yes** |
| `ambient_lofi_r2_take3` | r2 | +1.8 dB | 2.0 / 0.0 s | +1.8 dB | no |

Two round-2 loops were also re-pointed, but for the *seam* rather than the
level: their baseline fold had a measurable click, and the search found a
clean one.

### Shipped set

Delivery format is **AAC-LC 160 kbps, 48 kHz stereo**, mastered to −16 LUFS /
−1.5 dBTP like everything else. Not the 16-bit WAV the SFX ship as: the SFX
are one-shots measured in milliseconds, whereas the music is 48 minutes long,
and at WAV that would be ~500 MB of app download. AVAudioPlayer decodes m4a
with hardware assist, so a long track costs no more CPU than a wav.

Shipping all 28 candidates came to 62.9 MB against a 60 MB budget. Per the
brief's rule — trim track count before quality — one track was held back
rather than re-encoding the set lower: `orchestral_cinematic_r2_percussive`,
from the only context (playoffs) carrying more than it was speced for. It
stays in `gen_music/` and is the swap-in if one of the shipped playoff cues is
rejected.

27 files, 48.6 min, **59.7 MB** (AAC-LC 160 kbps, 48 kHz stereo).

| Ship name | Context | Source take | Round | Model | Seed | Dur | LUFS | Size |
|---|---|---|---|---|---|---|---|---|
| `music_menu_theme_a.m4a` | menu | `orchestral_cinematic_take1` | r1 | ace-step | 770301 | 89 s | -16.0 | 1.80 MB |
| `music_menu_theme_b.m4a` | menu | `orchestral_cinematic_take2` | r1 | ace-step | 770302 | 88 s | -16.1 | 1.79 MB |
| `music_menu_theme_c.m4a` | menu | `menu_theme_r2_take1` | r2 | ace-step | 970601 | 90 s | -16.1 | 1.84 MB |
| `music_dashboard_loop_a.m4a` | dashboard | `ambient_downtempo_take1` | r1 | stable-audio-open | 880301 | 44 s | -16.1 | 0.94 MB |
| `music_dashboard_loop_b.m4a` | dashboard | `ambient_lofi_take1` | r1 | stable-audio-open | 880101 | 46 s | -16.0 | 0.99 MB |
| `music_dashboard_loop_c.m4a` | dashboard | `ambient_downtempo_r2_take2` | r2 | stable-audio-open | 980301 | 45 s | -16.0 | 0.99 MB |
| `music_dashboard_loop_d.m4a` | dashboard | `ambient_downtempo_r2_take3` | r2 | stable-audio-open | 980302 | 45 s | -16.0 | 0.92 MB |
| `music_dashboard_loop_e.m4a` | dashboard | `ambient_lofi_r2_take2` | r2 | stable-audio-open | 980101 | 46 s | -16.0 | 0.93 MB |
| `music_dashboard_bed_a.m4a` | dashboard | `orchestral_cinematic_r2_strings` | r2 | ace-step | 970302 | 173 s | -16.0 | 3.51 MB |
| `music_dashboard_bed_b.m4a` | dashboard | `orchestral_cinematic_r2_noble` | r2 | ace-step | 970304 | 165 s | -16.1 | 3.38 MB |
| `music_dashboard_bed_c.m4a` | dashboard | `dark_hybrid_r2_slow` | r2 | ace-step | 970401 | 166 s | -16.1 | 3.40 MB |
| `music_dashboard_bed_d.m4a` | dashboard | `dark_hybrid_r2_atmos` | r2 | ace-step | 970403 | 171 s | -16.0 | 3.56 MB |
| `music_draft_a.m4a` | draft | `cue_draft_room_take1` | r2 | ace-step | 970501 | 105 s | -16.0 | 2.14 MB |
| `music_draft_b.m4a` | draft | `cue_draft_room_take2` | r2 | ace-step | 970503 | 100 s | -16.1 | 2.05 MB |
| `music_draft_c.m4a` | draft | `cue_draft_room_take3` | r2 | ace-step | 970504 | 96 s | -16.0 | 1.98 MB |
| `music_gameday_a.m4a` | gameday | `dark_hybrid_take1` | r1 | ace-step | 770201 | 90 s | -16.0 | 1.86 MB |
| `music_gameday_b.m4a` | gameday | `dark_hybrid_take2` | r1 | ace-step | 770202 | 89 s | -16.1 | 1.80 MB |
| `music_gameday_c.m4a` | gameday | `dark_hybrid_r2_aggro` | r2 | ace-step | 970404 | 156 s | -16.1 | 3.20 MB |
| `music_gameday_d.m4a` | gameday | `dark_hybrid_r2_drive` | r2 | ace-step | 970402 | 151 s | -16.1 | 3.07 MB |
| `music_gameday_e.m4a` | gameday | `gameday_build_take1` | r2 | ace-step | 970701 | 146 s | -16.1 | 2.97 MB |
| `music_playoffs_a.m4a` | playoffs | `orchestral_cinematic_r2_dark` | r2 | ace-step | 970305 | 150 s | -16.0 | 3.04 MB |
| `music_playoffs_b.m4a` | playoffs | `dark_hybrid_r2_crossover` | r2 | ace-step | 970405 | 160 s | -16.1 | 3.25 MB |
| `music_playoffs_c.m4a` | playoffs | `playoffs_dark_take1` | r2 | ace-step | 970801 | 148 s | -16.0 | 3.03 MB |
| `music_championship_a.m4a` | championship | `cue_championship_take1` | r2 | ace-step | 970502 | 106 s | -16.1 | 2.18 MB |
| `music_championship_b.m4a` | championship | `orchestral_cinematic_r2_brass` | r2 | ace-step | 970303 | 161 s | -16.1 | 3.25 MB |
| `music_offseason_loop_a.m4a` | offseason | `ambient_lofi_r2_take3` | r2 | stable-audio-open | 980102 | 45 s | -16.0 | 0.91 MB |
| `music_offseason_loop_b.m4a` | offseason | `ambient_downtempo_r2_take4` | r2 | stable-audio-open | 980303 | 45 s | -16.1 | 0.90 MB |

**Generated but not shipped:** `orchestral_cinematic_r2_percussive` — kept in `gen_music/` as candidates.

Playback is `MusicDirector.swift` (`dynasty/dynasty/UI/Common/`): one player
at a time, a shuffled no-repeat bag per context, a randomised silence gap
between tracks (30-90 s on the dashboard), its own `musicEnabled` /
`musicVolume` settings, and a hard suspend during the live coached game so the
crowd bed and play SFX own the mix.
