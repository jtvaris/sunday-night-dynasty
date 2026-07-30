# Trade System — Investigation Report & Overhaul Plan

*2026-07-30. Investigation by 4-agent recon over the full trade surface (valuation,
AI behavior, draft room, UI); every claim below carries a file:line in the agent
reports (scratchpad `trade_*.md`) and was verified against the working tree and
the 3-season smoke log. No code has been changed yet — this document is the
decision gate for the overhaul.*

---

## 1. Executive summary

**The valuation layer is NFL-grade and should survive untouched. The market
around it is inert: a fully simulated season produces approximately ZERO
trades** (real NFL: ~45–60 player trades per league year, plus 25–40 draft-day
pick swaps). The root cause is a single structural fact — **future-year draft
picks do not exist as objects** — from which nearly every other failure
cascades. Where the system does fire (user-initiated proposals), the AI is one
deterministic ratio test that is trivially exploitable and has no memory,
personality, or situation awareness.

Smoke-log proof: `grep -i trade audit_smoke.log` → **0 matches in 672 lines /
3 seasons / 76 advances**. Two independent reasons, both findings: the smoke
harness has zero trade instrumentation, and the code paths genuinely produce
zero trades.

## 2. What exists today (architecture map)

| Component | Lines | Status |
|---|---|---|
| `TradeValueEngine` (R21) | 895 | **LIVE** — the one valuation + AI authority |
| `TradeEngine` | 342 | `TradeProposal` + `executeTrade` live; its own valuation trio **dead** |
| `PickValueChart` | 60 | LIVE — faithful Jimmy Johnson chart 1…224 |
| `DraftDayTradeEngine` (R24) | 228 | LIVE — draft-room pick swaps, the best-shaped piece |
| `TradeView` (Trade Center) | 1770 | LIVE — builder + wizard + incoming offers |
| `TradeOfferBanner` | 96 | LIVE — draft-room accept/decline card |
| `TradeEvaluator` (GM personalities!) | 296 | **DEAD — zero call sites** |
| `DraftEngine.evaluateTradeOffer/generateAITradeOffers/evaluateTradeValue` | ~160 | **DEAD** |
| `Domain/Models/Draft/TradeOffer.swift` | 34 | **DEAD** (only referenced by dead code) |

Three parallel trade brains ship in the binary; only one runs. Two divergent
pick charts are live simultaneously: trades price picks on the JJ chart while
draft grading + the MockDraft trade-up hint use a linear `DraftEngine.pickValue`
that diverges **10×** by pick 160 — the pre-draft screen quotes trade-up costs
the draft room would laugh at.

## 3. What is genuinely good (keep verbatim)

- **`playerTradeValue`** — exponential OVR curve on the JJ point scale,
  position premiums (QB 1.3 … RB 0.85, K/P 0.5), *positional* aging curves
  (RB declines from 26 at −16 %/yr, QB from 33 at −7 %/yr), contract
  multiplier (expiring rental ×0.85, bargain up to ×1.2, overpaid ×0.8).
  More sophisticated than most commercial football games.
- **`PickValueChart`** — the real JJ table, correctly shared by both the trade
  center and the draft room.
- **Buyer/seller framing** — `buildContenderBuyOffer` / `buildRebuilderSellOffer`
  with the right narrative copy; correctly written, structurally unreachable.
- **`DraftDayTradeEngine`'s shape** — offers with a motive tied to the public
  board, mover-up premium 98–145 %.
- **TradeView's "vs Current Starter" card** and per-asset value breakdown.
- **The whole `ContractNegotiationEngine`/`View` interaction stack** — persona,
  rounds, transcript, concession curve, break-off locks — the proven template
  the new trade flow ports (§6, Wave 3).

## 4. Findings (ranked)

