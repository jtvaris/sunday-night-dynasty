# Release Checklist — run before EVERY TestFlight / App Store upload

Hard gates (any failure blocks the release):

1. **Anonymization bundle gate** — `tools/league-data/check_bundle.sh`
   Builds the Release configuration and scans the product: real-name blocklist
   (full names + initial forms + Levenshtein ≤2 variants), `league_2026_dev.json`
   absence, raw-data filenames, publish-template identity strings, and the
   source-level name-pool cross-product (gate E; coverage list =
   `SWIFT_NAME_POOLS` in `scan_bundle.py` — a NEW runtime name source must be
   added there or the gate is blind to it). Must exit 0.
2. **Template QA** — `cd tools/league-data && python3 make_templates.py`
   (19/19 gates; regenerates both templates deterministically). Re-run
   `check_bundle.sh` if templates changed.
3. **Balance suites** — `cd tools/balance-harness && ./run.sh all && ./run.sh
   draftclass && ./run.sh career && ./run.sh familiarity` — all green.
4. **League smoke** — 3 seasons on BOTH league sources:
   `SIMCTL_CHILD_PERF_SMOKE_SEASONS=3 [SIMCTL_CHILD_PERF_SMOKE_LEAGUE=fixed2026]`
   via `xcrun simctl launch --console-pty` — drift |Δ| ≤ 1.5, no watchdog/anomaly.
5. **Face library** — `faces_manifest.json` + `Faces/*.heic` present in the
   bundle; the human review sweep (`tools/faces/out/review.html`) has been done
   for the shipped generation (culled ids regenerated); `tools/faces/raw/` and
   `TRANSFORM_QA.md` are NOT in the bundle (covered by gate 1's raw-file check).
6. **Localization** — English only: `knownRegions` = en + Base, no fi entries
   in the catalog (grep `"fi" :` → 0 hits).
7. **Legal reminder** — before the FIRST public release with the realistic
   league content: IP-lawyer review of `docs/ANONYMIZATION_SPEC.md` + one
   generated build (see spec §7 residual-risk statement).

Notes: dev conveniences (`league_2026_dev.json`, `LeagueTemplateValidation`,
smoke hooks, debug tracers) are DEBUG-gated and must not appear in the Release
product — gate 1 checks the dev template explicitly; spot-check the rest if
build settings changed.
