# R2 — NFL Substance, PED & Gambling Discipline, 2015–2026

**Purpose:** grounding research for a FICTIONAL life-events system in an NFL management game.
Real names appear only as citations for the base rates and mechanics. Nothing here is meant to ship as
in-game text.

**Research date:** 2026-08-14. Web-sourced; primary policy documents pulled directly from NFLPA-hosted PDFs
(2021/2022 PES policy, 2023/2024 Substances of Abuse policy, 2024 side-by-side change memo) and extracted
locally with `pdftotext`. Local copies in this directory: `pes2022.txt`, `soa2024.txt`, `soa2023.txt`,
`sidebyside2024.txt`, `ridley.txt`.

**Confidence key used throughout:** `[HIGH]` = primary policy text or league statement.
`[MED]` = multiple concurring secondary reports. `[LOW]` = single source, or my own arithmetic on
someone else's aggregate.

---

## 0. Executive model — the three regimes

The decade splits into three distinct disciplinary regimes, and a game that models them as one system will
feel wrong. Each has a different *shape*:

| Regime | Trigger | Detection | Frequency | Career impact |
|---|---|---|---|---|
| **PED** | positive test / missed test / manipulation | high-volume routine testing, near-random | **steady ~16/yr**, no trend | moderate; recoverable |
| **Substances of abuse** | positive test, or *conviction* | testing collapsed post-2020; law-driven now | **collapsed** ~7/yr → ~1/yr | pre-2020: career-ending spirals; post-2020: near-zero |
| **Gambling** | investigation, betting-operator data feeds | integrity monitoring, not testing | **bursty**: 0–1/yr baseline, one 10-player wave in 2023 | severe; frequently roster-terminal |

The single most important design insight: **PED is a Poisson process, substances-of-abuse is a broken
regime with a hard 2020 discontinuity, and gambling is a rare cluster event.** Modelling all three as
"random bad thing, p per season" loses the flavour of all three.

---

## 1. PED POLICY — Performance-Enhancing Substances

### 1.1 The discipline ladder (current, from the 2021/2022 policy text) `[HIGH]`

Verbatim structure from §6 "Suspension and Related Discipline" of the *NFL Policy on Performance-Enhancing
Substances* (2021 text, distributed as the 2022 policy):

**Step One (first violation)** — suspended *without pay*:

| Finding | Games |
|---|---|
| Positive for **stimulant, diuretic or masking agent** | **2** regular and/or postseason games |
| Positive for **anabolic agent** | **6** regular and/or postseason games |
| Prohibited substance **+** diuretic/masking agent; or attempt to substitute/dilute/adulterate a specimen; or manipulate a test result; or §5 violation (possession/distribution) | **8** regular and/or postseason games |

**Step Two (second violation)**

| Finding | Games |
|---|---|
| Anabolic agent / substitution / manipulation / §5 | **17** games (a full regular season) |
| Stimulant, diuretic or masking agent | **5** games |

**Step Three (third violation)** — **banished from the NFL for at least two seasons.** May petition the
Commissioner for reinstatement after 24 months; reinstatement is "solely within the Commissioner's sound
discretion."

**Important regime note `[MED]`:** this 2/6/8 → 5/17 → banishment ladder is the *post-2021* schedule.
Through roughly 2014–2020 the operative schedule was a flat **4 games first offence / 10 games second /
2 years third**. This is why the observed data has a wall of 4-game suspensions in 2015–2019 (Ingram,
Edelman, Burfict, Davis, Turbin, Sanchez, Liuget, Mauro, Brothers, Bolden, Alexander — all 4 games in 2018
alone) and 10-game second offences (Lane Johnson 2016, Jalen Collins 2018, Nick Boyle), then a mix of 2s and
6s from 2024 onward (Garoppolo 2, Jameson Williams 2, Stoops 2, Alarcon 6, Beckham 6). **If the game is set
"now", use 2/6/8.** If it wants a historical feel, 4/10/2yr.

### 1.2 Ancillary consequences baked into the policy `[HIGH]`

- **Reserve/Suspended list.** Suspended players go on Reserve/Commissioner Suspension. They do not count
  against the roster limit — *the club gets to sign a replacement.* This is the mechanic that makes a
  suspension cheap for the team and expensive for the player.
- **No pay during suspension.**
- **Awards ineligibility.** A suspended player is ineligible for the Pro Bowl *and* for MVP, OPOY/DPOY,
  OROY/DROY, Super Bowl MVP, Walter Payton Man of the Year, Comeback Player of the Year, Art Rooney
  Sportsmanship, Salute to Service and Alan Page Community Service — **for the whole season in which the
  violation is upheld and served.** Excellent game hook: a suspension torches an award campaign, not just
  game checks.
- **Preseason carve-out.** If discipline lands before/during preseason, the player plays the whole preseason,
  then the suspension attaches at final roster cutdown. Suspensions carry over into the next regular season
  if the season runs out first.
- **Return gate.** Must test negative *and* be cleared as fit to play by the club physician before contact
  work. (Amended in Dec 2024 — see 1.6.)
- **Bonus forfeiture (§14).** Suspended players "shall be required to forfeit any applicable bonus amounts in
  accordance with Article 4, Section 9 of the CBA." The policy explicitly kills "facial invalidity" defences
  against forfeiture. This is the clause that voids guarantees.
- **Reasonable-cause pool.** Any player with a prior positive — *including a college/combine positive up to
  two seasons before his draft* — can be put in the reasonable-cause programme: up to **24 tests/year**,
  in-season and off-season, indefinitely. Once flagged, effectively flagged for life.
- **Cooperation discount.** The Management Council may cut a suspension **and the corresponding bonus
  forfeiture by up to 50%** if the player gives full assistance that produces a finding against another
  player, coach or trainer. A ready-made "snitch mechanic".

### 1.3 Testing volume — why detection is rare per test but common per career `[HIGH]`

From §3 of the PES policy:

- **Annual:** every player tested at least once per league year, at training camp, as part of the physical.
- **Preseason + regular season:** **10 players per club per week**, computer-randomised from active roster,
  practice squad and reserve lists.
- **Postseason:** 10 players per club per week for as long as the club survives.
- **Off-season:** up to **6** tests per player (urine and/or blood).
- **Reasonable cause:** up to **24** urine/blood tests per player per year.
- **Combine / pre-employment:** tested at the scouting combine and on free-agent signing.
- Blood testing: 20% of each club's annual-test cohort and 10% of the off-season cohort get blood draws.
- Labs: UCLA Olympic Analytical Laboratory and SMRTL (Salt Lake City), both WADA/ISO-accredited.

**Derived `[LOW]`:** 32 clubs × 10 players × ~21 preseason+regular-season weeks ≈ **6,700 in-season tests**,
plus ~2,000 annual tests, plus off-season and reasonable-cause draws → order **10,000+ tests/league-year**.
Against ~16 suspensions, the *per-test* detected-positive rate is roughly **0.15%**. Secondary reporting
puts it at "~2,400 regular season, 600 off-season, 300 playoffs" `[LOW]` — lower than the policy's stated
sampling implies, so treat volume as a range.

Design consequence: a realistic sim gives each player ~5–10 test events per season at ~0.1–0.2% detection
each — i.e. per-test risk is negligible, cumulative career risk is not.

### 1.4 The "tainted supplement" defence arc `[HIGH] policy / `[MED]` cases`

The policy forecloses it in one sentence, §8:

> "a positive test will not be excused because it results from the use of a dietary supplement, rather than
> from the intentional use of a Prohibited Substance. **Players are responsible for what is in their
> bodies.**"

That is strict liability. The arc it produces is stable and highly reusable as narrative:

1. Positive test → leak/announcement.
2. Player statement: "I would never knowingly…", names an over-the-counter or online supplement.
3. Appeal filed; **suspension does not take effect pending appeal** — the player keeps playing, sometimes for
   weeks.
4. Arbitrator upholds. Player accepts, or briefly floats litigation and drops it.
5. Public narrative splits into "he cheated" and "the system is strict-liability and unfair" and never
   resolves.

