# The Trade System: Implementation Audit and Realism Assessment

**Scope:** read-only analysis of `/Users/jtvaris/workspace/projects/Dynasty`. Engine under `dynasty/dynasty/Engine`, UI under `dynasty/dynasty/UI`, harness under `tools/balance-harness`.
**Date:** 2026-08-21. **Branch:** `feat/skeletal-mocap-players` @ `3423d35`.
**Deliverable:** assessment only. No source file was modified.
**Precedent:** `docs/INJURY_SYSTEM_ANALYSIS.md`. Prior art: `docs/TRADE_OVERHAUL_PLAN.md` (2026-07-30), whose Waves 0–5 are the code being audited here.

> **Reading the evidence markers.** `[V]` = hard-verified by reading the shipped code (call sites counted, arithmetic derived from literals). `[D]` = derived arithmetic — the constants are verified, the expectation is my calculation. `[I]` = inference, stated as such. Claims sourced to the developers' own doc comments are marked `[dev-claim]` and are **not** independently confirmed, because no smoke log is committed to the repo.

---

# PART 1 — HOW IT WORKS TODAY

## 1.1 The map: every path that can create a trade

Eight live creation paths, one dead surface, one measurement path. `TradeEngine.executeTrade` (`Engine/Contract/TradeEngine.swift:107-201`) is the single primitive that moves assets — it takes a mandatory `TradeLedger.Context`, so no path can move a player without writing a `TradeRecord` row. That invariant holds: every call site below passes one.

| # | Path | Entry point | Trigger | Ledger kind | Max rate |
|---|------|-------------|---------|-------------|----------|
| 1 | AI-vs-AI, weekly in-season | `WeekAdvancer.swift:2290-2300` → `TradeValueEngine.runLeagueMarketPass` (`:3341`) | End of every regular-season week 1…8 | `.aiMarket` | 1 deal/club/window (`dealsPerClub`, `:3318`) |
| 2 | AI-vs-AI, deadline flurry | `WeekAdvancer.swift:2306-2331` | End of week 9 | `.aiDeadline` | **2** deals/club |
| 3 | AI-vs-AI, offseason | `WeekAdvancer.swift:4080-4096` → `runOffseasonTradeMarket` (`:5743`) | Exit of `.reviewRoster`, `.freeAgency`, `.proDays`, `.otas`, `.rosterCuts` — 5 windows/cycle | `.aiOffseason` | 1 deal/club/window |
| 4 | AI offer → the user, in-season | `WeekAdvancer.swift:1660-1701` → `TradeValueEngine.generateAIOffer` (`:2204`) | Weekly hazard ramp, weeks 1–9 | `.aiWeeklyOffer` on accept | Hard cap **8**/season (`:2126`) |
| 5 | AI offer → the user, offseason | `WeekAdvancer.swift:5750-5795` | Same 5 offseason windows | `.aiWeeklyOffer` | Hard cap **5**/cycle (`:2127`) |
| 6 | User-built proposal | `UI/Contracts/TradeView.swift:1553` → `TradeNegotiationView` → `TradeValueEngine.respond` (`:1186`) | User taps Propose | `.userProposal` | **Unlimited** |
| 7 | Draft-room deals (4 sub-shapes) | `UI/Draft/DraftDayCoordinator.swift:962` | See §1.5 | `.draftDay` | See §1.5 |
| 8 | Forced holdout trade | `Engine/FreeAgency/HoldoutEngine.swift:205-291` → `TradeValueEngine.buildForcedTradePackage` (`:3967`) | User picks "Force Trade" in the holdout dialog | `.holdoutForced` | Per holdout |
| — | **Dead surface** | `UI/Draft/Components/TradeOfferBanner.swift:31` | — | — | **Zero call sites** (the file header at `:13-24` admits it) |
| — | Measurement only | `MultiSeasonSmokeTest.printTradeDiagnostics` (`:564`) | DEBUG smoke run | reads the ledger | — |

The plan's headline findings **S1** (no future picks) and **S5** (the other 31 teams never trade) are genuinely fixed. Future `DraftPick` rows for N+1…N+3 exist, the AI-vs-AI market runs in fourteen distinct windows a league year, and every executed deal writes a ledger row and a news item. **The market is alive.** What follows is what is still wrong inside it.

### Paths that exist but cannot fire, or fire only under conditions a real player will not meet

- **The whole draft-day trade market lives inside a SwiftUI object.** `DraftDayCoordinator` is constructed in exactly one place — `UI/Draft/DraftDayView.swift:77` `[V]`. Every AI-vs-AI pick swap, every incoming trade-up call and the user's own trade-up board are methods on it. There is no headless equivalent: the harness's `MultiSeasonSmokeTest.runAIDraft` (`:446-527`) walks all 234 picks and **contains no trade code at all** `[V]`. Consequence: the smoke line prints `draftSwaps=` and it is structurally always `0`, and there is **no band assert on it** (`MultiSeasonSmokeTest.swift:766-786` checks nine bands; `draftSwaps` is printed at `:628` and never checked) `[V]`. The plan's §5 target "12–35 draft-weekend pick swaps, ≥3 in Rd 1" has never been verified by anything.
- **`runAIDraft`'s own doc comment names a caller that does not exist.** `MultiSeasonSmokeTest.swift:444-445`: *"Internal (not private) so the DEBUG dashboard skip can reuse it when fast-forwarding a real career through the draft phase (R39)."* `grep -rn "runAIDraft" --include="*.swift" .` returns hits only inside `MultiSeasonSmokeTest.swift` `[V]`.
- **`DraftStoryRecorder.events(forYear:)` (`Engine/Draft/DraftStoryRecorder.swift:32`) has zero callers** `[V]`. Every `.tradeOffered` / `.tradeDeclined` / `.tradeAccepted` / `.tradeExpired` `DraftEvent` row written by `DraftDayCoordinator.recordTradeEvent` (`:1057`) is a write-only DB row. The in-memory ticker (capped at 30, `:1077`) dies with the war room, so after the draft closes the only surviving trace of draft-night trades is the `NewsItem` in `career.newsLog`.
- **`TradeEngine.TradeCapOutcome.totalDeadCap` (`TradeEngine.swift:76`) has zero call sites** `[V]`.
- **The `TradeRecord` ledger is never read by any UI.** `grep -rn "TradeRecord" dynasty/dynasty/UI/` returns only construction sites and a schema list `[V]`. `TradeRecordKind.label` — "Your proposal" / "Incoming offer" / "League deal" (`TradeRecord.swift:191-195`) — is dead copy. The ledger's only reader in the entire binary is `MultiSeasonSmokeTest`, which is DEBUG-only.

## 1.2 The AI-vs-AI market — rates, derived

### Weekly targets (`TradeValueEngine.leagueTradeTarget`, `:3270-3316`)

```
weeks 1-2:  20% chance of 1     → E = 0.20 each
weeks 3-6:  Int.random(0...1)   → E = 0.50 each
week  7:    Int.random(1...2)   → E = 1.50
week  8:    Int.random(2...4)   → E = 3.00
```
Sum weeks 1–8 = **6.9 target deals** `[D]`. The deadline formula assumes exactly this: `leagueMarketTarget` computes `deficit = max(0, 7 - leagueTradesThisSeason)` (`WeekAdvancer.swift:5705`), so the two numbers agree.

```
deadline:   min(15, max(12, Int.random(12...15) + deficit))   → 12…15, biased to 15
offseason:  reviewRoster 4-7 · freeAgency 5-8 · proDays 5-9 · otas 4-7 · rosterCuts 3-5
            = 28.5 expected target, per-window cap 12, cycle cap 38
```

