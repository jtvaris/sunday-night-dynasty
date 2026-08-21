# AI Design Decisions — the six choices behind 38 queue entries

> **DECIDED 2026-08-21 by the user.** Brief: *move toward realism, stay playable and interesting,
> the AI makes mistakes, and losing costs you something.* The rulings are recorded per decision
> below under **DECISION**, and the implementation order is at the bottom. Where the ruling departs
> from the queue's own proposal, the reason is realism and it is stated.


`docs/AI_FIX_QUEUE.md` flags 38 entries as **Needs user decision**. They are not 38 independent
questions. They are six, and the rest follow: settle D1–D6 and 34 of the 38 stop being open.

Every number below is measured, and the source is named. Nothing here is a guess dressed as a
finding. Where two audits disagreed, both figures are given.

**How to read an option.** Each carries what it changes, what it settles, what it costs to build,
and — where it is knowable — what it does to a number that is already being tracked. The
recommendation at the end of each decision is mine; the trade-off above it is the real content, and
a different taste reads the same table differently.

**One rule runs through all six.** It comes from the roster audit and it is worth stating once
rather than six times:

> Fogging only the AI is a gift. Making the AI worse is not the same as making it human.

Every option that adds AI error is paired with either a matching user-side cost or an explicit note
that the asymmetry is deliberate and bounded.

---

## D1 — Does the user keep his structural advantages?

**DECISION — remove the impossible numbers, keep the real phenomenon, and reject the artificial cap.**
* **Opponent prep**: thread it through the simulator as real per-play modifiers AND give it to all
  32 clubs, with the magnitude cut to roughly a fifth. Reason: the phenomenon is real, but +2.1 wins
  a season is more than an entire head coach is worth in the NFL (best-to-worst spread ≈1.5-2.5
  wins), and modelling a real thing accurately for one team out of 32 makes the unrealism sharper,
  not smaller.
* **Free-agency multiplier**: the sign is wrong, not just the size. Real free agents demand MORE to
  join a bad club — the loser tax — while the game lets a 2-15 user outbid a 14-3 AI at 79 cents.
  Invert it: a losing club pays a premium. The hometown/contender discount stays, at the few percent
  it is worth in reality rather than 21 %.
* **Trade cap**: NOT adopted, against the queue's own proposal (F-08). A real GM is not limited by a
  rule; he is limited by counterparties who stop taking his calls. The mechanism already exists
  (`TradeTalkRegistry`) and only started working when F-06 made it survive a relaunch. Make refusal
  bite and price it visibly instead of imposing 2/week.


**At stake.** Three edges are wired into the engine rather than earned at the desk:

| edge | measured size | where |
|---|---|---|
| Opponent prep | ×1.10 own score, ×0.925 opponent's, applied **after the game is over** — ≈ +4.2 pts/game ≈ **+2.1 wins a season** | `GameSimulator.swift:528-538` |
| Free-agency bid | structural ×1.10 / ×1.15 / ×1.25 against a maximum 12.4 % losing-team penalty — a **2-15 user outbids a 14-3 AI club at 79 cents on the dollar** | `scoreBid` |
| Trade volume | AI clubs are capped at 1–2 executed trades per window. The user has **no cap at all** | `WeekAdvancer` counters |

These are the reason a rebuild lands a season early, and they are invisible to the player, which is
the part that matters: an advantage he cannot see is one he cannot enjoy.

**Option A — Remove them; the user wins by playing better.**
Opponent prep threads through the simulator as real per-play modifiers (or is deleted); the flat FA
multiplier is gated on team success; the user gets the same 2/week, 8/year trade cap the AI lives
under. Settles F-08, F-14, F-16, F-53, F-56.
*Cost:* threading prep through `PlaySimulator` is the expensive item — the original comment says it
was avoided deliberately. *Consequence:* rebuild slows by roughly a season. *Risk:* a player who has
been winning partly on invisible subsidy will feel the game got harder without being told why. That
is a patch-notes problem, not a design problem.

**Option B — Keep them, but make them visible and earned.**
Prep keeps its magnitude but is shown as an explicit pre-game modifier the user spends a limited
resource on; the FA bonus is renamed in the UI as the hometown/pitch advantage it is pretending to
be; the trade cap stays off but every executed trade prints its value delta.
*Cost:* low, mostly UI. *Consequence:* the numbers do not move; the fiction stops lying.
*Risk:* the fast rebuild survives intact, and D4's frozen table gets no help from here.