**Cited instances:**
- *Lane Johnson (OT, 2016)* — 10 games, second violation, positive for a peptide in an amino-acid product
  bought online. Hearing before arbitrator James Carter in the NFL's New York office; **upheld** 11 Oct 2016.
  Forfeited **$421,875 of a $675,000 base salary**, and the suspension **nullified the guaranteed money** in
  a freshly signed 5-year/$56M extension. Publicly criticised the NFLPA over supplement guidance. His 2014
  first offence (4 games) was blamed on prescribed medication taken without consulting team medical staff.
- *Julian Edelman (WR, 2018)* — 4 games for an "unrecognizable substance". Appealed to an independent
  arbitrator; **upheld**. Considered suing, declined.
- *Odell Beckham Jr. (WR, Oct 2025)* — 6 games for elevated testosterone from a test taken in 2024 while with
  Miami; announced 7 Oct 2025, effective from Week 12 as a free agent. Said he was told only "your
  testosterone levels are too high," maintained he ingested nothing knowingly, **did not appeal**.
- *StarCaps (2008, pre-window but the canonical precedent)* — multiple players positive for a diuretic
  traced to a branded dietary supplement; produced the litigation that hardened the league's strict-liability
  stance.

### 1.5 Appeals — process and why they almost never work `[HIGH]`

Structure (PES §§9–11):

- All §6 (discipline) appeals go to **third-party arbitrators**, jointly selected and jointly paid by NFL and
  NFLPA, unaffiliated with any club. Minimum two-year terms. A **Notice Arbitrator** assigns cases.
- **Five business days** to file after notice of discipline.
- In-season hearings are auto-scheduled for **the fourth Tuesday** after the discipline notice; the calendar
  is pre-staffed with an arbitrator every Tuesday from before the first preseason game through the Super
  Bowl. Off-season hearings within 30 days.
- Player may bring counsel and present evidence; NFLPA may participate in parallel. Hearings by conference
  call unless a party demands in person.
- **Pending appeal, the discipline does not take effect.**
- **Two hard limits on the arbitrator, and they are the whole story:**
  1. the arbitrator **may not reduce a sanction below the policy minimum**; and
  2. the arbitrator **may not vacate discipline unless he finds the charged violation could not be
     established.**

  So the only winning appeal is a *factual* one — chain of custody, lab error, TUE paperwork. "I didn't mean
  to" cannot win, because intent is irrelevant under §8 and the minimum is fixed.
- Separate track: an **Appeals Settlement Committee** (Commissioner + NFLPA Executive Director or designees)
  can resolve any appeal, finally and bindingly, on "extraordinary circumstances" — the negotiated-settlement
  escape hatch, and the likeliest explanation for off-schedule outcomes.
- A narrow **Due Process Appeal** to the CBA Article 15 Appeals Panel exists for §5 (possession/distribution)
  cases only, on industrial-due-process grounds or disparate treatment. Standard of review: "clearly
  erroneous and in manifest disregard." Relief is a remand, not a reversal.

**Success rate `[LOW]` — no published statistic exists.** What the record supports:
- On *drug-policy* discipline specifically, the documented outcomes in this window are **upholds**
  (Johnson, Edelman), and the structural limits above make that the expected outcome.
- The famous NFL appeal reversals — Ray Rice, Adrian Peterson, Bountygate (Vilma/Hargrove/Smith/Fujita),
  Maurkice Pouncey's 3→2 games — are **Personal Conduct / Article 46** cases, a completely different track
  with a Commissioner-appointed hearing officer and no numeric floor. Do not import their reversal rate into
  a PED model.
- Aggregate `[LOW]`: since 2010, roughly "two indefinite suspensions overruled, two one-game bans
  eliminated, two multi-game suspensions reduced, plus all of Bountygate" — a handful across all categories
  across 15 years.

**Modelling recommendation:** appeal filed in maybe 40–60% of PED cases; appeal *outcome* ≈ 5–10% reduction
or vacatur, ~90%+ upheld; but appeal reliably **delays** the suspension by ~4 weeks in-season, which is
itself the main value and a nice game lever.

### 1.6 Policy drift, Dec 2024 `[HIGH]` (from the NFLPA side-by-side memo)

Changes effective 6 Dec 2024 to the PES policy:
1. **Testing window extended** — was "test within 3 hours of notification"; now, notified before morning
   activities → must test before afternoon activities; notified before afternoon activities → within 1 hour
   of the end of them.
2. **Reinstatement decoupled from a clean test** — previously a suspended player could not be reinstated
   until he tested negative. Now he is reinstated (and paid) "if the presence of a substance(s) provides no
   performance enhancing effect." This ends the pattern of suspensions silently extending past their nominal
   length while a long-half-life substance cleared.
3. **Missed tests reset to zero** after 365 days clean (previously cumulative for a whole career), and all
   then-pending missed-test discipline was excused.
4. **$15,000 fine** for recording/posting the sample-collection process on social media (previously
   undefined, "potential for large fines and possible suspension").
5. **Suspension start timing:** if discipline becomes final before 12:00 ET three days before the next game,
   the suspension starts that week; if after, it starts after the next game.

Missed-test discipline under the old PES text: 1st **$25,000 fine**, 2nd **2 game checks**, 3rd+ **2-game
suspension**; deliberate avoidance is punished as a positive test.

### 1.7 PED profile — who gets caught `[MED]`

Raw counts (USA Today Sports database, via NFL Draft Diamonds, Feb 2022):
- **258 PED suspensions since 2001**; **82 in the five years to early 2022** (≈16.4/yr).
- **Defensive linemen 57**, **linebackers 41** — the two largest raw blocks.
- **≥25 Adderall-attributed suspensions since 2009** — stimulants are a large minority of the total, not a
  footnote. Under the current ladder those are the *2-game* cases.
- Affects "every team and every position", including Pro Bowlers, QBs, long snappers and kickers.

Per-capita rates (Sports Illustrated 10-year study, published 2016) — **all** suspensions vs
**behaviour-only** suspensions, per player per year:

| Position | All suspensions | Behaviour-only | **PED-only (derived)** |
|---|---|---|---|
| DL | 1 in 45 | 1 in 76 | **1 in 110** |
| OL | 1 in 78 | 1 in 204 | **1 in 126** |
| LB | 1 in 57 | 1 in 97 | **1 in 138** |
| TE | 1 in 92 | 1 in 196 | **1 in 173** |
| DB | 1 in 59 | 1 in 83 | **1 in 204** |
| RB | 1 in 51 | 1 in 65 | **1 in 237** |
| WR | 1 in 42 | 1 in 48 | **1 in 336** |

The PED-only column is **my arithmetic** (`1/all − 1/behaviour`), so `[LOW]` — but it is internally
consistent with SI's own two tables and it produces the cleanest design rule in this whole document:

> **PED risk concentrates in the trenches (DL, OL, LB). Behaviour/substance risk concentrates at skill
> positions (WR, RB).** Weight the two event families in opposite directions across the depth chart.

SI also notes OL had only **30 suspensions in 10 years**, the fewest of any position group except QB and TE —
so OL are *rarely* suspended in raw terms but disproportionately for PEDs when they are.

Counter-signal `[LOW]`: self-reported anabolic steroid use among *retired* players runs **9.1% overall,
16.3% among OL, 14.8% among DL** — i.e. actual use is far above detected use, and the positional skew of
actual use matches the positional skew of PED suspensions. Useful if the game wants a hidden "using" flag
distinct from a "caught" event.

---

## 2. SUBSTANCES OF ABUSE — the 2020 discontinuity

### 2.1 Pre-2020 regime `[MED]`

A confidential three-stage Intervention Programme. Entry by positive test, by observed behaviour/symptoms,
or by self-referral. First positive did not itself trigger discipline — it triggered *entry*.

- **Stage One** — up to 90 days, individualised, testing plus possible treatment. Clean exit → released from
  the programme.
