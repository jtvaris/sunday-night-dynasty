# Face Generation Plan (Phase 4) — realistic portraits for every person

Goal: realistic face portraits for all persons (players, coaches, scouts,
prospects — including every future draft class), deterministic and offline at
runtime. Approach: **pre-generated face library** with tag-bucketed
deterministic assignment. No runtime generation (cost, latency, offline,
App-Store review risk).

## 1. Library design

- **Pool size v1: 2,048 faces** (1,664 player-age + 384 coach/staff-age).
  *Superseded — see §6: the measured split is 1 672/376 and the pool is now
  2 560 (2 048 + a 512-id reserve range).*
  A 30-season career touches ~13k persons; reuse is handled by a cooldown
  (a face frees when its person leaves the league; reassignment allowed after
  ≥2 further seasons — no two ACTIVE persons ever share a face in one career).
  Pool can be extended later (append-only manifest, ids stable).
- **Buckets (tags per face):** role (player/coach) · ageBand (20-24 / 25-29 /
  30-36 / 38-50 / 50-68) · tone (editorial approximation of NFL demographics:
  ~55 % Black, ~28 % White, ~7 % Latino, ~4 % Pacific Islander, ~6 % mixed/
  other; coaches skew older with own distribution) · build (lean / athletic /
  heavy — heavy overweighted for OL/DL assignment). Buckets are assignment
  *hints*, never displayed.
- **Style constants** (every image): sports media-day headshot, head-and-
  shoulders, facing camera, neutral expression, plain dark-gray studio
  backdrop, soft even lighting, plain dark athletic top (coaches: plain polo),
  85 mm look, photorealistic. **No** text/logos/jersey branding, single
  person, adults only, "generic person, not resembling any public figure".
- **Format:** generated at 768², shipped at 384² HEIC (~25-30 kB) →
  ~55-65 MB total. Ship as an asset folder; move to On-Demand Resources if
  size becomes an issue. Detail views upscale 384² acceptably on iPad.

## 2. Assignment (Swift, deterministic)

- `FaceLibrary` loads `faces_manifest.json` (id, tags, filename).
- Person → face: at person creation, pick from the matching bucket
  (role/ageBand from person age; tone uniform-weighted by pool composition;
  build from position group) using seeded hash(personID) over the FREE faces
  of that bucket; persist `faceID` on Player/Coach (`String? = nil`, inline
  default — lightweight migration). Career keeps an in-use registry +
  cooldown queue (JSON blob on Career).
- Template leagues: faceIDs pre-assigned by the transform tool (same bucket
  logic, fixed seed) so the fixed league always shows identical faces.
- Legacy saves: backfill lazily at load (sentinel nil → assign once).
- Aging: v1 static face per person (acceptable; face is an identity anchor).
  v2 option: 2 age variants per face id.

## 3. Generation pipeline (`tools/faces/`)

- `generate_faces.py` — backend-pluggable batch generator. Backends:
  `replicate` (FLUX schnell, ~$0.003/img → ~$8 for 2k — RECOMMENDED),
  `fal` (FLUX), `gemini` (Imagen 3 via AI Studio key, ~$0.03/img → ~$65),
  `openai` (gpt-image-1), `vertex` (gcloud token). Prompt matrix from the
  bucket plan + per-image variation (face shape, hair, facial hair, seed);
  resume-safe (manifest-driven), concurrency 4, retries 3, every image
  validated (non-empty, decodes, min dimensions).
- `package_faces.py` — center-crop, resize to 384², HEIC via `sips`,
  exact-duplicate hash check, `faces_manifest.json`, and `review.html`
  contact sheet for human QA.
- **Pilot gate:** generate 24 samples across buckets → user approves the look
  BEFORE the full run. After the full run: contact-sheet sweep to cull
  artifacts/lookalikes (target cull rate <5 %, regenerate culled ids).