Ceilings: `WeekAdvancer.maxLeagueTradesInSeason = 24`, `maxLeagueTradesOffseason = 38` (`:131-132`).

**Conversion.** `runLeagueMarketPass` runs an attempt budget of `max(10, target × dealsPerClub × 8)` (`:3435`) and stops at the target. The developers' own measurement `[dev-claim]`, recorded at `TradeValueEngine.swift:3287-3291`: *"Measured end to end over two consecutive 3-season runs: 48-53 player trades a year, 17-21 of them in-season, 10-15 on deadline day, 30-32 in the offseason."* No log in the repo corroborates this; `tools/league-data/raw/_sources/smoke5.txt` predates the market entirely (its baseline `avgOVR=76.39` is the pre-calibration league).

**Derived, taking the developers' stated ~50 % conversion at face value** `[D]`: in-season ≈ 3.5 pre-deadline + ~7.5 on deadline day ≈ 11; offseason ≈ 14–19 at 50 %, 28+ at higher conversion. Last-three-weeks share ≈ 88 %, comfortably over the 60 % assert.

### Who trades with whom

`runLeagueMarketPass` (`:3341`) excludes the user's club by construction (`aiTeams = teams.filter { $0.id != userTeamID }`, `:3373`). Seller order is stance-weighted (rebuild ×1.6, retool ×1.1, contend ×0.7) times `persona.initiateWeight` times a random roll (`sellerOrder`, `:3407-3437`) — so the same three clubs are not the whole market. Buyers must have a starter-quality hole at the position: `interestGate` 0.18 ordinarily, **0.10 on deadline day** (`:3541`), and clubs that can absorb the salary go to the front of the call list (`:3560-3574`). That is a genuinely good market structure.

**Deal shapes** (`attemptLeagueDeal`, `:3580-3660`): the needs swap (football for football), the rental at the asking price, and the same deal at the seller's floor — tried in that order, first one both clubs sign wins. `sweeten` (`:3796`) adds exactly one asset from the seller's side to close a buyer's gap, capped at 34 % of the headline asset. This is why player+pick packages and 2-for-1s exist at all; the code comment at `:3607-3617` records that before these shapes existed, **186 of 186 AI-vs-AI deals over five league years returned nothing but future picks**.

### Does the user hear about it? Yes — this is a strength

Every executed AI-vs-AI deal goes through `TradeNewsFactory.announce` (`Engine/Media/NewsGenerator.swift:953`) at `WeekAdvancer.swift:5669-5677` `[V]`:
- the `NewsItem` lands in `lastNewsItems` → folded into the persisted `career.newsLog` at `WeekAdvancer.swift:955-957` → rendered by `UI/News/NewsView.swift:442`, which has a dedicated **"Trades" filter** (`:99-100`) and auto-pins every `.trade` item as trending (`:404`);
- an inbox message is generated **only** for a big deal (an 85+ OVR player or a first-rounder) or a division rival — `NewsGenerator.swift:1070-1085` → `InboxEngine.leagueTradeWireMessage` (`InboxEngine.swift:1067`). Ordinary league business is news-feed only, by design.
- deadline day adds a league-office roundup listing up to 8 deals (`TradeValueEngine.deadlineRoundupMessage`, `:3902`, delivered from `WeekAdvancer.swift:2325`).

There is **no Transactions screen** anywhere in the app — `grep -i "transactionlog\|TransactionsView\|transactionFeed"` returns zero hits in the source tree `[V]`. The news feed's Trades lens is the whole league transaction record.

## 1.3 Offers to the user — the derived volume

`TradeValueEngine.userOfferHazard` (`:2146-2183`) returns `(rolls, chancePercent)`; `WeekAdvancer` owns the dice (`:1674-1701`).

```
case .week(let week):
    guard offersSoFar < 8 else { return (0, 0) }
    if week >= 6 && offersSoFar < 2 { return (1, 100) }     // "pity floor"
    let chance = min(94, 22 + 9 * max(0, week - 1))
    return (week >= 7 ? 2 : 1, chance)
case .deadline:
    if offersSoFar < 3 { return (2, 100) }
    return (2, 94)
```

Expected **attempts** per in-season week, no pity floor engaged `[D]`:

| Wk | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 (deadline) | total |
|---|---|---|---|---|---|---|---|---|---|---|
| rolls×p | 0.22 | 0.31 | 0.40 | 0.49 | 0.58 | 0.67 | 1.52 | 1.70 | 1.88 | **7.77** |

This matches the doc comment at `:2141-2143` exactly. Offseason: 5 windows × 2 rolls at 60/70/{100\|75}/{100\|50}/{100\|60} ≈ **8.6 attempts**, hard-capped at 5 offers `[D]`.

Each attempt calls `generateAIOffer`, which shuffles up to **20 candidate clubs** weighted by `initiateWeight` (`:2246-2262`) and tries a buy builder and a sell builder for each. It returns `nil` when nothing believable exists — `funnel.offerNil` counts it. So realised offers ≤ attempts, and the smoke asserts 3–8 in-season and 2–5 offseason (`MultiSeasonSmokeTest.swift:783-786`).

**The pity floor is inverted at weeks 7 and 8** `[V]`. The `week >= 6 && offersSoFar < 2` branch returns `rolls = 1`, and it is checked **before** the `week >= 7 ? 2 : 1` line. So:

| Situation | week 7 | week 8 | wk 6–8 total |
|---|---|---|---|
| quiet season (0–1 offers so far) → pity fires | 1 × 100 % = **1.00** | 1 × 100 % = **1.00** | **3.00** |
| normal season (≥2 offers) → no pity | 2 × 76 % = **1.52** | 2 × 85 % = **1.70** | **3.89** |

A season the phone has not rung in gets **23 % fewer expected attempts in weeks 6–8 than a season that is already going well** — the branch written to protect a quiet league year is the branch that suppresses it. The guarantee of ≥1 attempt still holds, so the effect is bounded, but the code does the opposite of what its comment (`:2135-2139`, "a season still almost silent at week 6 … starts rolling at 100 %") claims to achieve.

### What an offer says and where it lands

`offerInboxMessage` (`:2860-2887`) — sender "Pro Personnel Dept.", `actionRequired: true`, attachment "Open Trade Center", body carries `offer.rationale`, which is written by the builder and names the club's record, its motive and the specific hole: *"…their CB room is starting the season's worst film. Ray Pellman is offering: a 2029 round 2 pick and G Alvarez (68 OVR)."* (`buildBuyOffer`, `:2358-2367`). The offer itself persists on `career.pendingTradeOffers`, capped at the last 5, de-duplicated per offering club (`WeekAdvancer.swift:1691-1694`), and wiped at the deadline with a receipt (`InboxEngine.tradeOffersExpiredMessage`, `WeekAdvancer.swift:2333-2340`).

Open negotiations also get one AI move per week — sweeten, walk away, or sit tight — from `WeekAdvancer.advanceOpenTradeThreads` (`:5854-6066`), which mails "X came back: new offer in your trade talks" (`:6050`). That is a real, working multi-week negotiation loop.

## 1.4 Is the AI's side sensible? Where the exploits are and are not

