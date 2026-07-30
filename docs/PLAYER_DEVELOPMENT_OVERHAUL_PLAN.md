# Player Development & Training Overhaul — Analysis & Implementation Plan (Phase 2)

Data anchors: `docs/DEVELOPMENT_NFL_REFERENCE.md` (this phase) and
`docs/DRAFT_NFL_REFERENCE.md` §6–8 (outcome targets). Builds directly on the
uncommitted draft-class overhaul (`docs/DRAFT_CLASS_OVERHAUL_PLAN.md`).
This plan also **closes the three open items from phase 1**: the league
potential ratchet, skipped finding #3 (ceiling-share targets) and skipped
finding #11 (blunt catch-up halving).

---

## 1. Current system — what exists, what is dead, what is broken

### 1.1 Live machinery (keep, extend)
- `PlayerDevelopmentEngine.developPlayer` (offseason): base points from
  workEthic (≤3) + coachability (≤2) + playingTime (≤3) × coaching multiplier
  0.5–1.8 (`CoachingEngine.hierarchicalDevelopmentBonus:1103-1140`: HC
  motivation ±8 %, AHC ±4 %, coordinator ±10 %, position coach ±15 %) × age
  factor (1.0 pre-peak / 0.5 in-window / hard 0 past peak) × rookie multiplier
  (2.5/1.8/1.3) + strength-coach physical bonus + 5 %/5 % rookie boom/bust roll.
- Young-player **catch-up growth** toward `developmentCeiling = pot·0.65+35`,
  current fractions **0.095/0.068/0.045/0.028** (yp 0-1/2/3/4; halved from
  0.19/0.13/0.09/0.06 in phase 1 to hold the 3-season OVR gate;
  `PlayerDevelopmentEngine.swift:198-213`, coachFactor clamp 0.9–1.1).
- Weekly `TrainingFocusEngine` (3 slots, gain chance 0.32/0.18/0.06 by age
  phase × workEthic × coach × morale), camp `TrainingPlanEngine`,
  `applyGameExperience` (mental XP; mentorship +10 % via
  `LockerRoomEngine.mentoredProtegeIDs`), `applyAgeRegression` (generic
  chance/magnitude by yearsPastPeak), `learnScheme` (now `learning/65` term),
  `HeatState` in-game form (in-memory, personality-scaled), retirement engine
  (emergent volumes), `WorkloadEngine` (tick + classify), holdouts (block all
  development), owner goals/satisfaction.
- Phase-1 additions: `Player.learning` (+ sentinel `storedLearning`),
  readiness/learning conversion (`DraftEngine.swift:308-317`: skill
  `0.49+r/99·0.28`, phys 0.97, mental `0.715+l/99·0.12`, floor-35
  interpolation; measured rookie OVR R1 72.6 → UDFA 55.1), rookie familiarity
  seeding 15–45, `backfillLegacyLearning` (`WeekAdvancer.swift:223-229`).

### 1.2 Dead code to activate (already written, zero call sites)
| What | Where | Value |
|---|---|---|
| Record/chemistry/pay/contract-year → morale (per-archetype swings) | `LockerRoomEngine.applyMoraleEffects:115`, `weeklyMoraleUpdate:204` | The entire designed morale loop |
| Coach's potential assessment (noise 2/1/0 by years-on-team, −1 if coach ≥80) | `PlayerDevelopmentEngine.assessPotential:552` | Scouting fog on potential |
| Potential drift from scheme fit + morale | `PlayerDevelopmentEngine.updatePotentialRealization:406-436` | Environment → ceiling link |

### 1.3 Defects & gaps this plan fixes
1. **Veteran `truePotential = Int.random(50...99)`** — uncorrelated with age,
   tier, OVR (`LeagueGenerator.generatePlayer:317-361` leaves the `Player.swift:286`
   default). A 31-yo 62-OVR depth man carries expected ceiling 83. This is the
   dominant ceiling-noise source and, with slot-correlated intake (~79.5 potential),
   the root of the league **potential ratchet** (+0.9/season observed).