### S1 — No future draft picks exist. Root cause of the dead market.
`DraftPick` rows are minted only at the proDays→draft boundary for the current
season and are all `isComplete` when the draft ends. During regular-season
weeks 1–8 the tradable pick pool is **empty**, which silently kills:
AI-vs-AI deadline trades (`guard !packagePicks.isEmpty` → 0 of the intended
2–4, every season, guaranteed), rebuilder sell-offers to the user
(`guard !askPicks.isEmpty` → never), counter-offers that ask for a pick, and
the entire pick column of the Trade Center. The `0.8^yearsOut` future discount,
`TradeEvaluator.futurePickDiscount`, and the UI's "future-year discount" label
are all provably dead branches — **no trade in this game has ever involved a
future pick**.

### S2 — The trade deadline is a phantom.
`WeekAdvancer` sets `career.currentPhase = .tradeDeadline` and reassigns
`.regularSeason` **on the next line**. The phase is never observable, so the
already-written deadline content — 3 GM tasks, the owner's "buyers or sellers?"
inbox letter, the dashboard deadline tile — is all unreachable. Deadline is
also week 8/18 (real: week 9, >50 % of the season).

### S3 — Executed trades don't affect the games.
`executeTrade` flips `player.teamID`, but the simulators read
**`Team.players`**, a relationship array assigned only at league creation and
never maintained. A traded player keeps suiting up for his old team. (This
invariant is also violated by FA/draft/cuts — a pre-existing systemic bug that
the overhaul must fix, or every other fix is cosmetic.) Additionally: the
`Contract` row is never re-pointed, no dead money (trades are free salary
dumps while the cut path models `deadCap` correctly), `noTradeClause` is
negotiated, stored and **never read**, and `HoldoutEngine.forceTrade` sets
`.traded` without moving the player.

### S4 — The live AI is one exploitable ratio test.
`respond`: accept ≥ 1.05 × value, reject < 0.90, else one deterministic
counter that targets 108 % — so propose → counter → accept is a solved 2-tap
loop. The only guards: "never their only QB" and a flat ×1.15 on incoming
top-3-need players (asymmetric — need never makes a player harder to *pry
loose*). No personality, no randomness, no memory, no record/cap/timeline
awareness, no roster-spot accounting, no proposal limit, and exact point
totals are printed in the UI. **Exploit:** value is a linear sum with a
shallow exponent, so four 75-OVR backups (780 pts) buy an 85-OVR star
(650 pts) at ratio 1.20 → deterministic accept, from any team, farmable
weekly. `TradeEvaluator.GMPersonality` (4 archetypes × 4 tunables) already
models the fix and is dead code.

### S5 — The AI almost never calls, and never calls in the offseason.
Weekly offer roll: 15 % × weeks 1–8 ≈ **1.2 attempts/season**, and both
productive sub-paths are dead (S1), leaving a filler-player fallback that can
only move ~74–78 OVR players 1-for-1. Offseason: `isTradeWindowOpen` says
open, but nothing ever generates an offer — no tag-and-trade, no cap
casualties, no March market, no draft-weekend player deals. AI-vs-AI trades
exist only in the (dead) deadline pass — the other 31 teams never trade with
each other, in any phase, ever.

### S6 — Draft room: half the fantasy is missing, and the good half is suppressed.
No user trade-**up** path exists at all (the most-wanted GM move; MockDraft
renders non-interactive "trade up?" hints priced on the *wrong chart*).
AI-vs-AI pick swaps: **zero, structurally** — every AI team picks at its
original slot in every draft, forever ("31 mannequins"). Top-5 picks become
untradeable from season 2 (3-pick package cap vs JJ prices; no future picks to
bridge). And the flagship moment — an AI banner offering to trade up with you
— is gated on `!isUserOnClock` inside a 1–3-picks window, which
`skipToMyPick` (the only sane way to play a 3.7-hour draft) skips entirely:
**the feature never fires on the real playback path**. Trade events are
persisted and never rendered (no ticker line, no drama overlay); declining a
trade-down offer accidentally blacklists the pick from trade-up offers (bug).