- **Stage Two** — continued treatment and unannounced testing; discipline (fines then game checks) for
  violations. Completing Stage Two discharges the player, who restarts at Stage One on any later violation.
- **Stage Three** — same treatment/testing obligations, but a violation meant a **one-year ban** — or a
  **10-game suspension** if the first Stage Three violation was for marijuana.

That third stage is what produced the multi-year career spirals of the 2010s. Marijuana was the dominant
driver, at a **35 ng/ml** THC positive threshold with year-round testing.

### 2.2 Post-2020 CBA regime `[HIGH]`

The March 2020 CBA rewrote it, and the change is drastic:

- **Suspensions for positive tests were abolished outright.** Stage Three was eliminated. Only two stages
  remain.
- **Testing window narrowed** from year-round to a strip between the start of preseason training and the
  first preseason game (widely described as "the first two weeks of training camp"). Miss that window and
  you cannot be caught for a year.
- **THC positive threshold raised 35 → 150 ng/ml.**
- **Stage One positive:** *no penalty at all* other than advancement to Stage Two.
- **Stage Two positive:** fines only. Original 2020 schedule: 1st ½ game check, 2nd 1 game check, 3rd 2 game
  checks, 4th+ 3 game checks — with the player **still eligible to play throughout**.
- Positive tests are reviewed by a jointly appointed board of medical professionals, who decide whether
  treatment is warranted. Clinical care replaced punishment as the organising principle.
- **A cooperating player can no longer be suspended or banished for testing positive, at any frequency.**

### 2.3 What can still suspend you under SOA `[HIGH]` (2024 policy text)

Three doors remain open, and only three:

**(a) Failure to cooperate with testing or clinical care**, in Stage Two:

| Violation # | Penalty |
|---|---|
| 1st | 1 week's salary |
| 2nd | 2 weeks' salary |
| 3rd | 3 weeks' salary |
| 4th | **3-game suspension** |
| 5th | **4-game suspension** |
| 6th | **8-game suspension** |
| 7th | **Banishment, indefinite, minimum one calendar year** |

**(b) Violations of law involving alcohol (§2.2).** Reviewed by the Commissioner. Absent aggravating
circumstances: **first offence = 3 games** without pay; **second or subsequent = 8 games**. Aggravators that
increase it: felonious conduct, **BAC ≥ 0.15%**, property damage, serious injury or death, or prior
drug/alcohol misconduct. Triggered by conviction *or* admission, explicitly including diversion programmes,
deferred adjudication and nolo contendere.

**(c) Violations of law involving other substances (§2.3).** First offence **up to 4 games**; second or
subsequent **6 to 10 games**. Same aggravator list. Treatment history may be considered.

So post-2020, an SOA suspension is essentially always **a legal event, not a lab event.** That is the single
cleanest way to model it: the drug test stopped being the trigger; the arrest report became the trigger.

### 2.4 Stage Two current discipline schedule `[HIGH]` (2024 text, post-Dec-2024 amendments)

| Trigger | 1st | 2nd | 3rd | 4th+ |
|---|---|---|---|---|
| Positive test | $15,000 | $20,000 | 1 week's salary | 2 weeks' salary |
| Unexcused failure to appear | $20,000 | $45,000 | 2 weeks' salary | 4 weeks' salary |
| Failure to cooperate | 1 wk salary | 2 wk | 3 wk | 3g / 4g / 8g susp → banishment (7th) |

Dec 2024 changes (side-by-side memo): **THC threshold 150 → 350 ng/ml**; clubs are no longer told *which*
substance caused a positive, only that there was a violation and what the penalty is; fentanyl testing
permitted where clinically indicated **with no discipline for a positive** (only a $15,000 fine for refusing
the mandatory meeting); missed-test counts reset after 365 clean days; all then-pending missed-test
discipline excused; the same 12:00-ET-three-days suspension-start rule as PES; clarified that concurrent
opiate prescriptions from two providers within 30 days without disclosure is a violation.

### 2.5 Banishment and reinstatement `[HIGH]`

Under the current SOA, banishment is indefinite with a **one-year minimum**. During banishment the player
**must still follow his treatment plan**, and **his NFL Player Contract is tolled** (it does not burn a year
— which is why long-suspended players return still under their old deal).

Reinstatement procedure (Appendix B):
- Apply in writing **no sooner than 60 days before the one-year anniversary** of the suspension's effective
  date.
- Application must document treatment, **abstinence across the entire banishment demonstrated by periodic
  toxicology testing**, any substance-related incidents, and any arrests/convictions.
- Player executes medical releases covering counselling attendance, 12-step attendance, progress reports and
  all diagnostic findings.
- Submits to testing at a frequency set by the Medical Advisor. He may *start* testing before applying, to
  build a clean history — a real strategic lever.
- Within **45 days**, Medical Director + Medical Advisor review (possibly interviewing him) and recommend to
  the Commissioner.
- Possible meeting with the Commissioner to negotiate conditions.
- Target decision **within 60 days** of the application.
- **On reinstatement the player is returned to Stage Two for the rest of his career**, subject to continued
  testing and *immediate rescission* on any further violation.

### 2.6 The long historical cases `[MED]`

The pre-2020 regime produced multi-year spirals that the current one structurally cannot. As mechanics
reference:

- **Josh Gordon (WR)** — the canonical case. 2 games (2013) → full season, reduced to 10 games (2014),
  reinstated Nov 2014 → year-long ban Jan 2015 (positive for **alcohol**, under the terms of his
  reinstatement) → first reinstatement application denied Jan 2016, reinstated Jul 2016 but still out
  4 games → 2017 spring application rejected, allowed back for the final 5 games → indefinite suspension
  Dec 2018 for violating reinstatement terms → indefinite suspension Dec 2019 under **both** the SOA and
  PES policies → reinstated Sep 2021. Missed all of 2015, 2016 (most), 2020, and large parts of several
  others. **Note: the 2020 CBA did not automatically reinstate him** — new policy, old discipline.
- **Aldon Smith (DE)** — full 2015 season; the 49ers later **sued** him and the Raiders to recover
  **$1,186,027** of a **$8,961,092** signing bonus after a nine-game 2014 suspension.
- **Martavis Bryant (WR)** — full 2016 season; **Darren Waller (TE)** — full 2017 season, second suspension;
  **Travis Henry (RB)** — 2008; **Dominic Rhodes (RB)** — 2011, third violation.
- **Jerrell Freeman (LB)** — 2-year banishment, 2018, third PED violation.
- **LaRon Landry** — never reinstated after multiple PED violations `[LOW]`.

Key design note: the **reinstatement-terms** mechanic is what made these spirals. A reinstated player is on
a hair trigger — a *legal* substance (alcohol) ended Gordon's 2015. That asymmetry ("clean bar is higher
after you come back") is the most interesting single rule in the whole SOA regime and is preserved in the
current policy's "returned to Stage Two for the remainder of his NFL career."

---

## 3. GAMBLING — the 2022–2024 wave

### 3.1 Current policy tiers `[HIGH]` (revised 29 Sep 2023, effective 2 Oct 2023)

The 2023 revision moved in **two directions at once**: harsher for betting on the NFL, materially softer for
betting on other sports from the workplace.

| Violation | Penalty |
|---|---|
| **Betting on your own team** | **minimum 2-year suspension** |
| **Betting on any NFL game** | **minimum 1-year suspension** (indefinite, ≥1 season) |
| **Fixing or attempting to fix a game** | **permanent banishment** |
| **Using/disclosing inside information for betting; betting through a third party (proxy)** | **indefinite, minimum 1 year** |
| **Betting on non-NFL sports from a club/league facility or while travelling with the team — 1st** | **2 games** (was 6) |
| — 2nd | **6 games** |
| — 3rd | **at least 1 year** |

Additional standing rules `[MED]`:
- **Players** may bet on non-NFL sports — but not from a facility, not while travelling with the team, and
  they may not enter a sportsbook during the playing season *even while injured*.