- **The cull loop is executable** (verified 2026-07-30 on a stub-backend copy):
  `culled.json` is the PENDING list, and `generate_faces.py` drops those ids
  from `manifest.json` (renaming the artifact to `<id>.png.culled`) so resume
  regenerates them from the same `(seed, id)` bucket, then clears each id from
  `culled.json` once its replacement lands. Until then `package_faces.py` keeps
  skipping the id — a culled artifact never ships, and a culled id is never
  silently lost. (Before this, the re-run was a no-op: resume skipped exactly
  the ids the sweep asked to redo.) A culled id that has NOT been regenerated
  simply drops out of the shipped catalog; `FaceLibrary.backfill` treats an
  unresolvable id like a missing one and re-draws, so nobody is stranded on a
  permanent silhouette.

## 4. Legal / safety notes

- AI-generated synthetic faces of non-existent people; prompts forbid
  resemblance to public figures. Cull anything that reads as a specific real
  person during review. Check chosen backend's commercial-use license terms
  (FLUX schnell: Apache-2.0 outputs OK; Imagen/OpenAI: commercial use per
  ToS).
- Faces are decorative identity anchors — never imply any real person.

## 5. Integration points (Swift wave — AFTER the league-integration workflow
finishes, to avoid conflicts)

`FaceLibrary` + `PersonFaceView` (rounded portrait, team-color ring, size
variants) → PlayerDetailView header · roster rows (small) · prospect cards +
Big Board · draft-day panels · coach views/staff list · news items (where a
person is the subject) · HOF/retirement ceremonies.

**Placeholders are per-person, not one shared glyph.** The zero-image state is
the current state AND a shipping state (the reserve range has no pictures), so a
single silhouette would make 53 roster rows identical — strictly worse than the
avatars the app had before the wave. `PersonFacePlaceholder`: players fall back
to the procedural `PlayerAvatarView` (UUID-derived helmet/skin/facemask), coaches
to one of the 20 bundled `coach_m*/coach_f*` photos (picked with
`FaceLibrary.stableHash`, not `String.hashValue` — that is seeded per process and
changed the photo on every launch), prospects to an initials monogram on an
id-tinted disc, and the bare silhouette is left for callers that only have a
face id (news items, HOF rows). The user's own GM+HC row uses the avatar picked
in the new-career wizard (`Career.avatarID`).

**Image loading is bounded and off the main thread.** `FaceImageCache` decodes
via `CGImageSourceCreateThumbnailAtIndex` at 288 px (the largest call site,
`.large` 96 pt at 3×) inside a detached task, and caches with a byte cost against
a 16 MB `totalCostLimit`. A count-only limit of 160 full-size bitmaps was ~90 MB
of RAM to draw 30 pt circles, and the synchronous `UIImage(contentsOfFile:)`
decode landed ~3.8 ms in the frame that scrolled each new row into view.

## 6. Status / blockers

- Pipeline scripts: DONE. **Swift core: DONE** (`FaceCatalog.swift`,
  `FaceLibrary.swift`, `PersonFaceView.swift` + `faceID` on Player/Coach/
  CollegeProspect and `Career.faceRegistryData`). UI wiring (§5 call sites) is
  the next wave.
- **The Swift side does not depend on the images existing.** When
  `faces_manifest.json` is absent the catalog is synthesized from the generator
  seed by a bit-exact CPython `random.Random` port — verified against every
  face generated so far (721/721 buckets identical, re-checked from the Python
  side by `make_templates.py` gate 19 on every template build). A missing HEIC
  renders a silhouette, so a bundle may legitimately ship the manifest before
  (or without) the pictures.
- **Template leagues ship their faces.** `tools/league-data/make_templates.py`
  bakes a `faceID` onto every player and every named coach of both profiles
  (§2 "Template leagues"), and `LeagueTemplateImporter` writes it straight onto
  the model. This is not an optimisation: the importer mints a fresh `UUID()`
  per person on every import and the runtime picker hashes exactly that UUID,
  so a fixed league that assigned at runtime would show different portraits
  every time it was created. Gate 19 (`face-preassignment`) enforces
  uniqueness, role correctness and the bucket-match floors; the determinism
  harness carries `faceID` in its player/coach fingerprints.