### S7 — There is no negotiation, no identity, no consequence.
The AI response is a modal `.alert`; the counter overwrites the user's builder
and the conversation ends. No transcript, no rounds, no GM name/persona, no
asking price, no urgency/expiry, no break-off risk, no memory of prior talks.
Accept/decline of AI offers has zero owner/media/locker-room reaction.
Trade history is `@State` — gone when the view closes; no persisted ledger,
no league transaction feed, no pick provenance from AI deals.

### S8 — Entry points are broken or missing.
`PlayerDetailView` has a "Propose Trade" button **with an empty action
closure** (it even computes a fake "~6 teams interested" teaser). The
dashboard trade tile is dead code with false copy. The Trade Center is
unreachable in the offseason (no task/tile/inbox route), and in-season only
reachable if an AI offer happens to exist. RosterView has no trade affordance;
"Trade Watch" badges link nowhere.

### S9 — Nothing measures trades.
No smoke counters, no persisted telemetry, no value numbers on executed AI
deals. This is why S1/S2 survived unnoticed. Any overhaul must land
instrumentation *first* to be verifiable.

## 5. NFL reference bands (targets for the rebuilt market)

Measured per league year unless noted. These become asserts in the smoke/
harness suite, same style as `DEVELOPMENT_NFL_REFERENCE.md` §8.

| Metric | NFL reality | Target band |
|---|---|---|
| Player trades league-wide / year | ~45–60 | **30–70** |
| — of which in-season (weeks 1–deadline) | ~15–25, back-loaded | **8–25**, ≥60 % in the last 3 weeks before deadline |
| — deadline-week flurry | 10–20 in ~72 h | **5–15** in deadline week |
| Offseason trades (March–draft) | ~25–40 | **15–40** |
| Draft-weekend pick swaps league-wide | 25–40 (8–12 in Rd 1) | **12–35**, ≥3 in Rd 1 |
| Trades involving a future pick | ~60–70 % of player trades | **≥50 %** |
| Player+pick packages | routine | must exist; **≥25 %** of player trades |
| AI offers reaching the user | constant phone | **3–8/season** in-season + 2–5 offseason |
| Contender deadline behavior | buys vets/rentals | buyers' acquisitions skew age ≥27 / expiring |
| Seller behavior | dumps expiring vets for picks | sellers' returns are ≥70 % pick value |
| User exploit ceiling | GMs don't get fleeced | quantity-for-quality (4×75 → 1×85) must be REJECTED |

## 6. Overhaul plan (dependency-ordered waves)

**Wave 0 — Instrumentation (before anything else). — DONE 2026-07-30.**
`SMOKE: diag trades season=… aiVsAi=… deadline=… userOffers=… draftSwaps=…
playersMoved=… picksMoved=… futurePickShare=…` in `MultiSeasonSmokeTest`;
persisted `TradeRecord` ledger (SwiftData: season, week, both sides' assets +
values, initiator, kind) that news/history/provenance read from. Re-baseline:
expect all zeros, proving S1/S5.

*Shipped: `Domain/Models/League/TradeRecord.swift` (model + `TradeLedger`
writer, registered in `DataContainer` and both harness schemas); ledger row
written at all three execution sites — `TradeEngine.executeTrade` (now requires
a `TradeLedger.Context`, so no path can move assets unmeasured),
`TradeValueEngine.executeDeadlineTrades`, `DraftDayCoordinator.acceptPickOffer`;
`WeekAdvancer.aiTradeOffersGenerated` counts offers that reach the user's inbox
(the ledger only sees accepted deals, and a headless harness accepts none).
No behaviour changed; no band asserts yet (Wave 2).*

