# Realistic Starting League — Plan (Phase 3)

Goal: new careers start from a **maximally realistic Feb-2026 snapshot** of the
NFL — every team's end-of-2025-season roster (anonymized), real career
histories, ratings derived from real production, and 2026 draft-pick ownership
including trades. Random generation stays available as an alternative start.

## Pipeline

1. **Data acquisition (running now, repo-safe):** research agents compile per-team
   JSON into `tools/league-data/raw/` — 53-man rosters (+notable IR) at end of
   the 2025 season, per-player: name, pos, age (Feb 2026), yearsPro, college,
   draft origin (year/round/pick), ht/wt, role tier
   (starter/rotation/backup/depth), 2025 stats, and for starters per-season
   career stats (≤8 seasons, position-relevant categories only). Plus:
   2026 pick ownership per team (all 7 rounds, trades as of Feb 2026) +
   draft order from 2025 standings + records (feeds `Team.lastSeasonWins`),
   and coaching staffs (HC/OC/DC + scheme identity per team).
   **No fabrication: unknown = null**, sources cited per file.
2. **QA & merge:** aggregate to `league_raw_2026.json`, per-team count checks,
   completeness report, re-fetch list for holes.
3. **Anonymization (build-time transform, only anonymized data ships in the app
   bundle):** deterministic, seeded name morph preserving rhythm/feel
   ("Jared Goff" → "Garret Joff" style): swap/shift onset consonants between
   first/last, small vowel shifts, keep syllable counts; collision-check against
   the full real-player set AND generated-name pools; stable across runs.
   Colleges stay real (factual), team names/cities per game's existing setup.
4. **Ratings derivation:** per-position heuristic tables map role tier ×
   production percentiles × reputation band → OVR target → solve attributes via
   the shared `PositionPhysicalProfile` / attribute-solver machinery (phase-1/2
   models). Physical attrs seeded from ht/wt/40-history where known; mental
   (incl. learning/competitiveness) from archetype-consistent sampling with
   career-shape hints (early-declining vet → lower durability etc.).
   `truePotential` per phase-2 veteran rules (age-anchored upside).
5. **Career history:** real per-season stat lines → `PlayerSeasonHistory` rows
   (yearly OVR back-estimated from production curve) so career views, HOF logic
   and the phase-2 adversity triggers work from day one.
6. **Integration — TWO FIXED TEMPLATES, both launchable (user requirement
   2026-07-29):** the transform tool bakes two complete league templates from
   the same raw data:
   - `league_2026_dev.json` — devProfile: **real** player and coach names, the
     real 32 club identities, the real principal owners and exact careers
     (decision 2026-07-30 — it is the developer's own NFL). Bundled in DEBUG
     builds only.
   - `league_2026_publish.json` — publishProfile per `ANONYMIZATION_SPEC.md`:
     fictional players/coaches/team nicknames, OVR-arc careers. Bundled always.
   Both templates contain **final, pre-solved attribute values** (the
   rating-derivation runs inside the transform tool with a fixed seed, not at
   career creation) → every new career from a template starts from the exact
   same constant league; nothing is regenerated per game. New-career setup
   gains a league-source picker: *Fixed 2026 (Dev)* [DEBUG only] / *Fixed
   2026* / *Generated* (the current random path, unchanged). `LeagueGenerator`
   gains the template-import path; draft-pick ownership imported (traded
   picks); contracts approximated from role/age bands (exact cap data
   optional later).
7. **Validation:** team OVR ordering correlates with real 2025 results
   (top-5/bottom-5 sanity), league avg OVR ≈ 70–71 preserved, roster/cap legal,
   all harness suites + smoke test green with the template league.

## Legal / publishability (decided 2026-07-29)

Facts (stats, standings, pick trades, team strength) are not copyrightable; the
risk is **identifiability** (right of publicity). Precedent: EA lost/settled
Keller & Davis (~$60M) with NO names — number+position+bio+stats sufficed. A
sound-alike name plus matching bio/stats is therefore *worse* than a neutral
fictional name (explicit intent to evoke the persona). NFL team names/logos and
the "NFL" mark are trademarks — game keeps its own team branding.

**Two build profiles from the same raw data:**
- `devProfile` (never distributed): real names, real club identities, real
  owners, exact careers — personal use, DEBUG-only, bundle-gated.
- `publishProfile`: fully fictional names (not sound-alike), bio jitter
  (same-tier college swap, age ±1, draft slot fuzzed within round, ht/wt ±),
  **no verbatim stat lines** — careers imported as per-year OVR arcs and the
  game's own sim renders stat history. Team strengths/roster shapes stay real.
  Coaches anonymized the same way (real coach names carry the same NIL issue);
  scheme identities (facts) stay.
- Complementary route for community realism: roster editor/import so users can
  build the authentic version themselves (user action, not our distribution).
- Raw real-name data never ships in the app bundle under either profile.
- Before an actual store release with this content: cheap IP-lawyer review,
  especially for the US market (NFLPA/OneTeam enforcement is real).

## Notes
- Raw files keep real names (factual public data) but never enter the app
  bundle; only the anonymized template ships.
- Implementation waits until phase 2 + fi removal are merged-clean; data
  acquisition runs now (touches only `tools/league-data/`).
- Open extension: anonymized real coaching staffs + scheme fits (Shanahan-tree
  wide zone etc.) — included in data pull, wiring decided at implementation.
