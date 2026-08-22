# AI_FIX_QUEUE — the consolidated, deduplicated fix queue

## STATUS — verified against the code, 2026-08-22

This list is a description of PROBLEMS, and forty of them are now fixed. Before
implementing any entry, check the stamp on its heading, and if it is unstamped
**grep the code anyway** — a stale queue is how the same work gets done twice, and
it already cost one agent a wasted assignment this week.

| state | count | what it means |
|---|---:|---|
| **DONE** | 59 | verified present in the source on this branch, not taken from a report |
| **CLOSED / REJECTED** | 2 | F-03 closed by measurement, F-08 rejected by the D1 ruling |
| **IN PROGRESS** | 0 | — |
| open | 15 | genuinely unstarted (F-71 / F-72 from measurement; F-74 split out of F-23; F-73 withdrawn) |

**2026-08-22, stamp audit.** All nine `IN PROGRESS` entries were finished and merged; the
stamps were stale. Each now names the commit AND the source evidence, because a commit
message is a claim and the tree is the fact. The audit also produced **one false alarm worth keeping on the record**: I filed F-73
claiming the playoff bracket was RNG, on the strength of a stale header comment, and
withdrew it an hour later after reading the function's body. Read the code between the
comment and the line you are suspicious of.

**2026-08-22, second wave** — QA-03, F-13, F-32, F-49(1,2), F-68, F-70(1,2), F-24.
**Four of those seven entries were wrong about their own subject**, which is now the
queue's most reliable failure mode: F-32's OVR table was off for rounds 4-6; F-68
named six bad comments when two were fine; F-24's "needs user decision" flag and its
F-23 dependency were both void; F-49 missed a sixth `newsLog` writer. Read the code,
not the entry.

The four waves of 2026-08-22 (lifecycle, draft brain, trades + reputation,
gameday) plus D2's four sub-parts account for nearly all of the DONE column;
`TODO.md`'s `## PÄIVÄ 2026-08-22` section is the narrative record.

**Entries whose diagnosis was corrected rather than implemented as written**,
and each correction is inside the entry: F-12 (the roster ceiling binds before the
appeal bars), F-25 (the run model is in band; the loss is in ordinary early-down
carries) and QA-03 (half of it was my own tooling). An entry that rests on a false
premise is closed by measurement, not built.