- **Pool arithmetic correction to §1 — the pool is 2 560, not 2 048.** The seed
  yields 1 672 player-age and 376 coach-age faces in the `--count 2048` range,
  while a random league is 1 696 players + 512 coaches and the *fixed 2026
  template* is 1 807 players + 512 coaches. "No two active persons share a
  face" is impossible inside 2 048. Decision (2026-07-29): keep uniqueness and
  extend the library with a 512-id **reserve range**,
  `face_02048`-`face_02559`, produced by
  `python3 tools/faces/generate_faces.py --count 2560` (ids are stable and the
  manifest is append-only, so the 2 048 already generated are untouched).
  - `make_templates.py` pre-assigns every template person a unique face and
    hands the reserve ids to its 135 least visible players (the whole `depth`
    tier + the 13 lowest-rated backups), so the pictures that land last belong
    to the people nobody looks at.
  - `FaceLibrary.pickLocked` treats the reserve as a **last resort**: free
    generated id → free reserve id → reuse inside the role → (degenerate
    catalog only) cross-role. A random league therefore never leaves the
    generated range, and no league reuses a portrait while an unused one
    exists. Within each stage the ladder is exact bucket → same age band, any
    build → any face of the role.
  - **Open:** the reserve images are not generated yet. Until that run, those
    135 template players (and anyone the runtime pushes into the reserve)
    render the placeholder silhouette — which is the designed behaviour for a
    missing HEIC, not a defect.
- **Prospects and coach candidates do not reserve faces.** A class is 350
  prospects of which ~30 sign, and a coach search is 25 candidates of which one
  is hired; reserving would drain the pool every offseason. They draw a
  non-reserving preview that prefers free faces, and the signing/hiring path
  claims it for real — **all six** of them now: the draft/UDFA conversion
  (`DraftEngine.copyProspectMetadata`), the carousel's two outside hires, the
  staff wizard (`HireCoachView.hire`), the medical hire
  (`CoachingStaffView.hireMedical`), the interview-expiry HC hire and
  `WeekAdvancer.refillAIStaffVacancies`. The four that did not claim could hand
  two people persisted from the same registry state the SAME portrait (identical
  free list × `stableHash(personID) % count`), and `backfill` used to be unable
  to repair it. It can now (see below).