The valuation is genuinely one-chair-per-GM. `GMMarketView` (`:793-946`) prices everything from one club's seat: persona chart lean (`pickLean` 0.87…1.14), stance (`pickMultiplier` 0.94…1.08, `futurePickMultiplier` 0.88…1.15), starter-quality need premium **symmetric in both directions** (`incomingPlayerValue` +28 % × severity, `outgoingPlayerValue` +24 % × severity — `:836-856`), package diminishing returns (`sideValue`, `:878-892`), roster-spot cost (`:894-908`), untouchables (`:910-932`) and last-man rules (`:934-945`). `partnerVerdict` and `respond` both route through the same `hardBlocker` (`:1132`), which is the mechanical guarantee that **preview ≡ outcome**. This is better than most commercial football games and I found no way to break it by arithmetic alone.

The quantity-for-quality exploit from the plan's finding S4 is dead: four 75-OVR backups (195 pts base each, 780 linear) ladder down to `195 + 166 + 137 + 107 = 605` at a balanced GM's 0.15 decay, **minus** a roster-spot charge of `3 × 26 × crowding` = 78–140, netting ~465–527 against an 85-OVR star's 650 `[D]`. It is rejected, and `isSuspiciousOverpay` (`:1315`) correctly refuses to *scar* the relationship for an over-generous package.

**What is exploitable:**

1. **Every anti-exploit counter is a process global, wiped on app relaunch.** See §1.7 — this is the headline finding and it defeats the rejection memory, both volume caps and the pity floor at once.
2. **There is no limit on how many trades the user makes.** AI clubs are capped at 1 deal per market window (2 on deadline day, `dealsPerClub`, `:3318-3324`) and the league is capped at 24 in-season deals. The user has no cap of any kind `[V]`: `startNegotiation` (`TradeView.swift:1553`) enforces one *conversation* per GM, never a count. Nothing stops him closing a deal with all 31 clubs in the same week.
3. **The buy-low/sell-high round trip is unusually profitable.** The stance leans are symmetric within one AI's chair, but the user has no counter-lean applied to him, so he collects both sides of the spread `[D]`:
   - *Buy a 30-year-old star from a rebuilder.* Rebuild `retentionAgeMultiplier(30) = 0.82` (`:589-597`). Accept needs `gets ≥ gives × userAcceptBar`; with a balanced GM (`acceptRatio` 1.06) and no need premium, the user pays **≈ 0.79 × chart**.
   - *Sell the same man to a contender.* Contend `incomingAgeMultiplier(≥28) = 1.10` (`:568-573`), and picks coming back are marked down by the contender's `pickMultiplier` 0.94 × `futurePickMultiplier` 0.88 × an old-school `pickLean` 0.87. The user can extract picks worth up to **≈ 1.44 × chart** in raw Jimmy Johnson points.
   - Round trip ≈ **+60–80 % of chart value per cycle**, repeatable weekly, bounded only by cap room and roster spots. The *direction* is realistic — rebuilders do sell veterans cheap — but the magnitude, combined with the absence of any per-user trade cap, is farmable.
4. **The user's own franchise carries a hidden, unchosen GM persona that sets what the league pays him.** `generateAIOffer` builds `userView = marketView(team: userTeam, …)` (`:2226-2229`), and `GMPersona.forTeam(id:)` (`:391-421`) draws the archetype from the user's `Team.id` bytes. So `buildBuyOffer`'s ask is `seller.outgoingPlayerValue(target) × seller.persona.askingPremium × seller.noise` (`:2299-2301`) where *seller* is the **user** — his `askingPremium` (1.05…1.25, a 19 % spread) sets his own sale price, and `userView.pickValue` applies his `pickLean` (0.87…1.14, a 31 % spread) to what he receives. None of this is surfaced anywhere in the UI. Two saves on the same franchise-selection screen get materially different trade economies for reasons the player can never discover.
5. **`saleCandidates` honours a standing trade request (`TradeRequestRegistry`, `:2525`) but only for AI sellers.** The user's team is excluded from `runLeagueMarketPass`, and `shoppingTarget` (`:2458-2496`) — the function that picks who the AI phones the user about — never checks the registry `[V]`. So when the user's star publicly demands a trade, **nothing in the market changes**: no extra calls, no discount, no premium. The one mechanical meaning a trade request has is unavailable to the player who owns the player.

## 1.5 The draft room

Four shapes, all live inside `DraftDayCoordinator`:

| Shape | Roll | Gate |
|---|---|---|
| AI trades **up into the user's pick** | 20 % per pick while the user is 1–3 picks away (`:832`) | partner must covet a top-6 board prospect at a top-3 need (`DraftDayTradeEngine.swift:388-390`); declines are blacklisted per pick (`:834`) |
| User **trades down** | user-initiated, one search per pick (`:709`) | ~65 % per candidate with a fitting top-8 prospect, ~20 % otherwise |
| User **trades up** | user opens the Trade Up board (`:776-792`) | quotes priced through the seller's own chair |
| **AI vs AI** pick swap | `aiSwapChance(round:)` — R1 0.15, R2–3 0.10, R4+ 0.06 (`DraftDayTradeEngine.swift:712-718`) | a top-6-falling prospect (`fallingWindow`) at a buyer's ≥0.22 need |

**Derived attempt count for a 234-pick draft** `[D]`: `32 × 0.15 + 64 × 0.10 + 138 × 0.06 = 4.8 + 6.4 + 8.3 = 19.5` rolls. The engine's own comment (`:706-710`) estimates ~2/3 convert → 12–14 swaps, ~4–5 in Round 1 `[dev-claim]`.

**The skip path is fixed and I verified it.** `autoAdvanceUntil` (`DraftDayCoordinator.swift:1685-1735`) calls `considerAIvsAISwap()` and `considerAITradeUpOffer()` **before** consuming each pick (`:1703-1704`) and breaks the tape when a phone rings (`:1705-1708`). The plan's finding S6 ("the flagship moment never fires on the real playback path") is genuinely closed `[V]`. `swapRolledPickNumber` (`:868`) correctly prevents double-rolling a slot when `beginCurrentPick` re-runs.

**Where the draft room still loses information:** the ticker (`DraftTickerPanel.swift:484-501`, TRADE WIRE) and the broadcast-rail beat (`DraftBroadcastRail.swift:1049-1062`, "We have a trade", notable deals only) are the only live surfaces. Both are in-memory and die with the room. The persisted `DraftEvent` rows are never read (§1.1). `DraftRecapView.swift` and `RoundRecapSheet.swift` contain no trade content `[V]`. And `DraftDayCoordinator.applyTrade` (`:962`) **discards `offeringDeadCap`/`receivingDeadCap`** — a draft-night deal that leaves dead money on the user's cap is never reported as such.

## 1.6 What the user sees — and where the copy stops matching the engine

**The good.** The rejection reason the user reads *is* the string the engine returned: `TradeNegotiationView.sendOffer` (`:657`) appends `reason` verbatim from `respond`'s `.rejected(reason:)`, and every one of those strings is written at the decision site — `hardBlocker`'s clause/untouchable/last-man lines (`:1132-1159`), `insultReason` (`:1355`), `overpayReason` (`:1329`), the strike-count escalation (`:1272-1281`). `counterLead` (`:1727-1744`) even distinguishes a GM who moved from one who is done moving, so "They come down:" is never printed over an identical ask. This is exactly the standard the repo has been holding this month.

**Cap and dead money before the deal:** `TradeView.capImpactSection` (`:1020-1072`) shows before/after cap room for both clubs plus dead-cap rows, with the explainer *"Dead money stays with the team trading the player away — his bonus proration can't follow him."* (`:1058`), computed from the same `CapManagementEngine.tradeCapSplit` the engine executes with. That is honest decision support.

