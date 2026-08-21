# Life Events System — Design Plan (#210)

*Drafted 2026-08-14. Status: DESIGN READY — implementation awaits user review.*
*Research foundation: `docs/life-events/research/` (4 reports, ~4,100 lines, citation-grounded).*
*Event catalog: `docs/life-events/catalog/` — 347 events across 3 files, all validated JSON.*
*Companion analysis: `docs/INJURY_SYSTEM_ANALYSIS.md` (#211) — shares the W0 prerequisite.*

## 1. Vision

Players are people. Between and during seasons they get arrested, suspended, married, robbed,
injured on jet skis, called out on podcasts, nominated for community awards — and each of these
lands on the roster as availability, focus, chemistry, money, or negotiating-table consequences.
The coach experiences this as a news feed, occasional blocking pop-ups with real decisions, and
visible status on the player card: **what is wrong (or right) with this player, and for how long.**

Design pillars, each traceable to research:

1. **The calendar is the mechanic** (r3). Events roll from calendar nodes (fireworks in early July,
   holdouts at camp-report day, anonymous-source stories in weeks 8–14 of losing seasons, burglaries
   during away games) — not from a flat weekly die.
2. **Incidence is flat, consequences are stratified** (r1). Stars and depth players get in trouble at
   the same rate; what differs is what happens next. Release speed tracks contract leverage, not
   charge severity (fringe median: 1 day; star: months-to-never).
3. **Three random shapes, not one** (r2): steady Poisson (PED ~16/yr), regime-gated rarity
   (substance suspensions post-2020 ≈ legal events only), and epoch clusters (gambling waves,
   burglary crews). The catalog encodes each shape explicitly.
4. **Two damage channels** (r3): availability AND money. NFI voids guarantees and pays no salary;
   Reserve/Suspended forfeits 1/18 salary per game and frees a roster spot; conduct suspensions do
   NOT void bonuses (r1 §Forfeitable Breach) — the money rules are where a GM actually feels events.
5. **Valence is contextual** (r3). A camp fight is "intensity" on a contender and "dysfunction" on a
   4-win team. 20+ events compute their framing from record vs expectation at fire time.
6. **Positives are structural, not rolled** (r3): 32 community-award nominees per season by rule,
   exactly one winner; captaincies, mentorships, milestone chases. ~25% of the catalog is
   positive/neutral so the system reads as "life", not "punishment".
7. **Personality decides who** — gates use ONLY existing frozen fields (see §4.3).

## 2. Catalog summary (347 events)

| File | Events | Coverage | Expected/league-yr (primary) |
|---|---|---|---|
| `k1_legal_discipline.json` | 121 | arrests (12 families), conduct policy, PED/SOA/gambling tiers, exempt list, appeals, pre-draft red flags | 57.2 primary + 59.1 derived (arcs) |
| `k2_personal_life.json` | 113 | relationships/births/bereavement, tragedy & burglary epoch, 25+ NFI mechanisms, mental health | 411.6 (mostly `userTeamOnly`; 173.6 league-wide feed) |
| `k3_drama_media_positive.json` | 113 | hold-ins/trade requests/tag drama, locker room & media, positives & milestones (38%) | 574.5 (185.2 league-wide feed) |

Feed budget: league-wide surfacing ≈ 360 items/season ≈ 11/club ≈ **~0.6 feed items/week for the
user's club plus league headlines** — plus `userTeamOnly` items (births, minor beats) only when they
hit the user's roster. Pop-ups: majors + everything carrying a decision (62 events have genuine
multi-option coach decisions; 118+ have multi-stage resolution arcs).

Every event carries: probability + calendar nodes + calibration line tracing to a research figure;
eligibility (position/age/star-tier/personality gates, repeat-escalation from real recidivism data);
effects with **explicit durations** on every lasting modifier; **playerCard block** (badge + countdown
+ detail line + career-timeline history entry — user requirement); resolution arcs with real
disposition rates (e.g. arrests: 47-50% convicted / 31% dropped / 13-15% diversion; DV inverts).

### Catalog conventions (cross-file, normative)

- **`scope`** field (K2 innovation, adopt everywhere): `player | team | league`. The playerCard
  requirement binds only `scope: "player"`.
