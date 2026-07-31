# Face age variants (TODO §5.8) — pilot, prompt fix, full run

Status: **shipped.** One aged variant for **every** id in the face pool — 3 712
of 3 712, 100 % coverage — packaged into the bundle, wired through
`AgedFaceCatalog` and measured by `FaceBundleAudit`. Spend: 3 712 paid images at
FLUX-schnell rates = **$11.14**, plus a few hundred re-rolls lost to backend
flakiness (upper bound $1.1, most of the failures were free 404/429s on the
create endpoint) — **≤ $12.3 against a $15 cap**.

## The problem

The face library paints every person exactly once, at the age his bucket says.
Player bands top out at `30-36`; coach bands at `50-68`. A career runs 20+
seasons, so a save reliably ends up with 35-year-old receivers wearing the
portrait drawn for a 22-year-old and a 68-year-old head coach who has not gone
grey. It is the one place the portrait layer visibly contradicts a number the
same screen is showing.

## What ships

| piece | path |
|---|---|
| generator | `tools/faces/generate_aged.py` (resume-safe, `--dry-run` prints plan + cost) |
| source renders | `tools/faces/raw_aged/` (gitignored, ~3.3 GB) |
| packaged HEICs | `tools/faces/out/AgedFaces/` → `dynasty/dynasty/Resources/Faces/` |
| manifest | `aged_faces_manifest.json` (bundle root after flattening) |
| review sheet | `tools/faces/out/review_aged.html` — source-left / aged-right pairs |
| Swift catalog | `dynasty/dynasty/Domain/Models/Faces/AgedFaceCatalog.swift` |
| render switch | `PersonFaceView.init(player:)` / `init(coach:)` |
| audit | `FaceBundleAudit` — `agedManifest=`/`agedImages=`/`coverage=`/`dangling=` |

Thresholds: **player 34+**, **coach 62+** (`AgedFaceCatalog.playerAgeThreshold` /
`coachAgeThreshold`). One step, not a per-year ladder — two portraits per person
is the cheapest thing that removes the contradiction, and every further step
multiplies the whole pool again.

The swap is **render-time only**. `player.faceID` keeps the original id forever:
the claim registry, the retirement cooldown and every duplicate check key on it.
Pull the aged manifest out of the bundle and every portrait is byte-for-byte what
it was.

## Technique, and its ceiling

A variant reuses the source's **seed** and its whole prompt except the age
clause, which is rewritten by table (`AGE_REWRITES`). FLUX schnell is
text-to-image, not an editing model, so this is the honest description of what it
buys:

* **bucket continuity — excellent.** Same backdrop, lighting, framing, wardrobe,
  crop, skin tone, build, hairstyle family, facial-hair family.
* **identity continuity — good on players, partial on coaches.** A player variant
  is one decade older and reads as the same man almost always; a coach variant is
  1–2 decades older and reads as the same man roughly 7 times in 10. The residual
  failure is nearly always the same one: a source with a *very* short cut
  (buzz/shaved) comes back with more hair than it started with.

## Pilot v1 → the prompt bug → v2

The 47-image v1 pilot failed its identity criterion (~55 % by eye). The cause was
not the model's ceiling, it was the rewrite table. v1 put the grey in the AGE
clause — `"in his late sixties, silver gray hair, weathered face…"` — and that
clause sits *before* the hairstyle token `build_spec` appended. In FLUX it beat
it, three ways at once:

| source | v1 result |
|---|---|
| `buzz cut` (`face_00080`) | full silver mane |
| `bald head` (`face_01507`) | hair grew back |
| dark-skinned + short hair (`face_00008`, `face_00195`) | several shades lighter — a silver mane is a white-coded feature in the model's prior, and it dragged the skin with it |

**v2** (`PROMPT_VERSION = 2`) states no hair volume in the age clause at all and
greys the source's own hairstyle token in place instead (`HAIR_AGE`), so the cut
survives the decade and `bald head` stays bald.