**Sources (read in full, all dated 2026-08-21, branch `feat/skeletal-mocap-players` @ `3423d35`):**
`docs/AI_GAMEDAY_DECISIONS_ANALYSIS.md` (488 l) · `docs/REBUILD_VIABILITY_ANALYSIS.md` (1243 l) ·
`docs/AI_TRADE_ANALYSIS.md` (415 l) · `docs/AI_ROSTER_DECISIONS_ANALYSIS.md` (450 l).
Ledger cross-reference: `TODO.md:4128-4256` (#213–#225).

**This file is the "what". The four reports remain the "why".** Every entry traces to a report
section; nothing here is invented. Where a report's recommendation is vague, the entry says so
instead of filling the gap.

---

## Ordering rationale

1. **P0 is measurement, not impact.** Fifteen of sixteen AI-vs-AI games never run the simulator
   (`corr(roster quality, wins) = 0`) and the talent→win curve reverses above a 5-point gap. Until
   both are fixed, *every* AI front-office finding in these reports — draft, free agency, trades,
   development — is unfalsifiable: its quality cannot show up in a standing. Two P0 items are
   instrumentation rather than engine work (F-04, F-05) because the constants the rest of this
   queue touches are currently un-gated in CI.
2. **P1 is the economy that decides the user's game.** The measured chain is
   `cap does not bind → free-agency round 1 is uncontested → user-proposed trades face no fairness
   check → +3 to +4 starter points in one offseason`. These items have the largest measured effect
   on the actual play experience and several of them are prerequisites for calibrating P2.
3. **P2 is realism and the imperfection model** — the user's explicit design goal (#221–#223).
   Deliberately last among the substantive work, because, in the gameday report's words, *"adding
   realistic coaching error to a league where 15 of 16 games are decided by dice is decorating a
   room with no floor"* (§4.3.6 item 4).
4. **P3 is copy, docs, and dead code.** Cheap, safe, and it stops the next audit starting from a
   false premise.

Within a band, entries are ordered so that a dependency always appears above its dependents.

**Class definitions.** `bug-fix` = restores what the code (or its own comment, or the UI copy)
already claims to do — no design conversation needed. `design-change` = alters intended behaviour
and carries a **Needs user decision** line. `measurement-gap` = neither; the behaviour is unknown
because nothing measures it.

---

## Summary table

| id | title | class | priority | one-line effect |
|---|---|---|---|---|
| F-01 | Make AI-vs-AI game results depend on the rosters | design-change | P0 **DONE (#213) — regular season AND postseason** | Turns the standings from a random-number generator into a consequence of AI front-office quality |
| F-02 | Make the roster-quality → win-probability curve monotone | bug-fix | P0 **DONE (#214)** | A better roster stops winning fewer games |
| F-03 | Stop underdog relief stacking inside the compression floor | bug-fix | P0 | Removes the second half of the win-curve reversal |
| F-04 | Instrument competitive dispersion in the smoke test | measurement-gap | P0 | Makes F-01/F-02/F-11/F-12 visible to CI instead of invisible |
| F-05 | Give the headless draft AI-vs-AI swaps and assert `draftSwaps` | measurement-gap | P0 | Un-blinds the fourth-largest trade category, which is structurally 0 in the harness |
| F-06 | Persist the trade anti-exploit counters on `Career` | bug-fix | P1 | Relaunching the app stops resetting every trade cap and every GM's memory |
| F-07 | Run the trade fairness band on user proposals | bug-fix | P1 | Closes the unbounded buy-low/sell-high value pump |
| F-08 | Give the user a per-window trade cap | design-change | P1 | Converts the remaining arbitrage from a farm into a decision |
| F-09 | Repair the pick-value chart tail (picks 130–224) | bug-fix | P1 | Makes 29 % of draft inventory usable as trade currency again |
| F-10 | Tighten the future-pick discount from ×0.8 to ×0.6/yr | design-change | P1 | Stops future picks being the cheapest possible currency |
| F-11 | Make the salary cap bind across league years | design-change | P1 | Gives every roster decision a cost that outlives one March |
| F-12 | Put bidders on the board in free-agency rounds 1–3 | design-change | P1 | Ends the uncontested premium market that is the fastest rebuild lever |
| F-13 | Fix the loyalty branch in `scoreBid` | bug-fix | P1 | "Prefers current team" stops meaning "prefers the human" |
| F-14 | Rebalance `scoreBid`'s structural user multipliers | design-change | P1 | A 2-15 club stops outbidding a 14-3 club at 79 cents on the dollar |
| F-15 | Route the opponent-prep drift penalty into a field the sim reads | bug-fix | P1 | The designed counterweight starts existing |
| F-16 | Replace the opponent-prep post-game score multiplier | design-change | P1 | Removes a user-only +4.2 pts/game ≈ +2.1 wins/season |
| F-17 | Give AI clubs a head-coach persona in the `gamePlan` slot | design-change | P1 | Un-nils the game plan for 31 clubs and creates a coach-driven 4th-down spread |
| F-18 | Stop injured players dressing; wire the depth chart to the engine | bug-fix | P1 | Two UI screens stop promising systems that do not exist |
| F-19 | Give the random league a real team-strength spread | bug-fix | P1 | Restores "take over a bad team" as an available premise |
| F-20 | Rebase the UI ladders and owner goals onto the starter average | bug-fix | P1 | "Elite"/"Rebuild goal"/"Championship" branches become reachable |
| F-21 | Pass the on-field unit, not the 53-man roster, to the familiarity terms | bug-fix | P1 | Scheme familiarity reaches ~100 % of its designed size instead of 69 % |
| F-22 | Make the rookie boom/bust roll reachable | bug-fix | P1 | Two 5 % branches that never fire start firing |
| F-23 | Give AI free agency a veteran perception model | design-change | P1 | 31 omniscient front offices stop reading true `overall`/`truePotential` |
| F-24 | Fog the AI development desk's potential read | design-change | P1 | The AI stops sorting on a number the user is explicitly denied |
| F-25 | Bring full-game play selection back inside the NFL bands | design-change | P1 | net YPA 8.4 / 3rd-down 50 % / 29 pts per team come back to band |
| F-26 | Give AI clubs house preferences (`GMTaste`) | design-change | P2 | Turns symmetric noise into a readable, learnable opponent |
| F-27 | Model position runs and clock panic in the draft | design-change | P2 | Restores the missing QB-per-round variance (real range 1–6) |
| F-28 | Fix the inverted magnitude in the need model's quality term | bug-fix | P2 | A 55-OVR position group stops being worth less than a missing fullback |
| F-29 | Scale draft need-weighting by round | design-change | P2 | Round 1 drafts for need the way real GMs do; day 3 does not |
| F-30 | Unify the three positional-value tables and fix the RT/FB inversions | bug-fix | P2 | Two constants that drifted apart stop disagreeing in three files |
| F-31 | Widen the draft board's positional-value spread | design-change | P2 | QB-over-RB becomes ~6 board points rather than 3.2 |
| F-32 | Fix the bidding-war gate and the receipt for a price nobody paid | bug-fix | P2 | Bidding wars become possible below round 3; the printed price becomes real |
| F-33 | Let the bulk free-agent market overpay | design-change | P2 | The same club stops being two different negotiators |
| F-34 | Make the FA stance lean an actual knob | bug-fix | P2 | A self-documented "RAIL" becomes the modifier it claims to be |
| F-35 | Merge the UDFA fog into `AIDraftPerception` | bug-fix | P2 | One scouting department, one error model |
| F-36 | Close the `draftGrade` fog breach | bug-fix | P2 | The user's own pick grade stops being computed from a hidden number |
| F-37 | Let AI clubs franchise-tag | design-change | P2 | 0 tags/year becomes a real-league 8–15 |
| F-38 | Give the coordinator misread model a floor, a grade scale, and an OC channel | design-change | P2 | The game's only modelled AI decision error stops being 0.0 for ~40 % of coordinators |
| F-39 | Give the AI kneel, timeouts and the onside kick | design-change | P2 | The three most basic acts of endgame management stop being user-only |
| F-40 | Fix the two-minute gates and the dead two-minute warning | bug-fix | P2 | A team up 3 stops running an 85 %-pass hurry-up; end-of-half drills start existing |
| F-41 | Recalibrate the kicking and punting numbers | bug-fix | P2 | FG make % rejoins the modern league; punter rating stops being cosmetic |
| F-42 | Make field-goal range depend on the kicker | design-change | P2 | Every club stops having an identical 62-yard range |
| F-43 | Sample `scoreDifferential` per play, not per drive | bug-fix | P2 | Game-management logic stops reading a stale score |
| F-44 | Give play selection a real red zone | design-change | P2 | The red zone starts at the 20 and reshapes the play mix |
| F-45 | Let quality and contract status matter to retirement | design-change | P2 | A 90-OVR 34-year-old stops retiring at the same rate as a 55-OVR one |
| F-46 | Make waiver claims actually move players | bug-fix | P2 | The one structural mechanism that hands talent to bad teams stops being a banner |
| F-47 | Give the season-1 roster something to develop | design-change | P2 | Inherited headroom 1.6 rises toward the draft pipeline's 12.0 |
| F-48 | Raise first-round bust risk toward the real range | design-change | P2 | 6.4 % R1 washout moves toward a real 17–57 % |
| F-49 | Unify the four trade receipts and fix the `newsLog` append bug | bug-fix | P2 | Force-trading your own star produces a receipt and a headline that renders |
| F-50 | Load the Trade Center's history card from the ledger | bug-fix | P2 | A card titled "Trade History (2029)" stops forgetting the season |
| F-51 | Add a Transactions lens over `TradeRecord` | design-change | P2 | A persisted, complete ledger gets its first UI reader |
| F-52 | Fix the inverted pity floor | bug-fix | P2 | The branch that protects a quiet season stops suppressing it |
| F-53 | Read the trade-request registry for the user's own players | design-change | P2 | A public trade demand acquires a market meaning |
| F-54 | Allow injured and tagged players to be traded | design-change | P2 | ~7 % of the league rejoins the market |
| F-55 | Raise `aiSwapChance` once the pick chart is repaired | design-change | P2 | Draft-weekend swaps move from ~13 toward the §5 band |
| F-56 | Surface or neutralise the user's hidden GM persona | design-change | P2 | Two saves stop having secretly different trade economies |
| F-57 | Report roster holes after an executed trade | design-change | P2 | "Cap adjustments have been processed" becomes a real consequence line |
| F-58 | Add shop-your-own-player and a trade block | design-change | P2 | Answers "who wants my backup tight end?" |
| F-59 | Make losing cost the user players | design-change | P2 | Free agents and stars start noticing a 2-15 record |
| F-60 | Let the AI adapt across games and seasons | design-change | P2 | Film study, week-over-week scouting, evolving personas |
| F-61 | Make guarantees and contract term AI negotiating levers | design-change | P2 | Prove-it deals, back-loading, void years |
| F-62 | Retune draft-board noise: the top-4 draw and the consensus spread | design-change | P2 | Replaces cosmetic randomness with structured error; R1 lands nearer the media board |
| F-63 | Let AI clubs elevate their own practice-squad players | design-change | P2 | Closes a one-directional practice-squad asymmetry |
| F-64 | Decrement coach contract years so firing has a cost | bug-fix | P2 | `contractYearsRemaining` stops being a decorative field |
| F-65 | Price and preview the cost of a scheme change | design-change | P2 | A correctly-shaped tax stops being invisible at the moment of choice |
| F-66 | Fill the clock-model gaps | design-change | P2 | Out-of-bounds, play clock, first-down stoppage, hurry-up tempo |
| F-67 | Delete the dead draft/trade code, including an armed fog breach | bug-fix | P3 | ~640 lines gone, one `truePotential` leak disarmed |
| F-68 | Correct the stale and false doc comments | bug-fix | P3 | The next fairness audit stops starting from a false premise |
| F-69 | Fix UI copy that promises engine behaviour that does not exist | bug-fix | P3 | Four screens stop describing systems with no call sites |
| F-70 | Repair trade news fidelity | bug-fix | P3 | Rumours stop contradicting the market; trade stories get portraits |
| F-71 | Fold `FantasyDraftEngine.aiPickIndex` into the one draft brain | design-change | P3 | Removes a second scorer that can drift from the first |

---

# P0 — makes everything else measurable

> **Note on two files.** `Engine/Simulation/WeekAdvancer.swift` and
> `Engine/Simulation/PlaySimulator.swift` are being edited right now by another agent for F-01 and
> F-02. Line numbers quoted for those two files come from the reports and are **stale**; navigate by
> symbol name. Do not start F-03 until F-02 lands.

### F-01 — Make AI-vs-AI game results depend on the rosters — **DONE** (`2c70d51`, #213)
- **Class**: design-change (with a bug-fix sub-item: the tie-break)
- **Priority**: P0 — **DONE (#213)**, verified in source 2026-08-22 for BOTH halves:
  `advanceRegularSeasonWeek` passes `homeRosterOverride` into `GameSimulator.simulate`, and
  `playPlayoffGames` runs `GameSimulator` for the user's game and for all 31 AI games alike.
  (I briefly split the postseason out as F-73 on the strength of a stale header comment; that entry
  is withdrawn — the premise was false.)
- **Where**: `Engine/Simulation/WeekAdvancer.swift` — `randomTeamScore(homeAdvantage:)` (reported
  `:8186-8214`), `simulateGameScore()` (`:971-990`), the tie-break (`:984-987`), call sites in the
  regular-season advance (`:1383`), the playoffs (`:7324-7327`), the Pro Bowl (`:3065`);
  `Engine/Camp/PreseasonEngine.swift:729`. Architecture note at
  `Engine/Simulation/SeasonStatSynthesizer.swift:16`.
- **What is wrong**: Every game the user is not in is scored by a function whose entire signature is
  one `Int`. No team, no roster, no coach, no scheme, no weather, no injuries. That is **15 of 16
  regular-season games every week**, plus all playoff games the user misses, the Pro Bowl and
  preseason. Measured consequence: `corr(roster quality, wins) = 0` for all 31 AI clubs, and the sd
  of team season wins is **2.06** against a real ≈3.0–3.2. Separately, because every score is a sum
  of 7s and 3s, **4.19 %** of matchups land on an exact tie and the tie-break hands every one of them
  to the home side, lifting the home win rate from 55.2 % to **58.8 %** against a real **53.2 %**.
- **What to do**: Replace `randomTeamScore(homeAdvantage:)` with a rating-aware score model that
  takes both teams. The gameday report proposes an Elo/Pythagorean model and notes it "would cost
  microseconds"; it does **not** specify the formula, so the exact model is an open design choice.
  The tie-break must become a genuine coin flip (or the NFL overtime rule), not an unconditional
  `homeScore + 1`. Flat home advantage should come down toward +2.5 once the tie-break no longer
  contributes +4.2 pp of it.
- **Risk / how to verify**: The whole league's standings distribution moves; `MultiSeasonSmokeTest`
  bands that depend on records (playoff seeds, coach firings, compensatory picks, trade stances)
  will shift. Gates: F-04's new dispersion metrics must land sd(team wins) ≈ 3.0–3.2, home win rate
  ≈ 53 %, and a positive `corr(starter average, wins)`. `./run.sh career` league-mean drift must
  stay inside its ≤ |0.40|/season gate. Clean build.
- **Depends on**: none (this is the root of the queue)
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §1.1 and PART 5 items 1 & 8; corroborated by
  `REBUILD_VIABILITY_ANALYSIS.md` §4.1 (year-to-year win correlation 0.63 vs a real 0.32; the AI
  "churns players, not team strength"). Ledger `TODO.md:4137`.

### F-02 — Make the roster-quality → win-probability curve monotone — **DONE** (`e04dac4`, #214)
- **Class**: bug-fix
- **Priority**: P0 — **DONE (#214)**, verified in source 2026-08-22: `PlaySimulator`'s
  `edgeCompressionScale` keys on BREADTH (`medianGap / meanGap`), not on the mean gap alone.
- **Where**: `Engine/Simulation/PlaySimulator.swift` — `edgeCompressionScale` (reported
  `:2769-2785`, constants `teamEdgeFull = 3.5`, `teamEdgeCrush = 9.0`, `teamEdgeFloor = 0.085`);
  ~14 call sites across the 0-centred talent channels (reported `:509-510`, `:573`, `:713`, `:796`,
  `:843-844`, `:1082`, `:1233`, `:1263`, `:1390-1391`, `:1466`, `:1525`, `:1588`, `:1644`, `:1689`).
- **What is wrong**: The scale is applied as a multiplier on the raw gap, so the *effective* on-field
  edge `gap × scale(gap)` peaks at a gap of **4.9** (value 4.18) and does not return to that level
  until a gap of **49** — a number no roster in this game can reach. Measured over ~110 000 harness
  games: win % by gap runs 50 / 60 / 71 / 80 / 86 / **88** and then falls to **85** (gap 6), **69**
  (gap 8), **64** (gap 10). On the shipped league that means an **88-OVR roster wins 11.4-5.6 — the
  same as an 80-OVR roster** — while an 83-OVR roster wins 14.0-3.0. The code's own comment defends
  the scale as "preserving the SIGN and RANK of every edge", which is true at a *fixed* gap; the
  derivative across gaps is what the justification never examines.
- **What to do**: Replace the multiplier with a monotone saturating map on the effective edge — the
  report suggests `effEdge = teamEdgeFull + (gap − teamEdgeFull) · k` with `k ≈ 0.10-0.15`, or a
  tanh knee. Preserve the flat-1.0 zone below `teamEdgeFull = 3.5`: that "single-unit safe zone" is
  what protects the QB leverage in F-* below and is explicitly correct.
- **Risk / how to verify**: This touches every talent channel in the engine; per-game aggregates
  will move. Acceptance test already exists — no new scenario needed:
  `./run.sh fullgame --home-tier X --away-tier 78 --n 3000` for X ∈ {78…95} must be **monotone
  non-decreasing** in home win % and must top out below ~92 % rather than reaching 100 %. Then
  re-run the QB sweep (`--home-tier 78 --home-override QB=$q`) and confirm 78→90 still buys ≈ +2.9
  wins — the single best-calibrated relationship in the game and the thing most at risk from this
  edit. Also re-run `regression`, `pass-talent`, `run-talent`.
- **Depends on**: none
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` §1.7, §4.2, §4.6 and recommendation 1 ("what to fix
  first, if only one thing"). Ledger `TODO.md:4146`.

### F-03 — Stop underdog relief stacking inside the compression floor — **CLOSED, no change** (its premise was removed by F-02)
- **Class**: bug-fix
- **Priority**: P0
- **Where**: `Engine/Simulation/PlaySimulator.swift` — `underdogReliefCompletion` (reported
  `:2896-2910`), constants `underdogGapMin/Peak/Plateau/Zero` (reported `:2883-2894`).
- **What is wrong**: The relief hands the weaker offense up to **+4.5 pp of completion** on a
  trapezoid that ramps in at a 4-point gap, plateaus at gaps 11–13 and fades by 19 — precisely the
  band in which `edgeCompressionScale` has already collapsed to its 0.085 floor. The favourite is
  being crushed and the underdog subsidised at the same time; this is the second half of the win-
  curve reversal in F-02.
- **What to do**: Either narrow the trapezoid to `[4, 8]` (where compression has not yet bitten) or
  scale the relief by `edgeCompressionScale` so the two cannot stack. Pick one after F-02 lands,
  because the correct choice depends on the new shape of the compression curve.
- **Risk / how to verify**: Over-correcting here re-opens the determinism problem the relief was
  written to solve (the harness README records `elite` vs `weak` landing at 100 % / ~103-4 points).
  Verify with the same `fullgame` monotonicity sweep as F-02, and confirm the top of the curve stays
  below ~92 %.
- **Depends on**: F-02
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 5 and §1.7; cross-referenced in
  `TODO.md:4155`.
- **RESOLUTION (measured, no code change)**: the entry's own instruction was to pick the remedy
  *after* F-02 landed, because the right choice depends on the new compression shape. It landed, and
  the finding it describes no longer exists. The pathology was **simultaneity** — the favourite
  crushed to a 0.085 floor while the underdog was subsidised in the same band — and F-02 removed the
  crush. The post-F-02 `fullgame` sweep is monotone *with the relief still in place*
  (73/83/86/89/89/89/91/91/95 across gaps 2-17), so the relief is not producing a reversal.
  It is now the only remaining softener at the top of the curve and is holding `elite`-vs-`weak` at
  96.0% rather than higher; narrowing the trapezoid to [4, 8] would push the top UP, which is the
  opposite of this entry's own acceptance criterion. The relief also exists for a reason unrelated
  to the gap — it corrects P0-1's flat de-inflation over-cooling a below-average offense — and that
  reason is untouched by F-02. Leave it alone.

### F-04 — Instrument competitive dispersion in the smoke test — **DONE** (`674527a`)
- **Class**: measurement-gap
- **Priority**: P0
- **Where**: `Engine/Simulation/MultiSeasonSmokeTest.swift:159`, `:251`, `:306`, `:855-933`
  (existing diagnostic blocks and band asserts).
- **What is wrong**: The smoke test tracks league average OVR, retirements, draftee counts, HC
  changes, cap bands, churn funnels and age pyramids. **Nothing anywhere in the repo tracks whether
  the standings stay competitive.** Every constant touched by F-01, F-02, F-03, F-11, F-12 and F-14
  is un-gated: a change to any of them is invisible to CI. The report's own league-churn model —
  4 000-season Monte Carlo, year-to-year win correlation 0.63 vs a real 0.32, 0.28 worst-to-first
  seasons vs a real 1.29, 4.2 new playoff teams vs a real 5.85 — was computed **outside** the repo.
- **What to do**: Add four per-season diagnostics and their band asserts: standard deviation of team
  wins (target ≈ 3.0–3.2), year-to-year win correlation (target ≈ 0.32–0.45), repeat-champion rate,
  and the share of last-place teams that reach the playoffs the next season. Also add
  `corr(starter average, wins)` — the number F-01 exists to move off zero.
- **Risk / how to verify**: Low risk (DEBUG-only instrumentation). Verify by running the smoke test
  before and after F-01 and confirming the metrics move in the predicted direction. Keep the new
  bands warn-level in season 1 and hard from season 2, matching the nine existing bands at
  `MultiSeasonSmokeTest.swift:766-795`.
- **Depends on**: none — **do this before F-01 lands** if the ordering can be arranged, so F-01 has
  a before/after reading.
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 14 and the Appendix note *"Nothing in
  the repo currently measures any of this."*

### F-05 — Give the headless draft AI-vs-AI swaps and assert `draftSwaps`
- **Class**: measurement-gap
- **Priority**: P0
- **Where**: `Engine/Simulation/MultiSeasonSmokeTest.swift:446-527` (`runAIDraft`), band block at
  `:766-786`, the `draftSwaps` print at `:628`, the `total=30…70` band; mirror source
  `UI/Draft/DraftDayCoordinator.swift:862-873` (`considerAIvsAISwap`) and
  `Engine/Draft/DraftDayTradeEngine.swift:712-718` (`aiSwapChance`).
- **What is wrong**: The entire draft-day trade market lives inside a SwiftUI object
  (`DraftDayCoordinator`, constructed only at `UI/Draft/DraftDayView.swift:77`). `runAIDraft`
  contains **no trade code at all**, so the printed `draftSwaps` field is structurally always `0`,
  and it is the one printed field with **no band assert** — nine bands are checked and this is not
  one of them. The plan's §5 target of "12–35 draft-weekend pick swaps, ≥3 in Rd 1" has never been
  verified by anything. Second gap in the same block: the `total=30…70` band is checked against
  `rows.count`, which **includes** `.draftDay` rows, so the band is satisfied by a number that is
  missing an entire category the plan bands separately.
- **What to do**: Add a headless mirror of `considerAIvsAISwap` to `runAIDraft` — it needs only
  `Board`, `aiSwapChance` and `TradeEngine.executeTrade`. Then assert `draftSwaps` (12–35, ≥3 in
  round 1) in the band block, and exclude `.draftDay` rows from the `total` band so the two
  categories are counted separately.
- **Risk / how to verify**: The new swaps will perturb every downstream smoke band that depends on
  draft outcomes; expect to re-baseline. Verify by running the multi-season smoke test and reading
  `SMOKE: diag trades`. Note the trade report's explicit judgement that the **balance harness cannot
  cheaply measure trade volume** (it would need SwiftData stubs for `DraftPick`, `Contract`,
  `TradeRecord` and `ModelContext`) — the in-app smoke is the pragmatic path here, not `run.sh`.
- **Depends on**: none
- **Source**: `AI_TRADE_ANALYSIS.md` §1.1, §1.8, §3.2 item 2, and recommendation B8. Ledger
  `TODO.md:4220`.

---

# P1 — the economy that decides the user's game

### F-06 — Persist the trade anti-exploit counters on `Career` — **DONE** (`ca3d03b` — career-scoped counters + strike registry)
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/Simulation/WeekAdvancer.swift` — the six `static var` counters (reported
  `:100-127`), `resetProcessStateForCareerSwitch()` (`:178-215`, the `TradeTalkRegistry.reset()`
  call at `:210`), `bind(to:)` (`:164-168`); caller `UI/Career/CareerShellView.swift:3220`;
  target `Domain/Models/Career.swift`; pattern to copy
  `Engine/Contract/ContractNegotiationEngine.swift:2254-2310` (`TradeRequestRegistry`,
  career-scoped via `CareerScopedDefaults.scopedKey`).
- **What is wrong**: `aiTradeOffersGenerated`, `aiTradeOffersOffseasonGenerated`,
  `aiOffersThisSeason`, `aiOffersThisOffseason`, `leagueTradesThisSeason`,
  `leagueTradesThisOffseason` are all process-global statics, and `activeCareerID` is `nil` on every
  cold launch, so `bind(to:)` wipes all six on every relaunch. Four consequences, all verified:
  rejection memory is erased (a user can lowball all 31 GMs until each hangs up, relaunch, and the
  whole league answers at base price with zero strikes); the 8-offer in-season and 5-offer offseason
  caps stop being caps; the pity floor becomes a guaranteed-offer farm; and the deadline deficit
  (`deficit = max(0, 7 − leagueTradesThisSeason)`) pins the deadline target at its **maximum of 15
  every time**. This is the only finding in the trade audit that lets a player farm the system
  deliberately.
- **What to do**: Move the four *season/offseason* counters onto `Career` as stored `Int`s using the
  same inline-default lightweight-migration pattern the 26 `careerID` fields used. Keep the
  monotonic `aiTradeOffers*Generated` pair as statics — they are harness instrumentation. Delete the
  `TradeTalkRegistry.reset()` call from `resetProcessStateForCareerSwitch()` (it is already called
  from `startNewSeason`, which is the only place a clean slate is correct) and career-scope the
  registry's keys.
- **Risk / how to verify**: A SwiftData schema change — exercise the lightweight migration on an
  existing save. Verify with the in-app smoke: `SMOKE: diag trades` offer counts must respect the
  8/5 caps across a simulated multi-session season, and the deadline target must vary in 12…15
  rather than pinning at 15.
- **Depends on**: none
- **Source**: `AI_TRADE_ANALYSIS.md` §1.7, §3.2 item 1, recommendations B1 and B2. Ledger
  `TODO.md:4212`.

### F-07 — Run the trade fairness band on user proposals — **DONE** (trade wave — `chartFairnessBlocker` on user proposals)
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/Contract/TradeValueEngine.swift` — `dealIsCoherent` (`:2729`, band 0.82–1.45;
  the AI-vs-AI fairness band is separately 0.72–1.70 at `:2818-2820`), existing call sites `:2337`,
  `:2416`, `:3671`; **missing from** `respond` (`:1186-1302`) and therefore from
  `partnerVerdict` (`:1086-1124`).
- **What is wrong**: The chart-neutral coherence check governs every AI-built offer and no
  user-built one. A user-proposed trade is judged solely against one GM's leaned, need-inflated
  ratio, with no reference to the public chart the user is looking at. Combined with the
  persona/stance spread on an identical future pick, this is a value pump: buy a 30-year-old 85-OVR
  from a rebuilding analytics club, sell him to a needy old-school contender, repeat across 31
  counterparties. `partnerVerdict` is additionally a free, unlimited binary search on the acceptance
  bar, and only offers below `insultCutoff` earn a strike.
  **The two reports disagree on the size of the spread and the profit** — see "Where the reports
  conflict" at the foot of this file. Use the conservative number (Trade's +60–80 %) as the
  acceptance target and the aggressive one (Rebuild's +531 chart points per flip) as the failure
  case the fix must make impossible.
- **What to do**: Call the same `dealIsCoherent` guard inside `respond`, using the public chart the
  user is shown, so preview and outcome stay identical (the `hardBlocker` invariant at `:1132` is
  the pattern to follow — it is already shared by preview and outcome and is rated A in the audit).
- **Risk / how to verify**: Legitimate user trades that lean on a genuine need premium may start
  being refused; the rejection string must explain *which* chart the deal failed against, matching
  the repo's standard that the reason the user reads is the string the engine decided on. Verify
  with the in-app smoke trade funnel (`diag tradeFunnel`) plus a manual round-trip attempt in the
  Trade Center. Re-run after F-09, which moves every value in the game.
- **Depends on**: none (but re-verify after F-09)
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 4, §1.2 and §2.8 asymmetry 5;
  `AI_TRADE_ANALYSIS.md` §1.4 item 3 and §3.2 item 5. Ledger `TODO.md:4212` (adjacent).

### F-08 — Give the user a per-window trade cap — **REJECTED by the D1 ruling** (a real GM is limited by counterparties, not by a rule; refusal is priced instead)
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Should the user be limited to N executed trades per week and M per
  league year, the way AI clubs are limited to 1–2 per window?* The trade report proposes **two per
  week, eight per league year**, noting the real league averages ~1.5 trades per club per year.
- **Where**: `Engine/Simulation/WeekAdvancer.swift` in-season loop; the AI-side precedent is
  `Engine/Contract/TradeValueEngine.swift:3318-3324` (`dealsPerClub`) and the league ceilings
  `WeekAdvancer.swift:131-132` (`maxLeagueTradesInSeason = 24`, `maxLeagueTradesOffseason = 38`);
  the user's only current gate is `UI/Contracts/TradeView.swift:1553` (`startNegotiation`), which
  enforces one *conversation* per GM and never a count.
- **What is wrong**: AI clubs are capped at 1 deal per market window (2 on deadline day) and the
  league at 24 in-season deals. The user has **no cap of any kind** — nothing stops him closing a
  deal with all 31 clubs in the same week. With F-07 alone the per-deal edge shrinks but the volume
  is still unbounded.
- **What to do**: Add a per-window executed-trade counter for the user's club, stored on `Career`
  alongside F-06's counters, and refuse execution past the cap with an explicit reason.
- **Risk / how to verify**: A cap that is too tight makes a legitimate deadline plan impossible;
  the report's suggested numbers are deliberately generous. Verify with the smoke trade diagnostics
  (user-side deal count per season) and by playing a deadline week.
- **Depends on**: F-06 (shares the persistence mechanism), F-07
- **Source**: `AI_TRADE_ANALYSIS.md` §1.4 item 2, §3.2 item 5, recommendation D2;
  `REBUILD_VIABILITY_ANALYSIS.md` §1.2 ("No per-season cap on user trades").

### F-09 — Repair the pick-value chart tail (picks 130–224) — **DONE** (trade wave — Johnson tail rebuilt, chart is `Double`)
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/Draft/PickValueChart.swift:44-57` (table), used by both the trade centre and the
  draft room; consumers include `Engine/Contract/TradeValueEngine.swift` and
  `Engine/Draft/DraftDayTradeEngine.swift`; the AI-vs-AI fairness band at
  `TradeValueEngine.swift:2818-2820`.
- **What is wrong**: The chart is **byte-faithful Jimmy Johnson for picks 1–129 and then collapses**.
  From pick 130 the game steps down ~1 point per pick where the real chart steps ~0.5. Verified cell
  by cell: pick 160 = **10** (real 27.4), pick 190 = **2** (real 15.4), pick 200 = **1** (real 11.4),
  pick 210 = **1** (real 7.4), picks 198–224 are all `1`. Round totals: R5 **817** vs ~1 096, R6
  **137** vs ~678, R7 **37** vs ~298. Rounds 6 and 7 — 64 of 224 picks, **29 % of the league's draft
  inventory by count** — are worth 174 points combined, less than one 68-OVR backup. In the tail the
  chart is **11× steeper than the steepest published chart in existence**, including the one it
  claims to be. Consequence: the game's trade market cannot conduct business below round 4, and
  rounds 4–7 are where roughly half of all real in-season trades settle.
- **What to do**: Replace picks 130–224 with the real Johnson values — a ~0.5/pick glide through R5,
  ~0.4 through R6, ending at 2.
- **Risk / how to verify**: **This will move every trade in the game.** Re-run the smoke bands and
  expect the AI-vs-AI fairness band to be able to *tighten* toward 0.82–1.45 afterwards (it was
  widened to 0.72–1.70 precisely because the tail made the canonical deadline trade unconstructible).
  Watch `diag tradeFunnel` for a shift in where deals die, and re-verify F-07's acceptance target.
- **Depends on**: none
- **Source**: `AI_TRADE_ANALYSIS.md` §2.4, §3.1 row 11, §3.2 item 3, recommendation B4;
  `REBUILD_VIABILITY_ANALYSIS.md` §1.2 (same chart, cited as the trade-value base). Ledger
  `TODO.md:4219`.

### F-10 — Tighten the future-pick discount from ×0.8 to ×0.6/yr — **DONE** (trade wave — future-pick discount ×0.6)
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *How aggressively should a future pick be discounted?* Massey–Thaler's
  implied rate is ~×0.42/yr; the practitioner "one full round down" rule is ×0.45–0.55; the trade
  report recommends **×0.6** as the point that lands inside the practitioner band without gutting
  the future-pick market the §5 volume bands depend on.
- **Where**: `Engine/Contract/TradeValueEngine.swift:172` (`pow(0.8, yearsOut)` inside
  `pickTradeValue`, also cited as `:169-174`); then reconsider
  `TeamStance.futurePickMultiplier` (`:558`, value 1.15) and `pickMultiplier` (0.94…1.08).
- **What is wrong**: At ×0.8/yr the game is 1.5–1.9× too generous to future picks. Worse, a
  rebuilder's stance multipliers cancel the discount entirely: `0.8 × 1.15 × 1.08 = 0.99`, so **a
  rebuilding club in this game values a 2028 second at 99 % of a 2027 second** where the real market
  values it at roughly half. This is a direct cause of the funnel note recording that 100 % of five
  league years' AI-vs-AI deals returned nothing but future picks — they are the cheapest currency a
  buyer can pay with, and the game barely discounts them.
- **What to do**: Move the base to `pow(0.6, yearsOut)`. At 0.6 base a rebuilder still nets 0.69,
  which is a real preference rather than a no-op, so `futurePickMultiplier` can stay at 1.15.
- **Risk / how to verify**: Reduces the currency AI clubs use most, so total deal volume may fall
  below the §5 bands. Verify with the smoke trade bands (in-season 8–25, offseason, `pkgShare`
  ≥25 %) and the funnel. Land it **after** F-09 so the two chart changes are measured together, not
  separately.
- **Depends on**: F-09
- **Source**: `AI_TRADE_ANALYSIS.md` §2.4, §3.1 row 12, §3.2 item 6, recommendation D1;
  `REBUILD_VIABILITY_ANALYSIS.md` §1.2 (states the same ×0.8 constant).

### F-11 — Make the salary cap bind across league years — **D2 (a)+(b) `ebf23f8`/`409899c`, (c)+(d) `55199ec` — ALL FOUR SUB-PARTS LANDED**
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Is the salary cap supposed to be a persistent constraint or a one-year
  inconvenience?* This is one decision with four sub-parts (dead-money persistence, a spending
  floor, a per-club reserve, a release lever) and the reports recommend all four. It is the single
  largest realism gap the roster audit found and the strongest available brake on the fast rebuild.
- **Where**: `Engine/Contract/FreeAgencyEngine.swift:691-720` (the annual true-up:
  `team.currentCapUsage = salaryByTeam[team.id] ?? 0`), `:1143` (`capReservePercent = 0.15`),
  `:686-689` (hand-inlined unconditional 5–8 % cap growth), `:919` / `:2520` / `:2906` (the three
  reserve-enforcing doors), `:2650-2653` (the mop-up wave);
  `Engine/Contract/CapManagementEngine.swift:106`/`:112` (`calculateDeadCap`, dead),
  `:857`/`:864`/`:875`/`:882` (`isAboveSalaryFloor`, `amountBelowFloor` — the real 89 % rule,
  dead), `:19`/`:29` (`calculateCapRollover`, dead), `:806` (`applyCapGrowth`, dead),
  `:824`/`:830` (`projectedCapSpace`, dead), `:49` (`processCompensatoryPicks`, dead), `:1123`
  (`canSelfHeal`, dead), `:1222` (`selfHealCapCompliance`, restructure-only by design);
  `Engine/Contract/ContractEngine.swift:1669-1687` (June 1 designations, implemented, never called).
- **What is wrong**: Four independent mechanisms over-determine the same result — **no AI club can
  ever be in cap trouble.** (1) The March true-up rebuilds `currentCapUsage` from the sum of rostered
  `annualSalary`, so every cut, trade and accelerated proration ages off in one league year; the
  file's own comment admits it and calls it a placeholder. (2) A hard 15 % reserve is enforced at
  three separate doors, so a club can never end free agency below 15 % room. (3) Cap growth is
  unconditional. (4) There is no salary floor: `isAboveSalaryFloor` models the CBA's 89 % rule and
  has zero callers. Measured over two four-season smoke runs: league cap room **34.4 → 40.3 → 32.9 →
  25.3 %** and **30.3 → 39.2 → 32.3 → 23.1 %**, with 31–32 of 32 clubs compliant every season and
  the worst club at −0.2 %; payroll **64.5–79.8 %** of a cap the CBA requires be spent at 89 %.
  Consequence for the user: a catastrophic cap sheet self-clears in one offseason (the `.capHell`
  career scenario is a one-season starting condition, not a state), the veteran market is
  permanently thin, and there is **no lasting cost to any roster decision**. ~120 lines of cap
  machinery sit unreferenced.
- **What to do**: Four changes, in this order. (a) Replace the annual wipe with the per-year dead-cap
  ledger its own comment asks for, wiring the existing `calculateDeadCap`. (b) Enforce the salary
  floor in the FA mop-up: a club under 89 % must spend whether or not it has a need — this alone
  lifts league payroll into the legal band and thickens the veteran market. (c) Make
  `capReservePercent` a per-club *taste* rather than a rail: ~0.18 for the analytics GM, ~0.06 for
  the aggressive one, so the aggressive club genuinely runs out of money in November. (d) Add a
  **bounded** cap-casualty pass — at most 1 per club per year, only on a man whose dead-money charge
  is less than his cap hit — as the missing half of `selfHealCapCompliance`, which is restructure-
  only for the stated and correct reason that cuts move task #53's calibrated churn.
- **Risk / how to verify**: Sub-part (d) is the dangerous one; it moves roster churn, which is
  separately calibrated. Gates: the smoke `capRoom` band must move from 23–25 % toward low single
  digits; payroll must clear 89 %; the age-pyramid and churn-funnel bands must hold. Run
  `./run.sh career` and `./run.sh leaguegen` for knock-on effects on the quality pyramid. Expect to
  re-baseline several smoke bands — do this as its own wave.
- **Depends on**: F-04 (so the effect on standings is visible)
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §2.3, §4.2 P2/P6, PART 5 items 1 & 4, and
  recommendation R5; `REBUILD_VIABILITY_ANALYSIS.md` §2.4, §1.1 ("structural free money on the
  table, all verified dead code") and recommendation 7. Ledger `TODO.md:4171`.

### F-12 — Put bidders on the board in free-agency rounds 1–3
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Which of the two levers, or both?* (a) lower the round-1 AI entry bar
  `targetMinOVR` from 85 to ~78; (b) make `ownCoreRetentionsPerClub` scale with roster quality — a
  contender keeps 5–6, a rebuilder keeps 1–2 — instead of a flat 3.
- **Where**: `Engine/Contract/FreeAgencyEngine.swift:2770-2779` and `:2885-2888` (the round gate,
  `marketAppeal >= 85`) × `:1415`, `:1421`, `:1426` (`ownCoreRetentionsPerClub = 3`,
  `ownCoreStarAppeal = 80.0`), `:1674-1686`; appeal formula `:1238-1249`.
- **What is wrong**: The round-1 AI entry bar sits **above** the auto-retain bar, so any free agent
  good enough to draw a round-1 AI bid necessarily cleared his own club's auto-keep threshold. He
  reaches the market only if his club had already spent all three retention slots on men ranked
  above him. Measured effect: **round 1 of free agency is, in practice, an uncontested board.** The
  players who leak through in volume are the ones the appeal formula pushes below 72 — an 85-overall
  30-year-old scores 71.0 and hits the board every year, drawing his first AI bid in **round 4**.
  Combined with F-14's multipliers this is the fastest rebuild lever in the game: +3 to +4 starter
  points in offseason 1, worth more than three seasons of everything else combined.
- **What to do**: Implement whichever lever(s) the user chooses. Note the report's framing of (b):
  the flat 3-slot cap is *"a flat talent tax on good AI teams and the main reason quality flows to
  whoever bids"* — every March, 31 clubs are forced to release roughly 80 % of their quality
  expiring players into a market where the user is the most attractive bidder.
- **Risk / how to verify**: Fewer good free agents reaching the board makes the user's rebuild
  slower — that is the point, but it interacts with F-11(b) (a floor forces spending) and could
  over-thin the market if both land at once. Verify with the smoke's own-core retention count
  (currently 70/league year = 2.3 per club against a ceiling of 3) and the `capRoom` band, then
  re-run F-04's dispersion metrics.
- **Depends on**: F-04; land after or with F-11
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 3, §1.1, §2.8 asymmetry 1;
  `AI_ROSTER_DECISIONS_ANALYSIS.md` §2.5. Ledger `TODO.md:4179`.

### QA-01 — Live QA findings, 2026-08-21 (one career, Fixed 2026, Las Vegas)

A full career was driven on the simulator to the start of the 2027 regular season.
Five findings were fixed in the same pass; two are recorded here because they are
not yet diagnosed to a cause.

**Fixed in `RosterStrength` + three call sites.** The team picker said Roster OVR
**76** and the career dashboard said **68** for the same club on the same save —
one label, two definitions, eight points apart. The picker was right: it averages
starters, which is what `DepthChart.teamOverall` reports once the career runs. The
dashboard, the FA recap and the pre-FA snapshot took the whole-roster mean, which
on an offseason roster of up to 87 averages in forty men who will never take a
snap. All three now read one shared definition. This is F-20, confirmed live.

**Fixed in `NewCareerView`.** "Choose Your Team" is `.disabled` until a name is
entered, and a disabled `NavigationLink` drops out of the accessibility tree
entirely — the button looked normal, did nothing, and explained nothing. A
standing hint now says why.

**Fixed in `NewCareerView`.** The portrait picker said "Cosmetic only — does not
affect gameplay" while offering twenty GM archetypes by name. The disclaimer was
misleading in its own right: the career's coaching STYLE carries +10 play-calling
(visible on the staff screen) and the introductory press conference builds a media
read whose own recap says it "shapes free-agent interest".

**Fixed in `CoachingStaffView`.** Auto-hire promised "the best affordable
candidate who fits your staff" and produced an offensive coordinator with
**play-calling 47** — because it ranked on the twelve-attribute mean, which gives
a coordinator's defining skill one twelfth of the vote. Ranking is role-weighted
now.

**Fixed in `CapComplianceView`.** The release dialog said the dead money lands "on
your books this year" for every contract. D2's ledger splits a release with three
or more years left across two league years, so the copy was wrong for exactly the
contracts where the number matters most.

---

### QA-02 — Free agency: the binding constraint is the ROSTER CEILING, not the appeal bars — **corrects F-12**
- **Class**: design-change
- **Priority**: P1
- **Where**: `Engine/Contract/FreeAgencyEngine.swift` — `faRosterCeiling = 46` (reported `:1144`),
  `simulateAIFreeAgency`'s eligibility filter, reached from `simulateRemainingFA`.
- **What is wrong**: F-12 blames the AI's entry bar (`targetMinOVR` 85 in round 1) sitting above its
  own retain bar (`ownCoreStarAppeal` 80). A live career says the mechanism is different, and the
  observation is unambiguous in both directions at once: **199 players hit the market**, the
  tampering board carried **eight men at 91-96 OVR** (a 96 OVR outside linebacker does not reach free
  agency in a real league), and after the whole league's market ran, **all six** of the user's
  expiring players went **unsigned** — including a **78 OVR** defensive tackle, with league cap room
  around 30 %.
  `targetMinOVR` is a per-round FLOOR (85 / 80 / 75 / 70 / 65 / 60), so a 78 OVR man is eligible from
  round 3 onward and the bars alone cannot explain him going unsigned. The eligibility filter also
  requires `rosterSize < faRosterCeiling`, and **46 is below what a club carries in March**. Clubs
  are full before the money is spent, which is the same wall that made D2(b)'s first attempt at a
  spending floor measure as a no-op: volume cannot be the lever when there are no seats.
- **What to do**: NOT a blind retune. `faRosterCeiling` carries a measured justification (task #53
  tried 42 and measured the opposite of its hypothesis), so this needs the same treatment: measure
  what the ceiling does to the unsigned pool and to the 80+ band before moving it. The question to
  answer first is whether the market should fill to 46 and leave the rest to the roster floor's
  refill, or whether the ceiling belongs nearer a real March roster.
- **Risk / how to verify**: `SMOKE: diag churn`'s `poolLeft` and `faSign` columns, and the §8 age
  pyramid, which is what #53 moved.
- **Depends on**: none
- **Source**: live QA, 2026-08-21.

---

### QA-03 — The week band read BYE while the card named an opponent — **DONE (display half); the "will not advance" half was MY TOOLING**
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `UI/Career/CareerShellView.swift` `reloadSeasonFixtures` (`:3178`),
  `UI/Career/SeasonWeekBand.swift`, `UI/Career/CareerDashboardView.swift`'s hero card.
- **What is wrong**: On the first regular-season week of a career, the week strip read
  **"1 BYE · 2 BYE · 3 BYE …"** with "No game this week" while the hero card on the same screen read
  **"Week 1 · vs LAC (Home)"**, and "Advance to Week 2" did nothing across six taps.
- **What is NOT the cause** (checked): both fetches filter `careerID` AND `seasonYear ==
  career.currentSeason`, so they are querying the same set; `reloadSeasonFixtures` IS called after
  every advance, via `loadShellData`; and the state was reached by the DEBUG skip, which loops the
  real `WeekAdvancer.advanceWeek` rather than shortcutting it — so it is not a debug-only shortcut
  artefact, though it may still be specific to a career that skipped its offseason tasks.
- **CORRECTION (same day, second career)**: the "will not advance" half is **not an app defect**. A
  fresh career, played normally with no debug skip, reproduced the symptom — and then a coordinate
  tap through `idb` actuated the same button immediately and opened its sheet. **XcodeBuildMCP's
  semantic `tap` does not actuate this control**, the same way its `swipe` silently fails on this
  app's Lists (already documented in the QA skill). Two careers' worth of "the button does nothing"
  was my tooling, and it is withdrawn.
- **What survives**: only the display half — the week strip read BYE for every week while the hero
  card named a Week 1 opponent.
- **REPRODUCED AND FIXED, 2026-08-22.** Reached Week 1 of a 2027 regular season and photographed it:
  every slat read `BYE`, the current one "No game this week", while the hero card read
  `Week 1 · @ CLE (Away)` and the advance popover read "Skip your Week 1 game vs CLE?". Three labels,
  two answers, on one screen.
- **Root cause**: `seasonFixtures` is `@State` on the shell, written by `reloadSeasonFixtures()`, and
  the note above ("it IS called after every advance, via `loadShellData`") is true only of
  `performShellAdvance`. **The DEBUG skip is a second mutator of the calendar**: `skipToFreeAgency`
  loops `WeekAdvancer.advanceWeek` itself and finishes with `loadAllData()` — the DASHBOARD's loader.
  Nothing tells the shell. And a career opened in the offseason has no `Game` rows for the season it
  is about to play, so the one fetch that did run found nothing and every week defaulted to a bye.
  The hero card disagreed because it reads a live query, not a snapshot.
- **The fix**: `reloadSeasonFixtures()` now hangs off `onChange(of: career.currentPhase)` and
  `onChange(of: career.currentWeek)` as well. The ladder is now a function of the calendar's STATE
  rather than of the code path that moved it, so any future mutator — a debug control, a full-screen
  flow, a migration — cannot desynchronise it again. Cost is one `Game` fetch per week boundary.
- **Honest scope**: as observed, this was reachable only through the DEBUG skip; the normal advance
  path was never broken. The fix is kept anyway because the fragility, not the symptom, is the defect
  — the band was one new caller away from lying on a shipping path.
- **Depends on**: none
- **Source**: live QA, 2026-08-21; reproduced and fixed 2026-08-22.

---

### F-13 — Fix the loyalty branch in `scoreBid` — **DONE 2026-08-22 (the decision was already fixed by D1; the DISPLAY was not)**
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/Contract/FreeAgencyEngine.swift:3353-3355` (the `.loyalty` branch), `:3273-3282`
  (where `bid.isPlayer` is set).
- **What is wrong**: The branch's own comment says "prefers current team", but it keys on
  `bid.isPlayer`, which is set **only for the human's offer**. So a loyalty-motivated free agent
  gives the *human* +25 % and every other club −15 %, regardless of where he has actually played.
  The code does the opposite of what it says.
- **What to do**: Key the branch on `bid.teamID == player.teamID`.
- **Risk / how to verify**: Removes a large user advantage on one motivation class; combined with
  F-14 the swing is material. Verify with the FA smoke diagnostics (user win rate on contested
  free agents) and by a manual round-1 negotiation against a loyalty-motivated player.
- **RESOLUTION, 2026-08-22.** The named site was already closed: D1 rewrote `scoreBid`'s `.loyalty`
  branch to `1.06 / 0.98` and priced the pitch at `× 1.02` (+`× 1.04` for a hosted visit). Keying on
  `bid.teamID == player.teamID` as this entry proposed is **not possible** — a free agent has no
  `teamID` and `Player` has no `previousTeamID`, which is why D1 repriced the flag as a pitch rather
  than repairing it as a bond.
- **WHAT WAS STILL BROKEN, and is the real content of this entry**: D1 fixed the function that SIGNS
  the man and missed its sibling, `scoreOfferForMotivation`, which computes the **leaning the
  negotiation screen shows**. It still carried every multiplier the ruling deleted — a flat
  `× 1.10` for being the user, `× 1.15` more on `.winning`, `× 1.05` more on `.stats`, and
  `1.25 / 0.9` on `.loyalty`. On equal money a loyalty free agent therefore DISPLAYED as
  `1.25 × 1.10 / 0.9 = 1.53` → "Strong interest" while the decision underneath scored him
  `1.06 / 0.98 = 1.08`, a coin flip. **The player was told he was winning men he then lost** — worse
  than either number being wrong alone, and the same one-quantity-two-spellings defect as #154 and
  QA-03.
- **The fix**: the user-side terms in `scoreOfferForMotivation` now mirror `scoreBid` exactly, with
  a doc comment on the function naming the constraint. They remain two functions — `scoreBid` is a
  local closure over `player`, `hostedVisit`, `allPlayers` and the record, so sharing one scorer is
  a real refactor, not an extraction. **Follow-up (open): unify them, and feed the leaning real team
  records so the loser tax reaches the display too** — the one call site passes `teamRecord: nil` for
  both sides today, so the leaning compares salary and motivation only.
- **Depends on**: none
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 6 (the second half, explicitly flagged
  as "mis-implemented against its own comment").

### F-14 — Rebalance `scoreBid`'s structural user multipliers — **DONE — `893da82` (D1 wave) — `scoreBid`'s structural multipliers are 1.06/0.98 + a 1.02 pitch; verified in source 2026-08-22**
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Should the user keep a flat structural bonus in free agency, and how
  large should the penalty for being a bad team be?* The report offers two options: gate the flat
  ×1.10 on team success, or give AI clubs a matching "their team" bonus.
- **Where**: `Engine/Contract/FreeAgencyEngine.swift:3340-3374` (`scoreBid`): `:3366-3368` (×1.10
  flat for the user), `:3372-3374` (×1.15 for a hosted visit), `:3340-3345` (the winning-motivated
  record term); the missing gate at
  `Engine/Contract/ContractNegotiationEngine.swift:679-681` (`refusalVerdict`, including
  `.losingCulture`, computed only when `negotiationType.isOwnClub`) and its FA caller
  `FreeAgencyEngine.swift:142-148`.
- **What is wrong**: The user's offer is multiplied by ×1.10 flat, ×1.15 for a hosted visit and
  ×1.25 for loyalty-motivated players, while the **entire** penalty for being a bad team is the
  winning-motivated record term — a **12.4 % spread between 0-17 and 17-0**. Net: a 2-15 user
  outbids a 14-3 AI at **79 cents on the dollar** (money-motivated, with a visit), or **61.8 %**
  for a loyalty-motivated player. There is additionally **no "won't sign with a loser" gate at all**
  in free agency: `.losingCulture` gates extensions of your own players only.
- **What to do**: Per the user's decision above. The `.losingCulture` half overlaps F-59.
- **Risk / how to verify**: Directly slows the fast rebuild — verify against
  `REBUILD_VIABILITY_ANALYSIS.md` §3.2's optimal-play table (season 1 at 7-10 / ~.410 today) and
  F-04's dispersion metrics. Confirm the average-play line (§3.3: playoffs in season 4) does **not**
  get slower — the report is explicit that the average path is already correct and should not move.
- **Depends on**: F-13
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 6, §1.1, §4.6. Ledger `TODO.md:4179`.

### F-15 — Route the opponent-prep drift penalty into a field the simulator reads — **DONE — `893da82` — `prepFocusDelta` is a real `GameSimulator.simulate` parameter and reaches the score (`:229`)**
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/Camp/OpponentPrepEngine.swift:26-30` (`driftPenalty`, −1…−3 after 3+
  consecutive opponent-heavy weeks), applied in `Engine/Simulation/WeekAdvancer.swift` (reported
  `:8560-8567`) to `player.physical.stamina`; the only engine reader of `stamina` is
  `Engine/PlayerDevelopment/WorkloadEngine.swift:119`.
- **What is wrong**: The designed counterweight to opponent prep lands in `physical.stamina`, and
  `stamina` has **zero occurrences** in `PlaySimulator.swift`, `GameSimulator.swift`,
  `DriveSimulator.swift`, `LiveGameEngine.swift` or `SimPlayer.swift`. Its one engine consumer feeds
  `cumulativeLoad`, which per `docs/INJURY_SYSTEM_ANALYSIS.md` §1.2 is a camp-time constant that
  never moves in-season. The only visible effect is cosmetic: `physical.average` at weight 0.30
  means −3 stamina = **−0.15 displayed OVR**; riding the penalty to the stamina floor of 40 across a
  season costs ≈ **−1.5 displayed OVR and exactly zero simulator effect**. This is the injury-system
  bug class in mirror image.
- **What to do**: Route the penalty into a channel `SimPlayer` actually carries, or delete it and
  price the cost into F-16's redesign. The reports do **not** specify which channel — that is
  deliberately left open, because F-16 may make the counterweight unnecessary.
- **Risk / how to verify**: Any live channel this lands in becomes a new balance surface. Verify
  with `./run.sh fullgame --home-tier 70 --away-tier 70 --n 3000` before/after: points per team must
  not move for a team that never triggers the penalty.
- **Depends on**: decide alongside F-16
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §2.2 and PART 5 item 2 (the bug half). Ledger
  `TODO.md:4237`.

### F-16 — Replace the opponent-prep post-game score multiplier — **DONE — `13a984b` — no `prepMultiplier` / `postGameScoreMultiplier` survives anywhere in `Engine/`**
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Should opponent prep (a) thread through the simulator as real per-play
  modifiers, (b) shrink to a defensible magnitude, or (c) be given to all 32 clubs so it stops being
  a subsidy?* The report recommends threading **and** giving AI clubs prep; all three sub-options
  change intended behaviour.
- **Where**: benefit at `Engine/Simulation/GameSimulator.swift:519-538` (the post-hoc multiplier),
  fed by `Engine/Camp/OpponentPrepEngine.swift:15-21` (`gameBoost`) from
  `Engine/Simulation/WeekAdvancer.swift` (reported `:1341-1357`, behind an explicit identity guard);
  the only construction site is `UI/Camp/GameWeekPrepPicker.swift:188-197`, which hard-codes
  `teamID: career.teamID`.
- **What is wrong**: No AI club has ever had an `OpponentPrepWeek` row. The user's row is converted
  into `(audibleBoost: 0.20×ratio, defReadBoost: 0.15×ratio)` and then applied **after the game is
  over, as a multiplier on the final score** — ×1.10 on the user's points, ×0.925 on the rival's. It
  never touches a play, a call, an audible or a defensive read; it is a scoreboard edit, and the
  code's own comment admits it. At an engine-typical 24 points a side that is `26.4` vs `22.2` — a
  **+4.2-point margin swing every regular-season game**. Against an NFL-typical margin sd of 13.5
  that converts a coin flip into 62.2 %, i.e. **8.5 → 10.6 wins: +2.1 wins per year, free, from one
  slider that no rival can ever have.**
- **What to do**: Per the user's decision. Note that option (a) is the expensive one — it means
  threading multipliers through every `PlaySimulator` call, which is exactly what the original
  comment says was avoided.
- **Risk / how to verify**: Removing +4.2 points/game from the user materially slows every career.
  Verify with `./run.sh fullgame` at a fixed tier (prep off must equal today's prep-off numbers) and
  with F-04's dispersion metrics on a played career.
- **Depends on**: F-01 (until AI-vs-AI games run the sim, "give AI clubs prep" has nowhere to land)
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §2.2, §2.6, PART 5 item 2. Ledger `TODO.md:4237`
  (#224).

### F-17 — Give AI clubs a head-coach persona in the `gamePlan` slot — **DONE** (gameday wave — `HCPersona` fills the `gamePlan` slot)
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Should AI head coaches have a derived risk-tolerance persona that drives
  4th-down and two-point decisions?* The report specifies the design in full (below) and stresses it
  requires **no schema migration**.
- **Where**: new `HCPersona` in `Engine/Match/CoordinatorPersona.swift` (mirror `DCPersona.derive`
  at `:52-62` and `stablePersonaPick(id:)` at `:31-35`); source fields on
  `Domain/Models/Coach/Coach.swift:24-37`; attachment points — the hard-coded `nil` in
  `Engine/Simulation/WeekAdvancer.swift` (reported `:1372-1373` regular season, `:7296-7297`
  playoffs) and `Engine/Match/LiveGameEngine.swift:1789`; consumer
  `Engine/Simulation/PlaySimulator.swift` `decidePlayCall` (reported `:409` and `:426`, the two
  `if let plan` branches).
- **What is wrong**: `GamePlan` has five sliders and **every write site in the repo is a SwiftUI
  view**. Greps for `aiGamePlan|selectGamePlan|chooseGamePlan|autoGamePlan|generateGamePlan` return
  zero hits. The AI's value is a hard-coded `nil` in the regular season, the playoffs and coached
  games, so `PlaySimulator`'s lines 409-415 and 426-429 are **unreachable for all 31 AI clubs** and
  `planPassBias` is identically 0 for them. The resulting complete AI 4th-down table: never goes for
  it while leading by 7+ (not even 4th-and-goal from the 1); goes only on 4th-and-≤2 inside the
  opponent's 5, or in a last-two-minutes desperation window; otherwise field goal from the opponent's
  45 or punt. Measured against the real league that is **6–10× too conservative** (≈0.15–0.25 vs
  **1.47** attempts per team-game in 2023) and structurally **zero** between the opponent's 6-yard
  line and midfield, where the real 4th-and-1 attempt rate is 48.6 % and converts at 71.3 %.
- **What to do**: Derive `HCPersona ∈ { riverboat, modern, orthodox, punter }` from `adaptability` +
  `playCalling` above/below 70, tie-broken by `stablePersonaPick(coach.id)`. Three fields:
  `fourthDownAggressiveness` 0.85 / 0.60 / 0.40 / 0.15; `twoPointBias` (chart-row shift) +1 / 0 / 0 /
  −1; `clockErrorRate` 0.10 / 0.15 / 0.25 / 0.35. Then change **nothing** about the two `if let plan`
  branches except the *source* of the value: pass the AI's `HCPersona.fourthDownAggressiveness` in
  the `gamePlan:` slot instead of `nil` at all three call sites. This is one line per call site and
  it fixes the §2.1 asymmetry and the 4th-down realism gap in the same edit.
- **Risk / how to verify**: A riverboat HC going for it past midfield changes scoring in every quick
  sim. Verify with `./run.sh fullgame --home-tier 70 --away-tier 70 --n 3000`: points per team must
  stay put, and 4th-down attempts per team-game should land near the real **1.47**. Also verify the
  `twoPointBias` does not break the existing two-point chart, which is rated **good** and is on the
  DO NOT TOUCH list.
- **Depends on**: F-01
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §2.1, §4.3.1, PART 3 rows 1–2, PART 5 items 3 & 4.
  Ledger `TODO.md:4243` (#225).

### F-18 — Stop injured players dressing; wire the depth chart to the engine — **DONE** (lifecycle wave — `MedicalEngine.dressed` before the roster snapshot)
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/Simulation/GameSimulator.swift:130-131` (the `!$0.isHoldingOut` filter),
  `:1885-1886` (`startingPlayer(at:in:)` = max by overall);
  `Engine/Match/LiveGameEngine.swift:1283-1284`; `Engine/Simulation/MatchupResolver.swift:26-87`;
  `Career.depthChartData` — zero engine read sites, consumers only at
  `UI/Roster/DepthChartView.swift:260`, `UI/Career/CareerShellView.swift:1424`, `:2779`,
  `UI/Schedule/ScheduleView.swift:97`; the admission at `CareerShellView.swift:1409-1411`; the
  unconditional fatigue add in `WeekAdvancer.swift` (reported `:1781-1784`, `Int.random(in: 3...8)`
  for every non-injured player on every roster).
- **What is wrong**: Three linked defects. (1) **Injured players still take the field** — the
  starter filter checks `isHoldingOut` only; `isInjured` appears nowhere in `PlaySimulator`,
  `DriveSimulator` or `GameSimulator`. Same terminus `docs/INJURY_SYSTEM_ANALYSIS.md` found:
  injuries do not affect a game result, for anyone. (2) **The user's saved depth chart never reaches
  the engine** — an hour on the depth-chart screen changes nothing, and the code says so in a
  comment. Both sides field max-by-overall, recomputed on every read. (3) **There is no rest, no IR,
  no inactive list** — a third-string guard fatigues at the QB's rate, and
  `injuredReserve|placeOnIR|isOnIR` returns exactly one hit repo-wide:
  `Engine/Event/EventTemplates.swift:396`, a narrative **button label** with no mechanical backing.
- **What to do**: (1) add `isInjured` (or the shared `PlayerAvailability` that #210/#212 both list as
  their W0 prerequisite) to the starter filter in both paths; (2) make `WeekAdvancer`'s
  `startingLineupIDs` read `Career.depthChartData` when present; (3) scale the weekly fatigue add by
  depth-chart position. Note the overlap: item (1) is the same wire-up #212 R1 already schedules, so
  coordinate rather than duplicating.
- **Risk / how to verify**: Benching injured starters changes every game result and will interact
  with the injury overhaul's own balance gates. Verify with `./run.sh fullgame` at a fixed tier with
  no injuries (must be unchanged) and with the injury smoke bands once #212 lands.
- **Depends on**: F-01 (so the change is visible league-wide); coordinate with #212
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §2.4, §2.6, PART 5 item 9.

### F-19 — Give the random league a real team-strength spread
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Data/Import/LeagueGenerator.swift:606-651` (`generateRoster`), `:655`
  (`generatePlayer(position:teamID:depthIndex:)`), `:618-623`, `:1625`;
  `Data/Import/LeagueTeamData.swift:20` (`TeamPreview.estimatedOVR`);
  `UI/Career/TeamSelectionView.swift:110`, `:1477-1478` (the "Dynasty"/"Rebuilding" labels);
  the working reference implementation is `tools/league-data/make_templates.py:1509-1567`
  (`TEAM_SPREAD_TARGET = 5.0` at `:94`).
- **What is wrong**: `generatePlayer`'s only behavioural inputs are `position` and `depthIndex`. The
  advertised `estimatedOVR` (spread 64–87) and the situation labels shown on the team-select screen
  never reach the generator: measured **`corr(advertised estimatedOVR, actual roster mean) = 0.14`**.
  KC ("Dynasty", advertised 87) averages 71.4; CAR ("Rebuilding", advertised 64) averages 70.7. Over
  400 generated leagues the 53-man team mean is **71.0 ± 0.96** with a best-minus-worst of **3.94**
  — the random league's entire quality spread is sampling noise. **In a random league the premise of
  the whole rebuild question is unavailable: there is no bad team to take over.**
- **What to do**: Thread a per-team level shift through `generatePlayer` so the random league lands
  on the same 4–5 point roster-mean spread the template achieves. The template path already solves
  exactly this problem by fixed point; port the approach rather than inventing a second one.
- **Risk / how to verify**: `./run.sh leaguegen --leagues 400` — the t=0 quality pyramid must hold
  its existing asserts while team spread rises to ≈5.0; `corr(estimatedOVR, roster mean)` must climb
  well above 0.14. Then re-run F-04's dispersion metrics on a random-league career.
- **Depends on**: none
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 2, §0.2. Ledger `TODO.md:4186` (#217).

### F-20 — Rebase the UI ladders and owner goals onto the starter average — **DONE** (`296e793` — `RosterStrength`, one starter-average definition)
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `UI/Roster/RosterSummaryBar.swift:172-190` (`rosterStrength`), pool at `:29-32`;
  `UI/Career/IntroSequenceView.swift:1048-1055`;
  `Engine/Media/OwnerGoalsEngine.swift:55-145` (`generateSeasonGoals`, branches at `:63`, `:83`,
  `:110`), pool at `:464-468`; the correct pool is
  `Domain/Models/Team/DepthChart.swift:376-381` (`teamOverall(lookup:)`); the stale calibration
  origin is `Data/Import/LeagueGenerator.swift:993` (pre-P1 league mean 76.5) vs `:1027-1034`
  (recalibrated to 71.00).
- **What is wrong**: All three read the **whole-roster** mean, whose real range in the shipped league
  is **68.4–73.3**, against thresholds written for a league that no longer exists. Consequences:
  "Elite" (80+), "Strong" (75–79) and "Weak" are unreachable labels — **all 32 teams render "Average"
  or "Below Avg"**. And the important one: `OwnerGoalsEngine`'s branches are `> 75` → championship,
  `>= 65` → playoffs, `< 65` → "Develop 3 Rookies", so **every club including the 3-14 one lands in
  the middle branch and is told "Make the Playoffs / Win 9+ Games"**. The rebuild grace-period branch
  and the contender branch are both dead. The user starting a rebuild is judged against a playoff bar
  from day one.
- **What to do**: Switch all three pools to `DepthChart.teamOverall` (real range 74.9–81.5) and move
  the thresholds to ~76 / ~79.5.
- **Risk / how to verify**: Owner satisfaction and the firing paths key off these goals — verify the
  season-2/3 firing risk does not become punitive. Clean build; run
  `python3 tools/lint/design_tokens.py` for the two view files (no regression); then start a career
  on NYJ (74.92 starters) and confirm the owner asks for a rebuild, not the playoffs.
- **Depends on**: none
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 9, §0.3, §2.5, §3.5.

### F-21 — Pass the on-field unit, not the 53-man roster, to the familiarity terms
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/Simulation/GameSimulator.swift:230-231` →
  `Engine/Simulation/DriveSimulator.swift:115-117` (`offensePlayers` / `defensePlayers`);
  consumed at `Engine/Simulation/PlaySimulator.swift:4063-4078` (blown-assignment branch), `:4042-4046`
  (`famCurve`), `:3952-3965`, `:4027` (`famBustPivot = 55`), and the contract comment at `:4022-4023`;
  `Domain/Models/Player/Player.swift:592-594` (off-side players return `schemeFam = 0`);
  `Engine/PlayerDevelopment/VersatilityDevelopmentEngine.swift:357-367`.
- **What is wrong**: The arrays handed to `simulatePlay` are the **entire 53-man roster**, and
  off-side players return a hard zero, so ~27 zeros are averaged into every squad reading. A
  league-average defense reads **~29.7** against a `famBustPivot` of 55 and fires the blown-coverage
  branch on **~3.3 % of pass plays**, directly contradicting the engine's own contract that "a
  neutral squad never busts". Realised scheme effect is **~69 % of its designed size** (+2.7
  points/game measured against a designed ~+3.5).
- **What to do**: Pass the on-field unit. The scheme-install tax (§1.6) is on the DO NOT TOUCH list
  and this fix makes it land at full designed size, so expect the tax to get *stronger*, not weaker.
- **Risk / how to verify**: `./run.sh familiarity` — the fam-100-vs-33 delta should move from ~+2.7
  toward ~+3.5 points/game, and the bust rate on a neutral squad should go to ~0. Re-run
  `./run.sh fullgame` with `--fam` set to confirm aggregate points stay in band.
- **Depends on**: F-02 (both edit `PlaySimulator` consumers; sequence to avoid conflicting edits)
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 10, §1.6.

### F-22 — Make the rookie boom/bust roll reachable — **DONE** (draft wave — the boom/bust roll is reachable)
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:1908` (`applyAgeRegression`,
  which bumps `yearsPro`) vs `:1918` (`developPlayer`) vs `:257` (the `player.yearsPro == 0` gate);
  the branch itself at `:252-285`.
- **What is wrong**: `processOffseason` calls `applyAgeRegression` **before** `developPlayer`, so a
  drafted rookie always arrives at `developPlayer` with `yearsPro == 1`. The **5 % ×3.0 breakout**
  and the **5 % zero-development / −2-all-mentals struggle** branches therefore **never fire in the
  shipped game**.
- **What to do**: Capture `yearsPro` before `applyAgeRegression` and pass it into `developPlayer`.
- **Risk / how to verify**: This is one of the few available sources of draft variance, so R1
  outcomes will widen. `./run.sh career` — R1 washout should rise off 6.4 % toward the harness's own
  NFL reference of 20–25 %, and the hit-rate gate at
  `tools/balance-harness/driver/CareerScenario.harness.swift:113-131` (currently widened to
  [58, 78] %) should be re-tightened rather than re-widened.
- **Depends on**: none
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 11 and §2.7 ("Defect found: the rookie
  boom/bust roll is unreachable").

### F-23 — Give AI free agency a veteran perception model — **DONE 2026-08-22, measured**
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Should AI clubs misjudge veterans, and should the user's own read of a
  free agent be fogged to match?* The roster report is explicit that **fogging only the AI is a
  gift**: the correct pairing is a small user-side veteran fog (±1–2 on free agents outside the
  user's division, narrowing with a scouting spend), or, if that is too large a UI change, capping
  the AI σ at 2.0 so the asymmetry stays small.
- **Where**: new `VeteranPerception` mirroring `Engine/Draft/AIDraftPerception.swift` (σ table
  `:60-67`, fat tail `:76-80`/`:163-170`, deterministic pair seed `:184-196`); attachment points
  `Engine/Contract/FreeAgencyEngine.swift:1238` (`marketAppeal(_:)`, takes a `teamID`), `:989`/`:977`
  (`RosterNeedIndex.need` / `.bestOverall`, take a lens), `:1690` (`resignAIOwnCore`'s appeal test);
  further true-value reads at `:952-1030` and `:1666-1700`.
- **What is wrong**: There is **no `AIDraftPerception` equivalent for free agency.** Every AI club
  reads every veteran's true `overall` and true `truePotential`. A club never signs a bust, never
  lets a good player walk because it misjudged him, never overpays for a name; all 31 rooms value
  all ~500 free agents identically and correctly. The draft, by contrast, has a real measured fog
  (league mean |error| **3.96 OVR**, fat tail firing at **6.99 %** against a 7 % target, determinism
  verified) — so the pattern is already proven in this codebase and just needs extending.
- **What to do**: Gaussian, σ **2.0–3.5** by GM archetype (analytics 2.0 / balanced 2.5 / aggressive
  3.0 / old-school 3.5) — roughly **half** the draft σ, because a veteran has NFL tape and a college
  prospect does not. Fat tail 4 % at ±6–10. **Season-anchored, not pair-anchored**: unlike the draft,
  re-roll each league year, so a club wrong about a man in 2028 can be right about him in 2030.
- **Risk / how to verify**: A fogged AI is a *weaker* bidder unless the user is fogged too — this
  can accidentally accelerate the rebuild it is meant to slow. Verify with the FA smoke diagnostics
  (contested-signing win rate, mean overpay) and F-04's dispersion metrics. The `perception`
  scenario is the template for the read-only diagnostic to add.
- **THE OPEN DECISION, DECIDED (user delegated it, 2026-08-22): take the σ cap, file the user-side
  fog.** D3 requires a pairing because fogging the AI alone is a gift, and names two options without
  choosing. I took the cap, because the user-side fog is a much larger change than it sounds: every
  screen printing a free agent's rating would have to print a fogged one, that number would stop
  meaning what it means everywhere else in the app, and it needs a scouting-spend mechanic to narrow.
  That is a feature and deserves to be built as one, not smuggled in as the tail of a balance change.
  **Filed as its own entry rather than skipped.**
  The cap is applied as a **scale, not a clamp** — `2.0/3.5` over the whole archetype table, so the
  maximum lands on 2.0 and the clubs still differ (1.14 / 1.43 / 1.71 / 2.00). A clamp would have
  flattened three of the four archetypes onto one number and thrown away the only property D3's
  Option A is actually about: that the rooms are distinguishable, and therefore learnable.
- **RESOLVED.** `AIDraftPerception.veteranLens` / `veteranRead` reuse the draft's machinery rather
  than the separate `VeteranPerception` file this entry proposed — one perception module cannot drift
  from itself, and the harness already syncs this one. `read` gained an optional `seedSalt` (0 = the
  existing pair-anchored behaviour, bit-identical) so the veteran read can be **season-anchored** as
  this entry asks.
- **Attachment**: the fog lands on whatever each path actually DECIDES. The interactive rounds
  (`generateAIOffers`) decide by bid, so it moves money (`perceptionPricePerOVR = 0.03`, capped
  ±20 %). The bulk market (`simulateAIFreeAgency`) decides by a weighted pick, so it moves appetite
  (`perceptionWantPerOVR = 0.06`, capped ±35 %). `marketAppeal` is deliberately left alone — it is
  the league-wide consensus queue, not one club's read.
- **MEASURED** (`./run.sh perception`, new VETERAN READ block, which is the read-only diagnostic this
  entry asked for):
  - league mean |perceived−true| **1.54 OVR** vs the draft's **3.97** — veterans are the tighter read,
    which is the whole justification for halving σ;
  - archetype ORDER preserved and legible: analytics **1.27** < balanced **1.55** < aggressive
    **1.74** < oldSchool **1.95**;
  - fat tail **3.91 %** against a 4 % target;
  - **stable within a league year = true**, **re-rolls across league years = true**.
- **No regression**: `./run.sh career` after the change fails the same two pre-existing assertions
  (6.9b 19.05 %, 6.9g 4.31 %) and nothing else; OVR drift unchanged at **+0.021**; every price gate
  holds (6.11a-e), including league salary/market **0.732** and the 85+ cohort at **0.810**.
- **Depends on**: ~~F-01, F-04~~ — both landed
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §4.2 P1, PART 5 item 2, recommendation R1;
  `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §4.2 (the "where the AI is omniscient" theme). Ledger
  `TODO.md:4229` (#222).

### F-24 — Fog the AI development desk's potential read — **DONE 2026-08-22 (D3 had already decided it; the 'needs user decision' flag was stale)**
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Should the AI's training-focus desk read `truePotential`, the number the
  user is explicitly denied?* The reports recommend routing it through a fogged read the way
  `AIDraftPerception` already does for the draft, but do **not** specify the fog's shape for this
  path.
- **Where**: `Engine/PlayerDevelopment/TrainingFocusEngine.swift:296-300` (the
  `$0.truePotential > $1.truePotential` sort in `autoAssignFocus`, implementation `:265-311`, also
  cited as `:293-308`); the user-side contrast is `UI/Roster/DevelopmentReportView.swift:9` and the
  `HeadroomFog` at `:19-30`; the weekly caller is `Engine/Simulation/WeekAdvancer.swift` (reported
  `:1926-1939`, running for all 31 AI clubs).
- **What is wrong**: The AI development desk sorts candidates on hidden truth and therefore picks the
  three genuinely-highest-ceiling young players every week, while the user's own screens show the
  noisy `assessedPotential` label and `DevelopmentReportView` states the rule outright — printing
  headroom would hand the manager a number the engine deliberately hides. The AI's desk is
  omniscient and the user's is not. Secondary, smaller defect in the same function:
  `defaultArea(for:)` (`TrainingFocusEngine.swift:65-67`) returns `areas(for: position).first` — the
  AI always picks the **first listed** training area, never a situational one.
- **What to do**: Route the sort through a fogged potential read. Note this is otherwise a **good**
  system: training focus is one of only two weekly systems that are genuinely symmetric, it runs for
  all 31 AI clubs every week, and its value reaches the simulator through real player attributes.
  Do not weaken it, only fog the read.
- **Risk / how to verify**: Fogging the AI's read makes AI development slightly worse — measure with
  `./run.sh career` (league mean OVR drift must stay inside ≤ |0.40|/season) and the smoke's league
  average OVR band.
- **The 'needs user decision' flag was STALE.** D3 already ruled: *"The development desk's
  `truePotential` read is closed as pure information unrealism"* and *"Fog the development desk
  (F-24) as part of A, since it reads a number the user is denied."* Nothing was waiting on the user.
- **The stated dependency on F-23 was also void**: `AIDraftPerception.read` already takes a bare
  UUID, so the machinery was shareable as it stood.
- **RESOLVED 2026-08-22.**
  - **The fog**: `AIDraftPerception.ownRosterLens(forTeam:)` — the same deterministic,
    persona-shaped, fat-tailed machinery as the draft, narrowed for familiarity. A front office sees
    its own players every day and is *better* at them than at a stranger, so σ is scaled by
    `ownRosterSigmaScale = 0.45` (≈1.4 analytics to 2.7 old-school on the ceiling read) and the
    catastrophic-misread rate drops to `ownRosterFatTailRate = 0.03`. Not zero: the "we believed in
    him" bust is exactly the tail D3(3) asks for. `Lens` now carries `fatTailRate` so how often a
    room is completely wrong can depend on how well it knows the man.
  - **Verified the draft path is untouched**: `./run.sh perception --n 200` after the change reports
    league mean |perceived−true| **3.96 OVR**, fat tail **6.89 %** — the same numbers as before, so
    the new lens field does not leak into `lens(forTeam:)`.
  - **The secondary defect** (`defaultArea` always returning the first listed area, so all 31 clubs
    developed every quarterback along one identical path): AI assignment now goes through
    `TrainingFocusArea.autoArea(for:teamID:playerID:)`, drawn deterministically from the
    `(team, player)` pair — **club-shaped and stable**, D3's coherent plan rather than a per-tick die
    roll. **Honest limit: this is not SITUATIONAL.** That would develop the attribute the player is
    worst at, and no area→attribute reader exists — the mapping lives inside the private `bump`
    switch on the position-attribute enum. Exposing one is the better fix and is left open.
- **VERIFIED 2026-08-22.** `./run.sh career` — **the gate this entry names PASSES**: §8 league mean
  OVR drift **+0.021**/season against the ≤ |0.40| limit. Fogging the desk did not measurably weaken
  AI development, which is the risk the entry flagged.
  Two of the 36 assertions fail (6.9b §8 80+ share 19.00 % against a [12,19] band; 6.9g 33+ age share
  4.33 % against ≤4.0 %). **Both are PRE-EXISTING and neither is a regression** — measured, not
  assumed, by running the same scenario in a worktree at `a37e045` (the commit before any of today's
  work), which fails the same two at **19.16 %** and **4.39 %**. Today's wave moved both slightly
  toward their bands and left the drift gate unchanged (+0.022 → +0.021).
  `6.9g` carries its own note calling it a retirement-calibration follow-up; `6.9b` sits a rounding
  step outside a band that `LeagueGenScenario`'s own comments record the league historically running
  at 19.8-21 %. Neither belongs to F-24; both are worth their own entry.
- **Depends on**: ~~F-23~~ — void, `AIDraftPerception.read` already takes a bare UUID
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §2.3, §4.2 item 3, PART 5 item 7;
  `REBUILD_VIABILITY_ANALYSIS.md` §1.4. Ledger `TODO.md:4229`.

### F-25 — Bring full-game play selection back inside the NFL bands — **ROOT CAUSE FOUND 2026-08-22; play selection, but the SEQUENCE not the situation**
- **Class**: design-change
- **Priority**: P1
- **Needs user decision**: *Which lever moves first — the base pass weights, the situational
  branches, or the yardage channels?* The report identifies the cause but not the remedy, and the
  harness README's own diagnosis is quoted as *"the gap is pure play-selection"*.
- **Where**: `Engine/Simulation/PlaySimulator.swift` `decidePlayCall`, base weights (reported
  `:450-469`: 1st down 0.50 · 2nd-and-7+ 0.65 · 2nd-and-short 0.50 · 3rd-and-≤3 0.42 · 3rd-and-4-6
  0.65 · 3rd-and-7+ 0.80 · 4th-down-go 0.55); evidence in `tools/balance-harness/README.md` §Round-5.
- **What is wrong**: At the engine's own calibration point (70 vs 70, attribute-identical to the
  per-play bands that all read `[OK]`) full games land net YPA **8.4**, pass yards **330**, 3rd-down
  **50 %** and **29 points** per team — all `[OUT]` high against NFL bands — while plays, completion
  and sacks sit in band. The situational brain is more efficient than real coaches, in the direction
  that inflates scoring. Every aggregate quoted anywhere else in these four reports inherits this
  bias.
- **What to do**: Retune `decidePlayCall`'s weights against the `fullgame` bands. Land it **after**
  F-17, F-39, F-40 and F-44, all of which also change the play mix — otherwise the retune will be
  invalidated immediately.
- **Risk / how to verify**: This is the aggregate calibration everything else is measured against;
  changing it invalidates prior measurements. Gates: `./run.sh fullgame --home-tier 70 --away-tier
  70 --n 3000` must bring net YPA, pass yards, 3rd-down % and points into band **without** pushing
  plays/completion/sacks out. Re-run `spam` and `stacking` to confirm the balanced-control invariant
  (`Δypc +0.01`, `ΔpassEV +0.11`) and the worst-case floors are untouched.
- **Depends on**: F-17, F-39, F-40, F-44
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §1.6, PART 5 item 15;
  `REBUILD_VIABILITY_ANALYSIS.md` Caveat 1 ("absolute per-game aggregates run hot against NFL bands
  at every tier, a known engine property").

---

# P2 — realism and the imperfection model

> **The three rules the gameday report sets for every item in this band** (§4.3), and they are the
> right ones: **A** — imperfection is *structured bias*, not symmetric noise, because the user plays
> 17 games a season against 17 different opponents while each opponent plays him once, and therefore
> harvests variance far more efficiently than they do. **B** — every new AI error needs a matching
> user error path or a matching user cost. **C** — apply it to *both* sides of the ball and *all* 32
> clubs, or it is a subsidy. Plus the guardrail: cap aggregate AI error at ~2 decision errors per
> coach per game (mirroring `passTotalMalusCap` / `runGrandBiteCap`), and make roughly half of
> `clockErrorRate` outcomes *over*-aggression that sometimes helps the AI — otherwise "imperfection"
> is a difficulty slider wearing a costume.

- **ROOT CAUSE, each step measured (2026-08-22):**
  1. The run model is IN BAND — `percall` gives the NFL blend **4.09**, stuff 18.6 %.
  2. A full game at 80 vs 78 gives 3.68; at **70 vs 70** — identical players, and
     `edgeCompressionScale` returns exactly 1.0 below a 3.5-point gap so compression is not even
     active — it gives **3.33**. That rules out compression, the talent curve, and personnel (with
     all-70 players there is no better man for the depth chart to pick).
  3. Fatigue is ruled out by the new `RUN SPLIT` line: Q4 reads **3.39** against **3.34** on early
     downs. If backs were tiring, Q4 would be the low bucket.
  4. What a neutral snap does not model is the one thing left: `measureRun` passes
     `runKeyIntensity: 0`, so the defence never reads the run. `percall`'s "vs-mix" means a random
     defensive PACKAGE, not an adaptive opponent.
  5. `spam` prices the mechanism: a repeated inside run collapses **4.12 → 1.74** (42 % of first-call
     value) while a **mixed** caller loses **0.07** (4.45 memory-on vs 4.52 off).
- **Therefore**: the adaptive defence works as designed, and the game's own play-caller is predictable
  enough to be keyed. A mixed caller would sit near 4.45; the game measures 3.33.
- **What to do**: vary the SEQUENCE in `decidePlayCall`. NOT a retune of the run model — its base
  band's doc comment says the harness dialled it — and NOT the situational mix: the red zone reading
  2.18 is a short field with a stacked box, which is what a short field should yield.
- **Also noticed**: `spam`'s r4 reads 1.74 against a stated floor of ~1.8. Probably noise at this N,
  worth one look by whoever takes the retune.
- **A correction worth keeping**: an earlier note recorded that F-25's play-selection diagnosis was
  wrong, because the loss sits in ordinary early-down carries rather than special situations. The
  observation was right and the conclusion was not. It IS play selection — the sequence, not the
  situation.

### F-26 — Give AI clubs house preferences (`GMTaste`) — **DONE** (draft wave — `GMTaste`, +42 % between-club spread vs control)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should each club carry a permanent, deterministic 2-of-6 bias vector on
  its draft and FA boards?* The roster report calls this "the single highest-value addition, because
  it turns symmetric noise into a readable opponent" — the measure of success is that the user can
  learn "Denver always overpays for size" and that exploiting it costs him something elsewhere.
- **Where**: new `GMTaste` alongside `Engine/Contract/TradeValueEngine.swift:391-421`
  (`GMPersona.forTeam(id:)`); consumed as an extra additive term in
  `Engine/Draft/DraftEngine.swift` `aiMakePick` (a new line after `:277`) and as a multiplier in
  `Engine/Contract/FreeAgencyEngine.swift:2570` (`weightedPick` inside `simulateAIFreeAgency`).
- **What is wrong**: All 32 draft boards differ only by a **zero-mean symmetric Gaussian**. There is
  no trait bias, no scheme fit, no position bias, no small-school aversion, no character-hawk /
  boom-or-bust axis, no house preference of any kind. Nobody is *systematically* wrong about
  anything — which is exactly what a real GM is. Consequence in the measured board: over-drafting a
  stocked position is possible but unmotivated, and no individual AI club has a trait bias at all
  (`aiMakePick` never reads a combine number, a 40 time, height/weight or `nflReadiness`).
- **What to do**: Each club draws 2 tastes deterministically from its UUID. The report specifies six
  with magnitudes: *traits over tape* `+0.4 × (physicalScore − 70)`; *scheme fit* `+2.5` on an
  OC/DC-matching prospect; *position bias* `+3.0` on one group, `−1.5` on another; *small-school
  aversion* `−2.0`; *character hawk* `−4.0` per disclosed red flag (opposite archetype ignores them);
  *age hawk / age blind* `marketAgeDiscountPerYear` ×1.4 or ×0.6 for that club only. Magnitude
  matters: **2–4 OVR points is one letter grade and 15–27 slots of round-1 consensus movement** —
  enough to be noticed, not enough to break the board.
- **Risk / how to verify**: A taste that is too large produces a club that never drafts a position.
  Verify with `./run.sh perception --drafts 12`: R1 position shares must stay plausible (today CB
  20 %, WR 13 %, DE 11 %, QB 9 %) while *between-club* variance rises; reaches and steals must not
  blow past today's 13.25 / 65.92 per draft.
- **Depends on**: F-01, F-04
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §4.2 P3, PART 5 item 3, recommendation R2. Ledger
  `TODO.md:4234` (#223).

### F-27 — Model position runs and clock panic in the draft — **DONE** (draft wave — run tax + QB premium jump)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should AI clubs chase position runs?* Specifically the QB rule: if a club
  with a QB deficit sees two go in the last five picks, should `quarterbackPremium` jump from 2.0 to
  ~6.0?
- **Where**: `Engine/Draft/DraftEngine.swift:161` (`aiMakePick` — needs two new inputs it does not
  receive today: `recentPositions` and `pickNumber`), QB premium at `:275-277`; the detection
  plumbing already exists and is dead at `Engine/Draft/DraftEventEngine.swift:170-180`;
  pick history is held by `UI/Draft/DraftDayCoordinator.swift`.
- **What is wrong**: **The AI never panics.** Nothing in `aiMakePick` reads how many picks have gone
  at a position, how long the club has been on the clock, or what it just lost in free agency. There
  is no run-chasing, no "the third quarterback just went so we take ours now". Measured consequence:
  **2.9 QBs per first round with almost no variance**, against a real 15-year mean of ~3 but a real
  range of **1 (2022) to 6 (2024)**. The game's QB count is right on average and far too stable.
  This is the most legible GM error in the sport and it is entirely missing.
- **What to do**: Thread `recentPositions` and `pickNumber` into `aiMakePick`, then add the run tax
  (`if recentPositions.suffix(6).count(of: prospect.position) >= 2 { score += 1.5 }`) and the QB
  premium jump. The report notes this is the cheapest realistic panic model available because the
  plumbing already exists.
- **Risk / how to verify**: `./run.sh perception --drafts 12` — the QB-per-round *distribution* must
  develop a fat right tail without moving the mean far off 2.9; CB share (today 20 %, already flagged
  as over-drafted) must not rise further.
- **Depends on**: F-26 (same signature change to `aiMakePick`)
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.5, §4.2 P4, PART 5 item 11, recommendation R4.

### F-28 — Fix the inverted magnitude in the need model's quality term — **DONE** (draft wave — quality term magnitude corrected)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Draft/DraftEngine.swift:1395-1407` (specifically `:1401-1403`,
  `multiplier += 0.2` under 60 OVR and `+= 0.1` under 70) × `:261` (`deficitPoints = 5.0 × max(0,
  multiplier − 1)`); ideal counts at `:1364-1425`, against the FA roster ceiling
  `Engine/Contract/FreeAgencyEngine.swift:1124` (`faRosterCeiling = 46`).
- **What is wrong**: The quality half of the need model is a rounding error and **inverted in
  magnitude**. A position group averaging under 60 OVR is worth **+1.0** board point; being two
  bodies short at any position is worth **+1.5**. So a club whose entire cornerback room grades 55
  values that hole *less* than a club that is two bodies short at fullback. The report is explicit:
  *"That is backwards and it is a bug, not a taste."* Compounding it, the ideal counts sum to **48**
  against rosters that leave free agency at **46**, so most positions carry a deficit of 0 and
  contribute exactly 0 — need is near-inert on a normal board.
- **What to do**: Raise the quality bumps to `+= 0.45` (under 60) / `+= 0.25` (under 70), which
  prices a replacement-level room at **+2.25 board points instead of +1.0**. Separately reconcile the
  48-vs-46 ideal-count mismatch so the count half is not dead either.
- **Risk / how to verify**: `./run.sh perception --drafts 12` — R1 reaches (today 13.25/draft) and
  the true-BPA-slides-past-pick-5 rate (today 25 % of drafts) should both fall slightly as need
  becomes a real term; position shares should spread.
- **Depends on**: none
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.2, PART 5 item 9, recommendation R3 (second half).

### F-29 — Scale draft need-weighting by round — **DONE** (draft wave — round-scaled need)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should AI clubs draft for need in round 1 and for value on day 3?* The
  report's proposal is `deficitPoints = 5.0 × roundScale(pickNumber)` with roundScale = **2.0 in R1,
  1.0 in R2-3, 0.6 after**.
- **Where**: `Engine/Draft/DraftEngine.swift:261`.
- **What is wrong**: Need weighting is flat across all seven rounds. Real GMs draft for need in round
  1 far more than the value curve justifies, and much less on day three.
- **What to do**: As above; requires the `pickNumber` input that F-27 also needs.
- **Risk / how to verify**: `./run.sh perception --drafts 12` — R1 reaches will rise; keep them
  bounded and re-check the R1 mean `|pick − publicRank|` (today 26.0, already flagged as too noisy in
  F-62). These two items pull in opposite directions and must be tuned together.
- **Depends on**: F-27 (shares the `pickNumber` plumbing), F-28
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` recommendation R3 (first half).

### F-30 — Unify the three positional-value tables and fix the RT/FB inversions — **DONE** (draft wave — `draftPositionalWeight`, one derived ladder)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Draft/DraftEngine.swift:1413-1420` (`teamNeedComponents`'
  `positionalWeight`) vs `Engine/Contract/ContractEngine.swift:453-524` (`positionMultiplier`,
  the authoritative one) vs `Engine/Contract/FreeAgencyEngine.swift:1083-1091` (`holePriority`, a
  third copy whose own doc says it "mirrors `DraftEngine.teamNeedComponents`").
- **What is wrong**: Three copies of one idea with **two live inversions**. **RT** is paid 0.85 —
  above MLB 0.80, S 0.75 and TE 0.70 — but drafted at 0.6, *below all three*. **FB** is paid 0.25
  (bottom tier, same as a kicker) but drafted at 0.6, *the same as a right tackle*. These are the
  classic "two constants that were supposed to be equal and drifted" pair, and the drift has now been
  replicated into free agency by the third copy.
- **What to do**: Derive the first two tables from the third, e.g.
  `weight = clamp(positionMultiplier / 1.25, 0.3, 1.6)`, so there is one source of truth and the
  inversions cannot recur.
- **Risk / how to verify**: This changes both the draft board and FA hole priority at once. Verify
  with `./run.sh perception --drafts 12` (position shares) and the FA smoke diagnostics. Keep the
  specialist discount intact: `−8.0` on K/P (`DraftEngine.swift:268`) puts kickers at −12.0 total and
  is the one positional statement the AI makes emphatically — it is correct (no kicker has gone in
  round 1 since 2000) and is on the DO NOT TOUCH list.
- **Depends on**: none
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.4, PART 5 item 8, recommendation R8 (first half).

### F-31 — Widen the draft board's positional-value spread — **DONE** (draft wave — spread widened on the unified table)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *How much should position matter on an AI draft board?* The report
  proposes widening `positionalValuePoints` from **8.0 to ~14**, making the QB-vs-RB tilt ~+6 board
  points instead of +3.2.
- **Where**: `Engine/Draft/DraftEngine.swift:202` (`positionalValuePoints = 8.0`), applied `:267`
  (`(weight − 0.8) × 8.0`, realised range −1.6 … +1.6).
- **What is wrong**: The whole positional-value opinion is **±1.6 points — 5.5 % of the 29-point
  talent span**. A quarterback is worth **3.2 points** more to an AI club than a running back of
  identical grade: about two thirds of one letter grade. The game's own money table prices that gap
  at **3.67 : 1** and the real 2025 market at **2.9 : 1** ($60.0M Prescott vs $20.6M Barkley). The
  draft board prices it at 1.0 : 0.6.
- **What to do**: As above, after F-30 gives the tables one source of truth.
- **Risk / how to verify**: `./run.sh perception --drafts 12` — QB and EDGE R1 shares should rise,
  CB's 20 % (over-drafted) should fall. Watch that the specialist discount does not become
  proportionally weaker.
- **Depends on**: F-30
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.4, PART 3, PART 5 item 10, recommendation R8
  (second half).

### F-32 — Fix the bidding-war gate and the receipt for a price nobody paid — **DONE 2026-08-22 (plus a third bug found while fixing it)**
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Contract/FreeAgencyEngine.swift:2982-2983` (`maxBidders = max(1,
  Int(aggression × qualityFactor × 6))`, `qualityFactor = (overall − 60)/40`) vs `:3043`
  (`bids.count >= 4`); the affordability test at `:3057` vs the signing door at `:919`; the escalation
  at `:3048`; the documented race at `UI/FreeAgency/FAWeeklyView.swift:1895-1912`; the printed lie at
  `UI/FreeAgency/FARoundSummaryView.swift:127` and `generateHeadlines` (`:3471-3484`).
- **What is wrong**: Two bugs in one mechanic. (1) **Bidding wars are arithmetically impossible in
  rounds 4–6** and require a **99-OVR** free agent in round 3 — solving the gate gives a minimum OVR
  of 87 (R1), 92 (R2), 99 (R3), 113 (R4), 151 (R5), 193 (R6). Against a league whose 90+ band is
  1.7–3.1 % and whose star door keeps 80+-appeal men off the market, the mechanic fires on a handful
  of players a decade. (2) When it *does* fire it produces a **false receipt**: the escalation
  affordability test uses `team.availableCap` **without subtracting the 15 % reserve** — the only
  cap test in the file that does not — then the signing door refuses exactly that bid on
  `availableCap − reserve >= salary`. But `BiddingWarInfo.escalatedPrice` has already been written
  and is printed to the user verbatim as *"Price escalated to ~$XM/yr"* for a deal that may not have
  been struck, with `bidderCount` taken from before the drop-outs.
- **What to do**: Decouple the two quantities — keep the bid cap, but trigger `processBiddingWars` on
  `bids.count >= 3` **or** on the top two offers being within 10 %. And subtract the reserve at
  `:3057` so the escalated price is one the signing door will honour.
- **Risk / how to verify**: More bidding wars means higher FA prices league-wide. Verify with the FA
  smoke diagnostics (mean signing price vs ask, wars per round) and the `capRoom` band. Note the
  reserve subtraction becomes moot if F-11(c) makes the reserve per-club — sequence accordingly.
- **RESOLVED 2026-08-22.**
  - **Arithmetic re-derived, and this entry's table was partly wrong.** Solving `Int(aggression x
    (ovr-60)/40 x 6) >= 4` gives minimum OVR **87 / 92 / 99 / 114 / 137 / 194** for rounds 1-6. The
    first three match; R4-R6 were stated as 113 / 151 / 193. The conclusion is unaffected — rounds
    4-6 are impossible and round 3 needs a 99 — but the numbers are corrected in the code's doc
    comment, which is now the reference.
  - **Gate**: `bids.count >= 3` **or** the top two offers within 10 % (`biddingWarMinBidders = 3`,
    `biddingWarCloseness = 0.90`). The second clause is the one that decouples the trigger from the
    bid cap rather than moving it down by one: two clubs a percent apart IS a war, and it is
    reachable in every round.
  - **Receipt**: the drop-out test now subtracts the reserve through `capReserve(forTeam:)` — the
    same question `signFreeAgentAI` asks — so a surviving bid is one the door will honour, and the
    escalated price the user is shown is a price that can actually be paid. The raised-bid clamp
    uses the reserve-aware figure too. F-11(c) landed first, so this consumes the per-club reserve
    as that entry's note anticipated.
  - **THIRD BUG, not in this entry, found while fixing the other two**: `aiBids[playerID] =
    survivingBids` ran unconditionally. When every bidder failed the affordability test the player's
    whole bid list was replaced with an empty array — a war nobody could afford did not fizzle, it
    **erased offers that already existed** and left the man unsigned by anyone. A war with fewer
    than two survivors is now a war that did not happen: original bids stand, nothing is reported.
- **Verification owed**: not yet measured. This raises FA prices league-wide by construction, and
  the gates this entry names (mean signing price vs ask, wars per round, the `capRoom` band) still
  need a harness run. Compiles clean; behaviour unverified.
- **Depends on**: coordinate with F-11
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §2.4, PART 5 items 5 & 6, recommendation R7. Ledger
  `TODO.md:4179` (last sentence).

### F-33 — Let the bulk free-agent market overpay
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the skip button and the played market price players the same way?*
  The report's proposal: let the first 15 % of `sortedAgents` settle at
  `floor + (ask−floor)·U^(1/lean) × U(1.0, 1.25)`, decaying over the wave.
- **Where**: `Engine/Contract/FreeAgencyEngine.swift:2601-2602` (bulk:
  `settlement = floor + (ask − floor)·U^(1/lean)`) vs `:2953-2956` (interactive:
  `rawOffer = ask × needFactor × U(0.85·agg, 1.05·agg + 0.05)`); entry points
  `simulateAIFreeAgency` (`:2334`) via `simulateRemainingFAOnce` (`:863`), reached from
  `UI/FreeAgency/FAWeeklyView.swift:2076` and `WeekAdvancer.swift:3668`.
- **What is wrong**: **The bulk market can never exceed the agent's opening ask**; the interactive
  path can exceed it by up to **2.36×**. The same club, in the same league year, is a different
  negotiator depending on whether the user pressed "skip". Half the league's contracts cannot be
  overpays, by construction — and overpaying in the first 48 hours is the single most-cited GM error
  in the sport.
- **What to do**: As above. Note the interactive path already does this correctly and is called out
  as *"the one place the model already does something a real GM does"* — copy its shape, do not
  invent a third.
- **Risk / how to verify**: FA smoke: mean settlement as a fraction of ask must rise for the top of
  the market only; `capRoom` must fall; the veteran market must not empty. Interacts with F-11(b).
- **Depends on**: F-11
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §2.1, §4.2 P5, PART 5 item 14, recommendation R6.

### F-34 — Make the FA stance lean an actual knob
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Contract/FreeAgencyEngine.swift:1310-1335` (the doc at `:1310-1320`, the clamp
  at `:1331-1335`).
- **What is wrong**: The contender/rebuilder lean is clamped to `[0.769, 1.30]` while the doc itself
  admits the real span is 0.72–1.10 — so **exactly one branch bites** (0.72 → 0.769) and the upper
  bound is unreachable. The file self-documents it as *"a RAIL, not a working knob"*. It is one of
  only three error sources in the whole FA brain, and it is near-dead.
- **What to do**: Either widen the produced span to reach the clamp or narrow the clamp to the real
  span, so the modifier actually varies. The report does not say which — pick the one that leaves the
  documented intent (contenders pay more, rebuilders less) intact.
- **Risk / how to verify**: FA smoke — signing distribution by team stance must develop a visible
  contender/rebuilder split.
- **Depends on**: none
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §4.1 item 6, PART 5 item 15.

### F-35 — Merge the UDFA fog into `AIDraftPerception` — **DONE** (`296e793` — UDFA reads `AIDraftPerception`, local hash deleted)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/FreeAgency/UDFAMarketEngine.swift:283-287`, `:1071` (uniform integer ±6,
  σ = 3.74) and `:1153-1166` (its own FNV hash) vs `Engine/Draft/AIDraftPerception.swift:60-80`
  (Gaussian by archetype + 7 % fat tail) and `:184-196` (`pairSeed`, a SplitMix64/xxHash fold
  explicitly *not* `hashValue`); AI posting at `UDFAMarketEngine.postAIOffers:1050-1110`.
- **What is wrong**: **Two incompatible scouting fogs, two days apart.** The draft uses Gaussian
  σ 3–6 by GM archetype with a 7 % fat tail, deterministic per `(team, prospect)` pair. The UDFA
  market — running on the same clubs, on the same class, immediately after the draft — uses a uniform
  ±6 with no archetype, no fat tail and a different seed function. One scouting department should
  have one error model. (Also noted in the same file: the user's UDFA board is **NOT WIRED**, per the
  file's own header at `:190-197`.)
- **What to do**: Replace `UDFAMarketEngine.boardNoise` with `AIDraftPerception.read` on the same
  lens the club drafted with two days earlier.
- **Risk / how to verify**: `./run.sh perception --drafts 12` covers the draft half; the UDFA half
  has no harness scenario — verify via the in-app smoke's UDFA signing counts and quality, and note
  in the commit that this path remains under-instrumented.
- **Depends on**: none
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §4.1 item 10, PART 5 item 13, recommendation R9.

### F-36 — Close the `draftGrade` fog breach — **DONE** (draft wave — `publicOVREstimate` replaces the `trueOverall` read)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Draft/DraftEngine.swift:1026` (`draftGrade` boosts the published pick grade by a
  full letter when `prospect.trueOverall >= 80`).
- **What is wrong**: The grade the user is shown for **his own pick** is partly computed from a
  number he is never allowed to see. This is the one real fog breach surviving in a *live* path (the
  other, `generateStaffRecommendations`' sleeper sort on `truePotential`, is dead code and is handled
  by F-67).
- **What to do**: Compute the grade from the user's own scouted read, or from the public consensus
  board, not from `trueOverall`.
- **Risk / how to verify**: Pick grades will get less flattering on genuine steals — that is the
  point. Clean build; verify by drafting a known 80+ prospect the user has not scouted and confirming
  the grade no longer jumps.
- **Depends on**: none
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.3, PART 5 item 16.

### F-37 — Let AI clubs franchise-tag
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should AI clubs use the franchise tag?* The reports state the gap and the
  real-world rate but do **not** specify a decision rule for which player a club tags.
- **Where**: `Engine/Contract/ContractEngine.applyFranchiseTag` — reachable only from
  `UI/Contracts/FranchiseTagView.swift:673` and `UI/FreeAgency/FinalPushView.swift:1342`;
  the league-wide settler already exists at `Engine/Contract/FreeAgencyEngine.swift:1924`
  (`settleFranchiseTags`) and runs, but only the user's tags ever exist.
- **What is wrong**: **No AI club ever franchise-tags anybody.** The real NFL applies **8–15 tags
  league-wide every March**. The settling machinery is already built and league-wide; only the
  application is user-only.
- **What to do**: Add an AI tag decision to the rollover, feeding the existing `settleFranchiseTags`.
- **Risk / how to verify**: Tags remove players from the market the user shops in — this compounds
  with F-12 and could over-thin round 1. Verify with the FA smoke (tags per league year should land
  8–15) and the own-core retention count.
- **Depends on**: F-12 (they move the same market in the same direction)
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §2.5, §4.2 P6, PART 3, PART 5 item 12.

### F-38 — Give the coordinator misread model a floor, a grade scale, and an OC channel — **DONE** (gameday wave — misread floor, grade scale, OC channel)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should `balanced` and `conservative` coordinators be allowed to guess
  wrong, and should the AI offense have a misread channel at all?* Three sub-parts, all specified.
- **Where**: `Engine/Match/CoordinatorPersona.swift:88-94` (`DCPersona.misreadChance`), applied at
  `Engine/Match/LiveGameEngine.swift:1978-1983`; `DCPersona.derive` at `:52-62`; `OCPersona` at
  `:333-517`, which has **no `misreadChance` at all**, to be applied at `LiveGameEngine.swift:2018-2025`
  mirroring `:1978-1983`; the counter acts through existing package modifiers at
  `Engine/Match/AdaptiveOpponentAI.swift:281-283`.
- **What is wrong**: **The shipped game contains exactly one modelled AI decision error**, it exists
  only in coached games, and it is **0.0 for `balanced` and `conservative`** — and `derive` maps
  `base43 → {balanced, conservative}`, `tampa2 → conservative`, `cover3 → {conservative, balanced}`,
  so three of the seven scheme buckets, covering the most common defensive systems, produce a
  coordinator with a **literally zero error rate**. For an aggressive elite DC the rate is 10.8 % of
  defensive snaps; for a balanced grade-70 DC it is **0.0 %**. `OCPersona` has no misread field at
  all, so **the AI offense never misreads the user's defensive tendency** anywhere in the game.
- **What to do**: (a) Floor `conservative` and `balanced` at ~0.05. (b) Scale by coordinator grade:
  `effectiveMisread = basePersonaMisread + max(0, (70 − dcGrade) / 100 × 0.15)` — +0.045 at grade 40,
  +0 at grade 90, so coach quality buys *fewer mistakes*, which is what coach quality actually buys.
  (c) Add `OCPersona.misreadChance` (suggested `airRaid 0.15`, `groundAndPound 0.05`,
  `westCoast 0.08`, `balanced 0.05`) and apply it exactly as the DC's is applied — because the
  counter acts purely through existing package modifiers, a wrong counter is automatically a
  bad-but-legal call with no new balance surface.
- **Risk / how to verify**: Apply the §4.3.6 guardrails — cap aggregate error at ~2 decision errors
  per coach per game, and make roughly half of the error outcomes over-aggression that sometimes
  helps the AI. Verify with `./run.sh spam` (the mixed-parity balanced-control line must stay at
  `Δypc ≈ +0.01`, `ΔpassEV ≈ +0.11`) and `./run.sh stacking` (the worst-case floors must hold), plus
  `./run.sh fullgame --home-tier 70 --away-tier 70` for points/team.
- **Depends on**: F-01
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §4.1, §4.3.3, §4.3.4, PART 5 item 6. Ledger
  `TODO.md:4224` (#221).

### F-39 — Give the AI kneel, timeouts and the onside kick — **DONE** (gameday wave — AI timeouts, kneels, onside at 0.08)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the AI get the three endgame capabilities the user already has,
  and should the onside recovery rate be lowered from 0.12 to ~0.08 first?*
- **Where**: kneel — `Engine/Simulation/PlaySimulator.swift` `decidePlayCall` (reported `:450-469`)
  never returns `.kneel`, though the resolution exists at `:2090` (40 s); timeouts —
  `Engine/Match/LiveGameEngine.swift:163-190` (`:175`: *"AI teams never call timeouts"*) and
  `GameSimulator`/`DriveSimulator` have **no timeout concept at all**; onside —
  `Engine/Simulation/GameSimulator.swift:37-38` (`:37`: *"quick sim never onsides"*;
  `onsideKickRecoveryChance = 0.12`); the user's equivalents are
  `UI/Match/CoachedGameView.swift:1725`, `:1734`, `:2367`, `:4282`.
- **What is wrong**: Three structural user-only advantages. **The AI cannot end a game it has won** —
  three dropbacks at ~2.3 % INT is a ~7 % chance of gifting it back, every time. All six timeouts go
  unused in every simulated game, where real timeouts roughly double the snaps a trailing team gets
  on its last drive. A trailing AI down 5 with 0:40 left **always kicks deep**. And the onside rate
  itself is ~2× too generous: **12 %** against a real **8.7 %** (2018–2023), 4.23 % in 2023, 6.45 %
  in 2024.
- **What to do**: Lower `onsideKickRecoveryChance` to ~0.08 first. Then a rule-based AI user with a
  persona-scaled error rate: **timeouts** — trailing, ≤2:00, opponent has the ball, 3rd/4th down →
  burn one, with an `HCPersona.clockErrorRate` chance of not doing it (requires threading a timeout
  counter through `DriveSimulator`, which has none today); **onside** — trailing by ≤8 with <2:00, or
  by any margin with <0:30 → attempt; **kneel** — make `decidePlayCall` able to return `.kneel` when
  leading and the opponent cannot get the ball back, then gate the *failure* to kneel on
  `errorChance = clockErrorRate × (1 + leverageIndex)`, using the `leverageIndex` that already exists
  at `PlaySimulator.swift:3581-3583`. A `punter` HC in a one-score fourth quarter then fails to take
  the knee ~50 % of the time — both an error and correct football history.
- **Risk / how to verify**: Endgame changes move close-game outcomes disproportionately. Verify with
  `./run.sh fullgame --home-tier 70 --away-tier 70 --n 3000` (points/team must hold) and the §4.3.6
  per-game error cap. Onside attempts per team-game should stay rare.
- **Depends on**: F-17 (supplies `HCPersona.clockErrorRate`), F-40
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §2.6, §4.3.2, §4.3.5, PART 3 rows 9, 11, 12,
  PART 5 item 5. Ledger `TODO.md:4243`.

### F-40 — Fix the two-minute gates and the dead two-minute warning — **DONE** (gameday wave — two-minute gates)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Simulation/PlaySimulator.swift` — `isTwoMinuteDrill` (reported `:349-350`:
  `quarter == 4 && timeRemaining <= 120 && scoreDifferential < 7`), the game-management bias
  (`:308-310`, `:339-346`, fires only at Q3+ **and** `|margin| ≥ 7`);
  `Engine/Simulation/GameSimulator.swift:29` (`twoMinuteWarning = 120`).
- **What is wrong**: Three defects the code's own intent contradicts. (1) **A team up 3 with 2:00
  left runs an 85 %-pass hurry-up**, because `isTwoMinuteDrill` requires only `margin < +7` while
  `mgmtPassBias` requires `|margin| ≥ 7` — so between +1 and +6 the leading team gets the trailing
  team's behaviour. Real leading teams bleed clock from the moment they lead late. (2) **The
  end-of-first-half drill does not exist**: the gate is `quarter == 4` only, and end-of-half drills
  are a standard, high-value part of every real game. (3) `GameSimulator.twoMinuteWarning = 120` is
  **declared and never read anywhere in the repo** — a dead constant standing in for an automatic
  clock stoppage that is not modelled.
- **What to do**: Extend `isTwoMinuteDrill` to `quarter == 2 || quarter == 4`; change the
  leading-team gate from `scoreDifferential < gameMgmtLeadPts` (7) to a **possession-aware** test;
  and either wire `twoMinuteWarning` into the clock model or delete it.
- **Risk / how to verify**: Adds a scoring drive to the end of most first halves — points per game
  will rise before F-25 pulls them back. Verify with `./run.sh fullgame --home-tier 70 --away-tier 70
  --n 3000`: plays per game and points per team, then hand the retune to F-25.
- **Depends on**: F-02 (same file being edited)
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §4.3.2, PART 3 rows 7, 8, 10, PART 5 items 5 & 13.

### F-41 — Recalibrate the kicking and punting numbers — **DONE** (gameday wave — kicking/punting, plus the punt-floor defect it found)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: FG table `Engine/Simulation/PlaySimulator.swift:2040-2051` (0-30: 95 · 31-40: 85 ·
  41-50: 70 · 51-55: 50 · 56+: 30, ×0.975 block); XP at `:2215`
  (`0.90 + (acc−70)/300`, clamp 0.80–0.99, no block, no weather); punting at `:1976-1978` (the punter
  is fetched **for the description string only** and the `Int.random(in: 35...55)` roll is
  discarded) and `Engine/Simulation/GameSimulator.swift:28`, `:1429`
  (`averagePuntDistance = 40`, flat).
- **What is wrong**: The FG table is **10–20 pp below the modern NFL at every band ≥ 41 yards** (the
  league has made 84–85 % at all distances since 2015; 30–49 yd is above 85 %; 50+ is 58–64 %). The
  XP rate is ~4 pp low at average (real ≈ 94 % since the 2015 33-yard snap). And **punter rating is
  cosmetic with zero punt variance** — every punt is exactly 40 yards of field position, against a
  real net average of ≈41.5 with genuine punter spread.
- **What to do**: Move the FG bands to the modern rates; raise the XP base; use the punter roll that
  is already computed, scaled by the punter's rating, instead of discarding it.
- **Risk / how to verify**: More made field goals raises scoring, and real punt variance changes
  field position on every drive. Verify with `./run.sh fullgame --home-tier 70 --away-tier 70
  --n 3000`: points/team and drives/game. Sequence before F-25's retune.
- **Depends on**: F-02 (same file)
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` PART 3 rows 3, 4, 5, 16, PART 5 items 10 & 12.

### F-42 — Make field-goal range depend on the kicker — **DONE** (gameday wave — range gated on `kickPower`)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should each club's field-goal range vary with its kicker's leg?* The
  report states real range varies **8–12 yards by kicker** but does not specify the mapping.
- **Where**: `Engine/Simulation/PlaySimulator.swift:351` (`fieldGoalRange = yardsToEndzone <= 45`,
  fixed for every club) and the decision chain at `:397-436`; kick **power** is never read anywhere
  in the repo — only `kickAccuracy` is.
- **What is wrong**: Every club in the league attempts field goals from the opponent's 45 inward —
  **up to a 62-yarder — regardless of kicker**. Real 50+ yard attempts run ~130–155 per season
  league-wide (≈0.3 per team-game). The report is explicit that the **kicker-blind range is the
  defect, not the number**.
- **What to do**: Gate the range on the kicker's leg strength. This requires reading a power
  attribute that no simulator file currently reads, so confirm the attribute exists before starting.
- **Risk / how to verify**: 50+ yard attempts per team-game must land near 0.3. Same `fullgame` gate
  as F-41. Interacts with F-17: a `riverboat` HC with a weak-legged kicker should punt more, not
  attempt more.
- **Depends on**: F-41, F-17
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §4.2 item 5, PART 3 row 3, PART 5 item 10.

### F-43 — Sample `scoreDifferential` per play, not per drive — **DONE** (gameday wave — the real instance was overtime, fixed there)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Simulation/GameSimulator.swift:249`.
- **What is wrong**: `scoreDifferential` is sampled **once per drive** and handed to every play in
  it. The report is precise about the classification: *"That is an accuracy bug, not an imperfection
  model — it does not make the AI human, it makes it inconsistent."* Every game-management branch in
  `decidePlayCall` (the mgmt pass bias, the two-minute drill gate, the 4th-down late-game early
  return) reads a score that can be two scores stale.
- **What to do**: Sample it per play.
- **Risk / how to verify**: Late-game play mix will change. `./run.sh fullgame --home-tier 70
  --away-tier 70 --n 3000` for points/team; sequence with F-40, which fixes the gates this value
  feeds.
- **Depends on**: F-40
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §4.2 item 6.

### F-44 — Give play selection a real red zone — **DONE** (gameday wave — red zone at the 20)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the red zone start at the 20 for both play selection and defence?*
- **Where**: defence changes inside the **10** at `Engine/Simulation/DriveSimulator.swift:266-298`
  (`situationalDefensivePackage`, branch 1); pass depth is forced short inside the **10**; and
  `PlaySimulator.decidePlayCall` has **no red-zone branch at all**.
- **What is wrong**: The real red zone starts at the 20 and reshapes both the play mix and the
  defence. Here the threshold is the 10 and the scope covers only the defence and pass depth —
  **threshold and scope are both wrong**.
- **What to do**: Move the threshold to the 20 and add a red-zone branch to `decidePlayCall`.
- **Risk / how to verify**: Directly changes red-zone TD rate and therefore points. `./run.sh
  fullgame` before/after; sequence before F-25. Note `situationalDefensivePackage` is the **single
  shared** defensive call sheet — the live engine enters it at
  `Engine/Match/LiveGameEngine.baseDefensivePackage:1837-1846` — so quick sim and coached game cannot
  drift, and that property must be preserved.
- **Depends on**: F-40
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §1.3, PART 3 row 14.

### F-45 — Let quality and contract status matter to retirement — **DONE** (lifecycle wave — `qualityHazardScale`, age wall untouched)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should good players and unsigned players retire at different rates?* The
  report proposes a quality discount above ~80 OVR and a bump for the unsigned, without specifying
  magnitudes.
- **Where**: `Engine/PlayerDevelopment/PlayerRetirementEngine.swift:110-213`, specifically `:137-144`
  (the `overall` term) and `:196-208`.
- **What is wrong**: The `overall` term contributes **at most +0.20 and only below 60**, so a
  34-year-old **90-OVR quarterback retires at exactly the same 18 % rate as a 34-year-old 55-OVR
  one**. Contract status and snap counts are absent entirely. Compounding it, the OVR, injury and
  durability terms all sit *inside* `if yearsPastPeak >= 0`, so an in-window player is immune to
  them.
- **What to do**: As above. Note the retirement model is otherwise **well-shaped and symmetric** and
  is on the DO NOT TOUCH list for its age-wall structure (+0.18 at 33, +0.25 at 35, +0.30 at 37,
  forced at 41 — in practice 18 % / 43 % / 73 %); change only the quality and contract terms.
- **Risk / how to verify**: `./run.sh career` — career-length distributions and the §8 age pyramid
  must hold; the measured 33+ roster share (today **0.8 %** against a real 7–8 % at 31+, flagged as
  too young) should move up, not down.
- **Depends on**: none
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 12 and §2.3;
  `AI_ROSTER_DECISIONS_ANALYSIS.md` PART 3 (33+ share row).

### F-46 — Make waiver claims actually move players — **DONE** (lifecycle wave — `WaiverWireEngine`, 4 claims per club per window)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Camp/WaiverWireEngine.swift:24-42` (`processWaivers`), the write block at
  `:70-79`, priority at `:33-38`; called only from `Engine/Simulation/WeekAdvancer.swift` (reported
  `:8517-8529`, user camp cuts only); the only consumer is the banner at
  `UI/Career/CareerShellView.swift:1638-1673`.
- **What is wrong**: `processWaivers` computes worst-record-first priority and per-club interest
  correctly and then writes **only** `cut.claimedByTeamID`, `player.cutByTeamID` and `player.cutAt`
  — **never `teamID`, never a contract, never a cap charge.** It runs on user camp cuts only, and
  there is no user-facing claim path at all. **The one structural mechanism that hands talent to bad
  teams is a notification.**
- **What to do**: Make a successful claim move `teamID`, write a contract and charge the cap. Then
  run it on AI cuts too, and add a user claim path.
- **Risk / how to verify**: Real waiver movement changes roster composition league-wide at cutdown.
  Verify with the smoke's churn funnel and roster-size bands; watch that cutdown does not leave clubs
  short.
- **Depends on**: F-11 (a cap charge needs a cap that means something)
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 13, §2.9, §2.10.

### F-47 — Give the season-1 roster something to develop
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *How much potential headroom should the inherited roster carry?* The
  report says raise it for under-25 players at intake but does not name a target; the natural anchor
  is the draft pipeline's equilibrium of **12.02**, which the harness itself flags as a KNOWN GAP.
- **Where**: `Data/Import/LeagueGenerator.swift:914-960` (`veteranPotential`),
  `Data/Import/LeagueTemplateImporter.swift:352`, `tools/league-data/make_templates.py`.
- **What is wrong**: Measured mean potential headroom over current OVR is **2.05** for the generator
  (`./run.sh leaguegen`, assert `8.hea`) and **1.6** on the shipped template, against the draft
  pipeline's **12.02**. The bottom-six teams carry *no more* upside than the top six (1.68 vs 1.63)
  and are *older* (26.8 vs 26.65). **In seasons 1–2 the development engine — the most interesting
  system in the game — has nothing to act on**: at headroom 1.6 the catch-up channel yields ~+0.4
  OVR/player/year for the under-peak half against −1.0 to −1.5/yr for the 1-3-past-peak cohort.
- **What to do**: Raise intake headroom for under-25 players in both the generator and the template
  solver, so the roster the user inherits contains the players the rebuild is supposed to be about.
- **Risk / how to verify**: `./run.sh leaguegen --leagues 200` — the `8.hea` assert is the direct
  gate; the t=0 quality pyramid and the 90+ share (held at 1–2 % by the pyramid gate) must hold.
  Then `./run.sh career` for the knock-on to league-mean drift.
- **Depends on**: F-19 (both edit the generator's intake)
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` recommendation 8, §1.4, §3.5. Ledger `TODO.md:4186`.

### F-48 — Raise first-round bust risk toward the real range
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *How risky should a first-round pick be?* Real references: picks 1-5 bust
  **17 %**, picks 22 and 26 **57 %**, pick 32 **50 %**; R1 "hit" (Pro Bowl) 26.0–52.4 % by pick
  range, 49–73 % become full-time starters.
- **Where**: `Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:252-285` (the round-independent
  5 % breakout / 5 % struggle roll), `:824-851` (the realization factor `R`, mean 0.513, p10 0.214,
  p90 0.942); `Engine/Draft/AIDraftPerception.swift` (draft-day fog); the harness's own admission at
  `tools/balance-harness/driver/CareerScenario.harness.swift:113-131`.
- **What is wrong**: Measured R1 washout is **6.4 %** and R1 hit rate **75.0 %**. The `career`
  harness explicitly acknowledges this runs hot against its own NFL reference of 55–65 % hit and
  20–25 % washout, and **widens its gate to [58, 78] % rather than fixing the number.** A draft that
  is a much safer store of value than real football is a direct contributor to the fast rebuild.
- **What to do**: Land F-22 first (the unreachable boom/bust roll is free variance already written),
  re-measure, and only then decide whether `R`'s distribution needs widening. Re-tighten the harness
  gate rather than widening it further.
- **Risk / how to verify**: `./run.sh career` — R1 hit and washout must move toward the NFL
  reference without collapsing the rookie-entry curve, which is on the DO NOT TOUCH list.
- **Depends on**: F-22
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` §2.7, §4.5, §4.6.

### F-49 — Unify the four trade receipts and fix the `newsLog` append bug — **(1) and (2) DONE 2026-08-22; (3) the receipt unification is STILL OPEN**
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/FreeAgency/HoldoutEngine.swift:277-281` (`announcement.inbox` discarded;
  `career.newsLog.append(...)` at `:280`; `outcome.offeringDeadCap` unused at `:256`);
  the same append bug at `UI/Contracts/ContractNegotiationView.swift:1913`; the newest-first contract
  at `Domain/Models/Career.swift:707` and the truncating setter at `:718`
  (`Array(newValue.prefix(150))`); correct prependers at `UI/Contracts/TradeView.swift:1748`,
  `UI/Draft/DraftDayCoordinator.swift:996`, `WeekAdvancer.swift:956`; the two competing receipts
  `Engine/Media/InboxEngine.swift:1030` (`tradeCompletedMessage`, silent on dead money) vs
  `UI/Contracts/TradeView.swift:1826` (`completedTradeInboxMessage`, quotes it);
  `UI/Draft/DraftDayCoordinator.swift:962-976` and `Engine/Contract/TradeValueEngine.swift:3706`
  (both discard `offeringDeadCap`/`receivingDeadCap`); `Engine/Contract/TradeEngine.swift:76`
  (`TradeCapOutcome.totalDeadCap`, zero call sites).
- **What is wrong**: Three linked defects. (1) `newsLog` is documented and treated everywhere else as
  **newest-first**, and every other producer prepends — but the holdout path **appends**, so on an
  established career already at 150 items the headline for the user's own star being force-traded is
  **encoded away and never rendered**. (2) The user force-trades his own holding-out star and gets
  **no inbox receipt at all** — no asset list, no dead-money line. (3) There are **two receipts for
  the same event** and which one the user gets depends on which screen he executed from: the Trade
  Center quotes *"Dead money retained: $X.XM"*, while the factory version says only *"Roster and cap
  adjustments have been processed"* — so the draft room and the holdout path get the silent one.
- **(1) and (2) RESOLVED 2026-08-22 — and the bug CLASS is closed, not just its two instances.**
  Prepending at the two append sites would have left the trap armed for the next writer, so
  `Career.postNews(_:)` was added as the one way to publish. It prepends and lets the setter
  truncate, so the ordering and the 150-cap are no longer facts a caller has to remember. **All six**
  writers now go through it — the two broken appends (`HoldoutEngine:369`,
  `ContractNegotiationView:1913`) and the four open-coded prepends (`TradeView`,
  `DraftDayCoordinator`, `WeekAdvancer`, `CoachingStaffView`, the last of which this entry did not
  list). `newsLog` carries a note saying why `append` is a silent no-op: newest-first plus
  `prefix(150)` means the item is placed at index 150+ and encoded away in the same statement — it
  fails silently AND only on established saves, the worst combination available.
  **(2)** `announcement.inbox` is now delivered, staged on `WeekAdvancer.lastInboxMessages` (the
  channel a flow running with the shell off screen uses; the shell drains it on the next navigation
  change, i.e. the dialog closing). The user who force-trades his own star finally gets a receipt
  naming what came back.
- **(3) STILL OPEN**: the two competing receipts, and `offeringDeadCap` / `receivingDeadCap` still
  discarded at all four execution sites (`TradeCapOutcome.totalDeadCap` still has zero call sites).
  Which receipt the user gets still depends on which screen he executed from. Untouched here — it is
  a copy-and-plumbing unification, not a bug fix, and worth doing in one pass.
- **Verification owed**: compiles clean; not exercised on a live holdout force-trade.
- **What to do**: Prepend in both append sites; deliver `announcement.inbox`; return and use
  `offeringDeadCap`/`receivingDeadCap` from all four execution paths; fold the dead-money line into
  `InboxEngine.tradeCompletedMessage` so all four disclose identically; delete the duplicate
  `TradeView.completedTradeInboxMessage`; and either use `TradeCapOutcome.totalDeadCap` in the
  unified receipt or delete it (F-67 covers deletion).
- **Risk / how to verify**: Low. Clean build; force-trade a holding-out star and confirm the headline
  renders at the top of the news feed and the inbox receipt names the dead money; execute the same
  trade from the draft room and confirm identical disclosure.
- **Depends on**: none
- **Source**: `AI_TRADE_ANALYSIS.md` §1.5, §1.6 rows C2/C3/C4, §3.2 items 7 & 8, recommendations B5,
  B7, B11.

### F-50 — Load the Trade Center's history card from the ledger — **DONE** (trade wave — history card reads `TradeRecord`)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `UI/Contracts/TradeView.swift:67` (`@State private var tradeHistory`), `:1415`
  (`tradeHistoryCard`), `:1478` (`recordCompletedTrade`), `:1864-1899` (`loadData()`, which never
  reads it back); the unread archive is `TradeRecord` (schema at
  `Domain/Models/League/TradeRecord.swift`, labels at `:191-195`).
- **What is wrong**: The card is titled **"Trade History (2029)"** but is backed by view-instance
  `@State` populated only during this instance's lifetime. **Close the Trade Center and reopen it
  and a season of trading reads "No trades completed yet this season."** — while the real archive
  sits unread three files away. `grep -rn "TradeRecord" dynasty/dynasty/UI/` returns only
  construction sites and a schema list: the ledger's only reader in the entire binary is the
  DEBUG-only `MultiSeasonSmokeTest`, and `TradeRecordKind.label` ("Your proposal" / "Incoming offer"
  / "League deal") is dead copy. `TODO.md:2451` has logged this since R21 and Wave 3 promised it.
- **What to do**: Load `tradeHistory` in `loadData()` from
  `FetchDescriptor<TradeRecord>(predicate: careerID == cid && season == currentSeason)`. The rows
  already carry `sentSummary`, `receivedSummary`, `sentValue`, `receivedValue` and `kind` —
  everything `CompletedTrade` holds. This also gives `TradeRecordKind.label` its first reader.
- **Risk / how to verify**: Low. Clean build; `python3 tools/lint/design_tokens.py` for the view; do
  a trade, leave the screen, come back, confirm the row persists.
- **Depends on**: none
- **Source**: `AI_TRADE_ANALYSIS.md` §1.6 row C1, §3.1 row 15, §3.2 item 4, recommendation B6.
  Ledger `TODO.md:4222` (#220).

### F-51 — Add a Transactions lens over `TradeRecord` — **DONE — `29107d7` — `UI/Contracts/LeagueTransactionsView.swift` exists and the shell mounts it**
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the game have a league-wide Transactions screen?* The report calls
  it "the cheapest high-value item on this list once B6 exists".
- **Where**: new surface; data is `TradeRecord` (already written and complete); the nearest existing
  surface is `UI/News/NewsView.swift:99-100` (the Trades filter) and `:404` (auto-pin).
- **What is wrong**: There is **no Transactions screen anywhere in the app** — `grep -i
  "transactionlog\|TransactionsView\|transactionFeed"` returns zero hits. The news feed's Trades lens
  is the whole league transaction record, and it shows headlines rather than assets and values.
- **What to do**: A table of `TradeRecord` rows with both asset summaries, both point totals and the
  `kind` label, which would give "did I win that trade?" a durable answer.
- **Risk / how to verify**: New UI — `python3 tools/lint/design_tokens.py` must not regress. Clean
  build.
- **Depends on**: F-50
- **Source**: `AI_TRADE_ANALYSIS.md` §1.2, §3.1 row 5, recommendation D6.

### F-52 — Fix the inverted pity floor — **DONE** (trade wave — pity floor un-inverted)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Engine/Contract/TradeValueEngine.swift:2146-2183` (`userOfferHazard`), specifically
  `:2151-2154`; the doc comment at `:2135-2139`; the dice at
  `Engine/Simulation/WeekAdvancer.swift:1674-1701`.
- **What is wrong**: The `week >= 6 && offersSoFar < 2` pity branch returns `rolls = 1` and is checked
  **before** the `week >= 7 ? 2 : 1` line. So a quiet season gets 1.00 + 1.00 = **3.00** expected
  attempts in weeks 6–8, while a season already going well gets 1.52 + 1.70 = **3.89**. **A season
  the phone has not rung in gets 23 % fewer expected attempts than a season that is already going
  well** — the branch written to protect a quiet league year is the branch that suppresses it, doing
  the opposite of what its own comment claims.
- **What to do**: Compute `rolls` first, then apply the pity floor to `chance` only:
  `let rolls = week >= 7 ? 2 : 1; let chance = (week >= 6 && offersSoFar < 2) ? 100 : min(94, 22 + 9*(week-1))`.
- **Risk / how to verify**: Raises offer volume in quiet seasons — verify the smoke's asserted band
  of 3–8 in-season offers still holds (`MultiSeasonSmokeTest.swift:783-786`).
- **Depends on**: F-06 (the pity floor is also the relaunch farm; fix the persistence first)
- **Source**: `AI_TRADE_ANALYSIS.md` §1.3, §3.1 row 6, §3.2 item 10, recommendation B3.

### F-53 — Read the trade-request registry for the user's own players — **DONE** (trade wave — `shoppingTarget` reads the request registry)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should a public trade demand from the user's star change the market —
  more calls, different price?*
- **Where**: `Engine/Contract/TradeValueEngine.swift:2458-2496` (`shoppingTarget`, which picks who the
  AI phones the user about and **never checks the registry**) vs `:2525` (`saleCandidates`, which
  does, for AI sellers only); registry at
  `Engine/Contract/ContractNegotiationEngine.swift:2254-2310`.
- **What is wrong**: When the user's star publicly demands a trade, **nothing in the market changes**:
  no extra calls, no discount, no premium. It is the only registry in the codebase whose meaning is
  unavailable to the player who owns the asset.
- **What to do**: Read `TradeRequestRegistry.hasStandingRequest` in `shoppingTarget` as
  `saleCandidates` already does, raising both the number and the aggressiveness of incoming calls.
- **Risk / how to verify**: Raises offer volume against the asserted 3–8 in-season band. Verify with
  the smoke offer funnel.
- **Depends on**: F-06 (career-scoping the registries)
- **Source**: `AI_TRADE_ANALYSIS.md` §1.4 item 5, §3.2 item 9, recommendation D3.

### F-54 — Allow injured and tagged players to be traded — **DONE** (trade wave — INJURED HALF ONLY; the tag half is still open)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should injured players be tradeable at a discount, and should
  tag-and-trade be allowed?* The report proposes a discount scaled by `injuryWeeksRemaining` instead
  of a flat veto.
- **Where**: `Engine/Contract/TradeValueEngine.swift:1815-1821` (injured, flat veto in
  `validationErrors`) and `:1830-1836` (franchise-tagged, flat veto, honestly documented as an
  interim).
- **What is wrong**: Real deadline trades of injured players are routine, with failed-physical
  clauses, and tag-and-trade is a standard move. The flat rules remove ~7 % of the league from the
  market at any moment for no modelled reason.
- **What to do**: As above.
- **Risk / how to verify**: Raises deal volume; verify against the smoke's in-season band (8–25) and
  the fairness band. Interacts with F-18 (once injuries matter on the field, injured-player value
  must fall for a *modelled* reason).
- **Depends on**: F-18, F-37 (tag-and-trade needs AI tags to exist)
- **Source**: `AI_TRADE_ANALYSIS.md` §2.3, recommendation D4.

### F-55 — Raise `aiSwapChance` once the pick chart is repaired — **DONE** (trade wave — swap rates 0.22/0.15/0.10)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should draft-weekend swaps roughly double?* Proposal: R1 0.15 → 0.22,
  R2–3 0.10 → 0.15, R4+ 0.06 → 0.10, giving `32×0.22 + 64×0.15 + 138×0.10 ≈ 30` rolls ≈ 20 swaps —
  still under the real 43 but inside the §5 band.
- **Where**: `Engine/Draft/DraftDayTradeEngine.swift:712-718` (`aiSwapChance`), comment at `:706-710`.
- **What is wrong**: Draft weekend produces **12–14 swaps** (`[dev-claim]`, derived from 19.5 rolls at
  ~⅔ conversion) against a real **43 trades / 142 picks moved / 5.5 first-round trades** — roughly a
  third of reality, and **0 whenever the draft is not played in the war room**. A repaired Day-3
  chart (F-09) is what makes small swaps constructible at all.
- **What to do**: As above. **Verify with F-05's assert, not by eye** — the report is explicit.
- **Risk / how to verify**: `draftSwaps` band from F-05 (§5 target 12–35, ≥3 in Rd 1).
- **Depends on**: F-09, F-05
- **Source**: `AI_TRADE_ANALYSIS.md` §1.5, §2.3, §3.1 row 4, §3.2 item 2, recommendation D5.

### F-56 — Surface or neutralise the user's hidden GM persona — **DONE — `960f3c7` / merged `aee4404`**
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Surface the user's franchise archetype in the UI, or exclude his club
  from persona assignment and price his side neutrally?* The report offers both and prefers either
  to the status quo.
- **Where**: `Engine/Contract/TradeValueEngine.swift:391-421` (`GMPersona.forTeam(id:)`, drawn from
  `Team.id` bytes), used for the user at `:2226-2229` (`userView = marketView(team: userTeam, …)`)
  and consumed at `:2299-2301` (`buildBuyOffer`'s ask = `seller.outgoingPlayerValue(target) ×
  seller.persona.askingPremium × seller.noise`, where *seller* is the **user**).
- **What is wrong**: The user's own franchise carries a hidden, unchosen GM persona that sets what
  the league pays him: his `askingPremium` (1.05…1.25, a **19 % spread**) sets his own sale price and
  his `pickLean` (0.87…1.14, a **31 % spread**) sets what he receives. **None of this is surfaced
  anywhere in the UI.** Two saves started from the same franchise-selection screen get materially
  different trade economies for reasons the player can never discover. The report's judgement: *"the
  kind of thing this repo has been deleting all month."*
- **What to do**: Per the user's decision.
- **Risk / how to verify**: Neutralising changes every user trade price; verify with the smoke trade
  funnel and F-07's acceptance target.
- **Depends on**: F-07
- **Source**: `AI_TRADE_ANALYSIS.md` §1.4 item 4, recommendation D9.

### F-57 — Report roster holes after an executed trade — **DONE** (trade wave — `needProfile` before/after, 0.30 severity)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the post-trade receipt name positions the deal stripped bare?*
  Proposal: run `needProfile` before and after, and name any position that crossed 0.30 severity.
- **Where**: `Engine/Contract/TradeValueEngine.swift:1927` (`capDeltas`) / the unified receipt from
  F-49; `needProfile` at `:746`; the existing refusal-only guard at `:1857-1878`
  (`validationErrors` refuses a package that strips a position bare); the only adjacent surface is
  `UI/Roster/PlayerDetailView.swift:1772` (a pre-trade *preview*, not a receipt).
- **What is wrong**: **No message, tile, badge or news item ever tells the user a trade opened a
  depth hole.** The validation layer refuses the extreme case and says nothing about going from three
  corners to two.
- **What to do**: As above — it turns *"cap adjustments have been processed"* into a real consequence
  line.
- **Risk / how to verify**: Low; clean build and a manual trade that thins a position group.
- **Depends on**: F-49
- **Source**: `AI_TRADE_ANALYSIS.md` §1.6 ("Roster holes: nothing"), §3.1 row 14, recommendation D8.

### F-58 — Add shop-your-own-player and a trade block — **DONE — `401f18b`**
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the user be able to shop a player from his detail screen and
  maintain a trade block?* Wave 3 specified both and neither shipped.
- **Where**: `UI/Roster/RosterView.swift` (`grep -i trade` returns one unrelated comment),
  `UI/Roster/PlayerDetailView.swift:1893-1900` (the own-roster action bar; "Trade For" exists on
  *rival* players at `:1920`); prior spec `docs/TRADE_OVERHAUL_PLAN.md:282-283`.
- **What is wrong**: There is no way to shop your *own* player from his detail screen, no trade block,
  and no trade affordance in `RosterView` at all. The Trade Center's partner-first builder is a poor
  way to answer "who wants my backup tight end?"
- **What to do**: Add both entry points. Note the rest of the entry-point surface is in reasonable
  shape (nav bookmark, shell route, deadline-week dashboard tile, three `TaskGenerator` tasks, "Trade
  For" on rivals) — this is a gap, not a rewrite.
- **Risk / how to verify**: New UI; `python3 tools/lint/design_tokens.py` must not regress. Watch
  that it does not make F-08's cap easier to hit accidentally.
- **Depends on**: F-08, F-53
- **Source**: `AI_TRADE_ANALYSIS.md` §1.6 ("Entry points"), recommendation D7.

### F-59 — Make losing cost the user players — **DONE** (lifecycle wave — holdout frustration + `.losingCulture` reaches a stranger's negotiation)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should a losing record produce holdouts, trade demands and free-agent
  refusals?* Two separate mechanisms are implicated and the reports do not specify magnitudes for
  either.
- **Where**: `Engine/FreeAgency/HoldoutEngine.swift:57-84` (`detectStarHoldoutCandidates`, triggers on
  *contract* state only — expiring, or `salary < 0.85 × market` with `yearsPro >= 3`), called only
  for the user's roster at `UI/Career/CareerShellView.swift:1277-1338`, resolving within four weeks
  (`WeekAdvancer.swift:2654`, 50 % cave at week 3, guaranteed at week 4);
  `Engine/Simulation/LockerRoomEngine.swift:138`, `:270-336` (morale damped to ±3/week plus one point
  of reversion to a 70 baseline — the file states a 4-13 team bleeds ~−10 over a whole season);
  and the FA side, `Domain/Models/Contract/NegotiationThread.swift:214-218` (`.losingCulture`) gated
  at `ContractNegotiationEngine.swift:679-681`.
- **What is wrong**: **There is no wins term, no morale term and no losing-culture term anywhere in
  the holdout file.** A star on a 2-15 team applies exactly the same pressure as the same star on a
  15-2 team, and the only way he leaves is if the user ships him. It is also **user-only** — no AI
  team ever has a holdout — and self-resolving in four weeks. On the free-agency side `.losingCulture`
  gates extensions of your own players only, so there is **no "won't sign with a loser" gate at all**
  in the market where it would matter most.
- **What to do**: Add a record/morale term to holdout detection, and let `.losingCulture` reach the
  `.freeAgent` negotiation path. Coordinate with F-14, which is the same gap seen from the pricing
  side.
- **Risk / how to verify**: This is a direct brake on the fast rebuild; verify against
  `REBUILD_VIABILITY_ANALYSIS.md` §3.2's optimal-play table and F-04's dispersion metrics. Do not
  make it punitive enough to move the average-play line (§3.3), which is correct today.
- **Depends on**: F-14
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` §2.6, §1.1, §2.10.

### F-60 — Let the AI adapt across games and seasons
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should there be an opponent scouting report that survives a game?* This is
  the vaguest recommendation in the four reports — it names the gap precisely and proposes no
  mechanism.
- **Where**: `Engine/Match/AdaptiveOpponentAI.swift:523-524` and `:599` (`RunKeyState` and
  `PlayMemory` documented as having *"no `Codable` conformance, never persisted — the state lives for
  exactly one game and is rebuilt from scratch each time"*);
  `Engine/Match/CoordinatorPersona.swift:31-35` (`stablePersonaPick` hashes the coach's UUID).
- **What is wrong**: **The AI never adapts across games or across a season.** There is no opponent
  scouting report, no film study, no "they beat us with the same thing in week 4". And personas are
  constant for the life of a coach: the same DC is Aggressive every week of every season against
  every opponent.
- **What to do**: Undefined by the reports. Any design here must respect the fairness caps that make
  `AdaptiveOpponentAI` work (see DO NOT TOUCH) and rule B — if the AI remembers the user's tendencies
  across weeks, the user needs a symmetric channel.
- **Risk / how to verify**: `./run.sh spam` and `./run.sh stacking` — the balanced-control invariant
  and the worst-case floors are the rails that must survive any cross-game memory.
- **Depends on**: F-38
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §1.4, PART 5 item 14.

### F-61 — Make guarantees and contract term AI negotiating levers — **DONE — merged `1004e2b`**
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the AI negotiate on guaranteed money and length?* No magnitudes are
  specified in the reports.
- **Where**: `Engine/Contract/FreeAgencyEngine.swift:2606-2609` (`agreedYears = min(desiredYears,
  ceiling)`), `contractYearsCeiling(age:)` at `:1382`;
  `Engine/Contract/ContractEngine.swift:625-643` (`escalatingBaseSalaries` /
  `frontLoadedBaseSalaries`, which shape a schedule that no AI decision reads).
- **What is wrong**: **Guaranteed money does not move** — `Contract.guaranteedMoney` exists and the
  schedule shapers exist, but no AI decision anywhere reads or trades on guarantees, while in the real
  second-contract market guarantee structure is often the whole negotiation. And **term is a club
  veto, not a lever**: the AI never buys a year to save APY and never offers a shorter prove-it deal
  to lower risk.
- **What to do**: Undefined beyond the direction above.
- **Risk / how to verify**: Changes contract shapes league-wide; verify with the smoke `capRoom` and
  payroll bands, which F-11 will already have moved.
- **Depends on**: F-11
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §2.6, §4.2 P7, PART 5 item 19.

### F-62 — Retune draft-board noise: the top-4 draw and the consensus spread — **DONE** (draft wave — top-4 draw deleted, consensus retuned)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the fog σ or the consensus-anchor decay come down?* The report
  identifies the two contributing constants and does not pick between them.
- **Where**: `Engine/Draft/DraftEngine.swift:292-299` (the top-4 weighted-random draw,
  `[0.65, 0.20, 0.10, 0.05]`); `Engine/Draft/AIDraftPerception.swift:60-67` (σ by archetype) ×
  `Engine/Draft/DraftEngine.swift:283` (the consensus anchor `12.0 × exp(−consensusSlot / 64)`).
- **What is wrong**: Two findings that pull together. (1) **The top-4 draw is cosmetic** — over a
  350-man board whose top 4 sit within ~1–2 points, a 35 % off-argmax draw moves a pick by a few true-
  board slots. It is noise, not a decision; the real reaching comes from the fog (13.25 R1 reaches
  with fog vs 8.33 without). (2) **Round-1 board noise runs hot**: mean `|pick − publicRank|` of
  **26.0** slots in round 1, with **40 % of R1–3 picks taken more than 20 slots ahead of the media**,
  against a real consensus that is typically within ~10–15 slots in round 1.
- **What to do**: Replace the cosmetic draw with structured error (F-26's `GMTaste` is the intended
  replacement) and bring the R1 spread down. Sensitivity constant to work from: at slot 16 the
  consensus term's derivative is −0.146 points per slot, so **1 OVR point of misread ≈ 6.8 slots of
  round-1 board movement**.
- **Risk / how to verify**: `./run.sh perception --drafts 12` — R1 mean `|pick − publicRank|` must
  fall from 26.0 toward the mid-to-high teens **without** collapsing the steal and bust rates that
  make the draft interesting (today 65.92 steals/draft, true BPA slides past pick 5 in 25 % of
  drafts). This item and F-29 pull in opposite directions — tune together.
- **Depends on**: F-26, F-29
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.2, §1.5, §4.1 item 4, PART 5 items 18 & 20;
  `REBUILD_VIABILITY_ANALYSIS.md` §1.3 (same mechanism, reported as "the average AI first-round pick
  is the 27.8th-best player on the true board, vs 20.0 with fog off").

### F-63 — Let AI clubs elevate their own practice-squad players — **DONE** (lifecycle wave — own-squad elevation exists at all)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should AI clubs promote from their own practice squad?* Small, but it is a
  one-directional asymmetry.
- **Where**: `Engine/Contract/PracticeSquadEngine.swift` — `signToActiveRoster`, whose only callers
  are the two poach paths and `UI/Roster/PracticeSquadView.swift:305`; the weekly pass
  (`runWeeklyPass`, `:876`) is called for all 32 clubs from `WeekAdvancer.swift:2232`.
- **What is wrong**: AI clubs never elevate *their own* squad players — they can only poach. The other
  asymmetry in this system runs the user's way: the user's squad is protected by a one-week warning
  and a `userPoachInterestChance = 0.18` gate (`:184`, `:918-937`) while AI-vs-AI poaches land
  immediately.
- **What to do**: Add an own-squad elevation path to the weekly pass. Note the practice-squad system
  is otherwise **symmetric, injury-aware and working** and is on the DO NOT TOUCH list — this is a
  gap-fill, not a rework.
- **Risk / how to verify**: Roster-size and churn bands in the smoke.
- **Depends on**: F-18 (elevation is most meaningful once injuries remove players)
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §2.5, §2.6.

### F-64 — Decrement coach contract years so firing has a cost — **DONE** (lifecycle wave — decrement AND renewal)
- **Class**: bug-fix
- **Priority**: P2
- **Where**: `Coach.contractYearsRemaining` — never decremented anywhere in the engine;
  `UI/Staff/CoachDetailView.swift:1011-1014` (firing is free);
  `Engine/Budget/BudgetEngine.swift:15-48` (`annualBudget`, floor $12M, success multiplier spanning
  only 0.90–1.15); `Engine/Simulation/CoachingEngine.swift:669-705` (the only real gate on a losing
  club: a 40 % decline chance on premium candidates when `reputation < 40 && wins < 5`, plus a 10–15 %
  salary premium).
- **What is wrong**: `Coach.contractYearsRemaining` is a decorative field, so **firing a coach is
  free**. Combined with a coaching budget whose role maxima excluding the head-coach seat total
  **$37.3M** against a ~$35M average pot — and eight elite position coaches, the heaviest development
  weight in the game, costing **~$8.8M total** — a bad team can buy a near-elite staff on day one.
  The report calls coaching *"the single most underpriced lever in the game"*: ~+0.1 team overall per
  season via development, but **+2 to +3 points of scoring margin per game immediately**, worth
  roughly +1.5 to +2.5 wins in season 1, for money that does not touch the salary cap.
- **What to do**: Decrement the field and charge the remaining years on a firing.
- **Risk / how to verify**: Makes staff churn cost something; verify with the smoke's HC-change count
  and F-04's dispersion metrics. Do **not** touch `CoachingModifiers` itself — its symmetric, centred
  coefficients are on the DO NOT TOUCH list.
- **Depends on**: none
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` §1.5, §1.8.

### F-65 — Price and preview the cost of a scheme change — **DONE — `70893eb` — `UI/Staff/SchemeSelectionView.swift` carries the priced, confirmed switch**
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *Should the scheme-selection screen show the install cost before the user
  commits?*
- **Where**: `UI/Staff/SchemeSelectionView.swift:399-409` (switching is free and instant with no cost
  preview); the cost itself is real and correctly shaped —
  `Engine/PlayerDevelopment/VersatilityDevelopmentEngine.swift:229-237` (`installBaseline ≤ 50`,
  below the `famBustPivot` of 55), `Engine/Simulation/CoachingEngine.swift:487-509`
  (`rosterSchemeFit`), `Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:1556-1576`, `:1622`.
- **What is wrong**: Switching schemes costs ~**−2 to −3 points/game for one season**, takes ~1.6
  seasons to reach the scheme-fit pivot and **~3.7 seasons** to reach the completion pivot at 70 —
  and the UI presents it as a free, instant choice with no preview. The tax itself is one of the few
  counter-forces that works as designed and is on the DO NOT TOUCH list; only the *disclosure* is
  missing.
- **What to do**: Show the install curve and the expected one-season cost at the point of choice.
- **Risk / how to verify**: UI only — `python3 tools/lint/design_tokens.py`, clean build. Verify the
  quoted numbers against `./run.sh familiarity` **after** F-21, which changes the realised size of
  the effect.
- **Depends on**: F-21
- **Source**: `REBUILD_VIABILITY_ANALYSIS.md` §1.6.

### F-66 — Fill the clock-model gaps — **DONE** (gameday wave — endgame clock via `ClockContext`)
- **Class**: design-change
- **Priority**: P2
- **Needs user decision**: *How much clock fidelity is wanted?* Four named gaps, no proposed design.
- **Where**: `Engine/Simulation/DriveSimulator.swift:463-490` (flat draws: run/completion 25–40 s,
  incompletion 4–8 s, kneel 40 s, spike 3 s).
- **What is wrong**: The clock model is "broadly right in the mean" but has **no out-of-bounds, no
  40-second play clock, no first-down stoppage and no hurry-up tempo**. Every endgame item in this
  band (F-39, F-40, F-43) is limited by this.
- **What to do**: Undefined by the reports beyond the four named gaps.
- **Risk / how to verify**: `./run.sh fullgame` — plays per game is the primary gate and is currently
  `[OK]`; do not push it out of band.
- **Depends on**: F-39, F-40
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` PART 3 row 15.

---

# P3 — dead code, docs, and copy

### F-67 — Delete the dead draft/trade code, including an armed fog breach — **DONE** (draft wave — dead draft code deleted, fog breach disarmed)
- **Class**: bug-fix
- **Priority**: P3
- **Where**: `Engine/Draft/DraftEventEngine.swift` — whole file, 229 lines, zero callers, header at
  `:29-36` says "⚠️ NOT WIRED" (**but see F-27: its run detector at `:170-180` is the plumbing that
  item wants — harvest before deleting**); `Engine/Draft/DraftEngine.swift:1114-1213`
  (`generateStaffRecommendations`, 100 lines, zero callers), `:1233-1301` (`generateFanReaction`, 69
  lines, zero callers), `:1305-1314` (`gradeForPositionGroup`, called only by the two above);
  `UI/Draft/Components/TradeOfferBanner.swift` (zero call sites; its own header at `:13-24` asks for
  this; the surface that shipped is `UI/Draft/Components/DraftControlBar.swift:234-252`);
  `Engine/Contract/TradeEngine.swift:76` (`TradeCapOutcome.totalDeadCap`, zero call sites — delete or
  use it in F-49's unified receipt).
- **What is wrong**: ~640 lines of unreferenced code, and one piece of it is **an armed fog breach**:
  `generateStaffRecommendations`' "Chief Scout's sleeper pick" sorts the board by
  `prospect.truePotential` (`DraftEngine.swift:1195`) and hands the user the name. If it were ever
  wired, the user's own staff would be pointing at hidden truth.
- **What to do**: Harvest `DraftEventEngine`'s run detector for F-27 first, then delete all of the
  above. Leave the **cap** dead code alone — `CapManagementEngine`'s ~120 unreferenced lines are to
  be *wired* by F-11, not deleted.
- **Risk / how to verify**: Clean build is the whole test.
- **Depends on**: F-27 (harvest first), F-49 (decide `totalDeadCap`'s fate)
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.1, §1.3, PART 5 item 17;
  `AI_TRADE_ANALYSIS.md` §1.1, recommendations B10 and B11.

### F-68 — Correct the stale and false doc comments — **DONE 2026-08-22 (four of the six; two of this entry's claims were themselves wrong)**
- **Class**: bug-fix
- **Priority**: P3
- **Where**: `UI/Draft/Components/ProspectFog.swift:24-26`;
  `Engine/Contract/TradeValueEngine.swift:58-60`, `:50-55`, `:1490-1494`;
  `Engine/Media/InboxEngine.swift:946`; `Engine/Simulation/MultiSeasonSmokeTest.swift:444-445`.
- **What is wrong**: Six load-bearing comments that describe a codebase that no longer exists. The
  worst is `ProspectFog.swift:24-26`: *"The AI keeps drafting on the true values internally"* — this
  is **false** as of the current tree and is the single most misleading comment in the draft path;
  a reader auditing fairness would conclude the opposite of the truth. Then:
  `TradeValueEngine:58-60` says the window runs "up to and including the **Week 8** deadline" while
  the constant three lines above reads `deadlineWeek = 9`; `:50-55` carries a "PAIRED CHANGE"
  warning about a hardcoded `if week == 8` in `WeekAdvancer` that no longer exists
  (`WeekAdvancer.swift:23` reads the constant); `:1490-1494` justifies `deadlinePressure` with
  *"`Career.currentWeek` only ever holds 1…9"* when it holds 1…18 (the function is still correct, its
  stated justification is false); `InboxEngine.swift:946` still calls `tradeDeadlineMessages`
  *"Dead code until the phase became real"* when it is live via `WeekAdvancer.swift:2271-2281`; and
  `MultiSeasonSmokeTest.swift:444-445` names a caller for `runAIDraft` that does not exist.
- **What to do**: Correct all six. `ProspectFog`'s is the one that matters — it must say that
  `AIDraftPerception` is live and wired (`DraftEngine.swift:236-244`), measured at a league mean
  |error| of 3.96 OVR.
- **Risk / how to verify**: Clean build.
- **RESOLVED 2026-08-22, after checking all six against the tree.** Four were stale and are
  corrected; **two of this entry's own claims did not hold**, which is the same defect the entry is
  about:
  - ✅ `TradeValueEngine` `deadlineWeek`'s "PAIRED CHANGE" warning — stale. `WeekAdvancer.swift:23`
    reads `static let tradeDeadlineWeek = TradeValueEngine.deadlineWeek`; the hardcoded `8` is gone.
  - ✅ `isTradeWindowOpen`'s "up to and including the **Week 8** deadline" — stale, and it now names
    the constant instead of a literal so it cannot drift again.
  - ✅ `deadlinePressure`'s justification — false. It claimed `Career.currentWeek` "only ever holds
    1…9 during the regular season"; the season is 18 weeks and the counter runs the whole way.
    **The function is still correct and for a reason worth stating**: I checked whether the false
    justification hid a live bug (an offseason negotiation picking up deadline pressure) and it does
    not — the offseason parks the counter at 19…22 through the bracket and resets to 1 at the
    rollover, never inside 6…9. Weeks 10…18 return zero on the `week <= deadlineWeek` guard,
    correctly. The comment now says that.
  - ✅ `InboxEngine.tradeDeadlineMessages`'s "dead code until the phase became real" — stale.
    `WeekAdvancer:2410` sets `.tradeDeadline` and `generatePhaseMessages` routes it here.
  - ❌ **`ProspectFog.swift` was already fixed.** The comment does not say "the AI keeps drafting on
    the true values internally"; it carries an explicit "## What the AI sees, corrected" section
    that quotes the old sentence and says both halves stopped being true. Nothing to do.
  - ❌ **`MultiSeasonSmokeTest.runAIDraft`'s comment is accurate.** It says the method is internal
    "so the DEBUG dashboard skip can reuse it", and that caller EXISTS —
    `CareerDashboardView.skipToFreeAgency` calls `MultiSeasonSmokeTest.runAIDraft(career:context:)`.
    **This also voids the entry's stated dependency on F-05.**
- **Depends on**: ~~F-05~~ — void, see above; `runAIDraft` already has the caller its comment names
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.3, PART 5 item 7;
  `AI_TRADE_ANALYSIS.md` §1.6 rows C6–C9, §3.2 item 11, recommendation B9. Ledger `TODO.md:4229`.

### F-69 — Fix UI copy that promises engine behaviour that does not exist — **DONE — `373bed9` + `f5156ec`**
- **Class**: bug-fix
- **Priority**: P3
- **Where**: `UI/Match/GameSummaryView.swift:386` (prints
  `"\(aggressionLabel(r.plan.offensiveAggression)) offense"` in the post-game "planned vs actual"
  panel) against `Domain/Models/Team/GamePlan.swift:10` (`offensiveAggression` has **zero read sites
  outside `GamePlan.styleSummary`**); `UI/Career/NewCareerView.swift:468-469` (advertises "Cap
  rollover" with a checkmark) against `Engine/Contract/CapManagementEngine.swift:19-26`
  (`calculateCapRollover`, zero call sites); `UI/Contracts/TradeView.swift:636` (*"AI offers arrive
  weekly during the regular season"* — they also arrive in five offseason windows, per
  `WeekAdvancer.swift:5750`); and the two half-dead sliders
  `blitzFrequency` / `defensiveAggression`, which reach only the coached path
  (`Engine/Match/LiveGameEngine.swift:1821-1830`) and never `GameSimulator`.
- **What is wrong**: Four screens describe systems with no engine backing. A user who quick-sims his
  own game and moves the Defensive Style or Blitz slider changes **nothing at all**, and
  `offensiveAggression` changes nothing in any path, for anyone — while the post-game panel narrates
  its effect. The mode picker advertises a cap feature with no call sites.
- **What to do**: Either delete the copy or wire the behaviour. For `offensiveAggression` the report
  is explicit that this is a bug of *UI copy vs engine behaviour*, not a missing feature request. The
  cap-rollover checkmark is the minimum item on F-11's list — remove it even if F-11 is deferred. For
  `blitzFrequency` / `defensiveAggression`, either thread them into `GameSimulator` or say in the UI
  that they apply to coached games only.
- **Risk / how to verify**: `python3 tools/lint/design_tokens.py`, clean build.
- **Depends on**: F-11 (for the rollover decision), F-17 (which may give the sliders an AI-side twin)
- **Source**: `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §2.1, §2.6, PART 5 item 11;
  `REBUILD_VIABILITY_ANALYSIS.md` §1.1 and recommendation 7 ("at minimum, remove the checkmark");
  `AI_TRADE_ANALYSIS.md` §1.6 row C11.

### F-70 — Repair trade news fidelity — **(1) and (2) DONE 2026-08-22; (3) STILL OPEN**
- **Class**: bug-fix
- **Priority**: P3
- **Where**: `Engine/Media/NewsGenerator.swift:700-720` (`generateTradeRumor`), fired from
  `generateWeeklyNews` on `Bool.random() || phase == .tradeDeadline` (`:81-83`);
  `Engine/Media/NewsGenerator.swift:1041` (trade stories always set `relatedPlayerID: nil`);
  `Engine/Draft/DraftStoryRecorder.swift:32` (`events(forYear:)`, zero callers) against the writer
  `UI/Draft/DraftDayCoordinator.swift:1057` (`recordTradeEvent`) and the in-memory ticker at `:1077`
  (capped at 30, dies with the war room); `UI/Draft/DraftRecapView.swift` and
  `UI/Draft/RoundRecapSheet.swift` contain no trade content.
- **What is wrong**: Three fidelity defects. (1) `generateTradeRumor` **invents an interested suitor
  with no connection to the market pass** — the feed can print "PHI have interest in Vale" in the
  same advance in which the real market ships Vale to Denver. (2) Trade stories set
  `relatedPlayerID: nil`, so **no trade story ever renders a player portrait** while every other
  person-story does. (3) Every `.tradeOffered` / `.tradeDeclined` / `.tradeAccepted` /
  `.tradeExpired` `DraftEvent` row is a **write-only DB row**: after the draft closes the only
  surviving trace of draft-night trades is the `NewsItem`.
- **What to do**: Seed the rumour generator from the actual market pass (or gate it off when a real
  deal for that player exists); set `relatedPlayerID`; and give `DraftStoryRecorder.events(forYear:)`
  a reader — the natural home is `DraftRecapView` / `RoundRecapSheet`, which have no trade content
  today.
- **Risk / how to verify**: `python3 tools/lint/design_tokens.py`, clean build; read the news feed
  across a deadline week and confirm no rumour contradicts an executed deal.
- **PARTIALLY RESOLVED 2026-08-22.**
  - ✅ **(2) Trade stories carry a face.** `TradeRecord.headlinePlayerID` (optional, inline default →
    free migration per `SWIFTDATA_MIGRATION_PLAN.md` §4) names the best man in the deal, set by
    `TradeRecord.record(...)`; the news row reads it. This is exactly the handoff the old
    `relatedPlayerID: nil` comment asked for. Kept optional and separate from the summaries: it
    points at a row that may have retired, and a pick-only swap has no face.
  - ✅ **(1) The rumour can no longer contradict the market.** Root cause is ORDERING, which this
    entry did not name: `generateWeeklyNews` runs at `WeekAdvancer:1688` and the league market window
    at `:2428`, both inside `advanceRegularSeasonWeek` — the rumour was written before the deals
    existed. Rumour generation moved out of `generateWeeklyNews` into
    `NewsGenerator.weeklyTradeRumor`, called after the market pass with the executed men excluded.
    **Honest limit**: the exclusion set is each deal's headline player, not everyone who changed
    hands, so a rumour can still name a secondary piece in a completed package. It removes the
    reported case and does not claim to remove every one.
    Checked before moving it: appending after `OwnerSatisfactionEngine.updateSatisfaction` has read
    `lastNewsItems` is a **no-op** for that pass — it counts `.negative` / `.positive` rows and a
    rumour is `.neutral`.
  - ❌ **(3) `DraftStoryRecorder.events(forYear:)` still has no reader.** Draft-night trade events
    remain write-only DB rows. Needs a UI surface (`DraftRecapView` / `RoundRecapSheet`) and overlaps
    F-49's inbox/receipt work — left open deliberately rather than half-built.
- **Verification owed**: compiles clean and the design-token lint passes; the feed has NOT been read
  across a live deadline week. This season run has not reached week 9 yet.
- **Depends on**: F-51 (a Transactions lens is the other natural reader)
- **Source**: `AI_TRADE_ANALYSIS.md` §1.1, §1.5, §1.6 rows C5 and C10.

### F-71 — Fold `FantasyDraftEngine.aiPickIndex` into the one draft brain — **DONE** (draft wave — kept separate, deliberately, with a comment on each)
- **Class**: design-change
- **Priority**: P3
- **Needs user decision**: *Should the fantasy-draft league-creation mode share `aiMakePick`, or stay
  a deliberately separate scorer?*
- **Where**: `Engine/Draft/FantasyDraftEngine.swift:9`, `:115` (`aiPickIndex`) vs
  `Engine/Draft/DraftEngine.swift:161` (`aiMakePick`).
- **What is wrong**: There is exactly one AI pick function for the real draft, and
  `FantasyDraftEngine.aiPickIndex` is a **separate scorer** for the fantasy-draft league-creation
  mode, explicitly "modeled on" `aiMakePick` rather than sharing it — *a second brain that can
  drift*. Every fix in F-26 through F-31 will apply to one and not the other.
- **What to do**: Per the user's decision. If they stay separate, add a comment on each naming the
  other, so the next audit knows the divergence is intentional.
- **Risk / how to verify**: Clean build; run a fantasy-draft league creation end to end.
- **Depends on**: F-26, F-27, F-28, F-29, F-30, F-31 (fold *after* the shared brain settles)
- **Source**: `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.1.

---

# Where the reports genuinely conflict

Three places. In each, both numbers are given rather than one being picked.

1. **The size of the trade arbitrage.** `AI_TRADE_ANALYSIS.md` §1.4 computes the persona × stance
   spread on an identical asset as **1.5×** (`pickLean` 0.87…1.14 × stance `pickMultiplier`
   0.94…1.08 = 0.82…1.23) and the round-trip profit as **+60–80 % of chart value per cycle**.
   `REBUILD_VIABILITY_ANALYSIS.md` §1.2 computes the same spread as **1.97×**
   (`0.87 × 0.94 × 0.88 = 0.720` vs `1.14 × 1.08 × 1.15 = 1.416`) and the round trip as **414 → 945
   chart points, +531 per flip** (≈ +128 %). The difference is that the rebuild report folds
   `futurePickMultiplier` into the product and the trade report does not. **Both are arithmetically
   correct for the quantity each defines.** F-07's acceptance target uses the conservative figure;
   the aggressive figure is the failure case the fix must make impossible.

2. **Home-field advantage — two different paths, two different verdicts.**
   `AI_GAMEDAY_DECISIONS_ANALYSIS.md` §1.1 measures the AI-vs-AI dice path at **58.8 %** home wins
   (55.2 % before the tie-break bug) against a real 53.2 % and calls it a defect.
   `REBUILD_VIABILITY_ANALYSIS.md` §4.1 measures the **full simulator** path at **52.6–54.2 %** at
   talent parity against the same real .532 and marks it ✅. There is no contradiction — they are
   measuring two different code paths — but the practical warning matters: **F-01 must fix the dice
   path's home advantage without touching the simulator's, which is already correct.**

3. **How to read the draft fog.** `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.5 reports the fog's effect as
   R1 mean `|pick − publicRank|` of **26.0** (fog on) vs 7.88 mean `|rank − pick|` on the true board
   (fog off), and calls the round-1 spread "too noisy". `REBUILD_VIABILITY_ANALYSIS.md` §1.3 reports
   the same scenario as "the average AI first-round pick is the **27.8th-best** player on the true
   board of a 32-pick round, vs 20.0 with fog off", and treats the fog as a strength that makes the
   user's scouting edge decisive. These are the same measurement described from opposite ends. F-62
   is written to reduce the noise *without* removing the steals and busts the second reading values;
   if the two goals turn out to be incompatible, the roster report's framing (structured bias beats
   symmetric noise) is the tie-breaker.

---

# DO NOT TOUCH

Things all four reports explicitly found correct and well-built. A later pass should not "fix" these.

**Simulation and gameday**
- **`AdaptiveOpponentAI`'s three-layer design and its fairness caps.** The best-engineered part of
  the gameday audit. Measured: repeating one call collapses it to **43 % of its first-call value** by
  the fourth repetition; a *mixed* caller is untouched (`Δypc +0.01`, `ΔpassEV +0.11`). The caps
  (`passTotalMalusCap 0.24`, `runGrandBiteCap 1.80`, `exactPassCap 0.20`, `exactRunYardCap 2.00`) are
  the fairness rails and they are real.
- **The two-point chart** (`GameSimulator.shouldGoForTwo`) — base conversion 0.47 at equal talent is
  close to real, and the chart itself is rated **good**. (F-17's `twoPointBias` shifts a row; it must
  not rewrite the chart.)
- **The prevent-shell rule** (`DriveSimulator.swift:278-283`) — matches real practice.
- **`CoachingModifiers`' symmetric, centred coefficients**, correctly plumbed into both the quick sim
  and the live game. A real 7 pp completion spread between the best and worst staff.
- **The shared defensive call sheet.** `DriveSimulator.situationalDefensivePackage` is entered by both
  the live engine and the quick sim, so they cannot drift. Preserve that property.
- **The balance harness itself**, whose anti-drift construction (mechanical extract regeneration,
  39 constant lines diffed against the repo, build failure on any difference) is the reason the
  numbers in these reports can be trusted.

**Rosters, draft and development**
- **`AIDraftPerception`.** Real, wired, measured, deterministic: league mean |error| **3.96 OVR**,
  fat tail firing at **6.99 %** against a 7 % target, repeat reads identical. The best imperfection
  asset in the codebase and the pattern F-23 and F-26 are meant to extend, not replace.
- **The information asymmetry's *shape*.** The user is not structurally disadvantaged: on a man he
  has actually scouted his read is *sharper* than any AI club's (mean |err| 0.67–3.5 vs the league's
  3.96). The asymmetry is **coverage, not accuracy** — 25 paid evaluations against a 350-man class —
  and that is the right shape.
- **The kicker specialist discount** (−8.0 on top of −4.0, so K/P sit at −12.0). No kicker has gone
  in round 1 since 2000.
- **The rookie-entry curve.** A top-5 pick who is below average as a rookie and peaks around year 4
  is exactly right, and it is a braver design choice than most GM sims make. It also makes
  tanking-for-one-pick unattractive.
- **`resignAIOwnCore`** — the strongest piece of the FA brain. Saturated as designed: 70 retentions
  per league year = 2.3 per club against a ceiling of 3, at mean OVR 83.7, age 26.2.
- **`ContractEngine.estimateMarketValue`** and its documented position-multiplier ratio audit, which
  holds up against the 2025 top-of-market numbers (EDGE is the one visible under-price).
- **The aging, decline and retirement *structure*** — well-shaped, symmetric across all 32 clubs, and
  the only honest drag in the game. F-45 changes the quality and contract terms only.
- **The scheme-install tax** — a correctly-sized, correctly-timed cost of change and one of the few
  counter-forces that works as designed. F-21 makes it land at full size; F-65 only discloses it.
- **The AI front office as a whole.** All 31 clubs run a real offseason — tags, fifth-year options,
  core re-signings, free agency, cuts to 53 on `keepScore`, refill, a fogged competent draft, UDFAs,
  camp fill, coach carousel, facility investment, trades. Better than most commercial products ship.
- **Training focus and the practice squad** — the only two weekly systems that are genuinely
  symmetric between the user and the 31 AI clubs, and both reach the simulator through real player
  attributes and real roster membership.

**Trades**
- **Rejection honesty.** The reason the user reads *is* the string the engine returned;
  `hardBlocker` is shared by preview and outcome, so **preview ≡ outcome**. `counterLead` even
  distinguishes a GM who moved from one who is done moving. Rated **A** and described as "better than
  most commercial football games".
- **The market's structure.** Fourteen windows a league year, stance-weighted seller order, a
  need-gated buyer list with cap-absorbers at the front, three deal shapes tried in order, and
  `sweeten` capped at 34 % of the headline asset. The quantity-for-quality exploit is **dead**.
- **In-season volume and shape.** 17–21 in-season deals with ~88 % back-loading against a real 18–22;
  the deadline is week 9 of 18, which is **exact** against the post-2024 real calendar.
- **AI-vs-AI visibility.** Every executed deal is news, big/rival deals mail, deadline day adds a
  league-office roundup, and the news feed has a dedicated Trades filter that auto-pins.
- **The cap and dead-money preview** in `TradeView.capImpactSection`, computed from the same
  `CapManagementEngine.tradeCapSplit` the engine executes with. Honest decision support.
- **The player value curve** — `32 × 1.128^(OVR − 60)`. Best-in-class shape; only the bottom half is
  1–2 rounds expensive.
- **The pick chart for picks 1–129** — byte-faithful Jimmy Johnson. F-09 repairs the tail only.
- **`printTradeDiagnostics`** — one line per season with 14 fields plus two stage-by-stage funnels
  and a cap-room diagnostic. A genuinely good instrument; F-05 extends it rather than replacing it.
- **The draft room's skip path.** `autoAdvanceUntil` calls `considerAIvsAISwap()` and
  `considerAITradeUpOffer()` **before** consuming each pick and breaks the tape when a phone rings —
  the plan's S6 finding is genuinely closed.

### QA-06 — Two consecutive advances both say "Advance to the Championship"
- **Class**: bug-fix (copy)
- **Priority**: P3
- **Where**: `UI/Common/TimelineTasksPanel.swift` `advanceButtonLabel` — the `.playoffs` week-21 case
  (`"Advance to the Championship"`, hardcoded) and the outer `default:` (`"Advance to \(nextPhase)"`,
  which resolves to `"The Championship"` in the `.superBowl` phase).
- **What is wrong**: Observed in the live 2027 run (driver log iterations 151 → 152). From the
  Conference Championship week the button reads **"Advance to the Championship"**; tapping it moves
  the career into the `.superBowl` phase, where the button reads **"Advance to The Championship"** —
  the same sentence with a different capital T. To the user the control looks like it did nothing.
- **The real defect is not the capital letter**: by the second tap the club is already IN the
  Championship, so the label should say what advancing DOES (play/finish it) rather than re-announce
  arriving at it. The next tap after that correctly reads "Advance to Coaching Changes".
- **What to do**: give `.superBowl` its own case in `advanceButtonLabel` with a verb that matches the
  action. Check the sibling phases (`.proBowl`, `.allStar`) for the same shape while there — they
  also fall through to the generic `default:`.
- **Risk / how to verify**: pure copy; verify by advancing through weeks 21→22→offseason and reading
  the three consecutive labels.
- **Depends on**: none
- **Source**: live QA, 2026-08-22 season run.

---

### QA-05 — The trade wizard quoted picks in a different currency from the engine — **DONE 2026-08-22**
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `UI/Contracts/TradeView.swift` — `wizardPickChip`, `wizardSuggestionRow`,
  `tradeUpSuggestions`, `tradeDownSuggestions` and the combination search, all pricing through
  `PickValueChart.points(forPick:)`; the authority is
  `TradeValueEngine.pickTradeValue(pick:currentSeason:)` (`futurePickDiscountPerYear = 0.6`).
- **What was wrong**: Found by reading the Trade Center's asset board at the end of the live 2027
  season. It listed the club's **2028, 2029, 2030 and 2031 first-rounders at `1 000 pts` each** —
  identical — and every second at `420`, every third at `192`. The engine values those same four
  firsts at **600 / 360 / 216 / 130**: a 2031 first was displayed at **7.7×** what the deal would
  actually be judged on.
  Both sides of the wizard's fairness ratio used the raw chart, so a **same-year** swap looked right
  by accident. The moment the two sides are different years — which is the whole purpose of a
  trade-up / trade-down wizard — it recommended deals the engine treats as robbery and printed a
  reassuring **"100 %"** over them. The suggestion search itself ranked candidates in the wrong
  currency too, so the offered options were mis-ordered before the user ever saw a percentage.
- **The fix**: one private `wizardPickPoints(_:)` that calls `TradeValueEngine.pickTradeValue`, and
  every one of the wizard's eleven raw-chart call sites now goes through it — chips, ratio,
  suggestion filters, sorts and the multi-pick combination search. One function, so the three
  cannot drift apart again.
- **Note on scope**: the raw chart is still correct for surfaces that describe a pick's SLOT rather
  than its trade price (the war room's board, the draft-order screen). This entry changes only the
  wizard, which is quoting a price.
- **Verification**: compiles clean, both lints pass. Not re-observed on a live save — this build is
  newer than the one the season ran on.
- **Depends on**: none
- **Source**: live QA, 2026-08-22 season run (Las Vegas Highrollers, 2027).

---

### QA-04 — The postseason told a 4-13 club to prepare for a Wild Card game — **DONE 2026-08-22**
- **Class**: bug-fix
- **Priority**: P1
- **Where**: `Engine/Simulation/TaskGenerator.swift` `playoffTasks`, dispatched from the `.playoffs`
  case; the input comes from `CareerShellView.regenerateTasks`.
- **What was wrong**: Found in the live 2027 season run. Las Vegas finished **4-13** and the season
  review card correctly said **MISSED THE PLAYOFFS** — and the task rail on the same save still
  listed *"Prepare for Wild Card vs your opponent — Set your game plan for this win-or-go-home
  matchup"*, *"Review matchups — Compare your roster against the opponent's strengths and
  weaknesses"* and *"Check injury report — Make sure your key players are healthy for the biggest
  stage."* There was no matchup, no opponent and no stage.
  `playoffTasks` was generated unconditionally for the phase, and its `opponentName ?? "your
  opponent"` fallback is **what hid the fault** rather than what guarded against it: a missing
  fixture became a plausible sentence instead of an obvious blank. Same family as #154 and QA-03 —
  two surfaces on one screen disagreeing about the same fact.
- **The fix**: `playoffTasks` takes `isPlaying`, supplied by the shell as `!upcomingGames.isEmpty`
  (unplayed games at or after the current week). True while a live club prepares; false the moment it
  is knocked out; false all postseason for a club that never qualified. A club that is out gets a
  short, honest list that points at real surfaces — watch the round (`.standings`), see who is still
  playing (`.schedule`), start reading the draft board (`.scouting`) — and deliberately does NOT
  duplicate the offseason review phases that follow.
- **Verification**: compiles clean, both lints pass. Not yet re-observed on a live save — this build
  is newer than the one the season ran on.
- **Depends on**: none
- **Source**: live QA, 2026-08-22 season run (Las Vegas Highrollers, 2027, 4-13).

---

### F-73 — "The playoff bracket is random numbers" — **WITHDRAWN 2026-08-22. THE PREMISE WAS FALSE.**
- **Class**: —
- **Priority**: — (filed as P0, withdrawn the same hour)
- **What I claimed**: that `playPlayoffGames` sends all 31 AI playoff games to `simulateGameScore()`,
  so the champion is chosen by RNG and F-01 was only half done.
- **Why it is wrong**: `playPlayoffGames` **already runs `GameSimulator` for every game in the
  round.** The body carries an explicit `#213` block for the AI-vs-AI half, with real coaches and
  real rosters — it passes no `homeRosterOverride`, and `nil` is the documented correct default
  (`GameSimulator` then reads `currentRoster()`, the `teamID` query). The `simulateGameScore()` at
  the tail is the fallback for a game whose teams the career scope cannot resolve, exactly as in
  `advanceRegularSeasonWeek`.
- **How I got it wrong, because it is worth recording**: I read the function's HEADER comment, which
  said "the 31 AI games stay score-only", and the `simulateGameScore()` at the END, and concluded
  from the two without reading the sixty lines between them. The header was stale — it described the
  world before #213 and was left standing over a body that had already been fixed. **This is exactly
  the defect class F-68 exists for, and it cost a wrong P0 report within an hour of my closing
  F-68.** The comment is now corrected to match its body and says so.
- **What survives**: nothing actionable. F-01 is fully DONE, regular season and postseason alike.
- **Source**: filed and withdrawn 2026-08-22, both by reading the same function.

---

### F-74 — The user-side veteran fog (D3's other half of the F-23 pairing)
- **Class**: design-change
- **Priority**: P2
- **Where**: every surface that prints a free agent's `overall` — the FA board, the player card, the
  comparison views; plus a scouting-spend hook to narrow it.
- **What is wrong**: F-23 fogged the AI's read of veterans and paid for the asymmetry with D3's σ cap
  (2.0). That is a **bounded** answer, not the full one. D3's preferred pairing is that the USER also
  misjudges veterans he has not seen — his own division sharp, the rest fogged at ±1-2, narrowing
  with a scouting spend. Until that exists the user still reads every free agent in the league
  perfectly while all 32 AI rooms do not.
- **What to do**: decide first whether a fogged rating is DISPLAYED as a range/grade or as a shifted
  number. This is the load-bearing question: a shifted number silently changes what `overall` means
  on one screen and not others, which is the defect class this codebase keeps hitting (#154, QA-03,
  QA-05). A range or a letter is honest about being an estimate. `ProspectFog` / `HeadroomFog` are
  the precedent and should be the template.
- **Risk / how to verify**: this makes the user WEAKER, so it must be paired with lifting the AI σ
  cap back toward D3's 2.0-3.5, or the league simply gets foggier overall. Re-run `./run.sh career`
  and the FA price gates, and re-measure contested-signing win rate.
- **Depends on**: F-23 (landed)
- **Source**: split out of F-23 when its pairing decision was taken, 2026-08-22.

---

### F-71 — The §8 80+ share sits a rounding step outside its band
- **Class**: balance
- **Priority**: P3
- **Where**: `tools/balance-harness/driver/CareerScenario.harness.swift` assertion 6.9b; the shape is
  produced by `DraftClassBuilder` intake against the shipped development stack.
- **What is wrong**: `./run.sh career` reports the §8 80+ share at **19.00 %** against a `[12,19]`
  band and fails. Measured at `a37e045` it was **19.16 %**, so this is long-standing and not caused
  by any recent wave. `LeagueGenScenario`'s own comments record the four-season smoke running this
  share at **19.8-21 %** historically, which suggests the league has sat at or just outside the top
  of this band for some time.
- **What to do**: decide which is wrong — the band or the league. If the band is a real §8 target,
  the intake or the development stack has to give back roughly a point of 80+ share; if the league
  is right, the band's upper edge is mis-set and should say so. **Do not "fix" this by widening the
  band silently**; that is how 6.9b stops meaning anything.
- **Risk / how to verify**: touching intake or development moves every other pyramid gate with it.
  Re-run the full `career` assert block, not just 6.9b.
- **Depends on**: none
- **Source**: measured 2026-08-22 while verifying F-24; baseline established by worktree run.

---

### F-72 — The 33+ age share runs double its §8 target
- **Class**: balance
- **Priority**: P3
- **Where**: `tools/balance-harness/driver/CareerScenario.harness.swift` assertion 6.9g; the
  retirement pass in the offseason lifecycle.
- **What is wrong**: 33+ players are **4.33 %** of the league against a `≤4.0 %` assert and a §8
  target of **≤2 %** — the assert is already relaxed to twice the design target and still fails.
  Measured **4.39 %** at `a37e045`, so it is pre-existing. The assert's own message calls it a
  "retirement-calibration follow-up", i.e. this is a known deferral that has never been picked up.
- **What to do**: calibrate the retirement pass. Note the two numbers to hit are different — clearing
  the assert (4.0 %) is not the same as meeting §8 (2 %), and the entry should say which is being
  targeted before anyone starts.
- **Risk / how to verify**: retiring more veterans lowers the roster mean age (6.9f, currently 26.33
  in a `[25.5,26.5]` band) and frees cap, which feeds free-agency prices. Re-run the full `career`
  block and the FA price gates 6.11b/c.
- **Depends on**: none
- **Source**: measured 2026-08-22 while verifying F-24; baseline established by worktree run.

---

**League-level calibration**
- **The win *spread*.** sd of team wins **3.24** vs a real 3.10; luck share of record variance
  **36.6 %** vs a real 42 %; `corr(record, true strength)` **0.80** vs a real 0.75.
- **Quarterback leverage — the single best-calibrated relationship in the game.** Upgrading the QB on
  an otherwise-78 roster from 78 to 90 is worth **+2.9 wins**, landing squarely on the PFF WAR
  estimate, and the QB slot carries ~**6×** the win-leverage per point of team overall of the average
  slot against PFF's 5.8×. It exists partly by accident — a one-man upgrade barely moves the team
  mean, so it never triggers `edgeCompressionScale` — and **F-02 must preserve it**. The
  `teamEdgeFull = 3.5` "single-unit safe zone" is what protects it and is right to.
- **The average-play rebuild curve.** Playoffs in season 4 is "a good curve"; the problem is the gap
  between average and optimal, not the average path. Nothing in this queue should make the average
  path slower.