- **Coaches, club and league personnel** face a blanket prohibition: **no betting on any sport at all.**
- No daily fantasy sports.
- No accepting casino gifts over **$250**.
- An "Integrity of the Game" clause sits in the standard NFL Player Contract itself (predating all of this),
  giving the Commissioner the right to fine, suspend for a period certain **or indefinitely**, *and/or
  terminate the contract*, for betting on an NFL game or knowingly associating with gamblers.

### 3.2 Enforcement apparatus `[MED]`

Not testing — **surveillance and data feeds**:
- An **NFL Integrity Representative** assigned to every club, typically retired FBI or executive-level law
  enforcement, present on game day.
- **Genius Sports** and **IC360** monitor every game and key league events for betting anomalies and
  information leaks. This is how the 2023 wave surfaced: sportsbook account data, not confessions.
- Mandatory **in-person** gambling education for all players from 2024 (previously largely virtual);
  reported reach of **20,000+ league-affiliated individuals**.
- NFL/NCPG partnership extended, 3 years / **$6.4M**.

### 3.3 The wave, counted `[MED]`

| Year | Players suspended | Notes |
|---|---|---|
| 2015–2018 | **0** | |
| 2019 | **1** | Josh Shaw (CB, Cardinals) — indefinite, 29 Nov 2019, bet on NFL games while injured |
| 2020, 2021 | **0** | |
| 2022 | **1** player + 1 coach | Calvin Ridley (WR) suspended Mar 2022 for 2021 conduct; Miles Austin (Jets asst.) 1 year, Dec 2022, non-NFL betting |
| **2023** | **10** | the wave |
| 2024 | **0** | 5 reinstated Apr 2024; Uwazurike reinstated Aug 2024 |
| 2025 | **0** | |
| 2026 (to Aug) | **0 players**; 1 club executive | Ryan Gold, Cardinals dir. of college scouting — indefinite, 17 Jul 2026 |

The NFL's own August 2024 framing: **"10 players suspended for gambling violations last offseason"**, and
**no player suspended for gambling in the 13 months since.** As of mid-2026 the league counts **at least 15
players ever** suspended for gambling since 1963.

**The 2023 cohort in full:**

| Player | Pos | Team | Length | Conduct |
|---|---|---|---|---|
| Quintez Cephus | WR | Lions | indefinite (≥2023) | bet on NFL games, 2022 |
| C.J. Moore | S | Lions | indefinite | bet on NFL games, 2022 |
| Shaka Toney | DE | Commanders | indefinite | bet on NFL games, 2022 |
| Isaiah Rodgers | CB | Colts | indefinite | bet on NFL games, 2022 |
| Rashod Berry | DE/LB | Colts | indefinite | bet on NFL games, 2022 |
| Demetrius Taylor | DT | (FA, ex-Lions/Colts) | indefinite | bet on NFL games, 2022 |
| Eyioma Uwazurike | DE | Broncos | indefinite (~54 wks) | bet on NFL games incl. own; also at Iowa State |
| Jameson Williams | WR | Lions | 6 → **4** games | non-NFL bets from club facility |
| Stanley Berryhill | WR | Lions | 6 → **4** games | non-NFL bets from club facility |
| Nicholas Petit-Frere | OT | Titans | 6 → **4** games | non-NFL bets from club facility |

Announced in two batches: **five in April 2023** (Williams, Cephus, Berryhill, Moore, Toney) and **three in
July 2023** (Rodgers, Berry, Taylor), with Petit-Frere and Uwazurike alongside.

### 3.4 Reinstatement timelines observed `[MED]`

| Player | Suspended | Reinstated | Elapsed |
|---|---|---|---|
| Calvin Ridley | Mar 2022 | Mar 2023 (applied Feb 15 2023, first eligible day) | ~12 months |
| Jameson Williams / Petit-Frere / Berryhill | Apr–Jun 2023 | 2 Oct 2023 — **by policy revision, not petition** | 4 games served of 6 |
| Cephus, Moore, Toney, Berry, Taylor | Apr/Jul 2023 | 18 Apr 2024 | ~12 months |
| Eyioma Uwazurike | 24 Jul 2023 | Aug 2024 | **54 weeks** |
| Isaiah Rodgers | Jun 2023 | later than the other five (still suspended at the Apr 2024 batch) | >12 months |
| Josh Shaw | Nov 2019 | 2021 | ~2 seasons |

Pattern: **indefinite ≈ one calendar year in practice**, with the petition filed at the first eligible date
and granted at or shortly after the anniversary. Ridley's case shows the mechanic exactly: suspended
March 2022, first eligible to petition **15 Feb 2023**, petitioned that day, reinstated March 2023.

### 3.5 How teams reacted `[MED]`

This is the most game-relevant part, and the reaction was **not uniform** — it tracked player value:

- **Cut immediately.** The Colts **waived Rodgers and Berry the same day** the suspensions were announced.
  Rodgers was a starting-calibre CB. Taylor was already a free agent. Cephus and Moore were released by
  Detroit. By April 2024, of the five reinstated players, **only Toney was on an NFL roster.**
- **Kept and absorbed.** Detroit kept **Jameson Williams** — a 2022 first-round pick — through a 6-game (then
  4-game) suspension. He went on to a career year. Denver kept **Uwazurike** through a 54-week ban and
  reactivated him in 2024.
- **Traded while suspended.** Atlanta traded **Ridley** to Jacksonville in Nov 2022 *during* his indefinite
  suspension for a **2023 5th-rounder plus a conditional 2024 4th** — an asset trade on a player who could
  not play. His contract **tolled**, so Jacksonville acquired the 5th-year option year ($11.116M) intact.
- **Released after a short PED ban.** The Raiders released **Garoppolo** after his 2-game 2024 PED
  suspension; Miami released **Beckham** in Dec 2024, before the resulting suspension landed in Oct 2025.

**Rule of thumb for a sim:** value and draft capital, not the offence, determine survival. A 1st-round pick
or a starter with guaranteed money is retained; a rotational player or a UDFA is cut inside 24 hours.

### 3.6 Where gambling risk is heading `[MED]`

As of late 2025 / 2026 the NFL has avoided the federal-charge scandals that hit the NBA (Terry Rozier) and
MLB (Clase, Ortiz). The league's November 2025 memo to clubs bans four categories of prop bet with its
betting partners: inherently objectionable props (injuries, fan misconduct), officiating props, props
determinable by one person on one play (e.g. "first pass incomplete"), and predetermined events; and
designates prediction markets (Kalshi, Polymarket) as **prohibited gambling activity**. The July 2026
Cardinals case (leaking non-public 2026 draft information *plus* parlays on NFL and college games) is the
current shape of the risk: **front-office information leakage rather than player betting**. Worth a separate
staff-side event family in a management game.

Educational near-miss `[LOW]`: 2024 first-rounders Jayden Daniels and Malik Nabers disclosed a **$10,000**
wager between them on Offensive Rookie of the Year and received additional education sessions rather than
discipline — a nice model for a "warning" outcome tier.

---

## 4. CONSEQUENCES, QUANTIFIED

### 4.1 Games missed — distribution

**PED, current schedule (post-2021):**

| Games | Case type | Share of PED cases (est. `[LOW]`) |
|---|---|---|
| 2 | stimulant/diuretic/masking, 1st | ~35–45% (Adderall class is large) |
| 6 | anabolic, 1st | ~35–45% |
| 8 | manipulation / substance+masking / §5 | ~5% |
| 5 | stimulant class, 2nd | ~3% |
| 17 | anabolic class, 2nd | ~5% |
| ≥2 seasons | 3rd violation, banishment | ~1–2% |

Observed post-2021 examples: 2 games (Garoppolo 2024, Jameson Williams 2024, Drake Stoops 2025, Ronald
Jones 2023), 4 (Cam Robinson 2023), 6 (Isaac Alarcon 2025, Beckham 2025, Bobby Brown), 17 (Amani Bledsoe
2023), 2 years (Jerrell Freeman 2018).