**Wave 1 — Foundation: make a market possible.**
1. Mint `DraftPick` rows for seasons N+1…N+3 (rollover + league gen + template
   import), with provenance (`via ABC`). The `0.8^yearsOut` discount finally
   bites. (~30 lines in `prepareDraftOrder`/`LeagueGenerator` + importer.)
   — **DONE 2026-07-30.** `LeagueGenerator.futureDraftPicks` (no RNG, teams in
   abbreviation order) mints 7×32 rows per year for N+1…N+3 at league creation
   (both `generate` and `LeagueTemplateImporter.build` — the template FILE is
   untouched, so TVAL determinism is unaffected); `WeekAdvancer`
   `ensureFuturePickHorizon` keeps the horizon at 3 (called from
   `startNewSeason` and from both in-flight-migration spots, so existing saves
   self-heal mid-season). A future pick's slot is provisional — `round × 32 − 16`
   with the new `DraftPick.isProvisionalOrder` flag, so "a 2029 second" is one
   commodity rather than 32 differently-priced ones. When its year comes up,
   `prepareDraftOrder` ADOPTS the rows (`adoptFuturePicks`): renumbered from the
   final standings via the new `DraftEngine.draftSlotOrder`, `currentTeamID`
   untouched (traded picks keep "via ABC"), comp picks kept at their round's end,
   `teamAbbreviation` re-stamped. Comp awards now stash instead of slotting into
   a still-provisional pool. Scenario starts (`CareerScenarioApplier`) and
   `DraftOrderView` were scoped to one draft year so they don't gift/mortgage or
   render three boards at once.
2. Fix `Team.players` staleness: read rosters by `teamID` everywhere (or a
   single resync helper called after every transaction — trades, FA, draft,
   cuts). This is a repo-wide correctness fix beyond trades.
3. Make `.tradeDeadline` a real persisted week; move deadline to week 9;
   light up the existing dead tasks/inbox/tile. Offers get `weekOffered` +
   expiry; deadline wipe becomes visible ("offer expired").
   — **DONE 2026-07-30, except per-offer `weekOffered`/expiry** (that needs a
   field on `TradeProposal`, which lives in `TradeEngine` — handoff). The career
   now SPENDS week `WeekAdvancer.tradeDeadlineWeek` (= 9) in `.tradeDeadline`:
   the phase is set at the end of the week-8 advance and restored to
   `.regularSeason` when the deadline passes at the end of week 9, and
   `advanceWeek` routes both phases to `advanceRegularSeasonWeek` (the deadline
   week is an ordinary game week). Live content: `TaskGenerator.tradeDeadlineTasks`
   (now an OVERLAY on the weekly game-prep list, so the week keeps its game plan /
   depth chart / injury tasks), `InboxEngine.tradeDeadlineMessages` (delivered on
   ENTRY so "are we buyers or sellers?" arrives with a week left to act; the
   deadline-week advance asks for regular-season mail so they can't repeat a week
   late), `CareerDashboardView.tradeDeadlineTile` (already wired into the
   `.regularSeason` group grid, now reachable, and it counts the offers about to
   expire), the new `InboxEngine.tradeOffersExpiredMessage` receipt for the
   `pendingTradeOffers` wipe, and `NewsGenerator`'s guaranteed deadline-week trade
   rumor. Weekly AI offers now roll through week 9 instead of stopping at 8. The
   dead duplicate `CareerDashboardView.tradeTile` (finding S8) was deleted.
   **Handoff to the `TradeValueEngine` owner:** `deadlineWeek` there still reads
   `8` and is the *window* rule (`isTradeWindowOpen`) — point it at
   `WeekAdvancer.tradeDeadlineWeek`, and pass a week into
   `executeDeadlineTrades` so its ledger/news rows stop being stamped week 8.
   Also `TradeView`'s two "Week 8 deadline" strings and its `#N` pick labels
   (which quote a provisional slot for future picks) need the same follow-up.
4. Cap truth: dead money stays with the trader (reuse the cut path's
   `deadCap` math), `Contract.teamID` re-pointed, `noTradeClause` enforced
   (veto or waive-request flow), `forceTrade` actually trades.

**Wave 2 — A living AI market.**
1. AI-vs-AI trade pass: offseason windows (post-FA, pre-draft, cap-cut days)
   + weekly in-season with a hazard ramp into the deadline (e.g. 8 % →
   45 %/team-pair-week) + deadline flurry targeting the §5 bands. All deals
   through the same valuation + ledger + news.