**Option C — Give all 32 clubs the same tools.**
AI clubs get prep, a bid personality and the same trade freedom. Settles F-16(c) and F-17 together.
*Cost:* medium. *Consequence:* the subsidy becomes a mechanic. *Risk:* raises AI competence
everywhere at once, and the user loses ground on three fronts in one patch.

**Recommendation: A for prep and trades, B for the FA multiplier.** The prep multiplier is the one
edge with no defence — it edits the scoreboard after the whistle, and its designed counterweight
writes to a field no simulator file reads. The FA bonus, by contrast, models something real: players
do sign for less to go somewhere they want. Keep it, cap it, and say so on screen.

---

## D2 — Is the salary cap a constraint or an inconvenience?

**DECISION — Option A, all four sub-parts, landed alone and measured alone.**
The defining constraint of the job, currently disengaged. Dead money is the most characteristic
feature of real cap work (Denver carried ≈$85M of it on one contract in 2024); a league that erases
it annually has removed what makes a contract decision a decision. The 89 % cash floor is a real CBA
rule and is the specific mechanism that forces bad clubs to spend, which is where a veteran market
comes from — there is no other way to produce one. The release lever ships with it so AI clubs can
act rather than spiral.


**At stake.** No AI club can ever be in cap trouble, by four independent mechanisms. The decisive
one is the annual true-up at `FreeAgencyEngine.swift:718-720`, which rebuilds `currentCapUsage` from
rostered salary and therefore **erases every dollar of dead money each league year**. On top of it: a
15 % reserve enforced at every signing door, unconditional 5–8 % cap growth, and a salary floor at
`CapManagementEngine.swift:857` with **zero callers**.

Measured: league cap room 30.3 → 39.2 → 32.3 → 23.1 %, 31–32 of 32 clubs compliant every season,
payroll 64.5–79.8 % of the cap. The CBA mandates 89 % cash spend, and in March 2025 several real
clubs opened the league year tens of millions **over** the cap.

**This is the strongest brake on the fast rebuild that exists anywhere in the codebase**, and it is
currently disengaged.

**Option A — Full bind (all four sub-parts).**
Per-year dead-cap ledger replacing the wipe; salary floor enforced in the FA mop-up (a club under
89 % must spend whether or not it has a need); per-club reserve replacing the flat 15 %; a release
lever so a club in trouble can act. Settles F-11 entirely, and most of F-12 follows for free.
*Consequence:* every March, clubs are forced to cut good players into the market — the veteran
opportunity a real GM lives on, and the one the user has never had. Expect league payroll to move
into the 85–92 % band and cap room to fall toward 8–15 %.
*Risk:* the largest single behaviour change on this list. It interacts with everything, so it must
land alone and be measured alone.

**Option B — Dead money only.**
Just the ledger: bad contracts follow a club into the next year. Half the cost, most of the
narrative effect, and no forced-spending mechanics.
*Consequence:* AI clubs start making mistakes that persist, which is most of what "the cap binds"
means to a player. Payroll shifts only slightly.
*Risk:* clubs still never get desperate, so the veteran market stays thin.

**Option C — Leave it.**
The cap remains a one-year inconvenience. *Consequence:* rebuild stays fast, veteran market stays
thin, and D4 loses its most powerful lever.

**Recommendation: A, and land it by itself.** This is the decision with the largest realism return
per line changed. But it deserves its own wave with the `diag capRoom` and `diag balance` bands read
before and after — not bundled with anything else.

---

## D3 — What kind of wrong should the AI be?

**DECISION — Option A and Option C together; uniform noise explicitly rejected.**

**REFINEMENT (user, 2026-08-21) — three properties the error model must have.** These are not a
softening of Option A, they are its specification:

1. **The AI lives in fog too, and not only about players.** It does not know the opposing GM's
   valuations, the opposing coach's tendencies, or what a rival is willing to pay. Today it does:
   trade valuation, free-agency pricing and the draft board all read shared truth. Organisational
   fog is what makes a negotiation a negotiation rather than an arithmetic check.
2. **It does not guess randomly — it plans, and the plan can be wrong.** An AI club should have an
   intention (this is a rebuild; we need a tackle; we believe in athletic corners) and pursue it
   coherently across a season. Errors then come from bad information or a bad philosophy, not from
   a die rolled at the moment of decision. This is the difference between a GM who is mistaken and
   a GM who is incoherent, and only the first is recognisable as an opponent.
