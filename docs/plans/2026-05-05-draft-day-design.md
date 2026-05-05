# Draft Day — Design Document

**Date**: 2026-05-05
**Status**: Approved by user — ready for implementation planning
**Approach**: Event Engine + UI Overhaul (full rebuild, no legacy retained)

## 1. Vision and Pillars

The NFL Draft is the season's most important strategic moment. The redesign turns it into a **strategic chess game** (50 %) with a **dramatic narrative layer** (30 %) and a thin layer of **real-time pressure** (20 %).

The user's primary motivator is **finding a hidden gem** — drafting a player whose true value emerges over years. Smart strategic decisions (smart trades, value picks at need positions) are credited immediately; final "gem status" reveals over time.

The flow is modeled on the NFL Fantasy Draft (nfl.com): a live ticker with rankings, a clock that ticks for every team, drafted players visibly removed from the board, and the ability to skip to the next event or to your own pick.

## 2. Core Tensions (priority order)

1. **Pick capital optimization (B)** + **Risk management (C)** drive excitement: trade up for a star, but information is incomplete — bust risk is real.
2. **BPA vs Need (A)** is the strategic baseline that anchors every decision.
3. **Information incompleteness (D)** is what makes reactions matter: media, owner, locker room, and fans react to your moves with imperfect data.

## 3. Architecture

```
DraftDayCoordinator (@MainActor, ObservableObject)
  - state: DraftDayState (events, currentIndex, clock, mode, speed)
  - inputs: selectProspect, acceptTrade, proposeTrade, skipTo, pause, resume, setSpeed
  - state machine: loading → preDraft → playing ⇄ paused
                    ↳ userPick / tradeOffer / skipping(target) → playing → complete

DraftEventEngine (deterministic, seeded)
  - generates the entire event stream for a draft
  - delegates AI pick selection to existing primitives (rookie scaling, pick value chart)
  - decides when trade offers, position runs, big drops, scout interrupts trigger

DraftIntel (player-facing knowledge layer)
  - exposes ONLY what the player legitimately knows
  - public OVR (noised by scout confidence), custom rank, BB rank
  - team needs, scheme fit, scout-confidence stars

DraftStoryRecorder (persistence)
  - stores all events into SwiftData (DraftEvent)
  - stores Public/True grades (DraftPickGrade)
  - feeds the post-draft and seasons-later story arcs
```

**Key decisions:**

- The existing `DraftEngine.swift` is **not** retained — full rebuild. The pick-value chart and rookie scaling logic will be re-implemented inside the new engine, cleaner.
- `DraftStoryRecorder` is committed for the first iteration (event history is what enables the gem story arc — non-negotiable).
- `DraftIntel` is committed for the first iteration (the gap between true and visible knowledge is the foundation of "incomplete information" mechanics).
- The engine is **deterministic with a seed** (`career.id + seasonYear`). Same seed → identical event stream. Enables save/load, replay-mode, and ReAct balance iteration.

## 4. Main Screen Layout (iPad landscape, 3-pane)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ROUND 1 — Pick 5/32 — ON THE CLOCK: BUFFALO BILLS         ⏱ 1:47    │
│ ➤ Your next pick: #18 (13 picks away) • 6 picks remaining           │
└──────────────────────────────────────────────────────────────────────┘
┌──────────────┬───────────────────────────┬─────────────────────────────┐
│ LIVE BIG     │ DRAFT TICKER (live feed)  │ WAR ROOM                    │
│ BOARD        │                           │                             │
│              │ ✓ #1 Jaguars — A+         │ 📡 Scout chatter            │
│ Sort: My ▾   │ ✓ #2 Commanders — A       │ 🔄 Trade Radar              │
│ Pos: All ▾   │ ✓ #3 Bears — STEAL A+     │ 📊 Pick Value chart         │
│              │ ⏱ #5 Bills ← live         │ 🎤 Owner mood / Media tone  │
│ ★1 Henson★★★★★│ ─── UPCOMING ───         │                             │
│ 2 Smith ★★★★ │ • #6 Giants               │                             │
│ 3 Davis ⚠★★ │ • #7 Falcons              │                             │
│ ...          │ • #8 Rams (yours #18)     │                             │
└──────────────┴───────────────────────────┴─────────────────────────────┘
   [⏭ Skip to my pick]  [⏵ Skip to event]  [⏸ Pause]  [Play 1× / 2× / 4×]