2. Team stance model: contend/retool/rebuild from record, roster age curve,
   `RosterValue`, cap space. Stance sets pick-vs-player preference, age
   weighting ("we're 1–7, future picks are worth ×1.15 to us"), and
   untouchables (young stars on contenders).
3. GM personas: revive `TradeEvaluator.GMPersonality` concepts keyed
   deterministically on `Team.id` (the `AgentPersona` UUID trick):
   asking-premium, patience/maxRounds, insult threshold, initiate chance.
4. Kill the exploits: package-size diminishing returns (best asset 100 %,
   each further asset ×0.85, ×0.7, …) + roster-spot cost + per-GM hidden
   asking noise (±5–10 %) + rejection memory (re-spamming worsens terms,
   eventually season-long talk lock). Fold hard rules into the preview verdict
   so preview ≡ outcome.
5. Need model upgrade: starter-quality-aware (not roster counts), and needs
   make a team's own players *harder* to buy, not just incoming ones cheaper.

**Wave 3 — Negotiation UX (the contract-negotiation port).**
Port the proven stack: `TradeMessage` transcript with offer-snapshot bubbles,
rounds + persona patience, GM identity header (name, style chip, one-liner),
concession curve (open ~125 %, concede toward ~105 %), structural objections
("a future 1st is a non-starter"), break-off + per-team season talk locks,
persisted multi-week threads (an offer can sit and be revisited). Entry
points: wire the dead `PlayerDetailView` button, roster multi-select "shop
players", trade block, offseason dashboard route, deadline pressure card,
incoming offers as threads with expiry chips. Trade history from the ledger.

**Wave 4 — Draft-room unification.**
User trade-up (from the pick sheet and from a Big-Board prospect: "call about
moving up"); AI-vs-AI pick swaps during the draft (with ticker lines + drama
beats — the events are already persisted, just rendered nowhere); future picks
+ veterans in draft-day packages (unlocks top-5 pick trades); offers keep
firing on the skip path (roll offers *before* fast-forward resumes); one pick
chart everywhere (MockDraft hints re-priced on `PickValueChart`); decline-
blacklist bug fixed; draft trades flow through the same negotiation thread UI
and the ledger.

**Wave 5 — Cleanup.**
Delete the two dead trade brains + `TradeOffer.swift` + `TradeEngine`'s
duplicate need model after harvesting; delete the dead dashboard tile;
`ReactionsEngine`/owner/media hooks for notable trades; docs.

## 7. Decisions — LOCKED by user 2026-07-30

1. **Chart philosophy: JJ baseline + per-GM analytics lean via persona.**
   The Jimmy Johnson chart stays the game's public language (war room, UI);
   each GM persona applies a hidden lean — old-school GMs pay JJ prices to
   move up, analytics GMs refuse. Market variety and fleecing stories without
   complicating the user's view.
2. **AI offer volume: 3–8 in-season (deadline-ramped) + 2–5 offseason**,
   with the quality gate (offers target the user's sellable assets or fill
   the offering team's holes).
3. **Multi-team trades: v2.** Two-team player+pick packages are V1's scope.
4. **Conditional picks: v2.** V1 ships plain future-year picks.
5. **`Team.players` fix: teamID-reads everywhere.** The relationship array is
   demoted from source of truth; every roster query filters by `teamID`.
   Kills the staleness bug class permanently.

## 8. Measurement & gates

- Smoke: `SMOKE: diag trades` bands from §5 asserted per season (warn-level
  first season, hard from season 2).
- Balance harness: new `trades` scenario — 200 simulated seasons, distribution
  of trade counts/kinds/values; exploit probe (auto-builder tries
  quantity-for-quality and star-fleecing packages → must be rejected).
- Determinism: template import untouched; AI market runs on the season RNG,
  never inside the import path.
- UI: negotiation thread snapshot tests on the sim (transcript renders, offer
  bubbles carry assets, locks display).