Measured on 200 random coach pairs, median skin-tone drift is **+1.1 luma**
(v1's black-tone bucket was +3.1), and only 8/200 shift lighter by more than 15
luma. Remaining known weakness: a *very* short cut (buzz/shaved) still tends to
come back with more hair than it started with, and one source that had rendered
off-prompt (`face_01735`, painted from a "white American man" prompt but rendered
dark-skinned) snapped back to its prompt in the variant.

A manifest carrying a different `promptVersion` now aborts the run rather than
resuming into a pool aged two different ways.

## The full run

| pass | ids | notes |
|---|---|---|
| v2 pilot (`--role coach --limit 48`) | 47 | proportional sample over (gender, ageBand, tone) |
| coaches (`--role coach`) | 788 | |
| player pilot (`--role player --limit 48`) | 48 | |
| everything (`--role all`) | 3 712 | 100 % of the pool |

Bundle cost: **52 MB** of aged HEICs on top of the 47 MB main pool —
`Resources/Faces/` goes 47 MB → 100 MB, 3 830 → 7 543 files. 384², HEIC quality
80, the same treatment `package_faces.py` gives the main pool.

### The thing that will bite the next run: Replicate's low-credit throttle

Once the account drops below **$5 of credit**, Replicate cuts prediction creates
to **6 per minute with a burst of 1** and says so in the 429 body. Throughput
went from ~68 images/min to 5.8 — the last 750 images took two hours, and no
amount of parallelism helps (`--workers 12` and `--workers 2` are identical under
the throttle; 2 is quieter). **Top the account up above $5 before starting a
sweep of this size.**

Two side effects of a run that long, both now handled:

* The manifest is written once, at the end. A killed sweep left ~2 300 *paid*
  images on disk that no manifest listed and resume could not see. `--reconcile`
  adopts them (the entry is a pure function of the source manifest + rewrite
  table, so nothing is guessed).
* `--package` now converts with 8 parallel `sips` processes; 3 712 serial spawns
  was a coffee break for no reason.

### Two backend bugs found and fixed on the way (`generate_faces.py`)

Both were costing money and images, and both hit the main generator too:

1. **`replicate.delivery` 404s** for a second or two on a fraction of freshly
   returned URLs. The prediction is already paid for, so `fetch` now retries the
   *download* with backoff instead of letting the caller re-roll the image.
2. **`Prefer: wait` is a courtesy, not a guarantee** — it returns `processing`
   with no output on a fraction of calls, which the old code raised as "empty
   output" and answered with a second, full-price prediction. `gen_replicate` now
   polls the prediction URL instead.
3. The create endpoint itself 404s intermittently under sustained parallel load
   (~1 call in 6 during the 741-image coach sweep). A 404 means nothing was
   created, so the POST is retried — it cannot double-charge.
4. 429 gets its own budget and honours `Retry-After` (see the throttle note
   below); a 1.5 s backoff cannot outlast a 9 s reset, so every worker used to
   burn its attempts and fail the id while still hammering the endpoint.

Before the fixes: 10 hard failures in 48 images. After: 0 in 30, and 0 in the
final 137-image sweep.

## Installing (already done; here for the next re-run)

```sh
cd tools/faces
python3 generate_aged.py --role all --workers 2   # resume-safe; re-run until todo=0
python3 generate_aged.py --reconcile              # only after an interrupted run
python3 generate_aged.py --package
cp out/AgedFaces/*.heic          ../../dynasty/dynasty/Resources/Faces/
cp out/aged_faces_manifest.json  ../../dynasty/dynasty/Resources/Faces/
```

`Resources/Faces/` is a filesystem-synchronized group, so no `project.pbxproj`
edit is needed.

## Verifying

`FaceBundleAudit` (DEBUG, `FACE_BUNDLE_AUDIT=1`) now claims the aged catalog into
the same `claimed` set the extras use and prints:

```
FACEBUNDLE: agedManifest=bundle-root agedImages=3712/3712 coverage=100.0% of pool dangling=0 (aged_face_* variants, player 34+ / coach 62+)
```

It fails on the three states that would silently degrade the feature: an aged
manifest that is bundled but does not decode, aged HEICs with no manifest (they
land in the orphan check with an `aged_faces_manifest.json missing or stale`
culprit), and `dangling` — an aged entry naming a source id the main catalog does
not have, which means the two manifests were packaged from different generations
of the pool.

## If the identity drift is ever judged too much

The fix is not more prompt engineering — v2 is close to what a text-to-image
model can do from a prompt alone. It is an identity-preserving img2img pass
(FLUX Kontext / PuLID / InstantID) seeded with the source PNG. That is a
different price point (~$0.025/image ⇒ ~$90 for this pool, 8× the cap this run
was given) and `generate_aged.py`'s backend seam is where it would go.