3. **Big blunders are allowed.** Not just a wide-ish Gaussian: the occasional franchise-altering
   mistake — the contract that eats a club for three years, the trade-up that costs two firsts for a
   bust. Real front offices do this every season somewhere in the league. The fat tail belongs in
   the model, and D2 is what makes it *matter*: a blunder with no lasting cap consequence is not a
   blunder, it is a bad afternoon.

Note the coupling: (3) is only real once D2 lands, and (1) is what D7 below is about.

Real organisations err in correlated, persistent ways because a scouting department has a
philosophy. Uniform noise is realistic per decision and false in cause: it produces 32 clubs that
are all slightly worse than the user and indistinguishable from each other, which is both unrealistic
and unlearnable, and it grows the user's edge because he is the only actor with a consistent plan.
House tastes bounded at 2-4 OVR points — readable, never certain. The user-side pairing is
mandatory: he misjudges veterans he has not seen (his own division sharp, the rest fogged, narrowing
with a scouting spend). The development desk's `truePotential` read is closed as pure information
unrealism.


**At stake.** Your explicit design goal. Current state:

- **The draft is already right.** `AIDraftPerception` is live and wired (`DraftEngine.swift:236`):
  mean absolute error 3.96 OVR, fat tail 6.99 %, old-school GMs 5.25 vs analytics 3.01. The user is
  *sharper* on men he scouts; the asymmetry is coverage — 25 evaluations against a 350-man class.
  This is the correct shape and should be the template.
- **Free agency has no perception model at all.** Every AI club reads true `overall` and true
  `truePotential`.
- **The development desk reads `truePotential`** — the number `DevelopmentReportView.swift:9`
  explicitly denies the user.
- **No club has a house preference.** 32 boards differ only by zero-mean symmetric Gaussian noise.
- **Gameday has exactly one modelled decision error** — `DCPersona.misreadChance`, coached games
  only, and exactly `0.0` for `balanced` and `conservative` (≈40 % of coordinators) and for every AI
  offense in the league.