**Where it breaks:**

| # | Surface | The lie |
|---|---|---|
| C1 | `TradeView.tradeHistoryCard` (`:1415`), backed by `@State private var tradeHistory` (`:67`) | The card is titled **"Trade History (2029)"** and is populated only by `recordCompletedTrade` (`:1478`) during this view instance's lifetime. `loadData()` (`:1864-1899`) never reads it back. Close the Trade Center and reopen it and a season of trading reads **"No trades completed yet this season."** — while the real archive (`TradeRecord`) sits unread three files away. `TODO.md:2451` has logged this since R21; Wave 3 promised "Trade history from the ledger" (`TRADE_OVERHAUL_PLAN.md:284`) and did not ship it. `[V]` |
| C2 | `HoldoutEngine.swift:280` | `career.newsLog.append(announcement.news)` — but `newsLog` is documented and treated everywhere else as **newest-first** (`Career.swift:707`), every other producer prepends, and the setter truncates with `Array(newValue.prefix(150))` (`:718`). On an established career whose log is already at 150 items, the headline for the user's own star being force-traded is **encoded away and never rendered**. Same bug shape at `ContractNegotiationView.swift:1913`. `[V]` |
| C3 | `HoldoutEngine.swift:277-281` | `announcement.inbox` is discarded. The user force-trades his own holding-out star and gets **no inbox receipt at all** — no asset list, no dead-money line — while `outcome.offeringDeadCap` sits unused at `:256`. `[V]` |
| C4 | `InboxEngine.tradeCompletedMessage` (`:1030`) vs `TradeView.completedTradeInboxMessage` (`:1826`) | Two receipts for the same event. The Trade Center's quotes *"Dead money retained: $X.XM"* (`:1853`); the factory's says only *"Roster and cap adjustments have been processed"* with no figure. Which one the user gets depends on **which screen he executed from** — draft room and holdout path get the silent one. `[V]` |
| C5 | `NewsGenerator.generateTradeRumor` (`:700-720`) | Invents an interested suitor with no connection to the market pass. Fires from `generateWeeklyNews` on `Bool.random() \|\| phase == .tradeDeadline` (`:81-83`). The feed can print "PHI have interest in Vale" in the same advance in which the real market ships Vale to Denver. `[V]` |
| C6 | `TradeValueEngine.isTradeWindowOpen` doc, `:58-60` | *"…during the regular season up to and including the **Week 8** deadline."* The constant three lines above it is `deadlineWeek = 9`. `[V]` |
| C7 | `TradeValueEngine.deadlineWeek` doc, `:50-55` | *"PAIRED CHANGE: `WeekAdvancer` still gates its deadline pass on a hardcoded `if week == 8`."* It does not — `WeekAdvancer.swift:23` reads `static let tradeDeadlineWeek = TradeValueEngine.deadlineWeek`. Stale warning describing a bug that no longer exists. `[V]` |
| C8 | `TradeValueEngine.deadlinePressure` doc, `:1490-1494` | *"`Career.currentWeek` only ever holds 1…9 during the regular season."* It holds 1…18 (`WeekAdvancer.swift:2378` `if week == 18`). The function is still correct — weeks 10–18 fail `week <= deadlineWeek` — but its stated justification is false. `[V]` |
| C9 | `InboxEngine.swift:946` | Doc comment still calls `tradeDeadlineMessages` *"Dead code until the phase became real"*. It is live via `WeekAdvancer.swift:2271-2281`. `[V]` |
| C10 | `NewsGenerator.swift:1041` | Trade stories always set `relatedPlayerID: nil`, so no trade story ever renders a player portrait while every other person-story does. `[V]` |
| C11 | `TradeView.incomingSectionCard` empty state (`:636`) | *"AI offers arrive weekly during the regular season."* Offers also arrive in five offseason windows (`WeekAdvancer.swift:5750`) — the copy tells the user a market exists half the year that actually runs all year. `[V]` |

**Roster holes: nothing.** No message, tile, badge or news item ever tells the user a trade opened a depth hole. `PlayerDetailView`'s pre-trade "if cut/traded" depth-chart preview (`:1772`) is the only adjacent surface, and it is a *preview*, not a receipt. `validationErrors` refuses a package that strips a position bare (`TradeValueEngine.swift:1857-1878`) but says nothing about going from three corners to two.

**Entry points are in reasonable shape.** Persistent nav bookmark (`TopNavigationBar.swift:71`), shell route (`CareerShellView.swift:1990`), the deadline-week dashboard tile (`CareerDashboardView.swift:1571`, visible for exactly one week a season), three `TaskGenerator.tradeDeadlineTasks` (`TaskGenerator.swift:1456`), and `PlayerDetailView`'s "Trade For" on rival players (`:1920`). The plan's S8 dead button is genuinely fixed. **Missing:** any way to shop your *own* player from his detail screen, any trade block, and any trade affordance in `RosterView` — `grep -i trade RosterView.swift` returns one unrelated comment `[V]`. Wave 3 listed "roster multi-select 'shop players', trade block" as entry points (`TRADE_OVERHAUL_PLAN.md:282-283`); neither shipped.

## 1.7 The persistence hole — every anti-exploit is process-global

`WeekAdvancer` holds six trade counters as `static var` (`:100-127`):

```
aiTradeOffersGenerated · aiTradeOffersOffseasonGenerated
aiOffersThisSeason     · aiOffersThisOffseason
leagueTradesThisSeason · leagueTradesThisOffseason
```

None is on `Career`. All six, plus `TradeValueEngine.TradeTalkRegistry.reset()` and the funnel, are cleared by `resetProcessStateForCareerSwitch()` (`:178-215`). That function is called from `bind(to:)` (`:164-168`), which fires whenever `activeCareerID != career.id` — and `activeCareerID` is `nil` on every cold launch. `bind(to:)` has exactly one call site: `CareerShellView.loadShellData()` (`:3220`), which runs every time the user opens a career. `[V]`

**So every app relaunch mid-season resets the trade system's entire memory.** Four separate consequences:

1. **Rejection memory is wiped.** `TradeTalkRegistry` is `UserDefaults`-backed and would survive on its own, but `reset()` (`TradeValueEngine.swift:1004-1009`) deletes every key with the `tradeTalkStrikes` prefix. Wave 2's §6.4 anti-exploit — *"re-spamming the phone worsens terms, eventually a season-long talk lock"* — is undone by force-quitting the app. A user can lowball all 31 GMs until every one hangs up, relaunch, and the entire league answers again at its base price with zero strikes. The `+5 %` per-strike surcharge on `userAcceptBar` (`:1094`) and the `maxRounds` freeze-out both evaporate.
2. **The 8-offer in-season cap and the 5-offer offseason cap stop being caps.** A season played across five sessions can deliver far more than 8 offers, because `aiOffersThisSeason` restarts at 0 in each.
3. **The pity floor becomes a farm.** On relaunch at week ≥ 6 with `offersSoFar == 0`, `userOfferHazard` returns `(1, 100)` — a **guaranteed** offer attempt. In deadline week, `offersSoFar < 3` returns `(2, 100)` — two guaranteed attempts.
4. **The deadline flurry is maximised.** `leagueMarketTarget(.deadline)` computes `deficit = max(0, 7 - leagueTradesThisSeason)` (`:5705`). Relaunch before advancing week 9 and `leagueTradesThisSeason == 0` → deficit 7 → target `min(15, rand(12…15) + 7)` = **15 every time**, with headroom back at the full 24. The comment at `:5698-5703` calls the catch-up "exactly what the real deadline is for"; a relaunch turns it into a switch.

