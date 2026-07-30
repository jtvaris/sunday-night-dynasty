# Face age variants (TODO §5.8) — pilot report and decision

Status: **pilot done, plumbing shipped, full run NOT run — waiting on one human look.**
Spent so far: **$0.17** of the ~$12 cap (57 FLUX-schnell calls incl. retries).

## The problem

The face library paints every person exactly once, at the age his bucket says.
Player bands top out at `30-36`; coach bands at `50-68`. A career runs 20+
seasons, so a save reliably ends up with 35-year-old receivers wearing the
portrait drawn for a 22-year-old and a 68-year-old head coach who has not gone
grey. It is the one place the portrait layer visibly contradicts a number the
same screen is showing.

## What was built

| piece | path | state |
|---|---|---|
| generator | `tools/faces/generate_aged.py` | done, resume-safe, `--dry-run` prints the plan + cost |
| pilot images | `tools/faces/raw_aged/` (47 PNGs) | done |
| packaged HEICs | `tools/faces/out/AgedFaces/` (47, 740 kB) | done, **not** copied into the bundle |
| pilot manifest | `tools/faces/out/aged_faces_manifest.json` | done |
| review sheet | `tools/faces/out/review_aged.html` | source-left / aged-right pairs |
| Swift catalog | `dynasty/dynasty/Domain/Models/Faces/AgedFaceCatalog.swift` | done, inert until the manifest ships |
| render switch | `PersonFaceView.init(player:)` / `init(coach:)` | done |

Thresholds: **player 34+**, **coach 62+** (`AgedFaceCatalog.playerAgeThreshold` /
`coachAgeThreshold`). One step, not a per-year ladder — two portraits per person
is the cheapest thing that removes the contradiction, and every further step
multiplies the whole pool again.

The swap is **render-time only**. `player.faceID` keeps the original id forever:
the claim registry, the retirement cooldown and every duplicate check key on it.
Pull the aged manifest out of the bundle and every portrait is byte-for-byte what
it was.

## Technique, and its ceiling

A variant reuses the source's **seed** and its whole prompt except the age clause,
which is rewritten by table (`AGE_REWRITES`). FLUX schnell is text-to-image, not
an editing model, so this is the honest description of what it buys:

* **bucket continuity — excellent.** Same backdrop, lighting, framing, wardrobe,
  crop, skin tone, build, hairstyle family, facial-hair family.
* **identity continuity — partial.** Same seed plus a mostly-identical prompt
  keeps the composition, but facial geometry drifts.

## Pilot: 48 coach ids, stratified

Selection is proportional over (gender, ageBand, tone) — a `--limit` sample has
to look like the population, not like its first N ids. 47 of 48 landed (one
Replicate delivery URL 404'd three times).

### Criteria set before looking, and the verdict

| # | criterion | bar | measured | verdict |
|---|---|---|---|---|
| 1 | style/bucket continuity | ≥ 95 % | 47/47 — backdrop, lighting, wardrobe, crop, tone, build all carried; hairstyle family carried on 45/47 | **PASS** |
| 2 | reads as clearly older | ≥ 90 % | 47/47 — grey/silver plus lines in every pair | **PASS** |
| 3 | reads as the SAME person | ≥ 2/3 | ~55 % by eye | **FAIL** |
| 4 | no artifact, no wrong gender, no wrong ethnicity | 100 % | 47/47 clean; 0 gender errors, 0 tone errors | **PASS** |
| 5 | cost inside the cap | ≤ $12 | $0.17 for the pilot; $2.4 / $4.4 / $11.1 for the three full-run scopes | **PASS** |

Criterion 3 is the whole decision and it is a **taste call, not a technical one**:

* Against it — a player who remembers his head coach's face will notice the man
  change somewhere around season 8.
* For it — the user never sees the two side by side. The swap happens between
  seasons, on a 30–56 pt circle, and the thing it replaces is a 68-year-old with
  a 45-year-old's face. Football Manager regenerates faces as players age and
  nobody files it as a bug.

So: **`tools/faces/out/review_aged.html` is the deliverable that decides this.**
Open it, look at 47 pairs, and answer one question — does the man on the right
read as the man on the left, ten years on, often enough?

If the answer is no, the fix is not more prompt engineering: it is an
identity-preserving model (FLUX Kontext / PuLID / InstantID img2img seeded with
the source PNG). That is a different pipeline and a different price point, and
`generate_aged.py`'s backend seam is where it would go.

## Full-run scopes, if it is a yes

| scope | ids | cost | added bundle |
|---|---|---|---|
| coaches only (`--role coach`) | 788 | ~$2.4 | ~10 MB |
| coaches + the `30-36` player band | 1 468 | ~$4.4 | ~18 MB |
| everything (`--role all`) | 3 712 | ~$11.1 | ~46 MB |

Recommended if approved: **coaches only.** It is the case §5.8 actually names, a
34-year-old player is not visually old, and it is a fifth of the bundle cost.
The current face payload is 47 MB for 3 830 HEICs — `--role all` doubles it.

## Installing (do NOT do this before the look above)

```sh
cd tools/faces
python3 generate_aged.py --role coach            # ~$2.4, resume-safe
python3 generate_aged.py --package
cp out/AgedFaces/*.heic          ../../dynasty/dynasty/Resources/Faces/
cp out/aged_faces_manifest.json  ../../dynasty/dynasty/Resources/Faces/
```

`Resources/Faces/` is a filesystem-synchronized group, so no `project.pbxproj`
edit is needed.

**One blocking dependency, and it is in a file this work did not own.**
`FaceBundleAudit.run()` cross-checks physical HEICs against what the catalogs
claim and reports the remainder as orphans — it knows `FaceLibrary` and
`ExtrasCatalog`, not `AgedFaceCatalog`. Dropping aged HEICs in without teaching
it the third catalog turns the audit red *by design*. See the handoff:

> `FaceBundleAudit`: claim `AgedFaceCatalog.shared.entries` into the same
> `claimed` set the extras use, add `agedImages=`/`agedCatalogCount=` counters,
> and extend the orphan culprit message with the `aged_` prefix
> (`AgedFaceCatalog.isAgedID`) the way it already splits out
> `ExtrasCatalog.isExtraID`.

## Side finding, already fixed

`tools/faces/generate_faces.py` could not reach Replicate at all: Cloudflare
rejects the default `Python-urllib/3.x` user agent with `403 / error code: 1010`
before the request reaches the API, so a valid token failed exactly like a
missing one. Both `http_json` and `fetch` now send a UA. Verified 403 → 200 on
`/v1/account` with the same token.