- **Hold-in ≠ holdout** (K3): a hold-in must NOT set `Player.isHoldingOut` (that flag removes the
  player from the game sim). Only true holdouts do, via `HoldoutEngine.startHoldout`.
- **Money routing** (K3): no event writes contract money directly — route through
  `DealTargetYear.plan` + verdict (#186 machinery).
- **`motivation.set` normalization**: catalogs use both `"distracted"` (K2/K3, 36 events — focus
  loss, external cause, temporary) and `"discouraged"` (K1, 34 events — morale loss). Implementation
  adds **`.distracted` as a new MotivationState case** (String-raw enum on an optional column —
  schema-free per c1). Both semantics stand; `.distracted` is wiped at `trainingCamp` like the rest,
  so in-season durations carry their own week counters in LifeEventsState.
- **Field-name corrections** (writers verified against source): `PlayerPersonality.discipline` and
  `MentalAttributes.composure` do NOT exist — gates use `workEthic`/`coachability`/`clutch`/
  `Player.competitiveness`. `MotivationState` today = `driven/focused/complacent/discouraged`.

## 3. Architecture

### 3.1 Persistence — no V2 migration needed (c1 §8)

Follow the established blob pattern (26 precedents on `Career`, e.g. `lockerRoomLogData` +
`pendingLockerRoomEventData`): three new `Data? = nil` columns on Career with inline defaults —
`lifeEventsStateData` (scheduler state: epoch flags, per-player cooldowns/priors, node cursors),
`lifeEventLogData` (resolved history, capped), `pendingLifeEventData` (queued popups/decisions) —
plus typed computed-property bridges and a `season` stamp via the self-invalidating
`UDFAMarketEngine.state(career:)` pattern. `docs/SWIFTDATA_MIGRATION_PLAN.md` §4.1 confirms this is
migration-free. **Forbidden without V2:** new fields on `PlayerPersonality`/`MentalAttributes`
(frozen composites — a non-optional addition silently empties every save's blob), any @Model schema
change, any rawValue rename.

### 3.2 Engine

- **`LifeEventsEngine`** absorbs the dead first draft: `EventEngine`/`EventTemplates` already define
  `EventType` (arrest, suspension, socialMediaIncident, tradeRequest…) and `EventOption`'s 4-meter
  effect vector — with zero callers/renderers. Absorb, don't duplicate (the `FAStorylineEvent`
  orphan is the cautionary tale). The inert `freakInjury` template becomes the first real event.
- **Catalog as bundled resource**: the 3 JSON files ship (fictionalized, English-only, trademark-clean
  — word-boundary-verified) and are decoded once per launch; a build-time validator enforces schema
  + forbidden-token rules (extend `trademark_guard.sh` to cover the bundled catalog).
- **Scheduler**: hooks at `WeekAdvancer.advanceWeek:917` (both lanes; in-season `:1737`, offseason
  `:4086`). Each tick resolves the current calendar node(s), draws per-club then per-player using
  **seeded RNG** — SplitMix64 from `(careerID, season, salt)` + `playerSalt(id)` per the
  `ScoutingEngine.cycleSeed` pattern (never `hashValue`; iteration-order-independent). Epoch flags
  (burglary wave, gambling wave) live in LifeEventsState with onset/decay rolls.
- **Availability**: suspensions land on a `reserveSuspended` state — **shared `PlayerAvailability`
  model (W0)** so the ~25 `!isInjured && !isHoldingOut` call sites are edited once, jointly with the
  injury overhaul (#212). Suspension shares availability but NOT the medical loop; NFI is its own
  list with the no-pay/guarantee-void levers. NOTE: today injuries don't gate the sim at all
  (c2 gap 1) — wiring availability into `GameSimulator`/`LiveGameEngine`/`MatchupResolver` moves
  balance numbers by design and must land with harness gates.
- **Effect wiring** (all existing seams, c1): morale 4-meter vector (owner/fans/lockerRoom/player);
  `MotivationState` + new `.distracted`; contract willingness via ONE new
  `ContractNegotiationEngine.situationBreakdown` Source case (`.lifeEvent`); development via existing
  xp-multiplier path; performance debuffs as fog-safe effective-rating modifiers (never surfaced as
  trueOverall); fines/forfeits via cap ledger receipts (engine-side, like #188's lesson: receipts
  written inside the engine op).

### 3.3 UI

- **News**: catalog headlines/bodies flow into the existing inbox/news feed (`inboxData`/
  `newsLogData` surfaces). `userTeamOnly` filtering per catalog rule 4.
- **Pop-ups**: majors + decisions through the single enum-sheet point (`CareerShellView:36/:732/:741/:900`
  — exhaustive switches), DSResultSheet standard, one gold fill per screen (the decision CTA).
- **Player card** (user requirement): active-event badge chip with countdown (`SUSPENDED · 2 GM`,
  `NFI · 4 WK`, `DISTRACTED`, `BEREAVEMENT`, `HOLD-IN`, `CAPTAIN`…), a status detail line, and a
  career-timeline **history entry** after resolution (fogged wording). All catalog events with
  lasting effects carry the `playerCard` block already.
- **Decisions matter mechanically**: e.g. high-leadership CAPTAIN badge unlocks the
  "let the room handle it" option in three drama templates; club framing choice on mental-health
  events changes repeat probability.

### 3.4 Balance & harness

- `LifeEventsEngine` (+ touched engine files) added to `sync_sources.sh` (sha-verified verbatim
  set — 33 files today; touching `MotivationState`/`PersonalityArchetype` etc. requires the sync
  update or the career/draftclass gates break).
- New harness diagnostic block: events/league-year by family vs calibration targets, availability
  man-games lost, morale-meter drift, contract-willingness deltas — gates on the calibrated bands.
- Existing gates (career 36/36 ×3, draftclass 39/39, leaguegen 19/19) must stay green; the
  availability wiring is the risky part and belongs to W0/W1 with before/after measurement.

## 4. Phasing (each wave gated, no commit without user's word)

- **W0 — PlayerAvailability (shared prerequisite with #212).** One model consumed by sim, dev, trade
  AI, UI; injury/holdout semantics preserved exactly; harness measures the (intended) balance shift
  when availability starts gating the sim. This is also injury-overhaul R1 — do it once.
- **W1 — Engine core.** Persistence blobs, catalog loader + validator, scheduler + seeded draws,
  effect application for news-tier events (no decisions yet), news-feed surfacing. Sim-QA on scratch
  sims; harness diagnostics.
- **W2 — Decisions & card.** Pop-up sheets with option vectors, player-card badges/countdowns/history,
  decision consequences + followupRisk tracking. Image-judge QA both orientations (per project rule).
- **W3 — Arcs & epochs.** Multi-stage legal arcs (charge → resolution forks with real disposition
  rates), appeal delays, epoch flags (waves), repeat-escalation counters, contract seams
  (`.lifeEvent` willingness, NFI guarantee voids, suspension forfeits).
- **W4 — Calibration.** Tune to catalog targets with the harness block; adversarial review of fog/
  careerID/determinism; full gates; TestFlight-facing polish.

Estimated engine surface: ~10 new files + ~15 touched; the catalog ships as data, so content
iteration after W1 is JSON-only.

## 5. Compliance & content rules

All shipped content fully fictional (placeholders `{PLAYER}`/`{TEAM}`/`{CITY}`…), English-only,
word-boundary trademark-clean ("the league", "the Championship" — verified over all 347 events);
real incidents informed *rates and shapes only*. One deliberate content boundary from research
(r1 §"do not model"): the system never encodes demographic risk factors — eligibility gates are
personality/attribute/role-based only. Mental-health events are non-punitive by construction
(no fines, no suspensions, no permanent attribute loss — the only lever is the club's framing
choice). One permanent attribute loss exists in the entire catalog (fireworks amputation).

## 6. Open questions for the user

1. **Volume dial**: default calibration is realism-anchored (~0.6 league-wide feed items/week for
   your club + userTeamOnly extras). Want a settings slider (Off / Realistic / Dramatic ×2)?
2. **Severity ceiling**: the catalog includes rare career-enders (death, banishment, amputation) at
   realistic (tiny) rates. Keep, or cap at season-ending?
3. **Retroactive saves**: enable on existing careers at next league-year rollover (safest) or
   immediately mid-season?
4. **Staff events**: research covers coach-side incidents too (front-office gambling leak is the
   current real-world risk shape) — in scope for v1 or later?