Compare with `TradeRequestRegistry` (`ContractNegotiationEngine.swift:2254-2310`), which is career-scoped via `CareerScopedDefaults.scopedKey` and is *not* nuked on bind. Two registries in the same domain, one durable, one not.

## 1.8 Measurability

`MultiSeasonSmokeTest.printTradeDiagnostics` (`:564-798`) is a genuinely good instrument: one `SMOKE: diag trades` line per season with 14 fields, plus `diag tradeFunnel` and `diag tradeOfferFunnel` (`:756-757`) reporting where every candidate deal died, plus `diag capRoom` — because the funnel showed the cap was vetoing 1 240 of 1 530 value-cleared deals (`:3100-3105`). Nine §5 bands are asserted, warn-level in season 1 and hard from season 2 (`:766-795`).

**Two gaps.** (a) `draftSwaps` is printed and never asserted, and structurally always 0 because `runAIDraft` has no trade code (§1.1). (b) The `total=30…70` band is checked against `rows.count`, which *includes* `.draftDay` rows — so in the harness the band is being satisfied by a number that is missing an entire category the plan bands separately.

**The balance harness cannot measure trade volume today, and it is a large job to make it.** `tools/balance-harness/sync_sources.sh:1030-1047` stages only a keep-list slice of `TradeValueEngine` — the `GMPersona` block — which `PerceptionScenario.harness.swift:273,377` uses for an archetype census. Nothing else. `run.sh`'s scenario list (`driver/main.swift:1692-1710`) has no trade scenario. To add one you would need SwiftData stubs for `DraftPick`, `Contract`, `TradeRecord` and `ModelContext` (the harness has stubs only for `Player`/`Team`/`Coach`/`CoachRole` in `GameModels.harness.swift`), plus `TradeEngine.executeTrade`, `TradeLedger`, `CapManagementEngine.tradeCapSplit` and `CampRosterEngine.isCampBody`. That is a substantially bigger staging surface than the `career` scenario needed. **The pragmatic path is the in-app smoke, not the harness** — and the one thing the harness *could* cheaply do is compile `DraftDayTradeEngine`'s pure pricing functions (`packageValue`, `moveUpPremium`, `assetValue`) against synthetic boards to probe the swap-conversion rate that `aiSwapChance`'s comment currently asserts from memory.

---

# PART 2 — REALISM BENCHMARK

## 2.1 Real NFL trade volume

| Metric | Real figure | Source |
|---|---|---|
| Total trades, 2025 league year (March → Nov 4 deadline) | **97** | NFLTradeRumors.co 2025 Trades Tracker |
| Draft-weekend trades | **43** (2023, record); 40 (2019, prior record) | ESPN, Apr 2023 |
| Picks changing hands per draft, 5-yr avg 2021–25 | **142** (148/147/147/128/138) | NFL.com, "NFL IQ: Trade trends", 2026 draft preview |
| First-round picks traded per draft, 5-yr avg | **12** (10/18/16/10/6) | NFL.com, same |
| First-round *trades* on draft night, 10-yr avg 2016–25 | **5.5** | PFF, 2026 |
| — of which involve picks 1–10 | **1.3/yr**; ≤1 in six of the last seven drafts | PFF |
| — of which involve picks 23–32 | **3.5/yr**; 46 % of the final 10 picks get traded | PFF |
| In-season trades (kickoff → deadline), 2024 | **18** | NFL.com 2024 tracker |
| In-season trades, 2025 | **22** (record since ≥1995) | PFN / CBS, Nov 2025 |
| Players traded, kickoff → deadline | 2020: 15 · 2021: 16 · 2022: 22 · 2023: 16 · 2024: 19 · **2025: 27** | CBS / NFL.com trackers |
| Trades in the October window | 2015: 4 · 2017: 8 · 2018: 9 · 2022: 18 · 2023: 18 · 2024: 18 — a **4.5× rise in a decade** | Schefter, ESPN, 10 Oct 2025 |
| Deadline **day** itself | 2022: 10 deals/12 players (most in 30 yrs) · 2024: 8 · 2025: 8–11 (outlets differ) | CBS 2022; NFL.com/PFN 2024–25 |
| Deadline week | **after Week 9** since 2024 (Nov 5 2024, Nov 4 2025); it was after Week 8 before | NFL.com |
| Trades involving a player vs pure pick-for-pick | ~**50/50** — building a pure pick dataset from 1983–2023 required discarding ~half of all trades as player-involving | Dartmouth Sports Analytics, Apr 2024 |
| In-season trades involving a **future-year** pick | **essentially 100 %** — all 18 of 2024's did; current-year picks are spent by September | CBS 2024 tracker |
| Draft-pick trades per team, 1983–92 → 2014–23 | **4.21 → 9.34** (near-linear doubling, n = 856 trades) | Dartmouth, Apr 2024 |
| Team heterogeneity | league avg 4.2 picks moved/draft; Chiefs/Rams/Vikings 5.8; **Chargers 1.4**, zero 1sts moved in 5 years | NFL.com 2026 |
| Star trades | 2025 set the record with **three** in-season former first-team All-Pros (Gardner, Q. Williams, Shaheed). Norm is **0–1 per deadline** — roughly 10 % of in-season trades | CBS/PFN Nov 2025 |
| Star-for-star | Ramsey ↔ Fitzpatrick (2025) was the **first trade of two 5+-time Pro Bowlers for each other since at least 2002** | SI / CBS 2025 |

**Typical return by tier**, from the complete 2024 in-season list (CBS) and the 2025 deadline (PFN):

| Tier | Return | Examples |
|---|---|---|
| Depth / expiring backup | **6th or 7th** | Josh Uche → 2026 6th; Khalil Herbert → 2025 7th |
| Rotational starter | **5th–6th**, often conditional | Mike Williams → 2025 5th; Baron Browning → 2025 6th |
| Good starter / productive rental | **4th**, or 4th + 5th | Ernest Jones IV → player + 2025 4th; Rashid Shaheed → 2026 4th + 5th |
| Very good, near-Pro-Bowl | **3rd** | Davante Adams → cond. 2025 3rd; Amari Cooper → 2025 3rd |
| Multi-time Pro Bowler | **3rd + 4th + 6th** class | Marshon Lattimore → 2025 3rd, 4th, 6th |
| Genuine All-Pro | **multiple 1sts** | Sauce Gardner → 2026 + 2027 1sts + a WR |

## 2.2 The value charts

**Jimmy Johnson (real):** 1 = 3000, 2 = 2600, 3 = 2200, 5 = 1700, 10 = 1300, 16 = 1000, 32 = 590, 33 = 580, 50 = 400, 64 = 270, 128 = 44, 160 = 27.4, 190 = 15.4, 200 = 11.4, 210 = 7.4, 224 = 2. (WalterFootball / FootballPerspective; DraftTek differs by ~20 % in the last 25 picks.)

**Shape, expressed as pick 1 ÷ pick N:**

| Ratio | Jimmy Johnson | Rich Hill | Chase Stuart | OTC / Fitzgerald–Spielberger |
|---|---|---|---|---|
| 1 : 32 | 5.1× | 5.4× | 2.8× | 2.4× |
| 1 : 64 | 11.1× | 12.5× | 4.3× | 3.4× |
| 1 : 100 | 30× | 28.6× | 6.5× | 4.5× |
| 1 : 200 | 263× | 200× | 38× | 9.5× |
| **pick 33 as % of pick 1** | **19.3 %** | 18.0 % | 35.5 % | 40.9 % (PFF WAR-based: **56 %**) |