- **Corrected invariant (measured, 2026-07-30).** "No two active persons ever
  share a face in one career" is NOT achievable with 2 560 ids, and the reserve
  range only bought the first offseason. Measured on a 3-season
  `MultiSeasonSmokeTest` run of a random league:

  | after season | living people | free ids | duplicated |
  |---|---|---|---|
  | t0 (creation) | 2 208 | 352 | 0 |
  | 1 | 2 514 | 46 | 0 |
  | 2 | 2 758 | **0** | 378 |
  | 3 | 2 703 | 0 | 143 |

  A league persists 224 draft picks + up to ~124 AI UDFAs every offseason
  against 40-90 retirements, and unsigned free agents / unemployed coaches never
  leave the store — so the population passes the catalog size during season 2.
  The invariant the code actually enforces (and audits) is therefore:

  > **nobody shares a portrait while an unused one exists**, and when the pool
  > IS full the duplicate lands on somebody nobody looks at.

  Four mechanisms implement it:
  1. `pickLocked` gained an **early cooldown reclaim** stage — before it will
     duplicate, it hands out any id no LIVING person holds, cooldown ignored.
     That alone keeps season 1 unique (the polite free list is empty by the first
     draft while 40-90 retirees' portraits sit behind the 2-season cooldown).
  2. **Coach retirement releases the face.** `Coach.isRetired` is new: 65+
     retirement used to be modelled as `teamID = nil` with the row kept, and
     `backfill` re-claimed the portrait of every Coach row on every advance, so
     the coach half leaked monotonically (a career reaches ~60 retired coaches
     by season 3).
  3. When the pool is full, the reuse tier prefers a face worn by an **unsigned
     free agent or unemployed coach** (~550 of them by season 2, against a ~200
     excess), so rosters and staffs stay unique long past the arithmetic limit.
     `FACEQA: onTeamDuplicates=` measures exactly this.
  4. `backfill` **repairs** a shared portrait (and an id the catalog cannot
     resolve) instead of only filling `nil` — but only while the pool has room:
     with a full pool a stable duplicate beats a portrait that changes weekly.

  Cross-season measurement now exists: `MultiSeasonSmokeTest` audits faces after
  every completed season (`FACEQA: smoke/season-N` + a `SMOKE: ANOMALY` line),
  and the audit traps ONLY on `duplicated > 0 && free > 0` — a real regression —
  never on a capacity limit. **Open decision for the user:** holding literal
  uniqueness past season 2 needs ~1 000 more generated ids (a `--count 3584`
  run, ~$3 and ~30 MB more bundle), otherwise the visible-people guarantee above
  is what ships.

- **Known limitation, pre-existing and app-wide: no `careerID` on people.**
  `Player`/`Coach` carry no career id and every engine fetch is store-wide, so
  two save slots share one population (creating a career inserts a second league
  into the same store; deleting one deletes only the `Career` row). The face
  registry is career-scoped, so with two saves the second career's registry
  reserves the first career's people. Fixing that is a data-model migration far
  outside the face wave — tracked in BACKLOG.
- **Generation is running** (Replicate / FLUX schnell, 721 images in
  `tools/faces/manifest.json` at the time of writing, resume-safe). Remaining:
  finish the 2 048 run, re-run with `--count 2560` for the reserve range, then
  the contact-sheet cull and `package_faces.py` → bundle
  `faces_manifest.json` + `Faces/`.

## 7. Bundle wiring (measured, 2026-07-30)

**Drop path — the one thing packaging must get right:**

```sh
python3 tools/faces/package_faces.py                      # → tools/faces/out/
cp tools/faces/out/Faces/*.heic        dynasty/dynasty/Resources/Faces/
cp tools/faces/out/faces_manifest.json dynasty/dynasty/Resources/Faces/
```

No project-file edit is needed and none should be made: `dynasty` is a
`PBXFileSystemSynchronizedRootGroup`, so it bundles whatever it finds under it.

**Measured, not assumed** (Debug build for the iPad Pro 13-inch M5 sim, a
12-image probe copied into the folder above and then removed again):

| | drop folder empty | 12-image probe in place |
|---|---|---|
| `.app` contents | no `.heic`, no `faces_manifest.json`, `.gitkeep` not copied | `dynasty.app/face_00000.heic` … + `dynasty.app/faces_manifest.json` |
| catalog | `synthesized/2560` | `manifest/12` |
| manifest resolved at | absent | **bundle-root** |
| images resolved | 0/2560 → 2 560 placeholders | 12/12 at bundle-root |
| verdict | PASS | PASS |

The sync **FLATTENS** `Resources/Faces/` — files ship at the bundle ROOT, not
under `Faces/`. This is why `FaceLibrary.manifestURL()` and
`FaceImageCache.bundleURL` each try the root arm as well as the `Faces/`
subdirectory; the subdirectory arm is there for a later move to a real resource
folder or On-Demand Resources.

**The gate:** `FaceBundleAudit` (DEBUG), env `FACE_BUNDLE_AUDIT=1`, one
`FACEBUNDLE:` block + PASS/FAIL. A bundle with zero images is a **PASS** — the
placeholder silhouette is the designed pre-shipment state. It measures images
through `FaceImageCache.bundleURL`, i.e. the renderer's own lookup, so it cannot
pass on a resolution the UI does not actually perform. Three failures, all
verified by deliberately breaking a probe build:

1. empty catalog (nothing could be assigned);
2. `faces_manifest.json` bundled but the catalog fell back to synthesis —
   corrupt/empty file. *Verified: truncated JSON → `catalog=synthesized/2560
   manifest=bundle-root` → FAIL.* Without this check a broken packaging step is
   invisible, because the fallback silently produces a working app;
3. bundled `.heic` files no catalog id claims — a stale manifest, i.e. images
   that ship and can never be shown. *Verified: dropping one entry from the
   bundled manifest → `heicsInBundle=12 orphans=1` → FAIL.*

`Resources/Faces/.gitkeep` keeps the folder in git and repeats the copy
commands. It is deliberately the only file there: a PARTIAL
`faces_manifest.json` is worse than none, because the manifest is authoritative
when present and would shrink the catalog to the ids it happens to list (the
probe run above is exactly that effect, on purpose).