```

**Always-visible information:**
- Current team on the clock + clock countdown
- User's next pick number + picks-away count
- Total picks remaining for user across draft
- Last 3-5 picks ticker + next 3-4 upcoming
- Top available prospects with custom rank, BB rank, scout confidence

**Pick Sheet (modal, doesn't replace screen):**
- Shows top available prospects sorted by user's custom rank
- Per-prospect inline grade preview: `Steal? +4 over BB / Solid / Reach`
- Need/Fit/Confidence indicators
- Trade Up / Trade Down / Draft buttons
- War Room one-line recommendation
- Modal sits over the ticker so context remains visible

**Visual mood:**
- Stadium background (`BgDraft` asset, dimmed) with team-color glow accent
- Live ticker uses slide-from-bottom animation; latest pick pulses briefly
- "On the clock" row tikitykset; viimeiset 30 s muuttuu punaiseksi ja sykäkkääksi
- Steal banner: ESPN-style breaking-news ticker
- Round transitions: full-screen fade banner

## 5. Pick Grade — two-tier system

### Public Grade (immediate feedback)

| Component | Weight | What it measures |
|-----------|--------|------------------|
| Value Δ   | 30 %   | (Big Board rank) − (pick number); positive = steal |
| Need fit  | 25 %   | Position is a critical team need |
| Public OVR| 30 %   | Visible (noised) overall rating |
| Scheme fit| 15 %   | Coaches' scheme alignment |

Letter mapping:
- **A+ Steal**: Value Δ ≥ +6, Need ≥ 0.6
- **A Smart Pick**: Value Δ ≥ 0, Need ≥ 0.5, decent OVR
- **B Solid**: Value Δ ≥ −3, basic need met
- **C Reach**: Value Δ ≤ −6 OR Need ≤ 0.3
- **D Big Reach**: Value Δ ≤ −10 AND Need ≤ 0.3

### Trade Grade

| Component | Weight |
|-----------|--------|
| Pick Value Δ (Jimmy Johnson chart) | 60 % |
| Target acquired                    | 30 % |
| Risk mitigation                    | 10 % |

### True Grade (revealed over years)

Computed by `CareerArcEngine` at season-end:
- Hall-of-Famer track (4+ Pro Bowl, contract extension): A++
- Solid starter (3+ years): A
- Role player: B
- Bust (cut before contract end): D

**Gem trigger**: True Grade ≥ A but Public Grade ≤ B → flashback story arc.

### Pick Sheet preview

Each candidate displays an inline `Steal? / Solid / Reach` chip *before* selection — supports strategic decision and immediately rewards a smart pick.

## 6. Reactions System

Four actors react with mechanical consequences:

| Actor       | Considers                                  | Mechanical effect                        |
|-------------|--------------------------------------------|------------------------------------------|
| Owner       | Pick value, contract impact, brand         | Owner trust → job security               |
| Media       | Hype potential, narrative, name value      | Media narrative → offseason pressure     |
| Locker Room | Position match, threat to existing starters| Team morale → game performance           |
| Fans        | Star names, position needs, hometown ties  | Fan mood → ticket sales                  |

**Selectivity** (avoid 4-actor clutter):
- A+ Steal → all 4 react positively
- A Smart Pick → 2 actors (Owner + Media)
- B Solid → 0–1 reactions (silence is fine)
- C Reach → 2 actors critically (Media questions, Fans disappointed)
- D Big Reach → all 4 react negatively

**Bonus triggers**: QB picks always get media coverage; rival's starter drafted shakes locker room; boom/bust positions raise media risk.

**UX**: reactions appear sequentially as bottom toasts (1.5–2 s each), then accumulate in the War Room "Reactions" column. Visual language varies by sentiment (gold positive / dark red negative / pulse for "BREAKING").

**Thresholds**:
- Owner trust: ±2..±8 per pick
- Fan mood: ±1..±5
- Locker room: ±0..±3
- Media narrative: cumulative; surfaces in press conferences and offseason storylines

## 7. Trade Engine

### Incoming offers (AI → user)

Trigger conditions:
- AI team has urgent need + top-tier prospect falling
- AI team has multiple similar-tier prospects + cap pressure → wants down
- GM personality (aggressive / patient / opportunist) influences likelihood

Offer surface includes:
- Outgoing/incoming picks
- Pick value calculation (Jimmy Johnson)
- AI motive (e.g., "Giants want a QB")
- User's scout opinion (one line)
- Time limit (offer expires)

### Outgoing offers (user → AI)

User opens Trade Builder from War Room. AI evaluates:
- **Accept** if delta < −50 pts (user gives more)
- **Counter** within ±50 (modified)
- **Decline + reason** if delta > +50 (user trying to rob)

Counter-negotiation 2–3 rounds.

### Value computation

```
TradeValue = Σ(Jimmy Johnson points)
  × (1.0 + need_bonus)
  × (current_year ? 1.0 : 0.65)        # future picks discount
  × gm_personality_factor              # aggressive=1.1, patient=0.9