The dividing line is **not** old-vs-new, it is *market-fitted vs performance-fitted*. Hill is fitted to observed trades and is as steep at the top as Johnson; Stuart, OTC and PFF measure production and flatten it. Hill's real difference from Johnson is a **~6× fatter tail** (Hill's pick 224 is 0.4 % of pick 1 against Johnson's 0.067 %).

**Do real trades follow Johnson?** Massey & Thaler, *"The Loser's Curse"*, *Management Science* 59(7), 2013: surplus value peaks in the **late 1st / early 2nd**, not at pick 1; the trade-market curve is far steeper than the surplus curve; across 14 drafts, "overwhelming evidence that a team would do better by trading down." Barnwell (ESPN, 2024), 242 pick-for-pick draft trades 2011–2019: the team trading up got the better player 42 % of the time, trading down 47 %, even 11 %; average surplus AV to the mover-up **0.0**. Dartmouth (2024): the market's *internal* consistency has improved sharply — mean model error fell from 14.22 picks (1983–92) to 5.97 (2014–23) — so teams now agree with each other far more, even where they collectively deviate from surplus value. Counterpoint worth knowing: Brill & Wyner (arXiv:2411.10400, 2024) argue the steep market curve is rational if GMs are buying *right-tail* probability rather than mean production.

**Future-pick discount.** Massey–Thaler estimate an implied discount of **136 %/yr** — a pick worth 100 this year is valued ~64 next year, and by the "one full round down" practitioner rule a 2027 2nd ≈ a 2026 3rd, i.e. **×0.45–0.55** on the Johnson chart. Taylor et al. (2018), 61 multi-year trades 2002–2016, found implied rates from −172.5 % to +625.8 %.

## 2.3 The game against the benchmark

| Dimension | Real NFL | Sunday Night Dynasty | Verdict |
|---|---|---|---|
| Player trades / league year | ~97 total (2025); ~50 excluding draft weekend | 48–53 `[dev-claim]` + 12–14 draft swaps `[dev-claim]` = **60–67** | Close. Low on the draft half. |
| In-season (kickoff → deadline) | 18 (2024), 22 (2025) | 17–21 `[dev-claim]`; band asserted 8–25 | **Excellent** |
| Deadline day | 8–11 | 10–15 `[dev-claim]`; target floored at 12 | Slightly hot |
| Back-loading | 18 of ~20 in-season trades fall in October | ≥60 % asserted in the last 3 weeks; derived ≈88 % | Right shape, slightly over-concentrated |
| Deadline week | after **Week 9** of 18 (50 %) since 2024 | **Week 9** of 18 (`WeekAdvancer.swift:23`, `:2378`) | **Exact** |
| Offseason (March → cutdowns, ex-draft) | ~35 | 30–32 `[dev-claim]` | Good |
| **Draft weekend** | **43 trades**, 142 picks moved, 5.5 first-round trades | **12–14 swaps** `[dev-claim]`, ~4–5 in Rd 1 — and **0 whenever the draft is not played in the war room** | **3× low, and unmeasured** |
| Future pick in an in-season trade | ~100 % | ~100 % structurally (current-year picks are all `isComplete` in-season) | **Correct by construction** |
| Player-involving vs pick-only | ~50/50 | pkgShare ≥25 % asserted; every AI-vs-AI deal moves a player by construction (`attemptLeagueDeal` always ships `asset`) | Pick-for-pick swaps exist only in the draft room |
| Star trades | 0–1/deadline typical, 3 in the record 2025 year | No explicit gate; `untouchableReason` blocks ≥77 OVR/≤27 on contenders, ≥81/≤26 retool, ≥79/≤24 rebuild (`:910-932`) | Plausible, unmeasured |
| Teams making zero trades | ~10–14 of 32 in-season `[I, arithmetic]`; Chargers move 1.4 picks/draft vs Chiefs 5.8 | `dealsPerClub` caps at 1–2 per window; `sellerOrder` is stance × persona × random. No club is structurally quiet | Less heterogeneous than reality |
| Injured players tradeable | Routine, with failed-physical clauses | **Forbidden outright** (`validationErrors`, `:1815-1821`) | Deviation |
| Franchise-tagged tradeable | Tag-and-trade is a standard move | **Forbidden outright** (`:1830-1836`, honestly documented as an interim) | Deviation |

## 2.4 Does the value model resemble a real chart?

**The player curve is the strongest part of the system.** `32 × 1.128^(OVR − 60)` (`:82`) times position, positional age and contract multipliers. Mapped onto picks `[D]`:

| OVR | base pts | ≈ pick | Real-world equivalent tier | Real return |
|---|---|---|---|---|
| 66 (market floor, `:2470`) | 66 | ~pick 99 (R4) | depth / fringe starter | a 6th or 7th |
| 70.5 (`solidStarterOVR`) | 122 | ~pick 98 (R4) | starter | a 5th |
| 75 | 195 | ~pick 79 (R3) | good starter | a 4th |
| 80 | 356 | ~pick 55 (R2) | very good starter | a 3rd |
| 85 | 650 | ~pick 29 (late R1) | near-Pro-Bowl | 3rd + 4th + 6th |
| 90 | 1187 | ~pick 12 (R1) | Pro Bowler | a 1st |
| 95 | 2168 | ~pick 3 | All-Pro | two 1sts |
| 99 | 3509 | **above pick 1** | generational | — |

The top half of that table is right. The **bottom half is systematically 1–2 rounds too expensive**: the game charges a late-3rd for the player the real market moves for a 4th, and a 4th for the player the real market moves for a 7th.

**And the pick chart is where that comes from.** `PickValueChart` (`Engine/Draft/PickValueChart.swift:22-58`) is advertised as "the real JJ table, correctly shared by both the trade center and the draft room" (`TRADE_OVERHAUL_PLAN.md:32`). Extracted and compared cell by cell `[V]`:

| Pick | 1 | 32 | 64 | 96 | 128 | **129** | **140** | **160** | **190** | **200** | **210** | **224** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Game** | 3000 | 590 | 270 | 128 | 44 | 42 | **30** | **10** | **2** | **1** | **1** | **1** |
| **Real JJ** | 3000 | 590 | 270 | 128 | 44 | 42 | ~36 | **27.4** | **15.4** | **11.4** | **7.4** | **2** |

**The chart is byte-faithful Jimmy Johnson for picks 1–129 and then collapses.** From pick 130 the game steps down ~1 point per pick where the real chart steps down ~0.5, and by the end of Round 5 it is 2.7× too low; by Round 6 it is 5–8× too low; picks 198–224 are all `1`.

Round totals `[V]`:

| | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R5–7 |
|---|---|---|---|---|---|---|---|---|
| Game | 37 065 | 13 312 | 6 171 | 2 490 | **817** | **137** | **37** | **991** |
| Real-JJ-shaped `[D]` | 37 065 | 13 312 | 6 171 | 2 490 | ~1 096 | ~678 | ~298 | **~2 072** |

**Rounds 6 and 7 — 64 of 224 picks, 29 % of the league's draft inventory by count — are worth 174 points combined, less than one 68-OVR backup.** A three-sixth-rounder package ladders to 21 points at a balanced GM's decay. The consequence is structural: *the game's trade market cannot conduct business below Round 4*, and Rounds 4–7 are where roughly half of all real in-season trades settle (§2.1). Every deal the game builds is forced up-market, which is precisely why `dealIsCoherent` needs a 0.72–1.70 fairness band between AI clubs (`:2818-2820`) to admit the canonical deadline trade at all.

