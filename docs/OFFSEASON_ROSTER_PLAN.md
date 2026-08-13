# Offseason Roster Plan — #204 (UDFA market) + #205 (90 → 53 arc, preseason games)

Status: PLAN. Written 2026-08-12 against audits A (#204) and B (#205).
Scope: the four offseason phases `.otas → .trainingCamp → .preseason → .rosterCuts`,
plus the `.draft` exit that feeds them.

Everything below is anchored to code that exists today. Line references are to the
tree at the time of writing; treat them as pointers, not as coordinates.

---

## 0. What the audits established, and the two places this plan overrules them

**Audit A (#204) — confirmed and adopted.** There are two unrelated UDFA paths that
share no pool definition, no quota and no ordering:

1. `DraftDayCoordinator.prepareUDFAStage / signUDFA / finishUDFASigning` +
   `UI/Draft/Components/DraftUDFAPanel.swift`, reachable only while
   `career.currentPhase == .draft` and only from inside the Draft Day route
   (`CareerShellView.isDraftRoomLive`, :1786).
2. The bulk fallback in `WeekAdvancer` `case .otas` (~:3750-3815), which
   **explicitly excludes the user's club** (`teams.filter { $0.id != career.teamID }`)
   and tells him about it by inbox message afterwards.

Three defects the audit found are treated as part of this wave's definition of done:

- **D1 — the bulk loop never clears `prospect.isDeclaringForDraft`.** The coordinator
  path does (`DraftDayCoordinator` :1531/:1585/:1591); the OTAs loop does not, so every
  AI-signed UDFA stays "declared" for `ClassDepthView`, `ScoutingHub` and the
  coordinator's own restore until `purgeStaleSeasonData` deletes the rows.
- **D2 — fog leak.** The inbox message prints `playerUDFAs.prefix(5)` off a pool sorted
  by `trueOverall` (`ScoutingEngine.getUDFAPool`, :3114). That is the league's real
  top five, printed past the scouting screen. Violates invariant (5).
- **D3 — no cap check, no need matching, no roster ceiling** on the fair-share loop.

**Audit B (#205) — confirmed, with one refinement and one correction.**

- Confirmed: **no new `SeasonPhase` cases.** Adding `.preseasonWeek1/2/3` would touch
  30+ exhaustive switches and shift `overallOrdinal` for every later phase. Invariant (2)
  permits additive cases; this plan does not need one.
- **REFINEMENT (overrules Audit B's proposed mechanism).** Audit B proposed holding
  `.preseason` for three advances with a sub-counter, which forces changes to
  `TaskProgressStore.cycle(season:phase:week:)` (`TaskGenerator.swift` :100) and to
  `CareerShellView.regenerateTasks`' `lastGeneratedWeek` guard (:2537). **That is not
  necessary and this plan does not do it.** The codebase already ships a
  multi-step-inside-one-phase machine: free agency runs an entire multi-round market
  inside a single `.freeAgency` phase, driven by `Career.freeAgencyRound` (:56) and
  `Career.freeAgencyStep` (:58) with `FAFlowBand` / `FAWeeklyView` / `FARoundSummaryView` /
  `FACompleteView` as its screens. **Preseason uses the same shape**: three games as three
  steps inside one `.preseason` visit, driven by `Career.preseasonStep`. Zero changes to
  `phase(after:)` (`WeekAdvancer` :5245-5249), zero changes to `TaskProgressStore`, zero
  risk to invariants (2) and (4).
- Confirmed: **preseason results must not be `Game` rows.** `Game` has only `isPlayoff`,
  and `career.currentSeason` is still the *finished* year N throughout the offseason
  (`+= 1` happens at the rosterCuts→regularSeason step, `WeekAdvancer` :4045). A preseason
  row at (season N, week 1-3, isPlayoff false) collides with season N's played weeks 1-3
  and corrupts `StandingsCalculator`, the schedule screen and `MultiSeasonSmokeTest`.
  This plan persists preseason as a **Codable blob on `Career`** — no new `@Model`, no
  SwiftData migration, no `FetchDescriptor<Game>` exposure at all.
- **CORRECTION to Audit B's cap arithmetic.** Audit B is right that a 90-man camp roster
  is ~$27.8M of new charge per club and that this hard-gates the user from `.proDays`
  onward (`CapManagementEngine.isComplianceWindow`, :758-768). It frames the choice as
  "top-51 rule **or** cap-exempt camp bodies". A literal top-51 rule is **not viable
  here**: `Team.currentCapUsage` is an *incrementally maintained* ledger (`+=` / `-=` at
  ~a dozen sites) that is only rebuilt from the roster once a year, at
  `FreeAgencyEngine.executeNewLeagueYear` :696-702. A top-51 rule is a statement about a
  *sorted set*, which an incremental ledger cannot express without recomputing on every
  mutation. This plan therefore takes the exemption route — see §3.

---

## 1. Phase map — what happens where

No new `SeasonPhase` cases. No change to `phase(after:)`. The existing chain
`draft → otas → trainingCamp → preseason → rosterCuts → regularSeason` is unchanged;
each phase gains an *in-phase step machine* where it needs one, and one new roster
ceiling gate on its exit.

| Phase | Roster on entry | What the phase is | In-phase steps | Exit gate |
|---|---|---|---|---|
| `.draft` (exit) | ~53 | Draft concludes. **UDFA market opens**: the undrafted remainder becomes a live market, `Career.udfaRound = 0`. | — | none (unchanged) |
| `.otas` | ~53 + picks | **UDFA frenzy** (#204) — the user works a board, 31 AI clubs bid against him over 3 rounds. Then **camp fill**: the 90-man camp is assembled from the unsigned pool, round-robin, never generated. Existing OTAs work (depth chart, training focus, mentoring) unchanged. | `udfaRound` 1→2→3 → `closed`, driven by `UDFABoardView` | none |
| `.trainingCamp` | ≤ 80 | Camp as today (`applyCampWeeklyTick`, `applySchemeChanges`, `processOffseason`, battles) on a real 80-man roster. | — | **Cut to 75** (required task; `userRosterLimitViolation` ceiling 75) |
| `.preseason` | ≤ 75 | **Three sim-only games** (#205). Per game: starter policy → sim → `DSResultSheet` recap. | `preseasonStep`: `game1 → game2 → game3 → complete` | **Cut to 65** (required task; ceiling 65) |
| `.rosterCuts` | ≤ 65 | Final cutdown as today; `trimAIRosters`, battles resolve, camp grades. | — | **Cut to 53** (existing `userRosterLimitViolation`, ceiling 53) |

**Why 80 and not 90.** `TradeValueEngine.offseasonRosterCeiling` is already **90** (:3118)
and its own doc comment claims "between the draft and cutdown day this league carries
80-90 players" — a claim that is false today and that this wave finally makes true. But
filling *to* the ceiling would make every offseason acquisition illegal on the body count
and kill the AI trade market in exactly the windows §5 of the trade plan expects business.
Fill target is therefore **80**, leaving ten slots of headroom under the rule that already
exists. `restockedRosterFloor = 40` (:3143) never binds at 80, so invariant (3) is
untouched: the phase-staggered floors and the cutdown ladder do not overlap anywhere.

**Why the ladder rungs move to earlier phases.** Today all three rungs
(`Cut to 75` / `Cut to 65` / `Cut to 53`) are emitted by `TaskGenerator.rosterCutsTasks`
(:1178-1240) into the single `.rosterCuts` phase, where a 60-man roster makes two of them
no-ops. `RosterCutView` already derives its stage from the roster count
(`CutDay.stage(forRosterCount:)`, :716) rather than storing it, so **the screen needs no
stage change at all** — only the task rows and the exit ceiling move. That satisfies spec
item (5): the trim points appear in the left menu at the phase where they are actually due.

---

## 2. #204 — the UDFA market

### 2.1 The architecture decision: prospect-native market, not Player-native

The pool could be converted to `Player` rows at market open, which would unlock
`SigningInterestEngine`, `FAOfferSheet` and the whole FA UI for free. **Rejected**, for two
reasons that are both load-bearing:

1. **Fog.** A `Player` row carries true attributes. The whole point of spec item (1)
   ("FA:n ajatus draftaamattomilla, **scoutatuin arvoin**") is that the user bids on
   `scoutedOverallGrade` / `scoutedPotentialLabel` / `scoutedPositionGrades` bands, which
   live on `CollegeProspect` (:66-75). Converting first and fogging afterwards means the
   fog is a display convention over true data — invariant (5) says it must be the other
   way round.
2. **Face claims.** `DraftEngine.convertUDFAToPlayer` → `copyProspectMetadata` (:368) calls
   `FaceLibrary.shared.claimFace`. Building ~110 candidate `Player`s to price a market
   would claim ~110 faces a season for men who are never signed. The face pool is 3 584
   ids and `MultiSeasonSmokeTest.auditFaces` already reports it running to `free=0`.

So the market is **prospect-native**. `Player` rows are created exactly where they are
created today: at the moment of signing, through `convertUDFAToPlayer`.

### 2.2 Reusing the FA math without copying it

`SigningInterestEngine.interest(player:…)` (:69) reads only four things off the `Player`:
`personality.motivation`, `overall`, `position`, `id`. `roleScore` (:140) reads
`overall` + `position` + the roster.

**Refactor, not duplicate:** introduce a value input and make the existing entry point
delegate to it. No behaviour change for any current caller.

```swift
// SigningInterestEngine.swift
struct Candidate {                      // NEW
    let id: UUID
    let position: Position
    let overall: Int                    // TRUE overall — engine-side only
    let motivation: Motivation      // Domain/Enums/Motivation.swift
}
static func interest(candidate: Candidate, askingPrice: Int, offer: …, team: Team,
                     allPlayers: [Player], offensiveScheme: …, defensiveScheme: …,
                     hostedVisit: Bool) -> Breakdown            // NEW, holds the math
static func interest(player: Player, …) -> Breakdown            // delegates to the above
```

Scheme fit is the one factor that cannot be reached this way — `CoachingEngine.schemeFit`
takes a `Player`. For a prospect the market passes `nil` (the engine's documented
neutral 0.5), which is honest: nobody knows how an undrafted rookie fits a system.
Record that as a deliberate simplification in the engine doc comment.

`BiddingHeatEngine.computeHeat` (:21) is keyed on `playerID` + `[FABid]` + `[FAVisit]`
and is reusable verbatim if the market writes `FABid` rows keyed on the **prospect's**
UUID. There are no visits in the UDFA market (there is no time for them in the real
league either), so `visits: []`. `FrenzyHeatTier.inflationModifier` then prices the
market exactly as free agency does.

`PlayerPreferenceEngine.offerRanking` (:67) and `OutbidNotifier.detect` (:47) are
UUID-and-bid based and are reused as-is.

### 2.3 The market machine

New file: `dynasty/dynasty/Engine/FreeAgency/UDFAMarketEngine.swift`.

```
openMarket(career:prospects:teams:)      // at .draft exit — seeds state, no signings
runAIRound(career:teams:allPlayers:…)    // one competitive round, 31 clubs
submitUserOffer(prospect:terms:)         // writes an FABid on the prospect's id
resolveRound(…) -> RoundOutcome          // who signed where, who is still open
closeMarket(career:…)                    // survivors return to the undrafted street pool
```

Rules, each one answering a defect the audit named:

- **Pool** — `ScoutingEngine.getUDFAPool` stays the pool definition (one authority), but
  gains an ordering that is not `trueOverall`: the market ORDER the user sees is his own
  board order (fog), and the AI's internal ordering stays `trueOverall` because an AI club
  has its own scouting. **Fixes D2** — nothing user-facing is ever sorted or printed off
  `trueOverall`.
- **Quota** — a club signs up to **6** UDFAs (the real number is 15-20, but this league's
  undrafted remainder is ~100-126 against 32 clubs; 6 is what the pool can actually
  support and still leave the user a market to compete in). The user's ceiling is the
  same 6 — no privileged quota.
- **Competition** — a prospect with N bidders prices at
  `askingPrice × FrenzyHeatTier.inflationModifier`. A UDFA's asking price is
  `DraftEngine.udfaContract(salaryCap:)` (three years at max(0.30 % cap, vet-min)),
  which stays the single definition of what a UDFA costs.
- **Cap** — every signing goes through the same charge path as any other
  (`team.currentCapUsage += player.annualSalary`), and a club that cannot fit the deal
  does not make it. **Fixes D3.**
- **Need** — AI clubs bid on `DraftEngine.topTeamNeeds(roster:limit:)`, not on the top of
  the list. **Fixes D3.**
- **Declaration** — `signUDFA` sets `prospect.isDeclaringForDraft = false` on *every*
  path, AI included. **Fixes D1.** This is the single most important one-line fix in the
  wave: it is the reason `ClassDepthView` and the scouting hub currently lie after the draft.
- **Round-robin fairness** — bid resolution iterates clubs in a shuffled order each round
  (the lesson `WeekAdvancer` :3757 already records as "defect #10", and the one
  `PracticeSquadEngine.fillSquads` re-learned as #144).

### 2.4 Persistence

`Career.udfaMarketData: Data? = nil` — inline default, never in `init`, exactly the
pattern every other blob on `Career` uses (`pendingTradeOffersData`, `inboxData`, …).
Contents:

```swift
struct UDFAMarketState: Codable {
    var season: Int
    var round: Int                  // 0 = not opened, 1-3 live, 4 = closed
    var signedProspectIDs: [UUID: UUID]   // prospect -> team
    var bids: [UDFABid]             // prospect, team, salary, years, submittedAt
    var userSignings: [UUID]
}
```

Career-scoped by construction (invariant 6): it lives on the `Career` row.

### 2.5 What happens to the two existing paths

- The `WeekAdvancer` `case .otas` bulk block is **deleted** and replaced by a call into
  `UDFAMarketEngine`. `udfaStageCompletedSeasons` (the process-global set) goes with it —
  process globals do not survive a cold launch, which is half of why the current path is
  unreliable. The season stamp lives in `UDFAMarketState.season`.
- `UI/Draft/**` is owned by the parallel v3.1 run and is **not touched in this wave**.
  `DraftUDFAPanel` therefore keeps working: if the user finishes UDFA signing on draft
  night, `closeMarket` sees a season already stamped and the OTAs board opens in its
  "market closed" state. **Follow-up ticket #204f** (post-merge, not this wave): reduce
  `DraftUDFAPanel` to a priority-board flagging surface and route its "Finish" into
  `UDFAMarketEngine.openMarket` so there is exactly one market. Until then the two paths
  are *exclusive*, not *contradictory* — which is already a strict improvement.

  > **SUPERSEDED by §3.3a (#208 G2).** They were contradictory, and the cost was the whole
  > wave: the panel's "Finish" cleared `isDeclaringForDraft` on the entire remainder, which
  > emptied the pool predicate before `openMarket` ever ran. #204f is done — the panel now
  > closes only the user's window and signs nobody else.

---

## 3. #205a — the 90 → 53 arc and the cap

### 3.1 The cap decision: camp bodies are cap-exempt, and why that IS the top-51 rule

**Decision.** A man carried above the 53 during the offseason is a **camp body**. His
salary is recorded on his row and is **never added to `Team.currentCapUsage`** while he is
one. The flag clears — and his salary is charged — the moment he survives to the 53, at the
`rosterCuts → regularSeason` boundary.

**Why this is the right simplification, not a dodge.** The real top-51 rule says: during
the offseason, only the 51 largest cap numbers count. The population it excludes is
precisely the bottom ~38 minimum-salary deals. Here, camp bodies are *by construction* the
men signed at or near `ContractEngine.veteranMinimum(cap:)` = `max(0.0028 × cap, 750)`,
i.e. exactly that population. The economic content is identical; the difference is that
this version is expressible in the ledger shape the codebase actually has.

**Why the literal rule is not available.** `currentCapUsage` is incremental
(`+=` / `-=` at `CapManagementEngine.applyRelease` :469, `ContractEngine` :1482/:1632,
`ContractExtensionSheet` :588, the UDFA and refill loops, …) and is rebuilt from the roster
exactly once a year (`FreeAgencyEngine.executeNewLeagueYear` :696-702). "The top 51 by
salary" changes membership on every mutation, so a literal rule means recomputing the whole
sum on every one of those sites — i.e. abandoning the incremental ledger. That is a
separate, larger piece of work (and a good candidate for the SwiftData migration wave).

**Precedent in-repo.** `PracticeSquadEngine`'s header states the same choice for the same
reason: "squad salary is recorded on the row for display but is never added to
`Team.currentCapUsage` … the cap ledger is maintained incrementally and its refund paths
all key on `player.teamID != nil`, so a charge made against a `teamID == nil` player could
never be refunded and would leak."

**The trap that precedent also warns about.** A camp body has `teamID != nil` (he must
dress in preseason, appear in the depth chart, be visible to `GameSimulator`), so the
refund paths *would* fire for him. Exactly one guard prevents the leak, in the one release
door the codebase already has:

```swift
// CapManagementEngine.applyRelease — the ONE release door (#102 F8)
// A camp body was never charged; crediting his salary back would walk the
// ledger down by the full amount on every camp cut.
guard player.rosterStatus != .campBody else { /* receipt only, no cap credit */ }
```

`FreeAgencyEngine.executeNewLeagueYear`'s true-up loop (:696) additionally filters
`rosterStatus != .campBody` — defensive, since the flag is always cleared before the next
rollover, but the true-up is the ledger's ground truth and it must not be able to disagree.

### 3.2 Data model

**`RosterStatus` gains one case** (`Domain/Models/Player/Player.swift` :663).

```swift
enum RosterStatus: String, Codable, CaseIterable {
    case active
    case practiceSquad
    case campBody          // NEW
}
```

Additive, rawValue-stable, and `rosterStatusRaw` already has an inline default
(`RosterStatus.active.rawValue`), so this is a safe lightweight migration. `rosterStatus`
has **13 usages repo-wide**; the two exhaustive switches are `displayName` and `shortLabel`
in the same file ("Camp Body" / "CAMP"). `isOnPracticeSquad` (:281) is unaffected.

Chosen over a new `Player.isCampBody: Bool` because the concept is a *roster tier*, and the
game already has an enum whose job is exactly that. One authority, not two.

**`Career` gains three stored properties**, all inline-defaulted, never in `init`:

```swift
var udfaMarketData: Data? = nil       // §2.4
var preseasonData: Data? = nil        // §4.3
var campFillSeason: Int = 0           // season the 80-man camp was assembled for
```

`campFillSeason` is the idempotency stamp for the fill pass — the same shape as
`Career.lastRolloverSeason` (:83) and `lastBulkMarketSeason` (:103), and the reason the
fill cannot double-run on a re-entered phase.

### 3.3 The camp fill

New file: `dynasty/dynasty/Engine/Camp/CampRosterEngine.swift`.

Runs on the `.otas` exit, after the UDFA market closes, for **all 32 clubs including the
user's** (this is the other half of Audit A's complaint — a league-wide pass that skips the
user's club is a bug, not a design).

```
fillCampRosters(career:teams:allPlayers:modelContext:) -> FillSummary
```

Rules, each with its reason:

- **Target 80, ceiling 90.** §1. Under `TradeValueEngine.offseasonRosterCeiling`, so the
  offseason trade market keeps ten slots of headroom.
- **NEVER generate a player.** The target is a *ceiling, not a quota*. A club that cannot
  find bodies carries fewer. This is `PracticeSquadEngine.squadGenerationFloor`'s lesson
  (#99) verbatim: the unbounded version of that pass minted 417/250/212/244 players a
  season and was the inflow half of the shadow-pool pathology. Here the arithmetic is
  worse — 32 clubs × ~27 open camp slots is ~860 bodies a season — so the generator door
  is closed outright, with no floor at all.
- **The pool is the resource, and the cycle is closed.** The unsigned pool is measured at
  ~900 (`PracticeSquadEngine` doc, #99). 900 / 32 ≈ 28, so filling to 80 parks essentially
  the whole shadow pool on camp rosters for four phases and returns it at cutdown. Net
  minting ≈ 0; the pool stops being a stagnant reservoir and starts being inventory. This
  is the single most interesting *balance* consequence of the wave and §6 measures it.
- **Round-robin, shuffled club order, one man per club per pass**, best-need-first within a
  club (`DraftEngine.topTeamNeeds`). Not club-at-a-time: that is defect #10 (`WeekAdvancer`
  :3757) and the #144 finding in `fillSquads`, both of which were "the first few clubs
  emptied the market".
- **Contract**: 1 year at `ContractEngine.veteranMinimum(cap:)`, no signing bonus →
  `applyRelease` books **zero dead money** on a camp cut. `rosterStatus = .campBody`,
  `careerID` stamped (invariant 6).
- **Camp bodies skip the expensive per-player passes.** `applyCampWeeklyTick` /
  `PlayerDevelopmentEngine.processOffseason` already skip AI clubs' per-player work for
  speed; camp bodies get the cheap path everywhere (workload tick and a camp grade only, no
  training-plan pass, no mentoring, no position battles). See §7 risk R5.

### 3.3a AMENDMENT — #208 G2: why the camp was still empty after wave 1

Wave 1 shipped `CampRosterEngine.fillCampRosters` exactly as §3.3 describes it and QA
still measured the user's roster peaking at **61**, with "Cut to 75" and "Cut to 65"
auto-satisfied on arrival. The mechanism was correct; two premises above were not.

**Premise 1 was false: the draft-night panel was still the league's UDFA market.**
§2.5 parked `DraftUDFAPanel` as "exclusive, not contradictory" and deferred the merge to
follow-up #204f. It was contradictory. `DraftDayCoordinator.finishUDFASigning` signed
**ten undrafted men per AI club** on draft night and then cleared `isDeclaringForDraft`
on the entire remainder. `ScoutingEngine.udfaPoolMembers` — the one pool predicate — is
`isDeclaringForDraft && mockDraftPickNumber == nil`, so:

| step | what wave 1 expected | what actually happened |
|---|---|---|
| draft night, "Finish" | user signs ≤ 5, class stays declared | ≤ 5 to the user, ~310 slots to the AI, **flag cleared on everyone else** |
| `.draft` exit, `openMarket` | seeds a live 3-round market | pool empty → market opens in its CLOSED state |
| `.otas` exit, `closeMarket` | resolves the owed rounds, writes survivors | nothing owed; `unsignedProspectIDs = []` |
| `.otas` exit, `fillCampRosters` | pool **+** undrafted survivors | free-agent pool only |

So #204's market never ran in the played path, and the camp fill lost its second source
entirely. **Fix:** `finishUDFASigning` now closes only the user's window — no AI bulk
signing, no blanket declaration clear — and `closeMarket`'s survivor sweep is keyed on
`isDeclaringForDraft` alone rather than on `udfaPoolMembers`, so a projected pick who slid
out of all seven rounds is swept off the scouting screens (D1) *and* becomes camp
inventory instead of being discarded. `campInviteCandidates` drops its mirrored
`mockDraftPickNumber == nil` clause for the same reason. #204f is closed by this.

**Premise 2 was false: there is no ~900-man unsigned pool.** §3.3 sized the resource from
`PracticeSquadEngine`'s #99 note and concluded "900 / 32 ≈ 28, so filling to 80 parks
essentially the whole shadow pool". The played league carries roughly **a hundred**
unsigned men at the `.otas` exit — #99 was fixed, and its inflow with it. Against that
inventory a strict one-man-per-club round robin deals 32 × 3 and stops: every club gets
three, nobody gets a camp, and the user's ladder is dead on arrival. QA's 58 → 61 is that
arithmetic exactly.

**Fix:** the fill now runs in two phases. **Phase A** fills the user's club to
`campRosterTarget` first, one turn at a time, out of the same inventory and through the
same `takeTurn` every club uses. **Phase B** is §3.3's round-robin, unchanged, over what
is left. This is not a privilege: the user's is the only camp in the league that is
played, the only one with a cut ladder gated on it (`userRosterLimitViolation`), and the
31 others are trimmed to 53 by `trimAIRosters` without anybody looking at them. Audit A's
defect was *excluding* the user from a league-wide pass; serving him first is its opposite.

**Target stays 80, not 90.** The ladder is real work at 80 (cut 5, then 10, then 12) and
`TradeValueEngine.offseasonRosterCeiling` is 90 — filling to the ceiling would veto every
offseason acquisition and close the AI trade market for the four phases §5 of the trade
plan expects business in. Rule 2 also stands: **no generation, at any target.** If the
inventory runs dry the user's camp is short, and `FillSummary.userShortfall` says so on
the `SMOKE: diag campRoster` line (`userShort=`) rather than a body being invented to hide
it.

### 3.4 The exit ceilings

`WeekAdvancer.userRosterLimitViolation` (:636) currently returns `nil` for every phase
except `.rosterCuts` and reads a hard `PracticeSquadEngine.activeRosterCeiling`. It becomes
phase-keyed, **derived from `CutDay` so the ladder has one authority**:

```swift
// One authority: the same enum RosterCutView derives its stage from.
static func rosterCeiling(exiting phase: SeasonPhase) -> Int? {
    switch phase {
    case .trainingCamp: return CutDay.cut90To75.target   // 75
    case .preseason:    return CutDay.cut75To65.target   // 65
    case .rosterCuts:   return CutDay.cut65To53.target   // 53
    default:            return nil
    }
}
```

`rosterLimitInboxMessage` (:655) already carries `actionDestination: .rosterCuts`, so the
blocked advance keeps leaving a letter that deep-links to the cut screen at every rung, not
just the last one.

`trimAIRosters` (:6695) gains the same phase-keyed ceiling so the AI walks the same ladder
the user does. It already routes through `CapManagementEngine.applyRelease` (the "one
release door", #102 F8), so camp cuts get the §3.1 guard for free.

`RosterCutView` needs **no logic change** — its stage is derived (:401), its ladder band is
derived, and `CutDay.stage(forRosterCount:)` already answers correctly for a 90-man roster.

---

## 4. #205b — preseason games

### 4.1 The step machine

`Career.preseasonStep: String` is not needed as a separate field — it lives inside
`preseasonData` (§4.3) as `PreseasonState.step`, because unlike `freeAgencyStep` it is
never read by anything outside the preseason flow. One blob, one decode.

```
.preseason entered → step = .plan(1)
  user picks a starter policy for game 1 → sim → step = .recap(1)
  DSResultSheet → Continue → step = .plan(2) … → .recap(3) → .complete
advance out of .preseason is gated on step == .complete AND roster ≤ 65
```

Precedent: `Career.freeAgencyStep` (:58) + `FAFlowBand` + `FAWeeklyView` →
`FARoundSummaryView` → `FACompleteView`. `FAFlowBand.swift` (182 lines) is the band this
flow's `PreseasonFlowBand` is modelled on.

### 4.2 The coach decision (spec item 3)

Per game the user picks one of three policies. The policy composes **which men dress**,
which is the only lever `GameSimulator` actually has (it picks the best available at each
position off the roster it is handed).

| Policy | Who dresses | Familiarity | Injury exposure |
|---|---|---|---|
| `.startersRest` | everyone **not** in `WeekAdvancer.startingLineupIDs` (:6841) | bubble full, starters none | bubble full, starters none |
| `.starterSeries` | full roster | starters × `starterSnapShare`, bubble full | starters × `starterSnapShare`, bubble full |
| `.fullTilt` | full roster | starters full | starters full |

`starterSnapShare = 0.35` — one constant, named, and re-derived in §6 rather than guessed
at forever. The three-game slate makes this a real decision with 27 combinations: bank
familiarity early against a healthy Week 1, or protect the starters and open the season
with a cold playbook.

**Engine reuse, no new engines:**

- Familiarity: `VersatilityDevelopmentEngine.learnScheme(player:scheme:coordinator:practiceIntensity:)`
  — the exact call `WeekAdvancer` :2087-2101 makes weekly, with
  `practiceIntensity = preseasonSnapIntensity × policyShare`. The `schemeInstallSeason ×1.25`
  install-year bonus rides along unchanged.
- Injury: `MedicalEngine.injuryCheck(player:playType:doctor:physio:trainer:frequencyMultiplier:)`
  — the exact call `WeekAdvancer` :1779 makes weekly, with
  `frequencyMultiplier = career.injuryFrequency.riskMultiplier × preseasonInjuryScale × policyShare`.
  Invariant respected: `career.injuryFrequency` still scales (and at `.none` still disables)
  everything.
- Workload: `WorkloadEngine` tick as the camp phases already do.

**Explicitly NOT ticked by preseason: contracts.** Invariant (1). Preseason games run
zero contract decrements. The only place a contract clock moves remains the week-18 tick
and `executeNewLeagueYear`. This must be stated in the `PreseasonEngine` header comment, in
those words, because the file is a natural place for someone to later add "and age the
deals" — which is precisely the #89 week-18 double-tick bug.

### 4.3 Persistence — a blob, not `Game` rows

`Career.preseasonData: Data? = nil`:

```swift
struct PreseasonState: Codable {
    var season: Int
    var step: Step                        // plan(1…3) | recap(1…3) | complete
    var policies: [PreseasonPolicy]       // one per game, rawValue-persisted
    var results: [PreseasonResult]        // one per played game
}
struct PreseasonResult: Codable {
    var gameIndex: Int
    var opponentTeamID: UUID
    var homeScore: Int, awayScore: Int
    var userLines: [PlayerGameStats]      // already a plain Codable struct, not a @Model
    var injuries: [UUID]
    var familiarityGains: [UUID: Int]
    var leagueScoreboard: [ScoreLine]     // 31 AI results, score-only
}
```

Zero new `@Model`s, zero `FetchDescriptor<Game>` exposure, zero SwiftData migration risk.
The 16 `Game` fetch sites Audit B enumerated (`CareerDashboardView` :3274/:3486/:4059,
`CareerShellView` :2746, `MultiSeasonSmokeTest` :1318, …) are untouched by construction.

AI-vs-AI preseason games are **scored, not simulated per-player**: 31 results from
`GameSimulator.simulate` with default rosters is 31 full play-by-play sims per game × 3
games = 93 extra sims per offseason. Instead the league scoreboard is generated
score-only (the same treatment postseason gives the 13 clubs the sim never box-scores,
`finalizePostseasonHistory`). Only the user's game is simulated in full. See risk R5.

### 4.4 The one engine signature change

`GameSimulator.simulate` reads `homeTeam.currentRoster()` (:115). It gains two additive
parameters, defaulted to today's exact behaviour, in the same style as the existing
`weather:` / `homeGamePlan:` additions:

```swift
static func simulate(
    homeTeam: Team, awayTeam: Team, …,
    homeRosterOverride: [Player]? = nil,   // NEW — nil = currentRoster(), today's behaviour
    awayRosterOverride: [Player]? = nil    // NEW
) -> GameResult
```

Two lines change inside the function. Nothing else in the sim, the live engine, or the
balance harness is affected (`tools/balance-harness/sync_sources.sh` copies
`GameSimulator.swift` verbatim and SHA-checks it — the harness will pick the new default-
valued signature up on the next `./run.sh` with no shim edit, which is exactly what that
rig is for).

---

## 5. UI surfaces

All new screens use `DSSlatBand` / `DSActionBar` / `DSResultSheet` / `DSListRow` /
`DSStatusPill` and `DSType` tokens. English only. `.sheet` discipline: **one enum-driven
`.sheet(item:)` per screen** — no stacked modifiers with no-op setters (the "B1 class" the
draft round-recap fix names).

| Surface | File | Notes |
|---|---|---|
| UDFA board | `UI/FreeAgency/UDFABoardView.swift` (new) | Modelled on `FAWeeklyView`. Columns show **scouted bands only** — `scoutedOverallGrade`, `scoutedPotentialLabel`, position grades. A prospect with no scouting shows "UNSCOUTED", never a number. Heat pill per prospect from `FrenzyHeatTier`. Offer via a compact sheet, not a full negotiation (a UDFA deal is a slot, not a negotiation). |
| UDFA round summary | reuse `DSResultSheet` | "Round 2 closed — you signed 3, the league signed 41." Chips: signings, cap spent, best remaining (by the user's *own board*, fogged). |
| Camp fill notice | inbox message | "34 players reported to camp." Replaces the current fog-leaking UDFA inbox message (D2). |
| Preseason flow | `UI/Camp/PreseasonView.swift` + `PreseasonFlowBand.swift` (new) | Three-step band mirroring `FAFlowBand`. Per step: policy picker (three `DSListRow`s with the trade-off stated in the row's own copy), a "Sim game" commit in `DSActionBar`. |
| Preseason recap | `UI/Camp/PreseasonRecapSheet.swift` (new), wrapping `DSResultSheet` | Spec item (4). Chips: final score · bubble snaps · injuries · biggest riser. `cost:` line carries the injury/familiarity price of the policy the user picked. The **full bubble stat table** renders on `PreseasonView` behind the sheet, revealed by Continue — DSResultSheet's contract is headline → what changed → what it cost → one commit, and a scrollable table inside it would break that (and §2.6's ban on in-place body swaps). |
| Left-menu trim points | `TaskGenerator.swift` | §5.1 below. |

### 5.1 Task rows (spec item 5, invariant 4)

One calculation authority, no ghost pointers (#134b), view-visit state through
`TaskProgressStore` (#138).

- `otasTasks()` gains **"Sign undrafted free agents"** — required, `destination: .udfaBoard`
  (new `TaskDestination` case + `ShellDestination` case + one route in
  `CareerShellView.destinationView`). Title carries a live counter,
  `"Sign undrafted free agents (3/6)"`, re-stamped by the existing
  `refreshTaskCompletionStatus` restamp path (:2248) — the same mechanism the draft-prep
  interview counter uses. `matchKey` strips the suffix, so nothing keyed on the row breaks.
- `trainingCampTasks()` gains **"Cut to 75"** — required when `rosterCount > 75`, exactly
  the shape `rosterCutsTasks` already uses for its 53 row (`isRequired: overLimit`,
  `status: overLimit ? .todo : .done`). `rosterCount` is already a `generateTasks`
  parameter and is already computed by `regenerateTasks` (:2543) — **no new parameter, no
  new fetch.**
- `preseasonTasks()` is rewritten: three game rows (`"Preseason Game 1 — set your plan"`,
  destination `.preseason`) driven off `PreseasonState.step`, plus **"Cut to 65"** required
  when `rosterCount > 65`. The current `"Review preseason results"` row — hardcoded
  `status: .done` with the copy "Preseason games auto-simulate" — is deleted; it is a ghost
  pointer at a thing that does not exist.
- `rosterCutsTasks()` **stops emitting** "Cut to 75" and "Cut to 65". It keeps the 53 row
  and the practice-squad keeper row.

`TimelineTasksPanel.orderedPhases` (:46) is unchanged — no new phases.

---

## 6. Balance impact and the harness ports that must be re-derived

Nothing here ships on a guess. Each port below states what moves, why, and what has to be
re-measured before the wave is called done. Runner: `MultiSeasonSmokeTest`
(`PERF_SMOKE_SEASONS`, 8 seasons) plus `tools/balance-harness` `./run.sh career` where the
gate lives there.

**Timing note that makes most of this tractable:** the smoke's season audit runs at the
`.regularSeason` boundary (`MultiSeasonSmokeTest` :234), i.e. **after** cutdown. Camp
bodies are gone and the flag is cleared by then, so `capRoom`, `salaryInflation` and the §8
band gates are measuring the same population they measure today. That is a property to
*verify*, not to assume.

| # | Gate / diag | Where | Why it moves | Required action |
|---|---|---|---|---|
| B1 | `capRoom`: `underCap ≥ 24/32`, `avgRoom ≥ 8 %` | Smoke :641-679 | Should be **unchanged** — camp bodies are cap-exempt and gone by the measurement point. | Verify green across 8 seasons. If it moves at all, the §3.1 refund guard is leaking; that is the first place to look. |
| B2 | `salaryInflation`: `payroll %`, `avgSal`, `yp0to3Pay %` | Smoke :690-712 | `rosteredPaid` filters `teamID != nil` — camp bodies would be counted if the measurement ever moved earlier. | Add `&& $0.rosterStatus != .campBody` to `rosteredPaid`, with the reason in a comment. Re-derive the printed bands. |
| B3 | §8 age/experience bands (yp0-3 share 45-55 %, 33+ ≤ 2 %) | Smoke drift diagnostics :899-1050 | Camp bodies skew young; same exposure as B2. | Same filter, then re-run the drift gate and re-state the measured numbers in the doc comment. |
| B4 | **Shadow pool equilibrium (~900, #99)** | `PracticeSquadEngine` doc; `ChurnDiag` | The camp fill parks ~860 unsigned men on rosters each offseason and returns them at cutdown. This is the biggest single change to the pool's dynamics since #144. | **New diag** `SMOKE: diag campRoster season=… filled=… fromPool=… generated=0 poolBefore=… poolAfter=…`. Gate: `generated == 0` (hard), and `poolAfter` within ±15 % of `poolBefore` across seasons. |
| B5 | **New: camp cap legality** | — | The compliance window covers `.otas … .rosterCuts` (`CapManagementEngine` :764). A user hard-gated during camp is the failure mode Audit B named. | **New diag** measuring `underCap` at `.preseason`, not just at the season boundary. Gate: `underCap == 32/32` during camp — a cap-exempt camp body must move nobody. |
| B6 | Waiver-wire throughput | `processCampWaivers`, `WeekAdvancer` :4041 | Cutdown now releases ~27/club instead of ~7 — ~860 rows into one waiver pass. | Measure the pass's wall time; if it is over ~200 ms, waivers run only on the 65→53 rung (camp cuts at 75 and 65 go straight to the pool, which is also the real rule — only vested-veteran-free players clear waivers). |
| B7 | Injury volume per season | `MedicalEngine` rolls | Preseason adds a fourth exposure window. | Re-derive `preseasonInjuryScale` and `starterSnapShare` so **season-total injuries stay inside today's measured band**. Method: run 8 seasons at `.fullTilt` on all three games (worst case) and at `.startersRest` (best case); the constants are fixed by making the worst case ≤ +8 % season-total injuries. |
| B8 | Scheme-familiarity equilibrium (task #66; `PlaySimulator.famBustPivot = 55`) | `WeekAdvancer` :7929, `VersatilityDevelopmentEngine` | Preseason snaps are new familiarity inflow. If the league mean at Week 1 rises past the pivot for everyone, the bust channel silently switches off. | Measure league-mean `schemeFamiliarity` at Week 1 before/after. Gate: the *install-year* cohort must still open below 55 — that is the whole mechanic. Tune `preseasonSnapIntensity` to hold it. |
| B9 | Trade market roster vetoes | `TradeValueEngine.funnel`, `SMOKE: diag tradeFunnel` | Clubs at 80 against a ceiling of 90 leave 10 slots; today they sit at ~60. | Verify offseason `rosterCeiling` vetoes do not rise. If they do, the fill target drops from 80 before anything else is touched. |
| B10 | UDFA class inflow | new | Today: ≤ 4 × 31 = 124 AI signings + ≤ 5 user. New: ≤ 6 × 32 = 192. | Measure actual signings/season. If inflow rises materially, the per-club quota drops — the *level* is a tuning knob, the *market* is the feature. |
| B11 | Harness user stand-in | `MultiSeasonSmokeTest.refillUserRoster` :1267 | It cuts the user's roster to 53 in one step and refills from the pool by raw `overall`. With a 90-man arc it is measuring a club that never walked the ladder. | Rewrite to walk 80 → 75 → 65 → 53 on `RosterValue.keepScore` (the key the AI ladder uses), so the harness franchise is not the one club in the league that does camp differently. |

---

## 7. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **Cap-ledger leak.** A camp body's salary is credited back on release though it was never charged, walking every club's `currentCapUsage` down by ~$20M a camp. | **Critical** | The §3.1 guard in `CapManagementEngine.applyRelease` — the single release door. B5 measures it directly. A unit-level assertion (`usage before camp == usage after cutdown minus the survivors' salaries`) belongs in the wave. |
| R2 | **Contract double-tick.** Three preseason "games" look like three weeks; someone adds a decrement. | **Critical** (invariant 1) | `PreseasonEngine` ticks nothing. Header comment names #89 explicitly. Preseason never increments `career.currentWeek` — the step machine lives in the blob. |
| R3 | **Fog leak in the UDFA board.** Any sort, any badge, any "top remaining" line computed off `trueOverall`. | High (invariant 5) | The board takes a fogged view model built in the view layer from `scouted*` fields; `trueOverall` is available only inside `UDFAMarketEngine`'s AI path. D2's inbox message is deleted, not reworded. |
| R4 | **Pool exhaustion / generator reopening.** Someone adds a "generate if the pool runs dry" fallback to the camp fill and reintroduces #99 at 860/season. | High | The engine has no generation path at all — there is nothing to accidentally raise. B4 gates `generated == 0` as a hard assertion, not a diag. |
| R5 | **Offseason performance.** ~860 extra rows through four phases of camp ticks, development, workload and waivers; the sim run already has a watchdog-stall history. | High | Camp bodies take the cheap path (§3.3). AI preseason games are score-only (§4.3). Measure per-advance wall time at `.otas`/`.trainingCamp`/`.preseason` before and after; the watchdog in `MultiSeasonSmokeTest` :303 is the backstop. |
| R6 | **Draft/** ownership collision.** `DraftUDFAPanel` and `DraftDayCoordinator` keep a second signing path alive this wave. | Medium | Paths are exclusive, not contradictory (§2.5). Ticket #204f queued for after the v3.1 run merges. No agent in this wave may open `UI/Draft/**`. |
| R7 | **Task-row ghosting.** A "Cut to 75" row that points at a screen showing a 53-man roster, or a counter that stops moving. | Medium (invariant 4) | Rows derive from `rosterCount`, which `generateTasks` already receives; `RosterCutView`'s stage is derived from the same count. The restamp path (:2248) keeps counters live. No new calculation authority. |
| R8 | **Save compatibility.** A save mid-offseason on the old build lands in a phase whose exit ceiling suddenly became 75 with a 60-man roster. | Medium | Every gate is `count > ceiling`, so an under-target roster passes silently. `campFillSeason` guards the fill from double-running. All three new stored properties are inline-defaulted → lightweight migration. |
| R9 | **`.otas` becoming a wall.** The UDFA board is a required task; a user who wants to skip the market is stuck. | Medium | Required means "the row is red", not "the advance is blocked": only the *roster ceiling* gates advances, and skipping the market leaves the club under 80, which is legal. Non-participation must never be punished — that is the exact complaint Audit A opened with. |
| R10 | **Preseason feels like filler.** Three sim-only games with no consequence is three taps. | Medium | The consequence is the cut ladder: the recap's bubble stat lines are the evidence the 75 → 65 decision is made on, and the policy is a real familiarity-vs-injury bet. If playtest says it is filler, the lever to pull is making camp grades move on preseason production — not adding more games. |
| R11 | **Balance constants set by feel.** `starterSnapShare`, `preseasonInjuryScale`, `preseasonSnapIntensity`, fill target 80, quota 6. | Medium | Every one of them is named in §6 with the measurement that fixes it. None ships un-derived; each gets its measured number written into its doc comment, in the house style. |
| R12 | **Portrait fit.** The left menu gains up to 3 rows in camp phases; the phase band is already at ~0 spare (7 slats + 6 tabs). | Low-Medium | Net task-row change is ≈ 0 (three rungs move out of `.rosterCuts` into the phases where they belong). Needs the user's eye on an iPad portrait screenshot before the wave closes. |

---

## 8. Work split — four agents, disjoint file ownership

`UI/Draft/**` is owned by the parallel v3.1 run and is **read-only for every agent here.**

### Wave 0 (blocking, Agent B alone) — the data-model commit

Agent B lands **only** the stored-property and enum additions, so nobody else races on
`Career.swift` / `Player.swift`:

- `Domain/Models/Player/Player.swift` — `RosterStatus.campBody` + the two switch arms.
- `Domain/Models/Career.swift` — `udfaMarketData`, `preseasonData`, `campFillSeason`
  (+ the `UDFAMarketState` / `PreseasonState` computed accessors, following the
  `pendingTradeOffers` / `inbox` accessor pattern).

A, C and D start against these declarations and never edit those two files again.

### Agent A — UDFA market engine (#204 engine half)

**Owns:** `Engine/FreeAgency/UDFAMarketEngine.swift` (new) ·
`Engine/FreeAgency/SigningInterestEngine.swift` · `Engine/Scouting/ScoutingEngine.swift`
(UDFA pool section only) · `Engine/Draft/DraftEngine.swift` (UDFA helpers only).

Delivers: the market machine (§2.3), the `Candidate` refactor (§2.2), the fog-safe pool
ordering, the `isDeclaringForDraft = false` fix on every signing path (D1), and a
documented four-call integration surface (`openMarket` / `runAIRound` / `submitUserOffer` /
`closeMarket`) that **Agent B** wires into `WeekAdvancer`. A never opens `WeekAdvancer`.

### Agent B — calendar, roster arc, cap (#205a) + integration

**Owns:** `Engine/Simulation/WeekAdvancer.swift` · `Engine/Camp/CampRosterEngine.swift`
(new) · `Engine/Contract/CapManagementEngine.swift` ·
`Engine/Contract/FreeAgencyEngine.swift` (true-up filter only) ·
`Domain/Models/Career.swift` · `Domain/Models/Player/Player.swift`.

Delivers: Wave 0; deletion of the `.otas` bulk block and its process-global; the calls into
A's market and into `CampRosterEngine`; the camp fill (§3.3); the phase-keyed exit ceilings
and the `trimAIRosters` ladder (§3.4); the cap-exemption guard and the true-up filter
(§3.1); the call into C's `PreseasonEngine`.

### Agent C — preseason simulation (#205b engine half)

**Owns:** `Engine/Simulation/PreseasonEngine.swift` (new) ·
`Engine/Simulation/GameSimulator.swift` (the two additive parameters only) ·
`Domain/Models/Camp/PreseasonState.swift` (new — the Codable structs).

Delivers: the three-game step machine, the policy → roster composition, the
familiarity/injury post-pass through the existing engines, the league scoreboard, and the
recap payload. C never opens `WeekAdvancer` — it exposes
`PreseasonEngine.simulateGame(career:index:policy:…) -> PreseasonResult` and B calls it.

### Agent D — UI and tasks

**Owns:** `Engine/Simulation/TaskGenerator.swift` · `UI/Career/CareerShellView.swift` ·
`UI/Common/TimelineTasksPanel.swift` · `UI/Camp/RosterCutView.swift` ·
`UI/FreeAgency/UDFABoardView.swift` (new) · `UI/Camp/PreseasonView.swift` (new) ·
`UI/Camp/PreseasonFlowBand.swift` (new) · `UI/Camp/PreseasonRecapSheet.swift` (new).

Delivers: §5 in full — the two new destinations end to end (`TaskDestination` →
`ShellDestination` → route), the reshuffled task rows, the fogged UDFA board, the preseason
flow and its `DSResultSheet` recap. D starts immediately against the signatures in §2.3,
§4.2 and §4.3 rather than waiting on A and C.

### Sequencing

```
Wave 0 (B, alone)
   ├── A ──┐
   ├── C ──┼── B integration pass (wires A + C into WeekAdvancer)
   └── D ──┘
                └── §6 measurement pass (B owns the harness edits B2/B3/B11 + the new diags B4/B5)
```

Builds: **only the builder agent runs `xcodebuild`.** No agent runs XCUITest in a sim run.

---

## 9. Definition of done

1. A user who never opens the Draft Day panel signs undrafted free agents on a real market,
   against 31 competing clubs, on scouted values — and a user who skips it entirely is not
   punished for it.
2. `prospect.isDeclaringForDraft` is false for every signed UDFA on every path (D1); no
   user-facing surface anywhere is ordered or printed off `trueOverall` (D2); every UDFA
   signing is cap-checked (D3).
3. Camp rosters reach ~80, are assembled without generating a single player, and the
   league's cap ledger is bit-identical at the season boundary to what it is today (B1/B5).
4. Three preseason games per season, sim-only, with a coach decision that trades
   familiarity against injury, and a `DSResultSheet` recap per game carrying the bubble
   cohort's stat lines.
5. The 80 → 75 → 65 → 53 ladder appears in the left menu at the phases where each rung is
   due, one authority per row, no ghost pointers.
6. Every gate in §6 is green, and every constant in §6/R11 has its measured derivation
   written into its doc comment.
7. Invariants (1)-(8) demonstrably intact: no contract tick outside `executeNewLeagueYear`,
   no new `SeasonPhase` case, no conflict with the phase-staggered roster floors, one task
   authority, fog held on UDFA values, `careerID` on all new data, one `.sheet` enum per
   screen, English-only `DSType` copy.
