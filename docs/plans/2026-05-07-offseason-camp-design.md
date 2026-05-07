# OTAs / Training Camp / Preseason / Roster Cuts — Design Brief

**Date**: 2026-05-07
**Goal**: Transform offseason camp phases from quiet pass-through into meaningful strategic + dramatic management moments.

## Phase rhythm

| Phase | Real-world | Sim-week | Pelilliset stakesit |
|-------|-----------|----------|---------------------|
| OTAs | May–Jun (3 wk) | 1 sim-week | Scheme install, no-pads, low risk |
| Training Camp | Aug (3 wk) | 2 sim-weeks | Full pads, position battles, high risk |
| Preseason | Aug–Sep (3 games) | 3 sim-weeks | Live snaps for evaluation |
| Roster Cuts | Sep | 1 sim-week | 90→75→65→53 (3 cut days) |

## Five mechanics (Phase 1–5 of implementation)

### Phase 1 — Focus sliders + Workload + Injury

Per training week, GM allocates 100 focus points across:
- **Tactical** (scheme + film) → schemeKnowledge, audibles, blitz-recognition
- **Physical** (S&C, conditioning) → stamina, durability, speed cap
- **Technical** (drills, fundamentals) → position-specific attributes

Per player:
- `workloadStatus`: underloaded / healthy / overloaded / burnedOut
- `cumulativeLoad` (resets weekly with recovery)
- Injury risk = base × (1 + overload_factor)

### Phase 2 — Roster Cuts (90 → 53 in 3 stages)

- 90→75 cut day, 75→65 cut day, 65→53 final cut day
- Per-player **camp grade** = aggregated daily training + preseason snaps
- Sortable columns per position
- Practice squad eligibility (10-player PS, no longer counts vs 53)
- Cap savings preview per cut

### Phase 3 — Position battles + Hard Knocks + Waivers

- Position battle: 2-3 players competing for starting spot
- Daily win/loss tracker
- Locker-room ripples after starter announcement
- Surprise breakouts (low-pick rookie outperforms)
- Cut day: 24h waiver wire, ranked claims by record (worst-first)
- Hard Knocks-style narrative: 5-10 storylines per camp

### Phase 4 — Game-week prep balance (regular season)

Per opponent week, slider:
- 100% general → pure attribute development, no opponent prep
- 50/50 balanced
- 100% opponent → +20% audibles success, +15% defensive read this game; -1 OVR drift after 3 weeks straight

### Phase 5 — Voluntary workouts + Locker Room

- Per week, GM can request optional/mandatory training:
  - "Voluntary OTAs": 70% participation, +3 scheme/attendee, +2 LR
  - "Mandatory minicamp": 95% participation, +5 scheme, -5 LR, +2% injury
  - "Saturday film": 40% participation, +1 scheme, neutral LR
- Personality affects compliance (Workhorse +, Diva -)
- "Hidden fatigue" accumulates → reveals in mid-November

## Architecture

### Domain (new + extensions)
- **Player extensions**: `cumulativeLoad: Int = 0`, `workloadStatusRaw: String?`, `campGradeRaw: String?`, `inHoldout: Bool` (already exists)
- **New @Model**:
  - `TrainingPlan` (per career-week: tacticalPct, physicalPct, technicalPct)
  - `WorkloadEvent` (per player: dayOfWeek, loadDelta, recoveryDelta)
  - `PositionBattle` (positionRaw, playerIDs, currentLeaderID, winnerID)
  - `RosterCut` (playerID, cutDay, capSavings, deadCap, claimedByTeamID)
  - `OpponentPrepWeek` (week, generalPct, opponentPct)
  - `VoluntaryWorkout` (week, type, participationPct, schemeBonus, lrDelta)

### Engine layer
- `TrainingPlanEngine` — applies focus pct → per-player attribute deltas
- `WorkloadEngine` — track cumulativeLoad, compute injury risk, classify status
- `CampGradeEvaluator` — daily grade per player (training + preseason snap quality)
- `RosterCutEvaluator` — recommend cuts; compute cap savings; surface PS candidates
- `PositionBattleTracker` — daily win/loss, end-of-camp resolution
- `WaiverWireEngine` — 24h post-cut claim window
- `OpponentPrepEngine` — boost current week vs cumulative dev cost
- `VoluntaryWorkoutEngine` — participation, scheme bonus, LR delta
- `HardKnocksNarrator` — generate 5-10 storyline events per camp

### UI surface
- `TrainingPlanView` — sliders + per-player workload list
- `WorkloadDashboard` — heat-map of overload risk
- `RosterCutView` — 3-stage flow with position cards
- `PositionBattleSheet` — daily standings + win indicators
- `WaiverClaimsBanner` — your cuts being claimed
- `GameWeekPrepPicker` — slider in regular-season game prep
- `VoluntaryWorkoutPrompt` — weekly request dialog
- `HardKnocksToast` — narrative event surfaces

## Phasing (implementation)

**Phase 1 (Foundation)**: Domain + Engine layer for all 5 mechanics
**Phase 2 (Core UX)**: TrainingPlanView + WorkloadDashboard + RosterCutView
**Phase 3 (Drama)**: PositionBattle + Hard Knocks + Waiver wire
**Phase 4 (Regular season)**: GameWeekPrepPicker
**Phase 5 (Depth)**: Voluntary workout prompts

## Acceptance criteria

- Phase 1: Build verified, schema updated, engine APIs callable
- Phase 2: Sliders functional + workload heatmap + 3-stage cut flow
- Phase 3: Battles tracked daily; waivers fire on cut
- Phase 4: Per-week prep balance affects this-week vs cumulative attribute drift
- Phase 5: Voluntary workout outcomes deterministic per personality mix