**Shape comparison** `[D]`:

| Ratio | Game | Jimmy Johnson | Rich Hill | Chase Stuart | OTC |
|---|---|---|---|---|---|
| 1 : 32 | **5.08×** | 5.1× | 5.4× | 2.8× | 2.4× |
| 1 : 64 | **11.1×** | 11.1× | 12.5× | 4.3× | 3.4× |
| 1 : 200 | **3000×** | 263× | 200× | 38× | 9.5× |

At the top the game is a defensible market-fitted curve. In the tail **it is 11× steeper than the steepest published chart in existence**, including the one it claims to be.

**Persona dispersion.** `pickLean` spans 0.87 (old-school) … 1.14 (analytics) — the locked decision §7.1's "hidden lean". Stance `pickMultiplier` adds 0.94…1.08. Product range 0.82…1.23 = a **1.5× spread** between the most and least pick-hungry GM `[D]`. The real spread between chart *philosophies* at pick 33 is 19.3 % (JJ) vs 40.9 % (OTC) vs 56 % (PFF) — a **2.1–2.9× spread**. The game's persona variety is roughly half the real dispersion, which is a reasonable place to be for a hidden modifier, but there is headroom.

**Future-pick discount: `pow(0.8, yearsOut)` (`:172`).** Real: Massey–Thaler's implied 136 %/yr ≈ **×0.42**; the practitioner "one full round down" rule ≈ **×0.45–0.55**. The game's ×0.8 is **1.5–1.9× too generous**, and a rebuilder's `futurePickMultiplier` 1.15 × `pickMultiplier` 1.08 pushes his net valuation of a next-year pick to **0.8 × 1.242 = 0.99** — a rebuilding club in this game values a 2028 second at 99 % of a 2027 second. The real market values it at roughly half. This is a direct cause of the funnel note at `:3884-3894` that 100 % of five league years' deals returned nothing but future picks: future picks are the cheapest possible currency the buyer can pay with, and the game barely discounts them.

---

# PART 3 — VERDICT

## 3.1 Scorecard

| # | Dimension | Grade | One-line justification |
|---|---|---|---|
| 1 | Market exists at all | **A** | 14 windows/year, real assets, real ledger. The plan's "~0 trades a season" is genuinely dead. |
| 2 | In-season volume & shape | **A−** | 17–21 with an ~88 % deadline concentration against a real 18–22; deadline day slightly hot. |
| 3 | Offseason volume | **B+** | 30–32 vs a real ~35. Five windows on the right dates. |
| 4 | **Draft-weekend volume** | **D** | 12–14 against a real 43; and 0 outside the war-room UI, with no assert anywhere. |
| 5 | AI-vs-AI visibility | **A−** | Every deal is news; big/rival deals mail; deadline roundup. No Transactions screen. |
| 6 | Offers reaching the user | **B+** | Derived 7.8 attempts → 3–8 offers in-season + 2–5 offseason, asserted. Pity floor is inverted at wks 7–8. |
| 7 | Offer quality | **A−** | Motive-driven, cap-aware, clause-aware, band-checked. The AI never proposes what it would refuse. |
| 8 | Exploit resistance (in-session) | **B** | Quantity-for-quality is dead; concession is capped; but no per-user trade cap and a ~60–80 % buy-low/sell-high round trip. |
| 9 | **Exploit resistance (across launches)** | **F** | Every counter and every strike is wiped by relaunching the app. |
| 10 | Player value curve | **A−** | Best-in-class shape; ~1–2 rounds expensive at the bottom. |
| 11 | **Pick value chart** | **C−** | Byte-perfect JJ to pick 129, then 3–11× too steep. 29 % of picks are unusable as currency. |
| 12 | Future-pick discount | **C** | ×0.8/yr against a real ×0.42–0.55. Rebuilders effectively don't discount at all. |
| 13 | Rejection honesty | **A** | The reason the user reads is the string the engine decided on. `hardBlocker` is shared by preview and outcome. |
| 14 | Consequence reporting | **C** | Cap preview is excellent; the post-trade receipt exists on one of four execution paths and roster holes are never reported. |
| 15 | **Trade history / receipts** | **D** | A persisted ledger no UI reads, and a card titled "Trade History (season)" that is session-scoped `@State`. |
| 16 | Measurability | **B** | Nine asserted bands + a stage-by-stage funnel — genuinely good. Draft swaps unmeasured; harness cannot help. |

## 3.2 The gaps, ranked by gameplay impact

**1 — Relaunching the app resets every trade counter and every GM's memory of the user.** `WeekAdvancer.swift:178-215` ← `:164-168` ← `CareerShellView.swift:3220`. This single line of plumbing defeats the rejection memory, the 8/5 offer caps, the pity floor and the deadline deficit at once. It is the only finding in this audit that lets a player farm the system deliberately.

**2 — Draft weekend produces a third of the real trade volume, and nothing can see it.** `DraftDayTradeEngine.aiSwapChance` (`:712-718`) yields ~19.5 rolls/draft; `MultiSeasonSmokeTest.runAIDraft` (`:446`) makes zero trades; `MultiSeasonSmokeTest.swift:766-786` asserts nine bands and not this one. The real NFL moved 142 picks in an average recent draft.

**3 — The Jimmy Johnson chart is only Jimmy Johnson through pick 129.** `PickValueChart.swift:44-57`. Rounds 6–7 are worth 174 points combined. The whole low end of the real trade market — depth for a 6th, a rotational body for a 5th — is arithmetically unreachable, which forces every deal up-market and is a large part of why the fairness bands had to be widened to 0.72–1.70.

**4 — The Trade Center's history card lies about its own scope.** `TradeView.swift:67`, `:1415`. Titled by season, backed by `@State`, with the real archive unread three files away. `TODO.md:2451` has known this since R21; Wave 3 said it would fix it and didn't.

**5 — The user has no trade cap and a 60–80 % arbitrage.** AI clubs get 1–2 deals per window; the user gets unlimited. Buy a 30-year-old from a rebuilder at ~0.79× chart (`retentionAgeMultiplier` 0.82), sell to a contender at up to ~1.44× (`incomingAgeMultiplier` 1.10 × pick leans), repeat weekly.

**6 — Future picks are barely discounted.** `pickTradeValue`'s `pow(0.8, yearsOut)` (`:172`) against a real ×0.42–0.55, and a rebuilder's stance multipliers cancel it to ×0.99.

**7 — Force-trading your own star produces no receipt and a headline that can be silently truncated.** `HoldoutEngine.swift:277-281`.

**8 — Four execution paths, two different levels of cap disclosure.** Only `TradeView` quotes dead money; the draft room and the holdout path discard it.

**9 — A player's trade request has no market effect for the user's own club.** `TradeValueEngine.swift:2525` is read for AI sellers only.

**10 — The pity floor suppresses the quiet seasons it exists to rescue.** `TradeValueEngine.swift:2151-2154`.

**11 — Five stale doc comments describing bugs that no longer exist or constants that have moved.** C6–C9 in §1.6, plus `runAIDraft`'s phantom caller.

## 3.3 Recommendations, with targets

### Bug fixes