2. **Morale is near-static** after generation (only holdout/tag/event/heat
   nudges; no win/loss source — the designed one is dead code).
3. **Workload is cosmetic**: `injuryRiskPct`'s only caller is a SwiftUI label
   (`TrainingPlanView.swift:298`); burnout multiplies nothing; AI teams never
   tick; `WorkloadEvent` stamps **wall-clock** `Calendar.current` dates
   (`WorkloadEngine.swift:50-52`).
4. **No consequence for scheme changes**: `schemeFamiliarity` is never decayed
   or taxed on coordinator turnover (writer inventory confirms).
5. **Coaching change effects are 2 constants** (−0.05 HC / −0.03 coord in
   adjustment); no continuity reward.
6. **Real playing time ignored**: offseason dev uses an estimate
   (`estimatePlayingTimeShare:837-848`) though `gamesPlayedThisSeason` /
   `gamesStartedThisSeason` are tracked and persisted.
7. **Three divergent `learning` generators** (LeagueGenerator 0.6/0.4 uniform;
   DraftClassBuilder 0.40/0.60 gaussian sd 15 → validated r≈0.62; backfill
   0.6/0.4 hashed) — cohort bias into `learnScheme`.
8. **No per-team prior-season record** (only user `SeasonSummary`) — adversity
   triggers impossible for 31 AI teams.
9. **`assessedPotential` never written** → `RosterEvaluationView:1745-1759`
   noise-0 fallback shows TRUE potential bands, no fog.
10. **UDFA loop over-asks**: 31 teams × 10-14 from a ~28-player pool, unshuffled
    team order (`WeekAdvancer.swift:2342-2368`) — order-biased allocation.