**Option A — Structured taste (the report's "single highest-value addition").**
Each club draws 2 of 6 permanent biases from its UUID: traits-over-tape `+0.4 × (physical − 70)`,
scheme fit `+2.5`, position bias `+3.0` / `−1.5`, small-school aversion `−2.0`, character hawk, age
hawk. Plus round-scaled need (R1 ×2.0, R2–3 ×1.0, day 3 ×0.6), position-run panic, and a veteran
perception σ 2.0–3.5 by GM archetype. Settles F-23, F-26, F-27, F-29, F-31, F-62.
*Consequence:* the success test is that you can learn *"Denver always overpays for size"* and that
exploiting it costs you somewhere else. That is the difference between an opponent and a dice roll.
*Cost:* medium, and the plumbing for the draft half already exists.
*Pairing required:* a veteran fog on the AI alone is a gift. Either a small user-side fog (±1–2 on
free agents outside your division, narrowing with a scouting spend) or cap the AI σ at 2.0.

**Option B — Uniform noise, turned up.**
Widen the existing Gaussians. *Cost:* trivial. *Consequence:* AI clubs get worse without getting
different. Nothing becomes learnable, and the user's edge grows. **This is the option that looks
like the goal and is not.**

**Option C — Gameday errors only.**
Floor `conservative`/`balanced` misread at 0.05, scale by coordinator grade
(`+max(0, (70 − grade)/100 × 0.15)`, so good coaches buy *fewer* mistakes), add an OC channel.
Settles F-38. *Cost:* small. *Consequence:* the mistakes become visible during the one game the user
watches, which is where they land emotionally.

**Recommendation: A and C together, B never.** They are the same idea at two timescales — a club
that misjudges in March and a coordinator who guesses wrong on 3rd-and-6. Fog the development desk
(F-24) as part of A, since it reads a number the user is denied.

---

## D4 — Should the league table unfreeze?

**DECISION — A first, then C. B is not adopted as a starting move.**
Real parity comes from mechanisms — the cap, injuries, free agency, draft order, coaching churn —
and the AI club currently participates in none of them at 1.4 roster moves a season. B (more bust
variance, looser retirement) would hit the 0.32 target statistically while faking it causally, and
it would cost the user something real: a table that moves without anyone acting makes his own work
invisible inside the noise. Do A and D2 first, re-read `diag balance`, and only then decide whether
B is still needed.
**C is explicitly in scope** on the user's brief that losing must cost something: a record/morale
term in holdout detection and `.losingCulture` reaching free-agent negotiation.


**At stake.** This one is new — it became measurable only after #213, and the first reading is bad:

| | measured | real NFL |
|---|---|---|
| year-over-year win correlation | **0.67–0.74** | 0.32 |
| last season's bottom four reaching the playoff field | **0 %** | common (1.29 worst-to-first seasons/yr) |
| AI roster moves per season | **≈1.4** | well over 100 |
| R1 washout rate | 6.4 % | 17–57 % by pick range |
| inherited-roster potential headroom | 1.6 | 12.0 in the draft pipeline |

A frozen table costs the rebuild fantasy twice: rivals never fall to you, and your own climb has no
one to pass.

**Option A — Churn the rosters.**
AI clubs elevate their own practice-squad men (currently **0 per club per season** — one clause,
`leagueSquad(excluding: suitor.id)`), react to injuries in the deadline need model, sign street free
agents, and use the franchise tag. Settles F-37, F-54, F-63, and most of the season-lifecycle audit.
*Consequence:* directly attacks the 1.4 moves/season figure. *Cost:* medium, spread over many small
sites.

**Option B — Churn the outcomes.**
Raise R1 bust risk toward the real range, let quality and contract status affect retirement, raise
draft-weekend swaps (R1 0.15→0.22, R2–3 0.10→0.15, R4+ 0.06→0.10 ≈ 20 swaps), tighten the future-pick
discount to ×0.6/yr. Settles F-10, F-45, F-48, F-55.
*Consequence:* more variance in who is good next year, without new systems.
*Risk:* variance without agency reads as unfairness if overdone.

**Option C — Churn the consequences.**
Losing costs the user players: a record/morale term in holdout detection, `.losingCulture` reaching
free-agent negotiation. Settles F-59 and half of F-14.
*Consequence:* the rebuild acquires a downside, which it currently has none of.

**Recommendation: A first, then C, then B.** A fixes a bug-shaped gap (clubs that cannot use their
own players), C adds the missing stake, and B is a tuning pass best done last, when the first two
have already moved the number. Re-read `diag balance` after each.

---

## D5 — How competent should the AI be on gameday?

**DECISION — A, then B, then C, with F-25's retune last.**
The goal is not a better AI but a DIFFERENT one. Real head coaches vary about threefold in
fourth-down aggression and most are measurably too conservative, so an AI that always makes the
EV-optimal call is less realistic than one that punts too much. The persona model is therefore
realism, not a difficulty setting.


**At stake.** `gamePlan` is hard-coded `nil` for all 31 clubs (`WeekAdvancer.swift:1372-1373`,
`:7296-7297` — the comment admits it), so `fourthDownAggressiveness` and `runPassRatio` are
structurally user-only. Timeouts, kneel-downs and onside kicks are user-only too. Coach quality
moves execution (±0.07 completion, ±0.75 ypc) but **not one situational decision**.

**Option A — Head-coach persona (fully specified, no migration).**
Derive `HCPersona ∈ { riverboat, modern, orthodox, punter }` from `adaptability` + `playCalling`,
tie-broken deterministically by coach id. Three fields: `fourthDownAggressiveness`
0.85/0.60/0.40/0.15, `twoPointBias` +1/0/0/−1, `clockErrorRate` 0.10/…
Settles F-17, and F-39's error-rate hook comes with it.
*Consequence:* AI clubs start making recognisably different decisions, and a punter-archetype coach
becomes a thing you can play against. *Cost:* small — the slot already exists.

**Option B — Endgame capability parity.**
Timeouts, kneels and the onside kick for the AI, with a persona-scaled failure rate. Lower onside
recovery from 0.12 to ~0.08 first (real: 8.7 % 2018-23). Settles F-39.
*Consequence:* late-game situations stop being free for the user.

**Option C — Situational fidelity.**
Red zone starting at the 20 for both play selection and defence, kicker-dependent field-goal range
(real spread 8–12 yards), the four named clock gaps. Settles F-42, F-44, F-66, and F-25's retune
must land *after* these or it is invalidated immediately.

**Recommendation: A, then B, then C, in that order, and F-25 last.** A gives the largest character
return for the smallest change. Note the ordering constraint is real: every one of these moves the
play mix, and F-25 is a retune against the play mix.

**Explicitly out of scope until asked:** F-60 (AI remembering your tendencies across weeks). The
reports name the gap and propose no mechanism, and by rule B it would require a symmetric channel
for the user. Do not start it without a design.

---

## D6 — What should the user be able to see?

**DECISION — adopted as one small wave, scheduled whenever there is a gap.**
Pure information realism: a real GM reads the league transaction wire, and this one is written to
the database with no screen reading it.


Cheap, low-risk, and all of it turns existing data into something readable.

- **F-51 Transactions screen** over `TradeRecord` — the ledger is written and no UI reads it. The
  reports call it "the cheapest high-value item on this list".
- **F-57 post-trade roster holes** — run `needProfile` before and after, name any position that
  crossed 0.30 severity. Turns *"cap adjustments have been processed"* into a consequence.
- **F-58 shop-your-own-player and a trade block** — specified in Wave 3, never shipped.
- **F-65 scheme-change cost preview** — show the install curve before the user commits.
- **F-71 fantasy-draft AI** — either fold `FantasyDraftEngine.aiPickIndex` into the one draft brain
  or leave a comment on each naming the other, so the next audit knows the divergence is deliberate.

**Recommendation: take all of D6 as one small wave.** No decision here is load-bearing, and the
whole group is a day's work that makes four other decisions legible to the player.

---

## D7 — What does an AI club know about the other 31? *(OPEN — new, raised by the refinement above)*

**At stake.** Property (1) of the refinement is not covered anywhere in the queue's 38, because no
audit thought to ask it. Today every AI club evaluates trades, prices free agents and ranks
prospects against **shared truth about the other organisations**: it knows exactly what a rival
values, so a negotiation resolves to an arithmetic comparison rather than a read on a person.

**Options.**
* **A — Valuation fog.** Each club carries a noisy estimate of what every other club will pay,
  narrowing with contact (you learn a GM by trading with him). Makes offers occasionally mispriced
  in both directions, and makes a *reputation* possible.
* **B — Tendency fog.** Clubs do not know an opposing coach's habits until they have played him;
  scouting a division rival twice a year is why divisional games feel different. This is F-60 with
  a mechanism, and by the pairing rule it needs a symmetric user channel.
* **C — Both, staged.** A first, because it lands inside systems that already exist (trade
  valuation, bid pricing); B second, because it needs a new per-matchup memory.
* **D — Neither.** Keep shared truth between organisations; fog stays a player-evaluation concept.

**Cost:** A is medium and self-contained. B is the larger one and is the only item on this page with
no proposed mechanism in any report.

**No ruling yet — this needs your call.**

## Still open after D1-D6

* **D7** above — the biggest of the four, and new.
* **F-56 — the user's own hidden GM persona.** Surface it in the UI as a franchise identity, or
  exclude his club from persona assignment and price his side neutrally? D1 settles the *pricing*
  half; this is the remaining half. Either is better than the status quo, where he has a persona he
  cannot see and cannot use.
* **F-61 — guarantees and contract term as AI negotiating levers.** Should a negotiation have more
  than one dimension (money) — can the AI trade term for guarantees the way real agents do? No
  magnitudes are specified anywhere; this is a genuine design question, not a tuning one.
* **F-66 — clock fidelity.** Four named gaps, no proposed design. How much clock detail is wanted
  is a taste question about how much of a real broadcast the sim should reproduce.

**Not decisions — tuning I will propose and measure rather than ask about:** F-42 (kicker-dependent
field-goal range mapping), F-45 (retirement magnitudes), F-47 (intake headroom target), F-48 (R1
bust distribution, and it is deferred with D4-B anyway), and F-25's choice of which play-selection
lever moves first.

## Ordering — APPROVED 2026-08-21

1. **D2** alone, measured alone — it moves every other number.
2. **D4-A** (roster churn), then re-read `diag balance`.
3. **D3-A + D3-C** (house taste, veteran fog with its user-side pairing, gameday misreads).
4. **D1** (prep threaded and shared at a fifth of its size; the FA multiplier inverted for a losing
   club; refusal priced instead of a trade cap).
5. **D5-A/B/C** in order, then F-25's retune.
6. **D4-C** (losing costs players) — placed here rather than earlier because F-14 and F-59 are the
   same gap from the pricing and the roster side, and D1 settles the pricing half.
7. **D6** whenever there is a gap.

**D4-B is deferred, not cancelled.** Re-read `diag balance` after steps 1-2; if year-over-year
correlation is still far above 0.32 with the mechanisms in place, revisit it then — with causes
exhausted first.

## What NOT to touch

Named by the audits as correct and well-built: the retirement age-wall, the coaching carousel
(0.145 firings/club vs a real ~0.20), UDFA, comp picks, `TeamStance`, the practice-squad system's
symmetry and injury-awareness, the adaptive play-calling brain's fairness caps, rejection copy
(engine strings, not decorative prose), the trade deadline's week-9-of-18 placement and its
back-loading, and the draft perception model's shape.