| # | Target | Fix |
|---|---|---|
| B1 | `WeekAdvancer.swift:200-211` + `Domain/Models/Career.swift` | Move `aiOffersThisSeason`, `aiOffersThisOffseason`, `leagueTradesThisSeason`, `leagueTradesThisOffseason` onto `Career` as stored `Int`s (the same inline-default lightweight-migration pattern the 26 `careerID` fields used). Keep the monotonic `aiTradeOffers*Generated` pair as statics — they are harness instrumentation. |
| B2 | `WeekAdvancer.swift:210` | Delete the `TradeTalkRegistry.reset()` call from `resetProcessStateForCareerSwitch()`. It is already called from `startNewSeason` (`:1176`), which is the only place a clean slate is correct. Then career-scope the registry's keys via `CareerScopedDefaults.scopedKey`, matching `TradeRequestRegistry` (`ContractNegotiationEngine.swift:2258`), so switching saves no longer needs a wipe at all. |
| B3 | `TradeValueEngine.swift:2151-2154` | Compute `rolls` first, then apply the pity floor to `chance` only: `let rolls = week >= 7 ? 2 : 1; let chance = (week >= 6 && offersSoFar < 2) ? 100 : min(94, 22 + 9*(week-1))`. Restores 2 guaranteed attempts in weeks 7–8 for a quiet season. |
| B4 | `PickValueChart.swift:44-57` | Replace picks 130–224 with the real Johnson values (a ~0.5/pick glide through R5, ~0.4 through R6, ending at 2). Round 5 sum 817 → ~1 096, R6 137 → ~678, R7 37 → ~298. **This will move every trade in the game** — re-run the smoke bands and expect the AI-vs-AI fairness band (`:2818-2820`) to be able to tighten toward 0.82–1.45 afterwards. |
| B5 | `HoldoutEngine.swift:277-281` | `career.newsLog = [announcement.news] + career.newsLog` (matching `TradeView.swift:1748`, `DraftDayCoordinator.swift:996`, `WeekAdvancer.swift:956`), and deliver `announcement.inbox`. Same append bug at `ContractNegotiationView.swift:1913`. |
| B6 | `TradeView.swift:67,1415,1864` | Load `tradeHistory` from `FetchDescriptor<TradeRecord>(predicate: careerID == cid && season == currentSeason)` in `loadData()`. The rows already carry `sentSummary`, `receivedSummary`, `sentValue`, `receivedValue` and `kind` — everything `CompletedTrade` holds. This also gives `TradeRecordKind.label` (`TradeRecord.swift:191`) its first reader. |
| B7 | `DraftDayCoordinator.swift:962-976`, `TradeValueEngine.swift:3706` | Return and use `offeringDeadCap`/`receivingDeadCap`. Fold the dead-money line into `InboxEngine.tradeCompletedMessage` (`:1030`) so all four execution paths disclose identically, and delete the duplicate `TradeView.completedTradeInboxMessage` (`:1826`). |
| B8 | `MultiSeasonSmokeTest.swift:446-527` | Add the AI-vs-AI swap roll to `runAIDraft` — a headless mirror of `DraftDayCoordinator.considerAIvsAISwap` (`:862-873`), which needs only `Board`, `aiSwapChance` and `TradeEngine.executeTrade`. Then assert `draftSwaps` in the band block at `:766-786` (§5 target 12–35, ≥3 in Rd 1). Without this the fourth-largest trade category in the game is permanently unmeasured. |
| B9 | Doc-only | `TradeValueEngine.swift:59-60` ("Week 8" → Week 9), `:50-55` (delete the stale PAIRED CHANGE warning), `:1490-1494` ("1…9" → "1…18, and weeks 10–18 fail the range test"), `InboxEngine.swift:946` (no longer dead), `MultiSeasonSmokeTest.swift:444-445` (no such caller), `TradeView.swift:636` (offers also arrive in the offseason). |
| B10 | `UI/Draft/Components/TradeOfferBanner.swift` | Delete. Zero call sites; `DraftControlBar.swift:234-252` is the surface that shipped. Its own header (`:13-24`) asks for this. |
| B11 | `TradeEngine.swift:76` | Delete `totalDeadCap` (zero call sites) or use it in B7's unified receipt. |

### Design changes

| # | Target | Change |
|---|---|---|
| D1 | `TradeValueEngine.swift:172` | Move the future-pick discount from `0.8^yearsOut` to `0.6^yearsOut` (Massey–Thaler's implied ~0.42 is the aggressive end; 0.6 lands inside the "one round down" practitioner band without gutting the future-pick market the §5 bands depend on). Then reconsider `TeamStance.futurePickMultiplier` 1.15 (`:558`) — at 0.6 base, a rebuilder still nets 0.69, which is a real preference rather than the current 0.99 no-op. |
| D2 | `WeekAdvancer.swift` in-season loop | Give the **user** a per-window trade cap the way AI clubs have one (`dealsPerClub`, `TradeValueEngine.swift:3318`). Two executed deals per week and, say, eight per league year is generous against the real league's ~1.5 trades per club per year, and it converts the buy-low/sell-high arbitrage from a farm into a decision. |
| D3 | `TradeValueEngine.swift:2458-2496` (`shoppingTarget`) | Read `TradeRequestRegistry.hasStandingRequest` here as `saleCandidates` (`:2525`) already does — a public trade demand from the user's star should raise the number and the aggressiveness of incoming calls about him. It is currently the only registry in the codebase whose meaning is unavailable to the player who owns the asset. |
| D4 | `TradeValueEngine.swift:1815-1821` | Allow injured players to be traded, at a discount scaled by `injuryWeeksRemaining`, instead of a flat veto. Real deadline trades of injured players are routine; the flat rule removes ~7 % of the league from the market at any moment for no modelled reason. |
| D5 | `DraftDayTradeEngine.swift:712-718` | Raise `aiSwapChance` once B4 lands (a repaired Day-3 chart makes small swaps constructible): R1 0.15 → 0.22, R2–3 0.10 → 0.15, R4+ 0.06 → 0.10 gives `32×0.22 + 64×0.15 + 138×0.10 ≈ 30` rolls, ~20 swaps — still under the real 43 but inside the §5 band. Verify with B8's assert, not by eye. |
| D6 | New surface | A **Transactions** lens — the ledger is already written and complete. `NewsView`'s `.trades` filter (`:99`) shows headlines; a table of `TradeRecord` rows with both asset summaries, both point totals and the `kind` label would make the league's business legible and would give the "did I win that trade?" question a durable answer. Cheapest high-value item on this list once B6 exists. |
| D7 | `UI/Roster/RosterView.swift`, `PlayerDetailView.swift:1893-1900` | Add a "shop this player" action to the own-roster action bar and a trade block to `RosterView`. Wave 3 specified both (`TRADE_OVERHAUL_PLAN.md:282-283`); neither shipped, and the Trade Center's partner-first builder is a poor way to answer "who wants my backup tight end?" |
| D8 | `TradeValueEngine.swift:1927` (`capDeltas`) / post-trade receipt | Report roster holes. `needProfile` (`:746`) already computes starter-quality severity per position; running it before and after an executed trade and naming any position that crossed 0.30 would turn "cap adjustments have been processed" into a real consequence line. |
| D9 | `GMPersona.forTeam` (`:391`) | Either surface the user's own franchise archetype (it silently sets his asking premium and pick lean — a 19 % and 31 % swing respectively) or exclude the user's club from persona assignment and price his side neutrally. A hidden multiplier on the player's own economy that he can neither see nor change is the kind of thing this repo has been deleting all month. |