11. Phase-1 leftovers: catch-up halving penalizes existing-save yp0-4
    (skipped #11); ceiling-share "starter-capable" targets unreachable by
    construction (skipped #3).

---

## 2. Core design: the Realization Model

**Principle (reference §2): potential is a ceiling few reach.** Outcomes are
decided by a per-player, per-offseason **realization factor R**, not by
inflating/deflating potential. NFL trajectory mix (Ascender ~25 % / Plateauer
~40 % / Bust ~25 % / Late bloomer ~10 %) must **emerge** from R's spread —
never a visible dice roll.

### 2.1 New attributes & state (all lightweight-migration-safe)
- `Player.competitiveness: Int = 55` + `storedCompetitiveness` sentinel
  (mirror the `learning` pattern exactly, `Player.swift:37-50`). The
  fighter-mentality stat: drives adversity response, complacency immunity,
  plateau-break. `CollegeProspect.trueCompetitiveness: Int = 55` generated in
  `DraftClassBuilder` (archetype-correlated: fieryCompetitor/teamLeader +12,
  mentor/steadyPerformer +5, feelPlayer/classClown −6; gaussian around the
  prospect's mental level, sd 12, clamp 25–99). Scouted `CMP` grade added to
  mental grade surfaces; copied in `copyProspectMetadata`.
- `Player.motivationStateRaw: String? = nil` + enum `MotivationState`
  { driven, focused, complacent, discouraged } with `displayName`/icon/color.
- `Team.lastSeasonWins: Int = -1`, `lastSeasonLosses: Int = -1` — written at
  season rollover **before** current wins/losses reset (fixes gap #8 cheaply).
- Backfills in `WeekAdvancer` next to `backfillLegacyLearning`:
  `backfillLegacyCompetitiveness` (sentinel 55 → deterministic UUID-hashed:
  base 0.45·workEthic + 0.25·clutch + 0.30·hash[30,85], archetype shift as
  above, clamp 25–95).

### 2.2 One shared mental generator (fixes #7)
New `MentalAttributeModel` (small enum, e.g. in
`Domain/Models/Player/PositionPhysicalProfile.swift` or sibling file):
`learning(awareness:level:)` = the **validated DraftClassBuilder math**
(0.40·awareness + 0.60·gaussian(level, 15), storedLearning clamp) and
`competitiveness(archetype:workEthic:clutch:seed:)`. LeagueGenerator,
DraftClassBuilder and both backfills all call it. Veteran mental generation in
`LeagueGenerator` switches from uniform `U[40,99]` to
`PositionPhysicalProfile.sampleMental` with the depth-tier level shift
(+3/0/−3), unifying cohorts (prospects already use it).

### 2.3 Motivation state machine (offseason, before `developPlayer`)
Computed once per player when entering `.trainingCamp` (stored, surfaced in UI
and dev reports). Score triggers (positive → driven, negative → discouraged):

| Trigger | Condition (data source) | Direction & gate |
|---|---|---|
| Team collapsed | `team.lastSeasonWins` ≤ 5 (new field) | comp ≥ 65 → +2 (fighter); comp ≤ 40 && age > peak.lower → −2 |
| Personal down year | latest `PlayerSeasonHistory.overallAtEndOfSeason` < previous − 2 | comp ≥ 65 → +2; comp ≤ 40 → −2 |
| Demoted/benched | latest `gamesStarted` ≤ 0.5 × previous season's (both ≥ 4 starts baseline) | comp ≥ 60 → +1; comp ≤ 40 → −1 |
| Rookie chip | yp ≤ 2 && (draftPickNumber > 100 or nil) && comp ≥ 70 | +2 |
| Contract year | `contractYearsRemaining == 1` && (comp ≥ 45 or motivation == .money) | +1 (§3 evidence: small bump) |
| Just paid | extended last offseason (contractYearsRemaining ≥ 3 && salary ≥ 0.95×market && yp ≥ 4) && workEthic < 60 && comp < 60 | −2 (complacency; .money motivation −1 extra, .winning immune) |
| Playoff heartbreak | user team lost in conference/SB round (`SeasonSummary`) | +1 team-wide, leadership ≥ 70 amplifies |
| Low morale | morale < 40 | comp ≤ 45 → −1 |
| Coach lift | HC motivation ≥ 80 | +1 to any negative-score player (pull toward focused) |

Map score → state: ≥ +2 driven · +1…−1 focused · −2 complacent (if payday
trigger dominant) · ≤ −2 discouraged. Effects:

- `developPlayer` points × **1.30 / 1.00 / 0.75 / 0.60**; morale +3 / 0 / −1 / −3.
- Weekly focus `weeklyGainChance` × 1.20 / 1.00 / 0.85 / 0.70 (composes with
  the existing morale factor; cap stays 0.6).
- R-factor input (below). Dev-report `Reason.motivation` entries + 2–4
  league-wide offseason news stories ("best shape of his life" / "showed up
  heavy") with archetype-flavored copy.

### 2.4 The R factor — merit-distributed growth (fixes ratchet + skipped #11)
Restore catch-up base table to the original **0.19/0.13/0.09/0.06** and scale
it per player:

```
base        = 0.30 + workEthic/99·0.40 + competitiveness/99·0.20 + learning/99·0.10   // 0.30–1.00
motivMult   = 1.30 / 1.00 / 0.75 / 0.60  (motivation state)
opportunity = 0.55 + 0.45 · realPlayingTimeShare      // floor = practice reps
health      = 1.0 | 0.7 missed camp | 0.4 lost offseason (rehab through it / major ≥6wk injury)
R           = clamp(base · motivMult · opportunity · health, 0.20, 1.45)
catchUpFraction = baseTable(yp) · R · coachClamp(0.85…1.15)
developPlayer points ×= motivMult · health          // NOT full R — points already contain workEthic & playing time
```

League-mean sanity (design target, harness-verified): mean base ≈ 0.72 ×
opportunity ≈ 0.72 ≈ **R ≈ 0.50** → league-average catch-up equals the current
halved table → **3-season drift gate preserved by construction**, while the
spread (p10 ≈ 0.25, p90 ≈ 0.95, driven starters to 1.45) produces ascenders,
plateauers and busts. Existing-save yp0-4 players are no longer blanket-halved
— they get whatever their factors merit (closes skipped #11 properly).

`realPlayingTimeShare` (fixes #6): from the just-snapshotted latest
`PlayerSeasonHistory` (or live fields if snapshot ordering requires):
`min(1.0, gamesStarted/17·0.85 + gamesPlayed/17·0.15)`, floor 0.15, and the
floor scales ×(0.8 + posCoach.playerDevelopment/99·0.4) — good coaches make
practice reps count. Delete `estimatePlayingTimeShare`.

### 2.5 Plateau & late bloomer (emergent + narrative tag)
- Track nothing new persistent except `Player.lastOffseasonOverallGain: Int = 0`
  (or derive from history). A player with yp ≥ 2, R < 0.45 in two consecutive
  offseasons and total OVR gain ≤ 1 is **plateaued** — dev-report line
  ("has settled into his role"), assessPotential (below) drops his label a
  band. No hard lock: each subsequent offseason, if motivation becomes driven
  OR position-coach quality improves ≥ +15 OR team change, roll 15 % →
  **late-bloomer breakout**: that cycle runs R × 1.25 and a news story. Target
  emergent shares (career harness): plateau 30–50 %, late bloomer 5–12 %.
- Existing 6 %/week `rollBreakout` (young high-potential) stays — it covers
  the year-2/3 leap; late-bloomer covers year 3-5 scheme/coach-change cases.

### 2.6 Potential semantics (closes skipped #3)
- Wire `updatePotentialRealization` into the offseason (after motivation,
  before developPlayer) with tightened deltas: scheme-fit term clamp ±2/yr,
  morale term clamp ±1/yr, **lifetime drift cap ±8 from draft-time potential**
  (store `Player.draftTruePotential: Int = 0` sentinel; 0 = backfill with
  current on first touch). Potential responds modestly to environment; it does
  not decide outcomes — R does.
- **Ceiling-share targets are retired as a metric.** The §7.6 deviation note
  in the `draftclass` harness scenario is rewritten to point at the new
  `career` scenario (§6 below), whose hit-rate asserts are the real
  "starter-capable" calibration. This is the principled resolution of skipped
  finding #3 — the plan decision it asked for.

### 2.7 Veteran generation made consistent (kills the ratchet's second leg)
`LeagueGenerator.generatePlayer`:
- `truePotential`: replace uniform 50–99 with realization-consistent draw —
  past peak: `overall + U[0,3]`; else `overall + max(0, N(µ,4))`,
  `µ = max(2, 14 − 2.5·max(0, age−22))` (22yo: 14 … 28yo: 2), clamp ≤ 99.
  Matches intake shape (draft-age upside ~7–14) so the league potential level
  is stationary from season 1: **leaguePot stabilizes instead of climbing
  toward intake**.
- Mental via `sampleMental` (§2.2), learning + competitiveness via
  `MentalAttributeModel`. Existing saves keep old veterans (transient washes
  out with turnover); new careers are consistent end-to-end.

### 2.8 Position-shaped regression (reference §1)
Add `Position.declineProfile` { cliff (RB, CB) · standard (WR, TE, EDGE, DT,
LB, S, FB) · glide (QB, OT, IOL, C, K, P) } consumed by `applyAgeRegression`:
- cliff: chance +15 pp per yearsPastPeak band, magnitudes +1; standard: current
  table; glide: chance −10 pp, magnitudes −1 (min 1).
- QB/glide mental exception: awareness/decisionMaking may still +1/yr while
  physical declines (processing keeps growing — reference §1) until 2 yrs past
  peak upper bound.
- Career harness asserts the resulting per-position peak-age modes and decline
  slopes (RB steeper than QB, CB steep, OL long).

### 2.9 Environment wiring
1. **Morale activation**: review and wire the dead `weeklyMoraleUpdate`
   (weekly, after games, damped: apply table then clamp per-week movement to
   ±3, plus reversion +1 toward 70 for the archetype-neutral) and seasonal
   `applyMoraleEffects` (once at season end, clamp ±8). Smoke gates: league
   morale mean 60–75, p05 ≥ 35 across 5 seasons — no spiral.
2. **Scheme change consequences** (fixes #4): at offseason coordinator/scheme
   swap detection — one-time team news, that season's `learnScheme` intensity
   × 1.25 (install reps), and **unused-scheme decay**: schemes not run by the
   team's current OC/DC decay −4/offseason, floor 35 (skill atrophy; keeps
   dictionaries meaningful). Familiarity for the *new* scheme is whatever the
   player carries (already correct).
3. **Coach continuity bonus** (§5 reference): coordinator with
   `seasonsOnTeam ≥ 3` and unchanged scheme → +0.05 on the development
   multiplier stack; verify `isInAdjustmentPeriod` actually expires after one
   season for non-XP coaches (only clear site is `CoachDevelopmentEngine.swift:95`
   — if a coach never converts XP it may stick; fix so it clears each offseason
   pass unconditionally).
4. **assessPotential persisted** (fixes #9): during camp, for the user team
   (and optionally all teams) write `player.assessedPotential =
   assessPotential(...)` using the position coach's rating; re-assess yearly
   (noise shrinks with years-on-team per the existing function). Plateau tag
   (§2.5) shifts the assessment down a band. `RosterEvaluationView` fallback
   stays for legacy saves.
5. **QB2 clipboard**: in `applyGameExperience`, backup QBs (0 starts) with a
   QB coach `playerDevelopment ≥ 70` or a mentored pairing get awareness/
   decisionMaking ticks at 0.35 × starter rate (instead of ~0).
6. **Workload teeth + fixes** (fixes #3): `checkForInjury` multiplies by
   `workloadStatus.injuryMultiplier` when the player has a non-default status;
   `TrainingPlanEngine` halves gains for `.burnedOut`; `WorkloadEvent` stamps
   game `seasonYear`/week (not `Calendar.current`); AI teams get a cheap
   weekly camp-phase tick at default intensity so statuses exist league-wide
   (or, if perf-prohibitive, statuses stay user-only and the injury multiplier
   applies only where a status exists — implementer measures and picks,
   documenting the choice).
7. **Holdout/injury development costs** stay as-is (already realistic); missed
   camp via holdout that resolves late = `health 0.7` in R (§2.4).
8. **UDFA loop fix** (fixes #10): shuffle AI team order; per-team ask
   `min(4, ceil(pool/31))`; raise `generateDeclarations` UDFA cushion 26 → 60
   so the post-draft pool is ~60 (annual inflow ≈ 224 + ~60 + street FA ≈
   NFL-realistic turnover); draftclass harness pool-assert threshold updated
   accordingly (a *target* change, documented, not a weakening).

### 2.10 UI & narrative surfaces (modest, reuse patterns)
- `PlayerDetailView`: motivation badge next to morale (icon+label, all three
  layouts), Competitiveness row in mental grids (beside Learning), "Coach's
  Projection" line showing `assessedPotential` in the development row.
- `DevelopmentReportView` / `DevelopmentReport.Reason`: new cases
  `.motivation`, `.plateau`, `.lateBloomer`, `.schemeChange` with labels;
  builder emits them (driven/complacent players, plateau tags, install-year
  notes). Prospect side: `CMP` grade column in mental tabs (widths 7→8 columns
  — shrink to 26 pt like the LRN change did).
- News: offseason motivation stories (cap 4 league-wide + always user team),
  scheme-install story, late-bloomer story.
- Localization: English only (the game ships English-only, decided 2026-07-29;
  String Catalog append pattern from phase 1 — never add `fi` values).

---

## 3. What is explicitly OUT of scope now (gap analysis → backlog)

Documented for BACKLOG/TODO, deliberately not in this wave:
practice-squad system & poaching · position conversions as development paths ·
facility/investment (weight room, medical) effects · full per-team season
archives (only lastSeasonWins/Losses added) · `OwnerGoalsEngine` proxy fixes
(division/streak/conference approximations) · `PlayerSeasonHistory` real stat
lines (keyStat1-3 unfilled) · contract incentive clauses as motivation ·
morale → in-game effects beyond HeatState · coach development-reputation as an
FA/draft lure · film-room/positional drills minigames · international/UDFA
pipeline depth. Each is a realistic-sim feature; none blocks this wave's
correctness.

---

## 4. Save compatibility

Same conventions as phase 1 (inline defaults, no init-signature changes, no
Codable-struct edits, sentinel-aware backfills, no new @Model types →
`DataContainer`/`MultiSeasonSmokeTest` schema lists untouched). New stored:
`Player.competitiveness`, `Player.motivationStateRaw`,
`Player.draftTruePotential`, `Player.lastOffseasonOverallGain` (if not
derived), `Team.lastSeasonWins/-Losses`, `CollegeProspect.trueCompetitiveness`.
`SimPlayer` unchanged (motivation acts through training, not per-play).

---

## 5. Implementation stages (workflow)

1. **Foundations**: MentalAttributeModel (shared learning+competitiveness),
   competitiveness fields + prospect generation + scouting CMP grade +
   backfills, Team.lastSeason fields + rollover write, LeagueGenerator veteran
   potential/mental/learning consistency (§2.2, §2.7). Build green.
2. **Realization core**: motivation state machine + storage, R factor +
   restored catch-up table, real playing time, health gating, potential drift
   wiring + draftTruePotential, plateau/late-bloomer, position-shaped
   regression (§2.3–2.6, 2.8). Build green.
3. **Environment**: morale activation (damped), scheme-change tax + decay,
   continuity bonus + adjustment expiry, assessPotential persistence, QB2
   clipboard, workload teeth + wall-clock fix, UDFA loop + declarations
   cushion (§2.9). Build green.
4. **UI & narrative** (§2.10). Build green.
5. **Career harness + calibration**: new `career` scenario (§6), iterate
   constants until asserts pass; update draftclass §7.6 note + pool assert.
6. **League equilibrium**: MultiSeasonSmokeTest 3-season (|Δ| ≤ 1.5) AND
   5-season (|Δtotal| ≤ 2.0, last-2-season drift ≤ 0.5/season, leaguePot
   plateaus: last-2-season pot drift ≤ 0.5) gates; morale distribution gate;
   re-run `draftclass`, `familiarity`, `all` suites; full build.
7. **Verify ×3** (design-compliance & math · save-compat & lifecycle ·
   balance/equilibrium & UI) → **fix** confirmed findings → re-run all gates.

## 6. Validation — the `career` harness scenario (definition of done)

Stage the development stack standalone (PlayerDevelopmentEngine + regression +
motivation + R + retirement math, stub coaches/teams with the harness pattern;
synthetic season loop: depth-chart rank by OVR within position cohort →
playing-time share; no game sim). Simulate ≥ 2 000 drafted careers (intake via
DraftClassBuilder) over 12 seasons, assert:

1. **Hit rates by round** (primary-starter proxy: OVR ≥ 75 by year 4) within
   ±8 pp of `DRAFT_NFL_REFERENCE.md` §6: R1 ~55–65 %, R2 ~45, R3 ~33,
   R4 ~25, R5 ~18, R6 ~12, R7 ~10, UDFA ~4.
2. Elite share (peak ≥ 90): R1 20–30 %, R2 8–15 %, R3-7 combined ≤ 4 %.
3. Trajectory shares: plateau 30–50 %, late bloomer 5–12 %, washout (out of
   league ≤ 4 seasons) R5-7 ≥ 45 %.
4. Peak-age mode per position inside `peakAgeRange`; decline slope ordering
   RB/CB steepest, QB/OL shallowest; no position peaking outside its window.
5. R distribution: league mean 0.45–0.55, p10 ≤ 0.30, p90 ≥ 0.85; motivation
   states distribute ≈ driven 15–25 % / focused 55–70 % / complacent 5–12 % /
   discouraged 5–12 % across a simulated league-season.
6. Career length: all-drafted mean 4.5–6 yrs, R1 mean ≥ 7.5 yrs.
7. Growth shape: mean OVR gain yp0→1 largest, monotone declining gains to
   peak (reference §1/§8 of draft doc).
8. Determinism guard: two runs with same seed (if seeded) or 2 000-career
   sample-to-sample stability of every asserted mean within its tolerance.

Plus §5 stage-6 league gates. **All previous suites must stay green** —
`draftclass` (with its two documented target updates), `familiarity`, `all`.