```

## 8. Skip Mechanism

| Button         | Action                  | Interrupted by                                       |
|----------------|-------------------------|------------------------------------------------------|
| ⏵ Play 1×     | Normal pace             | User pick, trade offer                               |
| ⏵ 2×          | Double speed            | + big drop                                           |
| ⏵ 4×          | Quadruple               | + position run                                       |
| ⏭ Next event  | Hop to next significant | Always interruptible                                 |
| ⏭ My pick     | Hop to user's pick      | Trade offer pre-empts                                |
| ⏭ Next round  | Hop over a round        | User pick, trade offer                               |
| ⏸ Pause       | Halt                    | —                                                    |

**Implementation**: when skipping, the coordinator runs events in no-animation mode but appends them to ticker history. On reaching the stop point, ticker rapidly scrolls through recent picks then snaps to normal flow with a "YOUR PICK IN 3" pulse.

**Critical rule**: skip-to-my-pick must respect trade offers — never miss a critical decision.

## 9. Career Arc and Gem Story

`CareerArcEngine` runs in the offseason per drafted player:

| Stage                    | Trigger                       | Story flashback                                        |
|--------------------------|-------------------------------|--------------------------------------------------------|
| Rookie Season End        | Snap count + stats            | "Rookie of the Year — drafted #65, looked like a reach"|
| Year 2 jump              | OVR rise, starts              | "Smith taking the leap. Pre-draft scouts vindicated"   |
| First Pro Bowl           | Pro Bowl selection            | "FLASHBACK: Public Grade C — now an All-Star"          |
| Contract Extension       | Extension signed              | "Bills lock down their hidden gem"                     |
| Bust event               | Cut before contract end       | "What went wrong? GM took heat — doubters were right"  |

**Surfaces**:
- News-feed (offseason flashbacks)
- Player Detail (Public/True badge)
- Draft History (re-watch old drafts; gold border on confirmed gems)
- End-of-Decade summary (top gems from N years ago)

## 10. Persistence

| Entity                | Status     |
|-----------------------|------------|
| `DraftPick`           | existing   |
| `Player`              | existing   |
| `DraftEvent`          | **new**    |
| `DraftPickGrade`      | **new**    |
| `CareerArcState`      | **new**    |
| `DraftReputation`     | **new** (or extend Career) |

## 11. Error Handling

| Situation                          | Handling                                                      |
|------------------------------------|---------------------------------------------------------------|
| User doesn't pick in time          | 30 s grace → AI BPA pick → "Owner override" toast (feature)   |
| SwiftData save error               | Rollback + non-blocking toast, retry after 2 s                |
| Engine error (no available)        | Force-end draft + log                                         |
| Trade offer expires while pondering| Offer disappears, "Giants withdrew offer" toast               |
| Invalid trade (don't own pick)     | UI prevents at Trade Builder level                            |

## 12. Testing Strategy

### Unit (Swift Testing)
- `DraftEventEngine`: determinism, AI pick logic, trigger conditions
- `PickGradeCalculator`: Value Δ, threshold boundaries
- `TradeEvaluator`: chart, future discount, personality factor
- `DraftIntel`: noise application, custom vs BB rank
- `SkipController`: target-reaching, trade interrupts, ticker history
- `CareerArcEngine`: True Grade transitions

### Integration
- Full-draft sim: 224 picks, no duplicates, all teams pick
- Save/load mid-draft: state restores
- Coordinator state machine: all transitions exercised

### Playtest (the "feel" test)
Use `auto-analyze` skill to run a draft in iOS simulator, capturing screenshots and logs per pick.

**Per-iteration metrics**:
| Metric                                  | Target |
|-----------------------------------------|--------|
| Subjective excitement (1–10)            | ≥ 7    |
| Gem feeling identified                  | yes    |
| Reach pick drew credible criticism      | yes    |
| Trade offers felt contextual            | yes    |
| Skip never missed a trade offer         | 100 %  |
| Reactions never overwhelmed             | ≤ 3 visible at once |
| Pick Grade matched intuition            | ≥ 80 % |
| Visual polish (★1–5)                    | ≥ 4    |

## 13. ReAct Loop — Phased Iteration

The implementation runs as six iterative phases, each its own `RUN → ASSESS → FIX` cycle.

| Phase | Focus                                  | Acceptance criterion                                                                 |
|-------|-----------------------------------------|--------------------------------------------------------------------------------------|
| 1     | Core mechanics                          | Draft completes end-to-end, no crashes, user pick visible                            |
| 2     | Decision support                        | Smart pick achievable from UI alone; reasons visible                                  |
| 3     | Trade Engine + reactions                | Trade offers feel fair; reactions enrich drama                                        |
| 4     | Drama + visual polish                   | Recognizable as "the draft" from across the room (invoke `design` / `ui-ux-pro-max`)  |
| 5     | Career Arc + story flashbacks           | 3-season sim surfaces a gem arc and a bust arc                                        |
| 6     | Balance + QA                            | 5/5 manual playtests rate "felt great"; 20+ auto-analyze runs hit metric targets      |

Per-iteration notes go to `docs/playtest-notes/YYYY-MM-DD-draft-iteration-N.md`.

**Stop conditions**: all six phases meet acceptance + 4/5 manual playtests rate "felt great" + auto-analyze averages hit targets.

## 14. Out of Scope (for this design)

- Multi-year mode (drafts beyond the current career arc)
- Multiplayer / asynchronous drafts
- Voice commentary / audio
- Draft Day Day-1 / Day-2 / Day-3 broadcast pacing differentiation (could be added in Phase 4 polish)
