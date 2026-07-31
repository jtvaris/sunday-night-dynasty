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

## Shipped files

Nothing has been shipped yet. Selection happens after the user reviews
`review_audio.html`; staged candidates in `staging/` are **not** shipped assets,
and nothing has been copied into `dynasty/dynasty/Resources/`.

| Shipped path | Category | Original filename | Source library | Bundle | Notes |
|---|---|---|---|---|---|
| _(none yet)_ | | | | | |

---

## Bespoke audio (non-bundle)

Categories the Sonniss archive genuinely cannot serve — these need to be created.
Record the tool and the prompt/session so provenance is reconstructible.

| Category | Why bespoke | Shipped path | Tool | Date |
|---|---|---|---|---|
| `kick` | Only 2 keyword hits in the whole archive and both are *motorcycle kick-starts*. No ball-kick/punt recording exists in any Sonniss year. | _(pending)_ | | |
| `catch` | 3 hits, all apparel foley (bracelet, leather jacket). No ball-into-hands/glove catch. | _(pending)_ | | |
| `crowd_boo` | Only 2 usable files archive-wide; likely needs more variations. | _(pending)_ | | |
| `chant` | Only 3 files, none football-specific (protest / basketball crowd). | _(pending)_ | | |