**Pre-2021 PED:** overwhelmingly **4 games**, with 10 for second offences and 2 years for third.

**SOA:** post-2020, near-zero from testing. From law: 3 (alcohol 1st), 8 (alcohol 2nd), up to 4 (other
substances 1st), 6–10 (2nd+).

**Gambling:** bimodal. Either **2–6 games** (workplace, non-NFL) or **a full season / indefinite ≥1 year**
(betting on the NFL). Almost nothing in between. That bimodality is worth preserving.

### 4.2 Salary forfeited `[HIGH]` mechanics / `[MED]` figures

- **Base salary:** forfeited at **1/18th per game missed** (17-game season plus bye). Suspension is "without
  pay", period.
- Worked example: A.J. Bouye, $13.0M base in 2020 = $764,706/week; forfeited **$3.1M** for four games of a
  six-game PED ban.
- Lane Johnson forfeited **$421,875 of $675,000** (10 of 16 games).
- Calvin Ridley forfeited **$11.116M** — his entire 2022 fifth-year-option salary — which also came **off
  Atlanta's 2022 cap**.

- **Signing bonus / roster bonus / option bonus / reporting bonus:** forfeitable under **CBA Art. 4 §9**
  ("Forfeitable Breach"). Both the PES policy (§14) and the SOA policy (§3.3) explicitly invoke it and
  explicitly disclaim "facial invalidity" defences. Only *bonus* money is forfeitable this way — **not other
  salary**.
- Worked example: Aldon Smith — 49ers recovered **$1,186,027** of a **$8,961,092** signing bonus for a
  nine-game 2014 suspension (~13.2% of the bonus, roughly the fraction of the contract's games missed).
- **Guarantees can be voided outright.** Lane Johnson's suspension **nullified the guaranteed money** in a
  just-signed 5-year/$56M extension. This is the single largest financial consequence available and it is
  *contractual*, not disciplinary — standard NFL contracts contain guarantee-voiding language triggered by
  league discipline.

### 4.3 Roster and cap mechanics `[HIGH]`

- Player moves to **Reserve/Commissioner Suspended**. **Does not count against the roster limit** → the club
  signs a replacement immediately.
- Salary comes **off the cap** for the games missed (Ridley: $11.116M off Atlanta's 2022 cap).
- **The contract tolls during an indefinite suspension / banishment** — the year does not burn. A player
  suspended for a season returns with the same years remaining. This is why Ridley was still tradeable and
  why Jacksonville got a real asset.
- **Facility access** during a suspension `[MED]`: barred for the first half of the suspension; permitted for
  the second half to condition. May participate in preseason if the discipline predates final cutdowns; may
  not attend regular-season or postseason games.
- **Suspended-elsewhere clause (PES §15):** someone banned by another testing organisation (WADA lab
  positive, etc.) **may still sign an NFL contract** — but goes straight into reasonable-cause testing. So
  Olympic/other-league doping bans are *not* portable disqualifications.

### 4.4 Post-suspension performance `[LOW] — thinly documented`

No peer-reviewed study of NFL performance after PED/SOA suspension appears to exist. What can be said:

- The adjacent literature (return-to-play after time-loss events) finds a mean **−0.50 fantasy points/game**
  after a reported injury, worst at QB (−1.95 PPG) and WR (−0.33 PPG). That is *injury*, not suspension, and
  is at best a loose analogue for the conditioning/rhythm cost of missed time.
- Anecdotally the record is genuinely mixed and **does not support a blanket penalty**: Jameson Williams
  returned from a gambling suspension into his best season; Edelman returned from his 4-game 2018 ban and
  won Super Bowl LIII MVP; Uwazurike returned after 54 weeks and was described as "finally back in a groove"
  only in his *second* season back — i.e. a **two-year** re-acclimation for a long ban.
- The reliable effects are structural, not physiological: **lost snaps → lost depth-chart position → lost
  next contract**, plus the awards ineligibility rule (§1.2) which mechanically zeroes accolades for the
  season.

**Recommended model:** no direct rating hit for short suspensions (≤6 games); a **conditioning/rust** debuff
proportional to games missed that decays over ~4–8 weeks; a **larger, slower** recovery for bans of ≥1 season
(model 1.5–2 seasons to full form); and a persistent **market/reputation** penalty at the next contract that
is much larger than the on-field penalty.

### 4.5 Media arc `[MED]`

Highly stereotyped, and cheap to generate procedurally. Four beats:

1. **Break** — report of an impending suspension, usually before the league confirms; source "per league
   sources".
2. **Statement** — player's own words. Three stable templates: *denial-with-supplement* ("I would never
   knowingly…"), *acceptance-with-contrition* ("I take full responsibility"), or *minimisation* (Ridley's
   "I only bet 1500", tweeted).
3. **Institutional** — league confirmation with boilerplate about integrity; club statement, which is the
   real tell: "fully support the league's decision" (distancing → likely release) vs. "we'll support him
   through this" (retention).
4. **Resolution** — appeal upheld / accepted, and either release, trade, or quiet return.

Goodell's language for NFL-game betting is the strongest in the corpus: it "put the integrity of the game at
risk, threatened to damage public confidence in professional football" and is "among the most significant
violations of league policy."

---

## 5. BASE RATES

### 5.1 Denominators

| Pool | Size |
|---|---|
| Active rosters | 32 × 53 = **1,696** |
| + practice squads (16) | **2,208** |
| Offseason 90-man camps | 32 × 90 = **2,880** |
| Distinct players touching a roster in a league year `[LOW]` | ~**2,600–3,000** |

### 5.2 Per-league-year counts

| Category | Era | Suspensions/yr | Confidence |
|---|---|---|---|
| **PED** | 2017–2021 | **16.4** (82 / 5 yrs) | MED |
| **PED** | 2001–2021 mean | **12.3** (258 / 21 yrs) | MED |
| **PED** | 2022–2026 | ~**10–16** (visible cases; no aggregate published) | LOW |
| **SOA (suspensions)** | pre-2020 | ~**5–10** | LOW |
| **SOA (suspensions)** | post-2020 | ~**0–2** — legal-conviction cases only | MED |
| **Gambling** | 2015–2022 | **0–1** | HIGH |
| **Gambling** | 2023 | **10** | HIGH |
| **Gambling** | 2024–2026 | **0** players | HIGH |
| **Personal conduct** (context, out of scope) | steady | ~**3–6** | LOW |

Cross-check: of the 26 players suspended to start the **2018** season, **16 were PED**, **5 substance
abuse**, **2 personal conduct**, **2 combined**, **1 undisclosed**. Of the ~17 in the **2023** tracker,
**10 gambling**, **4 PED**, **3 personal conduct**, **0 SOA-positive**. The regime shift is visible in a
single table.

### 5.3 Per-player-season probabilities

Using **1,696 active** / **2,208 incl. PS** / **2,880 camp** as denominators:

| Event | /yr | p(active) | p(+PS) | p(camp) |
|---|---|---|---|---|
| PED suspension, any | 16 | **0.94%** | 0.72% | 0.56% |
| — 2-game (stimulant class) | ~6.5 | 0.38% | 0.29% | 0.23% |
| — 6-game (anabolic) | ~6.5 | 0.38% | 0.29% | 0.23% |
| — 8-game (manipulation) | ~0.8 | 0.05% | 0.04% | 0.03% |
| — 2nd violation (5 or 17 games) | ~1.5 | 0.09% | 0.07% | 0.05% |
| — 3rd violation (banishment) | ~0.3 | 0.018% | 0.014% | 0.010% |
| SOA suspension, post-2020 | ~1 | **0.06%** | 0.045% | 0.035% |
| SOA fine only (positive test, no games) | unpublished; likely 10–40 `[LOW]` | 0.6–2.4% | — | — |
| Alcohol-law suspension (3 or 8 games) | ~1–2 `[LOW]` | 0.06–0.12% | — | — |
| Gambling — baseline year | 0.5 | **0.03%** | 0.023% | 0.017% |
| Gambling — wave year (2023) | 10 | **0.59%** | 0.45% | 0.35% |
| Gambling — 12-yr mean (2015–2026) | 1.0 | **0.06%** | 0.045% | 0.035% |

### 5.4 Positional multipliers (apply to the PED base rate)

Derived from the SI table in §1.7, normalised so the league mean ≈ 1.0:

| Group | PED multiplier | Behaviour/SOA multiplier |
|---|---|---|
| DL | **1.55×** | 1.30× |
| OL | **1.35×** | 0.48× |
| LB | **1.24×** | 1.02× |
| TE | 0.99× | 0.50× |
| DB | 0.84× | 1.19× |
| RB | 0.72× | 1.52× |
| WR | 0.51× | **2.06×** |
| QB `[LOW]` | ~0.35× | ~0.6× |

(Multipliers are `[LOW]` — my arithmetic on SI's per-position rates, rounded. The *direction* is well
supported; the magnitudes are not precise.)

### 5.5 Other modifiers worth carrying

| Modifier | Effect | Basis |
|---|---|---|
| Prior positive (any) | ×5–15 detection rate — reasonable-cause pool, up to 24 tests/yr vs ~5–10 | HIGH (policy) |
| Positive at combine / in college ≤2 yrs pre-draft | enters league already in reasonable-cause pool | HIGH (policy) |
| Age / years of service | rising in years 1–3 (rookie ignorance, camp-body desperation), falling late | LOW |
| Returning from injury | ↑ PED (rehab shortcut motive); ↑ gambling (Ridley and Shaw both bet **while on injured/NFI status**) | MED |
| Reinstated from banishment | permanently in Stage Two, immediate rescission on any violation → ↑↑ re-offence consequence | HIGH (policy) |
| Big new contract signed | ↑↑ *cost* of a violation (voided guarantees), not ↑ probability | MED |
| Practice-squad / fringe roster | ↓ detection (fewer snaps of scrutiny) but ↑↑ roster consequence (cut same day) | MED |

### 5.6 Career-cumulative sanity check

At 0.94%/season over a 5-year career: **P(at least one PED suspension) ≈ 4.6%**. Over a 10-year career:
**≈ 9.0%**. Against 258 suspensions since 2001 and ~9.1% self-reported retired-player steroid use, that
lands in a plausible range — with the caveat that the *self-reported use* rate ≈ *lifetime caught* rate is
coincidence, not confirmation.

---

## 6. ARCHETYPAL CASE TEMPLATES

Eight anonymised templates. Each carries the real case(s) behind it as a citation only.

---

### A. "The Stimulant Two-Gamer"
**Frequency:** most common PED event. **Length:** 2 games. **Category:** stimulant (Adderall-class).

A starter tests positive off a prescription stimulant taken without a valid Therapeutic Use Exemption. He
misses two games at the top of the season, is back before Week 4, and it is forgotten by midseason. No cap
consequence worth noting; team keeps him without comment. **The paperwork, not the pharmacology, is the
offence** — a TUE would have made it legal.
*Grounding:* Jimmy Garoppolo, Raiders QB, 2 games, 2024 — "prescribed medication without a valid therapeutic
use exemption." Jameson Williams, Lions WR, 2 games, 2024. Drake Stoops, Rams, 2 games, 2025. ≥25
Adderall-linked suspensions league-wide since 2009.

**Game hooks:** a low-cost, high-frequency event. Good for texture. Should be *survivable* and slightly
comic. Optional pre-event: a "file for TUE" front-office action that removes the risk.

---

### B. "The Tainted Supplement Six"
**Frequency:** common. **Length:** 6 games (anabolic, 1st). **Category:** anabolic agent.

A veteran tests positive for elevated testosterone or an obscure peptide. He names an over-the-counter or
online product and insists he never knowingly took anything. Strict liability (§8: "players are responsible
for what is in their bodies") makes the defence unwinnable. He either appeals — buying ~4 weeks of playing
time before the arbitrator upholds it — or accepts and takes the six.
*Grounding:* Odell Beckham Jr., 6 games, announced Oct 2025 for a 2024 test, elevated testosterone, did not
appeal. Isaac Alarcon, 49ers OT, 6 games, 2025. Bobby Brown III, Rams DL. Patrick Peterson, 6 games, 2019.

**Game hooks:** the appeal decision is a real choice — delay vs. reputation. Model the ~90% uphold rate
honestly and let the player learn it.

---

### C. "The Second Strike"
**Frequency:** ~1–2/yr. **Length:** 10 games (pre-2021) or **17 games** (current, anabolic class).
**Category:** repeat PED.

A high-value lineman with a prior violation tests positive again — often within a year of signing a large
extension. The suspension **voids the guaranteed money** in the new deal, which costs him more than the
forfeited game checks. Appeal is heard and upheld. He returns; the club keeps him because the guarantees are
gone and the deal is now team-friendly. He is in the reasonable-cause pool for the rest of his career, tested
up to 24× a year.
*Grounding:* Lane Johnson, Eagles OT, 10 games 2016 (2nd violation): forfeited $421,875 of $675,000 base;
suspension nullified guarantees in a new 5yr/$56M extension; upheld by arbitrator James Carter, 11 Oct 2016.
Jalen Collins, 10 games 2018. Amani Bledsoe, 17 games 2023. Nick Boyle, 10 games.

**Game hooks:** the cleanest illustration of "the money consequence dwarfs the games consequence." Should
visibly rewrite the contract in the cap screen.

---

### D. "The Banishment Spiral"
**Frequency:** rare and, under the current CBA, **structurally near-extinct.** **Length:** multiple seasons.
**Category:** repeat substances of abuse, pre-2020 rules.

A gifted skill player enters the intervention programme early, escalates through the stages, and is banned
for a year. He is reinstated on conditions — and those conditions are stricter than the base policy, so a
*legal* substance (alcohol) can end him. He re-offends, is banished again, applies for reinstatement, is
denied, applies again, is granted, plays a handful of games, and repeats. Net: three or four lost seasons and
a career that never matches the talent.
*Grounding:* Josh Gordon — 2 games (2013) → season/10 games (2014) → year-long ban (2015, positive for
alcohol under reinstatement terms) → denied Jan 2016, reinstated Jul 2016 → denied spring 2017, back for 5
games → indefinite Dec 2018 → indefinite Dec 2019 (SOA **and** PES) → reinstated Sep 2021. Also Martavis
Bryant (2016), Darren Waller (2017), Aldon Smith (2015).

**Game hooks:** if the game is set post-2020, this arc should be *unavailable via testing* and only reachable
through the law-violation door (§2.2/2.3) or repeated failure-to-cooperate. Making it rare is historically
correct. If the game offers historical eras, the pre-2020 rules make it a genuine roster hazard.

---

### E. "The DUI Three-Gamer"
**Frequency:** ~1–2/yr `[LOW]`. **Length:** 3 games (8 if repeat; more with aggravators).
**Category:** violation of law involving alcohol.

An arrest in the offseason. The league waits for the legal outcome — and takes a diversion programme,
deferred adjudication or nolo contendere as sufficient. Absent aggravators the discipline is 3 games. If BAC
was ≥0.15%, or there was property damage, injury or a prior drug/alcohol history, it goes up sharply.
*Grounding:* SOA policy §2.2 verbatim. This is the door that stayed open after 2020 — the positive test
stopped mattering, the police report did not.

**Game hooks:** the lag between incident and discipline (legal process) is the interesting part. A club may
have to decide whether to re-sign a player whose suspension length is not yet known.

---

### F. "The Rookie Who Bet From the Facility"
**Frequency:** the workplace-gambling tier; 3 cases in 2023, 0 since. **Length:** **2 games** now (was 6).
**Category:** non-NFL betting from a club facility.

A young player, often a rookie, puts a legal bet on a *different* sport — basketball, college — from inside
the team building or on a team flight. The bet itself is legal in his state; the *location* is the offence.
Integrity monitoring flags the account. Under the pre-October-2023 rules this was 6 games; the revision cut
it to 2 and retroactively released the players already serving.
*Grounding:* Nicholas Petit-Frere (Titans OT), Jameson Williams and Stanley Berryhill (Lions) — all 6 games,
all reduced to 4 games served when the policy changed on 2 Oct 2023. Current tier: 2 / 6 / ≥1 year.

**Game hooks:** the most "unfair-feeling" event in the set, and therefore memorable. Excellent as a low-stakes
teaching event for a young player, with a rules-education follow-up that reduces future risk (mirrors the
NFL's mandatory in-person training and the Daniels/Nabers warning).

---

### G. "The Season Gone"
**Frequency:** rare; 7 cases in 2023, ~1/decade otherwise. **Length:** indefinite, ≥1 season; **2 years** if
he bet on his own team. **Category:** betting on NFL games.

A rotational player — often on injured reserve, often bored — bets on NFL games, sometimes including his own
team's. Sportsbook data surfaces it months later. He is suspended indefinitely through at least the end of
the season. **He is waived within 24 hours.** He petitions at the one-year mark and is reinstated ~12 months
after suspension, but most never play again: of five reinstated together in April 2024, only one was on a
roster.
*Grounding:* Isaiah Rodgers and Rashod Berry — **waived by the Colts the same day**. Quintez Cephus, C.J.
Moore, Shaka Toney, Demetrius Taylor — reinstated 18 Apr 2024, only Toney rostered. Eyioma Uwazurike — bet
on games he played in, at Iowa State and Denver; 54 weeks; Denver kept him. Josh Shaw — bet while injured,
Nov 2019, ~2 seasons out.

**Game hooks:** the single most destructive event in the set, and the reaction should be **value-gated**: a
first-round pick survives it, a rotational player does not. Model the waive decision as an AI/GM choice, not
an automatic consequence.

---

### H. "The Star Who Bet $1,500"
**Frequency:** once. **Length:** full season. **Category:** betting on NFL games, high-profile.

An established starter, away from the facility on a non-football-injury/mental-health list, places small
parlays over five days on his own phone — including on his own team. Total stake: $1,500. The investigation
finds no inside information used, no game compromised, nobody else aware. He is suspended for the entire
following season anyway, because the *category* of the offence, not the *scale*, sets the penalty. He
forfeits **$11.116M**, which also comes off his club's cap. His contract **tolls**, so he remains a tradeable
asset — and is traded mid-suspension for real draft capital. He petitions on the first eligible day and is
reinstated a year later.
*Grounding:* Calvin Ridley — bets Nov 2021, suspended 8 Mar 2022, traded to Jacksonville Nov 2022 for a 2023
5th + conditional 2024 4th, eligible to petition 15 Feb 2023, petitioned that day, reinstated Mar 2023.
Tweeted "I bet 1500". Goodell: betting on NFL games is "among the most significant violations of league
policy."

**Game hooks:** the proportionality gap (small stake, maximal penalty) is the emotional core. Also the best
demonstration of contract tolling — the trade-a-suspended-star mechanic is genuinely fun and genuinely real.

---

### I. "The Front-Office Leak" *(staff-side, current risk shape)*
**Frequency:** emerging; 1 case, 2026. **Length:** indefinite. **Category:** inside information + betting.

A long-tenured scouting executive passes non-public draft information before picks are announced and also
places parlays on NFL and college games. Note that **league and club personnel may not bet on any sport at
all** — a rule strictly tighter than the players'. Suspended indefinitely; club issues a
"we fully support the league's decision" statement and isolates it as "a single employee."
*Grounding:* Ryan Gold, Cardinals director of college scouting, suspended 17 Jul 2026, 13th season with the
club, appealing.

**Game hooks:** if the game models a front office, this is the staff-side analogue — and the current one, as
player gambling cases have been zero since 2023.

---

### J. "The Career-Ending Third Strike"
**Frequency:** ~0.3/yr. **Length:** banishment, ≥2 seasons (PED) or ≥1 year (SOA).
**Category:** third PED violation.

A veteran on his third violation is banished for at least two seasons. He may petition after 24 months, but
reinstatement is "solely within the Commissioner's sound discretion" and at that age it is effectively
retirement. Some are never reinstated.
*Grounding:* Jerrell Freeman, LB, 2-year banishment 2018, third violation, retired. LaRon Landry, never
reinstated after multiple violations `[LOW]`. PES §6 Step Three verbatim.

**Game hooks:** the terminal state. Rare enough that it should feel like a genuine shock, and it should
generate a real retirement-decision moment rather than a silent roster removal.

---

## 7. DESIGN RECOMMENDATIONS — condensed

1. **Three separate generators, not one.** PED = per-test Poisson. SOA = law-event driven post-2020. Gambling
   = rare cluster with an occasional multi-player "wave" year.
2. **Model the test, not the suspension.** Give each player ~5–10 test events a season at ~0.1–0.2% detection.
   A prior positive moves him to a reasonable-cause pool with 3–5× the test count — permanently. That single
   feedback loop reproduces the real repeat-offender distribution without hard-coding it.
3. **Trenches vs. skill split.** PED risk: DL 1.55×, OL 1.35×, WR 0.51×. Behaviour risk: WR 2.06×, RB 1.52×,
   OL 0.48×. Opposite gradients.
4. **Make the money the punishment.** 1/18th base per game is the small number. Voided guarantees and
   forfeited signing-bonus proration are the large ones. Show them in the cap screen.
5. **Contracts toll during indefinite suspensions.** Do not burn the year. This preserves trade value and
   creates the best strategic decision in the whole system.
6. **Suspended players free a roster spot.** Reserve/Suspended does not count against the limit — so a
   suspension is cheap for the club and expensive for the player. That asymmetry drives the cut decisions.
7. **The awards lockout.** Suspended = ineligible for the Pro Bowl, MVP, OPOY/DPOY, ROY, CPOY and the rest for
   that whole season. Cheap to implement, disproportionately painful, historically exact.
8. **Appeals delay, they rarely reverse.** ~4 weeks of continued play, ~90% uphold. Offer it as a real choice
   with an honest payoff table. Add the 50% cooperation discount as a rarer, morally interesting branch.
9. **Reinstatement is a process, not a timer.** 60-days-early application window, 45-day medical review,
   60-day decision target, conditions attached, and permanent Stage Two status afterwards. The "clean bar is
   higher after you return" rule is the most narratively productive line in the policy.
10. **Club reaction should be value-gated.** First-round pick with guarantees → retained. Rotational player →
    waived same day. Star on a tolling contract → traded.

---

## 8. SOURCES

**Primary policy documents (downloaded, extracted locally):**
- NFL Policy on Performance-Enhancing Substances, 2022 edition (2021 text) — https://nflpaweb.blob.core.windows.net/website/Departments/Legal/2022-Policy-on-Performance-Enhancing-Substances.pdf
- NFL Policy and Program on Substances of Abuse, 2024 (updated 2 Dec 2024) — https://nflpaweb.blob.core.windows.net/website/Departments/Legal/2024-NFL-Policy-and-Program-on-Substances-of-Abuse-updated-Dec-2-2024.pdf
- NFL Policy and Program on Substances of Abuse, 2023 — https://nflpaweb.blob.core.windows.net/website/SOA-Policy-2023.pdf
- NFLPA, "Summary of Changes to the SOA and PES Policies" side-by-side comparison, 2024 — https://nflpaweb.blob.core.windows.net/website/Departments/Legal/Drug-Policy-Changes-Side-by-Side-Comparison-2024.pdf
- NFLPA Drug Policies hub — https://nflpa.com/active-players/drug-policies

**Policy change coverage:**
- ESPN, NFL/NFLPA agree to changes to drug policies (Dec 2024) — https://www.espn.com/nfl/story/_/id/42782846/nfl-players-association-agree-changes-drug-policies
- Pro Football Rumors, NFL relaxes policies on substance abuse / PES — https://www.profootballrumors.com/2024/12/nfl-relaxes-policies-on-substance-abuse-performance-enhancement-substances
- Marijuana Moment, NFL adopts new marijuana policy — https://www.marijuanamoment.net/nfl-adopts-new-marijuana-policy-for-players-reducing-fines-and-increasing-thc-limit-for-drug-tests/
- NBC Sports PFT, New CBA removes all substance-abuse suspensions for positive drug tests — https://www.nbcsports.com/nfl/profootballtalk/rumor-mill/news/new-cba-removes-all-substance-abuse-suspensions-for-positive-drug-tests
- NFL.com, NFL/NFLPA agree to modifications on SOA and PES policies — https://www.nfl.com/news/nfl-nflpa-agree-to-modifications-on-substances-of-abuse-performance-enhancing-substances-policies

**Gambling:**
- ESPN, NFL toughens penalties for bets on own team (Sep 2023) — https://www.espn.com/nfl/story/_/id/38521972/nfl-toughens-bets-own-team-new-gambling-policy
- Pro Football Network, NFL gambling policy — https://www.profootballnetwork.com/nfl-gambling-policy/
- Birches Health, NFL Gambling Policy 2025 — https://bircheshealth.com/resources/nfl-gambling-policy
- NFL.com, NFL suspends four players for violating gambling policy — https://www.nfl.com/news/nfl-suspends-four-players-for-violating-league-gambling-policy
- NFL.com, NFL reinstates five players suspended indefinitely — https://www.nfl.com/news/nfl-reinstates-five-players-who-were-suspended-indefinitely-for-violation-of-gambling-policy
- NFL.com, NFL reinstating Jameson Williams, Nicholas Petit-Frere — https://www.nfl.com/news/nfl-reinstating-jameson-williams-nicholas-petit-frere-gambling-policy-changes
- NFL.com, NFL increases gambling policy education / integrity monitoring — https://www.nfl.com/news/nfl-increases-gambling-policy-education-integrity-monitoring-efforts-following-successful-offseason
- LiveNOW from FOX, List of NFL players suspended for violating gambling policies — https://www.livenowfox.com/news/list-nfl-players-suspended-for-violating-gambling-policies
- NFL.com, Calvin Ridley suspended indefinitely — https://www.nfl.com/news/falcons-wr-calvin-ridley-suspended-indefinitely-through-2022-season-for-betting-
- GrayRobinson, "Why Calvin Ridley's Betting Resulted in a Season-Long Suspension" — https://www.gray-robinson.com/docs/Calvin-Ridleys-Suspension-Explained.pdf
- ESPN, NFL suspends Cardinals executive for violating gambling policy (Jul 2026) — https://www.espn.com/nfl/story/_/id/49386067/nfl-suspends-cardinals-executive-violating-gambling-policy
- ESPN, In memo, NFL details efforts to curb prop betting (Nov 2025) — https://www.espn.com/nfl/story/_/id/46957763/in-memo-nfl-details-efforts-curb-prop-betting-light-wider-gambling-probes
- ESPN, Broncos' Eyioma Uwazurike reinstated — https://www.espn.com/nfl/story/_/id/40734524/broncos-eyioma-uwazurike-reinstated-gambling-suspension

**Counts, rates and cases:**
- NFL Draft Diamonds, "Over the past 5 years there have been 82 suspensions in the NFL for PEDs" (USA Today Sports database) — https://nfldraftdiamonds.com/2022/02/performance-enhancing-drugs/
- Sports Illustrated, "Offensive Linemen: A Character Study" (per-position suspension rates) — https://www.si.com/nfl/2016/05/18/offensive-lineman-nfl-player-conduct-laremy-tunsil-richie-incognito
- FHE Health, "National Football League Drug Policy: Unresolved Issues" — https://fherehab.com/survey/nfl-drug-policy/
- Pro Football Rumors, "26 NFL Players Suspended To Start Season" (2018) — https://www.profootballrumors.com/2018/07/nfl-players-suspended-players-2018
- CBS Sports, 2023 NFL suspension tracker — https://www.cbssports.com/nfl/news/2023-nfl-suspension-tracker-a-look-at-alvin-kamara-and-other-players-set-to-miss-time-this-season-and-why/
- NBC Philadelphia, NFL players who have received season-long suspensions — https://www.nbcphiladelphia.com/news/sports/nfl/nfl-players-who-have-received-season-long-suspensions/3594608/
- ESPN, Lane Johnson 10-game suspension upheld — https://www.espn.com/nfl/story/_/id/17769925/10-game-suspension-upheld-philadelphia-eagles-ot-lane-johnson
- ESPN, Odell Beckham Jr. accepts 6-game PED suspension — https://www.espn.com/nfl/story/_/id/46522525/odell-beckham-jr-says-accepts-6-game-ped-suspension
- NFL.com, Julian Edelman won't sue over 4-game PED suspension — https://www.nfl.com/news/julian-edelman-won-t-sue-over-4-game-ped-suspension-0ap3000000941196
- NBC Sports Boston, Josh Gordon timeline — https://www.nbcsports.com/boston/patriots/josh-gordon-timeline-wr-has-long-troubled-substance-abuse-history
- Behind the Steel Curtain, NFL substance abuse policy explainer (pre-2020 stages) — https://www.behindthesteelcurtain.com/pittsburgh-steelers-nfl-features-news-blog-long-form/2015/8/28/9218621/what-you-need-to-know-about-the-nfls-substance-abuse-policies-martavis-bryant-steelers
- Pro Football Network, How do NFL suspensions work — https://www.profootballnetwork.com/how-do-nfl-suspensions-work/
- Over the Cap, CBA Article 4 Section 9 (forfeitable breach) — https://overthecap.com/collective-bargaining-agreement/article/4/section/9
- Over the Cap, Contract lessons from Myles Garrett's suspension — https://overthecap.com/contract-lessons-learned-from-myles-garretts-suspension
- Harvard Football Players Health Study, Ch. 4 (league drug policies compared) — https://footballplayershealth.harvard.edu/wp-content/uploads/2017/05/08_Ch4_Drugs.pdf
- Syracuse Law Review, "Is There Something Arbitrary about the NFL's Arbitration Process?" — https://lawreview.syr.edu/nfl-arbitration-process/
- Boston.com, NFL suspensions overturned or reduced in the Goodell era — https://www.boston.com/sports/new-england-patriots/2015/05/12/nfl-suspensions-that-have-been-overturned-or-reduced-in-the-goodell-era/

---

## 9. GAPS AND CAVEATS

1. **No published year-by-year PED suspension count exists.** The 82-in-5-years and 258-since-2001 figures
   come from a USA Today Sports database reported secondhand in Feb 2022. Everything after that is
   case-by-case. The ~16/yr figure is the most defensible single number.
2. **Spotrac's suspension trackers (2023–2025) block automated fetching (HTTP 403)** — they are the best
   remaining source for exact per-year counts and forfeited-salary figures and would repay a manual visit.
3. **The 4-games-vs-2/6/8 regime boundary is inferred**, not confirmed from a primary pre-2021 policy text.
   The observed data fits it cleanly but I did not retrieve the 2014–2020 PES policy PDF.
4. **No appeal success-rate statistic is published by anyone.** The ~90% uphold estimate is reasoning from
   the arbitrator's structural constraints plus the documented cases, not from data.
5. **SOA fine counts post-2020 are entirely unpublished.** Since fines are confidential and clubs are no
   longer even told the substance, the true positive-test rate under the current regime is unknowable from
   outside. My 10–40/yr estimate is a guess.
6. **Post-suspension performance is genuinely undocumented.** The injury-return literature is the only
   quantitative anchor and it is a weak analogue. Treat §4.4's recommendation as design judgement, not
   research.
7. **Web search budget was exhausted mid-research** (200/200 calls); the last third of the work was done via
   direct WebFetch on URLs already surfaced plus local PDF extraction. Coverage of 2025–2026 player-level
   cases is therefore thinner than 2015–2024.
