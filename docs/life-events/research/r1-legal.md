# R1 — Legal Incidents & League Discipline (NFL, 2015–2026)

**Purpose:** empirical grounding for a **fictional** "life events" system in an iPad NFL-management game.
Real names appear **only as citations behind anonymized patterns**. All shipped game content must be fully fictionalized
(the project's trademark guard already forbids real player/team/league marks in game data).

**Research date:** 2026-08-14. **Coverage:** 2015–2026, with pre-2015 baselines for trend.

**Confidence key:** `[A]` directly sourced · `[B]` derived/computed from sourced numbers · `[C]` synthesized estimate ·
`[D]` qualitative pattern, no hard number found · `[P]` primary document extracted directly (policy PDF, executed CBA,
federal statistical report) · `[S]` reputable secondary · `[U]` **untraceable — do not use**.

> ### ⚠️ Read this before using any number below
> **Two parallel arrest series exist and they disagree by up to 2× in the same year.**
> - **NFL-internal series** (reported via ESPN, Oct 2024): 2015 = 42, 2016 = 40 … 2023 = 38.
> - **Media-derived series** (USA TODAY / San Diego Union-Tribune database, built from press coverage):
>   2015 = 35 ("lowest on record since 2000"), 2016 = 26.
>
> Pick one and stay inside it. Mixing them produces false conclusions — I made exactly that error on the
> seasonality question in a first pass (dividing a media-series offseason count by an NFL-series annual total made the
> offseason look flat when it is not). **This document standardises on the NFL-internal series for annual volume
> and the USA TODAY database for composition/seasonality**, and flags every crossover.

---

## 0. TL;DR design numbers

| Quantity | Value | Conf |
|---|---|---|
| League-wide arrests/charges per calendar year, 2015–2023 (NFL series) | **38.6 mean · 38 median · SD ≈ 8.0 · range 28–53** | [A]/[B] |
| Same, 2011–2014 (pre-policy-revision baseline) | **70.5 mean** (74 / 68 / 72 / 68) | [A] |
| Decade trend | **−52%**: 71/yr (2011–13) → 34/yr (2021–23) | [A] |
| Recommended in-season denominator (53-man + 17 PS) × 32 | **2,240 players** | [A]/[B] |
| **P(incident) per player-season, modern era** | **1.5%** (1 in 66) using 34/yr ÷ 2,240 | [B] |
| Same, 53-man-only denominator | 2.0–2.3% (1 in 40 to 1 in 50) — the widely quoted "1 in 40" | [A] |
| Same, 90-man offseason rosters (2,880) | 1.2% | [B] |
| Career-lifetime prevalence | **6.8% of all NFL players are arrested at least once** (574 / 8,454, 2000–2014) | [A] |
| Repeat split among arrested players | **77% once · 16% twice · 7% three-plus** | [A] |
| Violent share of arrests | **27%** (209 / 774) | [A] |
| Single most common charge | **DUI, 28.3%** of all incidents (202 / 713) | [A] |
| Conviction rate, violence-against-women arrests | **17.9%** (21 of 117, 2000–2019) | [A] |
| Personal Conduct Policy baseline for assault / DV / sexual assault | **6 games** (since Dec 2014) | [A] |
| Modal actual league outcome of an arrest | **0 games** — most arrests produce no suspension at all | [B] |
| Incidents per team per year | **1.21** → 30% of teams have a clean year, 12.2% have 3+ | [B] |
| Offseason : in-season monthly rate ratio | **~2× (recommended)** — historically 3–4×, modern data flatter | [A]/[C] |

---

## 1. TAXONOMY OF LEGAL INCIDENTS

### 1.0 The reference composition table

**Source of truth for composition: USA TODAY NFL arrests database, 2000 – 10 Sep 2014, n = 713, as tabulated by
the NYT Upshot.** `[A]` This is the only clean, published, full category breakdown found.

| Charge | Count | Share |
|---|---:|---:|
| **DUI** | **202** | **28.3%** |
| Assault & battery (non-domestic) | 88 | 12.3% |
| **Domestic violence** | **85** | **11.9%** |
| Drug-related | 82 | 11.5% |
| Disorderly conduct | 43 | 6.0% |
| Gun-related | 38 | 5.3% |
| Alcohol, non-DUI | 35 | 4.9% |
| Burglary / theft | 21 | 2.9% |
| Sexual assault | 10 | 1.4% |
| Murder / manslaughter | 7 | 1.0% |
| Animal abuse | 6 | 0.8% |
| Residual (other / multi-charge) | ~96 | 13.5% |

Corroborations `[A]`: the top three families (DUI + assault/battery incl. DV + drug possession) = **72%** of all
incidents through Jul 2013; a 2000–2024 cut (n = 1,065) still puts **DUI first at 23.9% (247)**; the Goodell-era cut
(2006 – Oct 2014) gives DUI 118, drugs 61, assault/battery 60, DV 46 — same ordering.

**⚠️ One widely-linked source must be rejected:** SporViz's timeline reports Gun-Related **254** and Theft/Burglary
**200** against the NYT's 38 and 21. Those are almost certainly miscategorised multi-charge rows. Do not use.

### 1.0b Modern-era (2015–2026) adjusted mix — recommended generator weights

The 2000–2014 table needs three structural adjustments before it describes the present: **guns up**, **drugs down**
(the 2020 CBA removed the suspension consequence and narrowed testing), **DV flat-to-up** against a falling total.

| Category | Share `[C]` | Events / league-year at λ=38 `[B]` | P per player-season (n=2,240) `[B]` |
|---|---:|---:|---:|
| DUI / impaired driving | 26% | 9.9 | 0.44% |
| Domestic violence | 14% | 5.3 | 0.24% |
| Assault / battery (non-domestic) | 12% | 4.6 | 0.20% |
| Weapons charges | 12% | 4.6 | 0.20% |
| Drug possession | 9% | 3.4 | 0.15% |
| Disorderly conduct / public intox / alcohol | 9% | 3.4 | 0.15% |
| Theft / burglary / fraud | 4% | 1.5 | 0.07% |
| Reckless driving / street racing / fleeing | 4% | 1.5 | 0.07% |
| Sexual misconduct (criminal) | 2% | 0.8 | 0.03% |
| Homicide / vehicular homicide | 1% | 0.4 | 0.02% |
| Animal-related | 0.8% | 0.3 | 0.014% |
| Other / resisting / misc | 6.2% | 2.4 | 0.11% |

**Cross-checks that validate the adjustments `[A]`:** weapons at 12% → 4.6/yr sits against an observed
**17 gun arrests in the 39 months Mar 2020 – Jun 2023 (5.2/yr)**. DV at 14% → 5.3/yr sits against
**6.1/yr DV cases reported to the league, 2015–2023**. Both land inside a game-year of the observed value.

---

Each category below gives the **arrest → charge → resolution** pipeline with real durations, plus the game hooks.

### 1.1 DUI / impaired driving — the workhorse category

- **Prevalence:** the largest single charge type across the database's entire run — **28.3%**, and still #1 in the
  2000–2024 cut at 23.9%. `[A]` Roughly **10 per league-year** in the modern era. `[B]`
- **Pipeline:**
  - Arrest typically 12am–4am, player alone in his own vehicle. Booked, released on bond within hours.
  - An **administrative licence suspension often runs in parallel and bites immediately** (days), independent of the
    criminal case — a nice detail: the consequence lands long before the verdict.
  - Arraignment within 48–72h if held; a few weeks if released on bond (the normal case for an NFL player). `[A]`
  - **Resolution: 3–6 months typical** for a misdemeanour DUI; up to ~12 months in high-caseload urban courts;
    as fast as ~1 month on a standard plea offer. `[A]`
  - Typical ending: plea to DUI or a reduced "wet reckless", fine, 12 months probation, alcohol class, community
    service, ignition interlock. Jail rare on a first offence.
- **League response:** almost never a Personal Conduct suspension for a *first* DUI without injury. The alcohol track
  lives in the Substances of Abuse programme — **3 games first alcohol violation, 8 games subsequent** `[A]` — but in
  practice most first DUIs yield a fine and a programme referral, not games. `[C]`
- **Escalation branch — DUI with injury/death:** flips to felony, multi-year case, near-certain release within days,
  career over. Sourced: a WR's 156-mph drunk crash killing another driver → guilty plea → **3-to-10 years state
  prison**; released by his team **the same day**. `[A]`
- **Rate check vs population `[A]`:** NFL DUI arrests run **8.3 per 1,000 players/yr** vs **4.6** for the whole US
  population (+81%) but **9.4** for US adult males (−11%). NFL players are *not* unusual DUI offenders for their
  demographic; they are unusual only relative to the population average.
- **Game hook:** high frequency, low consequence, 1–3 day media arc. Meaningful only in aggregate (repeats) or when
  it lands on a cutdown date.

### 1.2 Domestic violence — the high-drama category

- **Prevalence:** **11.9%** historically `[A]`, ~14% modern `[C]`; **6.1 cases reported to the league per year on
  average, 2015–2023** (range 3–11). `[A]` Note the divergence between "arrests" and "reported to the league" —
  civil suits and non-arrest allegations enter league process without ever entering an arrest database.
- **Pipeline:**
  - Police called by partner, neighbour, or hotel/venue staff. Arrest often **mandatory** under state
    mandatory-arrest statutes regardless of the complainant's wishes.
  - Charge: usually misdemeanour assault-family-violence. **Strangulation / impeding breath is the standard felony
    upgrade** and is the single most predictive detail for "this becomes a big story."
  - **80–90% of DV complainants recant** at some point. `[A]`
  - Dismissal: ~15% of felony and ~30% of misdemeanour family-violence cases dismissed (Texas); 3%–31% depending on
    jurisdiction (San Diego). Many jurisdictions run **no-drop policies** — the prosecutor, not the complainant, owns
    the decision, so "she dropped the charges" is usually wrong as written. `[A]`
  - **Resolution: 4–12 months.** Half of felony cases disposed within 3.5 months; cases reaching trial run
    **7.1–7.4 months arrest → disposition**. `[A]`
  - Very common NFL endings: charge dropped when the complainant relocates or won't testify; pre-trial
    diversion/intervention with the record sealed on completion; acquittal at trial.
- **League response:** **6-game baseline** under the Dec-2014 policy, adjustable up (indefinite / banishment) or down.
  `[A]` The **Commissioner Exempt List** (paid, off the roster count, barred from facility and games) is the holding
  pen while a criminal case runs. `[A]`
- **Conviction reality — the most important single number in this file:**
  **21 of 117 (17.9%)** VAW-arrested players 2000–2019 were found guilty. 4 of those pleaded to a lesser crime;
  only **6 served prison time**. `[A]` **The modal legal outcome of a DV arrest is no conviction.**
- **Composition insight `[A]`:** DV is **48%** of NFL players' violent-crime arrests vs **21%** nationally — but the
  NFL's DV arrest *rate* is only **~55%** of the general-population rate for men 25–29. NFL players commit far fewer
  violent crimes overall; DV is a large slice of a small pie. *(Medium confidence — the FiveThirtyEight source is now
  delisted and these figures come via secondary summaries.)*
- **Game hook:** long arc (months), a league investigation running independently of the courts, exempt-list limbo, and
  the sharpest star-vs-depth divergence in team response.

### 1.3 Assault / battery (non-domestic)

- **Prevalence: 12.3%** — the #2 category. `[A]` ~4.6/yr. Bar fights, valet and nightclub altercations, road rage,
  disputes with security.
- **Pipeline:** misdemeanour simple assault → citation or overnight booking → 2–5 months → very often dismissed,
  diverted, or pleaded down to disorderly conduct. Felony aggravated assault (weapon, serious bodily injury) follows
  the 4–12 month felony track.
- **League response:** nominally the same 6-game baseline (the policy covers "assault" generally), but in practice
  non-domestic assault draws discipline far less often and far shorter. `[C]`
- **Game hook:** the mid-severity generic with an available counter-narrative ("he was defending himself"). Good
  fodder for a team-decision beat where the facts stay genuinely ambiguous.

### 1.4 Weapons charges — the rising category

- **Prevalence: 5.3% historically** `[A]`, but **rising** — **at least 17 gun arrests Mar 2020 – Jun 2023, about one
  every two months league-wide (≈5.2/yr)**. `[A]` This is the one category where NFL players genuinely exceed their
  demographic: **2.2 per 1,000 vs 1.0 for US adult males — 2.2×**; against the whole population, **3.2×**. `[A]`
- **Two sub-types the game should model separately:**
  - **(a) Airport / TSA carry — the "administrative" gun charge.** Player passes security or checks a bag with a
    firearm in it. Recurs constantly, especially at New York-area airports where a home-state permit is not valid
    locally. Charged as felony criminal possession in strict-permit states; **the standard ending is a plea down to a
    violation** — one sourced case began as two felonies and ended as a plea to disorderly conduct and a **$250 fine**.
    `[A]` Resolution 2–8 months.
  - **(b) Substantive weapons offences** — brandishing, discharging, felon-in-possession, weapons found incident to
    another arrest. Felony track, real suspension exposure.
- **League response:** type (a) has usually produced no suspension or a token one; type (b) can produce multi-game
  discipline. Exempt list available for either. `[C]`
- **Game hook:** the "unlucky paperwork" event — high embarrassment, near-zero football consequence, burns
  team-reputation currency without costing games. Ideal filler that still feels specific.

### 1.5 Drug possession — structurally broken by the 2020 CBA

- **Prevalence: 11.5% historically** `[A]`, ~9% modern `[C]`. Historically **73% of NFL drug arrests were
  marijuana-only, vs ~50% nationally**. `[A]` NFL drug-possession arrests ran **4.2 per 1,000** vs **10.4** for US
  adult males — **59% below** their demographic. `[A]`
- **The 2020 CBA changed this category more than any other `[A]`:**
  - **No suspension for a positive test for any substance of abuse** (marijuana through opioids) for the life of the
    CBA — fines only.
  - THC positive threshold raised **35 → 150 ng/mL**.
  - Testing narrowed to **the first two weeks of training camp** (was April–August).
  - Marijuana *possession* offences "generally will not result in suspension."
  - Positives route to a **jointly-appointed medical board for clinical review**, not to discipline.
- **Consequence therefore:** in a 2020+ game the drug branch should be nearly consequence-free at the league level
  unless quantity implies distribution, which flips to the felony track and to Substances-of-Abuse Stage Two
  discipline (**4 games first offence, 6–10 games subsequent**). `[A]`
- **Trend-model note:** drug arrests visibly spiked in the offseason pre-2020 *because testing was sporadic
  Apr–Aug*. `[A]` **That mechanism no longer exists** — a real structural break worth honouring if the game's
  timeline spans it.

### 1.6 Theft / burglary / fraud

- **Prevalence: 2.9%** `[A]`, ~4% modern with financial crime growing `[C]`. Two very different profiles:
  - **Petty/impulsive** — shoplifting, hotel or property theft, bar tab. Misdemeanour, quick plea, minimal coverage.
  - **Financial-crime / federal** — the growing sub-type. Sourced: a WR charged in a **$24M COVID-relief (PPP)
    conspiracy**, personally taking ~$1.2M, ~90 fraudulent applications prepared and 42 funded for ~$17.4M →
    **37 months federal prison**. `[A]`
- **Pipeline (federal):** indictment → very long tail. Federal cases run **12–36 months** to sentencing and are
  effectively career-ending for an active player, because he is both unavailable and radioactive to signers.
- **Game hook:** the only category that produces a **slow, quiet career death** rather than a loud one, and the only
  one that plausibly reaches back to *retired* players in a franchise-history sense.

### 1.7 Reckless driving / street racing / fleeing

- **Prevalence:** ~4% as a standalone `[C]`, and structurally under-counted — most speeding is a citation, not an
  arrest. The arrest happens at extreme speeds or with a fleeing/eluding element.
- **Sourced examples `[A]`:** an edge rusher clocked at **135 mph in a 70 zone** (with a prior 2022 speeding /
  suspended-licence arrest — a repeat case); a DT who pleaded no contest to **misdemeanour reckless driving and
  racing** after a crash that killed two people, receiving **12 months probation, a $1,000 fine, 80 hours community
  service and a defensive-driving course**.
- **League response: historically very lenient** — "pretty lenient with players when it comes to speeding and even
  reckless driving, unless there are other circumstances." One star was **cited for speeding at least seven times
  since 2017 with no league discipline**. `[A]` The exception that proves the rule: a **6-game suspension for a
  street-racing crash that injured multiple people**. `[A]`
- **Game hook:** cheap recurring flavour with a rare catastrophic tail. **Injury-to-others is the single switch** that
  converts a one-day story into a career event — a clean, legible rule for players to learn.

### 1.8 Sexual misconduct allegations

- **Prevalence: 1.4% of arrests** `[A]` — but arrests badly under-count this category. The dominant modern form is a
  **civil suit or a league investigation with no criminal charge at all**, which never enters an arrest database.
- **Pipeline:** allegation → grand jury often declines to indict → civil suits filed and settled → **league
  investigation continues independently and can discipline with no criminal case whatsoever.** This is the clearest
  live demonstration of the league's stated principle that its process is independent of the courts.
- **League response:** the heaviest non-lethal discipline of the modern era. Benchmark: **11 games + a $5M fine +
  mandated treatment** in the largest case, *after two grand juries declined to indict*. `[A]` Compare: another star
  with a heavily publicised allegation and no charge received **0 games**. `[A]` The variance is enormous and tracks
  the **number of accusers and volume of civil filings**, not the criminal outcome.
- **Game hook:** the "no arrest, still a catastrophe" branch. Model as a **separate event class** from the arrest
  pipeline, with a media arc measured in seasons.

### 1.9 Animal-related

- **Prevalence: 0.8%** `[A]` — roughly **one incident every 3 league-years**. `[B]`
- **Sourced `[A]`:** an LB charged with **aggravated animal cruelty** after his girlfriend's dog died of blunt-force
  trauma (2015), **released within days**; a *former* RB convicted in 2025 on six federal counts of possessing and
  selling dogs for an animal-fighting venture, **190 dogs seized — the most ever taken from one person in a federal
  dogfighting case** — who had also been charged in a 2004 bust (a 21-year-gap repeat offender).
- **Why it matters despite the rarity:** the highest **public-reaction multiplier relative to legal severity** of any
  category. The clearest case where fan and sponsor reaction ≠ legal exposure.
- **Game hook:** a rare card with abnormally high reputation cost and near-automatic release. A once-per-save
  memorable event.

### 1.10 Other / miscellaneous (~6%)

Disorderly conduct and public intoxication (very common as a *reduced* charge, less so as the original charge),
resisting arrest / obstruction (usually an add-on, almost never standalone), trespass, criminal mischief,
solicitation, child-support contempt warrants, and **failure to appear** — a *derived* event, the sequel to an
unresolved earlier case, and a nice escalation mechanic: an ignored case comes back worse.

### 1.11 Adjacent tracks that share the consequence machinery

Not "legal incidents," but they produce identical UI and consequence shapes, so model them in the same system:

| Track | First offence | Second | Third |
|---|---|---|---|
| PED — anabolic agent | **6 games** | **17 games** | **banishment ≥2 seasons** (petition at 24 months) |
| PED — stimulant / diuretic / masking agent | **2 games** | 17 games (stimulant 5) | banishment |
| PED — masking / tampering | **8 games** | 17 games | banishment |
| Substances of abuse — **positive test** (post-2020 CBA) | **fine only** ($15k) | $20k | 1 wk / 2 wks salary |
| Substances of abuse — **DUI conviction** | **3 games** | **8 games** | — |
| Substances of abuse — other law violation | up to **4 games** | **6–10 games** | — |
| Substances of abuse — failure to cooperate with testing | 4th violation **3 games** | 5th **4** | 6th **8**, 7th banishment ≥1 yr |
| **Gambling — betting on NFL games** | **indefinite, min 1 year** (min **2 years** if own team's game) | — | — |
| Gambling — fixing a game | **permanent banishment** | — | — |
| Gambling — non-NFL betting from the workplace | **2 games** | **6 games** | **≥1 year** |

All `[A]`/`[P]`. **Three provenance corrections worth recording:** the PED 6/17 counts date from the **2020 CBA**
(the 2014 numbers were 4 and 10); the THC positive threshold moved **35 → 150 (2020) → 350 ng/mL (eff. 6 Dec 2024)**
and is tested **only** between camp opening and the first preseason game; and the gambling "6 games first offence"
figure that circulates widely is the **pre-September-2023** rule. Volume check: **≥258 PED suspensions since 2001**. **The structural point worth designing around: the PED/substance/gambling tracks have published tariffs;
the Personal Conduct Policy has a baseline but is discretionary.** So make conduct outcomes **stochastic** and the
tariff tracks **deterministic** — that asymmetry is exactly what makes the conduct branch feel dramatic and the
tariff branch feel bureaucratic, which is true to life.

---

## 2. BASE RATES

### 2.1 League-wide incidents per year

**NFL-internal series** (reported by ESPN, 9 Oct 2024, sourced to the league): `[A]`

| Year | Arrests | Era |
|---:|---:|---|
| 2011 | 74 | pre-policy |
| 2012 | 68 | pre-policy |
| 2013 | 72 | pre-policy |
| 2014 | 68 | policy revised Dec 2014 |
| 2015 | 42 | post-policy |
| 2016 | 40 | |
| 2017 | 53 | |
| 2018 | 36 | |
| 2019 | 47 | |
| 2020 | 28 | COVID — treat as an outlier |
| 2021 | 32 | |
| 2022 | 31 | |
| 2023 | 38 | |

**Derived `[B]`:**
- 2015–2023 (9 seasons): total **347** · mean **38.6** · median **38** · SD **≈ 8.0** · range 28–53.
- Excluding COVID 2020: mean **39.9**, SD ≈ 7.4.
- 2011–13 mean **71.3** → 2021–23 mean **33.7** = **−53%**. The league's own framing: "down by half."
- **Recommended generator: Negative-Binomial, mean 38, variance ≈ 64** (r ≈ 57, p ≈ 0.6). The series is
  **over-dispersed** (variance 64 vs mean 38.6), so plain Poisson under-produces the occasional 50+ year. The
  over-dispersion is consistent with news-cycle clustering rather than independent draws — which is itself a nice
  argument for a mild in-game contagion term.

**2024–2026 — thin. No clean published full-year totals exist yet.** `[C]`
- 2024: 27 players arrested/charged/cited in the trailing 12 months as of April 2024; 16 arrests of current *and
  former* players across the 2024 offseason (DUI 4, drugs 4, DV 3, remainder rape/assault/disorderly).
- 2025: no published total; a row-count off the live database gives 8 arrests Jul–Dec 2025 (**undercount, unverified**).
- 2026: a row-count gives 12 arrests Jan 1 – Jun 23, 2026, a ~24/yr pace (**undercount, unverified**).
- **Do not treat 2024–26 as evidence of a further decline.** The counts are almost certainly incomplete.

**The database itself — correcting a common assumption `[A]`:** the **USA TODAY NFL arrests database is still live and
maintained** (`databases.usatoday.com/nfl-arrests/`), with entries continuing through **June 2026**. It was not
abandoned around 2019–21. Scope, verbatim: *"arrests, charges and citations of NFL players for crimes more serious
than common traffic violations,"* back to 2000, including players on a team at the time or signed shortly after. It
self-declares incompleteness ("cannot be considered fully complete") and **lists arrests even where charges were later
dropped or the player acquitted** — an inclusion rule the game should consciously copy or reject.
Predecessor: the *San Diego Union-Tribune* database (2000–2014). Derivatives: a Kaggle set (850 records to Mar 2017)
and assorted visualisations.

**Cumulative totals are NOT a consistent series — use only for rough scale `[C]`:**
666 (to Jul 2013) · 713 (to Sep 2014) · 769–774 (2000–2014) · 850 (to Mar 2017) · 1,010 (to Jul 2018) ·
1,065 (to May 2024). The implied ~55/yr accretion 2018→2024 exceeds every per-year count above, which proves the
cumulative figures were built on shifting inclusion rules.

**Design implication:** be explicit about your inclusion rule. The three defensible ones are
(i) arrests only, (ii) arrests + citations more serious than a traffic ticket (USA TODAY's rule), (iii) any publicly
reported legal entanglement including civil suits. **(iii) roughly doubles the count**, and is the one that best
matches what a fan actually perceives as "my team is in the news."

### 2.2 Denominator and per-player probability

| Basis | Size | Note |
|---|---:|---|
| Active rosters (53 × 32) | **1,696** | overstates the rate — excludes practice squads |
| Practice squads (17 × 32, 2025 rules) | **544** | 16 + 1 International Pathway |
| **In-season under contract** | **≈ 2,240** | **recommended standard denominator** |
| Offseason peak (90 × 32) | **2,880** | cut to 53 by late August |
| Distinct men touching a roster in a league year | ~2,800–3,200 | `[C]` churn/IR/PUP/street signings; no published figure |

**Practice-squad size grew through the decade — 8 (pre-2020) → 10/12 → 16 → 16+1** `[A]`, i.e. the denominator grew
~15% mid-decade. **Raw arrest counts therefore *understate* the per-capita decline.**

| Rate basis | P(incident) per player-season | Conf |
|---|---:|---|
| 2000s era, 42–43/yr ÷ 1,696 | **2.5% (1 in 40)** — the widely quoted figure | [A] |
| 2000–2013 average, published | **2.53%** | [A] |
| Modern, 34/yr ÷ 1,696 | 2.00% (1 in 50) | [B] |
| **Modern, 34/yr ÷ 2,240** | **1.52% (1 in 66)** ← **best estimate** | [B] |
| Modern, 38.6/yr ÷ 2,240 (NFL series mean) | 1.72% | [B] |
| Modern, 34/yr ÷ 2,900 churn-adjusted | 1.17% (1 in 85) | [B] |
| Independent check: 2013 offseason, 31 arrests | ~1.5%, "one in every 65" | [A] |
| **Career-lifetime** | **6.8% of players arrested at least once** (574 / 8,454, 2000–2014) | [A] |

**Use 1.2–1.7% per player-season for a modern-era game.** The 2.5% figure is the 2000s number and will over-produce
incidents by ~60% if applied to a 2020s setting.

**Internal-consistency check `[B]`:** at 1.5%/season over a mean career of ~3.3 seasons, ~4.9% of players see ≥1
incident; at the 2000s-era 2.3% it is ~7.4%. Observed career prevalence for the 2000–2014 cohort is **6.8%** — which
sits between, exactly as it should for a cohort spanning both eras. The model is coherent.

### 2.3 Seasonality — the offseason spike is real, and probably shrinking

**Historical evidence is strong and points to a large skew `[A]`:**
- **Since the Apr 2007 conduct policy: 378 arrests, 303 of them in the offseason — ~80%.**
- **2013: 47 offseason arrests vs 9 regular-season** — a ~5:1 ratio.
- **June–July are the peak months** — the last free weeks before camp. **September is historically the quietest.**
- **2013 offseason: 30 arrests Feb 3 – Jun 29, of which May alone = 11** (37% of the offseason total in one month).
- Declining first-half-of-year counts: 2013 **29** → 2014 **21** → 2015 **13** → 2016 **9**.
- Mechanism (pre-2020 only): drug crimes rose in the offseason *because testing was sporadic Apr–Aug*.

**Converting 80/20 to a rate ratio `[B]`:** offseason (Feb–Aug, 7 months = 58% of the year) holding 80% of incidents
vs in-season (Sep–Jan, 5 months = 42%) holding 20% gives a **monthly rate ratio of ~2.9×**. The 2013 47-vs-9 split
implies **~3.7×**.

**But modern evidence looks flatter `[C]`:** a row-level count of the live database for Jul 2025 – Jun 2026 (n = 20)
splits **Feb–Jul = 10, Aug–Jan = 10** — essentially flat. n = 20 is far too small to conclude anything, but it is
enough to warn against hard-coding the 2007–13 80/20. The plausible mechanism for genuine flattening is precisely the
one identified above: **the offseason drug-arrest driver was legislated away by the 2020 CBA.**

**Recommended monthly weights (multipliers on the base monthly rate; sum = 12.0) `[C]`** — a deliberate compromise at
**~2.2× offseason:in-season**, between the historical 3–4× and the modern ~1×:

| Month | Phase | Weight | Rationale |
|---|---|---:|---|
| Jan | playoffs / season end | 0.60 | full structure, highest stakes |
| Feb | post-Super-Bowl release | 1.05 | "since the Super Bowl" counters start here for a reason |
| Mar | free agency, players scattered | 1.15 | money + travel + unstructured time |
| Apr | draft, offseason programme begins | 1.15 | |
| **May** | **OTAs, maximum idle time** | **1.80** | strongest signal in the data (37% of one offseason in one month) |
| Jun | minicamp then the 5-week dead period | 1.65 | repeatedly cited peak |
| Jul | pre-camp dead weeks | 1.45 | last free weeks |
| Aug | training camp / preseason | 0.95 | supervised, in a hotel, cutdown pressure |
| Sep | season | 0.55 | historically the quietest month |
| Oct | season | 0.55 | |
| Nov | season | 0.55 | |
| Dec | season | 0.55 | |

Resulting split: **Feb–Jul ≈ 69%** of incidents in 50% of the year; **Aug–Jan ≈ 31%**.

**A caution about the "one arrest every 2–3 days" claim, which is wrong and widely repeated `[B]`:**
40–50/yr = one per **7.3–9.1 days**; even the 2011 peak of 74 = one per **4.9 days**. The 2–3 day figure only ever
held for a peak offseason month (11 in May 2013 = one per 2.8 days) and got laundered into an annual statistic.
**Do not use it to set the game's pacing** — it will produce ~3× too many events.

### 2.4 Trend over the decade

- **Direction: down, substantially.** 71/yr (2011–13) → 34/yr (2021–23), **−53%**, against a *growing* denominator
  (so the per-capita decline is steeper still). `[A]`
- **Inflection: the December 2014 Personal Conduct Policy revision.** The step is immediate and permanent:
  68 (2014) → 42 (2015), and the series never returns to the 60s. `[A]`
- **Confounders to be honest about `[B]`:** (a) the 2020 CBA effectively decriminalised marijuana *within the sport*,
  removing a whole sub-category from consequence and probably from some databases' inclusion; (b) COVID (2020 = 28);
  (c) a broad decline in US arrest rates generally over the same period; (d) practice-squad growth inflating the
  denominator. **The −53% is real but not purely a behaviour change.**
- **Category-level counter-trends:**
  - **Weapons rose** — 17 in the 39 months Mar 2020 – Jun 2023 (≈5.2/yr) against a 5.3% historical share. `[A]`
  - **Domestic violence shows no clean decline** `[A]`: cases reported to the league ran
    **8, 3, 9, 5, 6, 5, 3, 5, 11** for 2015–2023 — mean 6.1, noisy, with **2023 the highest of the series**.
    (Prior years: 2013 = 9, 2014 = 8.) DV is *not* following the aggregate down.
- **Game hook:** if the game spans 2015→2026, drift drug incidents **down** and weapons incidents **up** over the
  timeline, hold DV **flat**, and let the aggregate fall ~40%. That drift is real and free narrative texture.

### 2.5 Comparison to the general population — the essential sanity check

**Aggregate: NFL players are arrested LESS than comparable men.** `[A]`
- **3,740 per 100,000 (NFL) vs 4,889 per 100,000 (general population) in 2013**; the general rate exceeded the NFL
  rate in **every year 2000–2013**. The published academic conclusion: the general-population arrest rate was
  **nearly 2× the NFL rate**.
- **1 arrest per 11 NFL players (2000–2014) vs 1 per 6 US men aged 21–34 (2012).**

**Per-1,000-per-year by charge, NFL vs population (2010 FBI UCR baseline) `[A]`:**

| Charge | NFL | US (all) | vs all | US adult males | vs adult males |
|---|---:|---:|---:|---:|---:|
| DUI | 8.3 | 4.6 | +81% | 9.4 | **−11%** |
| Assault / battery / DV | 7.4 | 5.5 | +34% | 9.6 | **−23%** |
| **Weapons** | **2.2** | 0.68 | **3.2×** | 1.0 | **2.2×** |
| Drug possession | 4.2 | 5.3 | −20% | 10.4 | **−59%** |

**The punchline: against adult males, NFL players are arrested *less* for everything except weapons.**

**But the mix is skewed:** NFL players are *disproportionately* arrested for **domestic violence, sex offences,
homicide and weapons** relative to the general population — lower total, higher violent share. **27% of NFL arrests
are violent** (209 of 774, 2000–2014). `[A]`

**Design implication:** the fiction "players get in trouble constantly" is false to the data. The correct feel is
**rare but memorable** — about 1 player in 66 per year, **1.2 incidents per team per year**, most of them minor and
quickly forgotten. If your playtesters say "this happens too often," they are probably right and the data agrees.

**Data-quality caveat that matters for the resolution model `[A]`:** **204 of 769 database entries (26.5%) are marked
"resolution undetermined."** Public conviction data is badly incomplete — roughly a quarter of real cases simply never
produce a legible ending. A game that resolves 100% of its cases with a clean verdict is *less* realistic than one
that lets ~25% fade out unresolved. **That is a feature worth shipping deliberately.**

### 2.6 Per-team framing — the most useful unit for a management game

| Metric | Value | Conf |
|---|---:|---|
| Incidents per team per league-year (38.6 / 32) | **1.21** | [B] |
| P(a given team has zero incidents in a year), Poisson(1.21) | **30%** | [B] |
| P(exactly one) | 36% | [B] |
| P(two or more) | 34% | [B] |
| P(three or more) — "your team is in the news again" | **12.2%** | [B] |

**Observed team spread, 2000–2024 (n = 1,065) `[A]`:**
highest — Vikings **60**, Broncos **56**, Bengals **54**, Jaguars **45**, Chiefs **43**;
lowest — Texans **17**, Lions **19**, Eagles **21**, Rams **23**, Giants **24**; league average **~33**.
The worst franchise's annual player-arrest rate was **5.0% vs a 2.53% league average**. `[A]`

**So the real best-to-worst franchise spread is ~3.5×** (60 vs 17 over the same window), and the worst team ran
**~2× the league rate**. That bounds the **team-culture / locker-room modifier**: cap the organisational multiplier at
roughly **0.5×–2.0×**. Letting culture swing incident rates by 10× would be unfaithful and would also make the
mechanic too dominant — at 2× maximum, culture is a real but not decisive lever, which is the right weight.

---

## 3. PLAYER-PROFILE PATTERNS

The best single source is a peer-reviewed **matched-pairs** study of **117 NFL players arrested for violence against
women 2000–2019**, each matched to a non-arrested comparison player (234 total). It is the only source found that
quantifies *who* gets arrested **and** what happens to their career afterwards. `[A]`

### 3.1 Age

| Finding | Value | Conf |
|---|---|---|
| Median age at arrest | **25** | [A] |
| Effect of age on post-incident career length | **each additional year = 9% fewer expected remaining seasons** | [A] |
| Expected remaining seasons, age 25 | 3.0 | [A] |
| Expected remaining seasons, age 29 | 2.1 | [A] |

Incidents concentrate in the **22–27** band, which is simply where the population is. There is no strong evidence of
an age-specific *propensity* multiplier beyond roster share, so a flat hazard across 21–32 with a mild young-skew is
defensible. `[C]`

**Age matters far more on the consequence side than the incidence side.** The 9%-per-year effect is a clean,
ready-made game rule: **an older player is much more likely to be cut and never re-signed for the identical offence.**

### 3.2 Star vs depth — the strongest pattern in the entire dataset

The study is titled *"More Talent, More Leeway."* Post-incident expected career length, **holding offence constant**,
by pre-incident **start percentage**: `[A]`

| Pre-incident role | Expected seasons still played after the incident |
|---|---:|
| Starter (~75% of games started) | **4.05** |
| Rotational (~25%) | **1.95** |
| Never started (0%) | **0.90** |

**A 4.5× spread for the same category of offence.** The finding summarised elsewhere: *"the top 75 percent of players
didn't really see, on average, an impact from their accusation."* `[A]`

Two further calibration points from the same study `[A]`:
- The matched **non-arrested** baseline player was expected to play **3.0** more seasons; the arrested baseline
  **4.07** (+35.9%) when arrest *timing* is ignored — **raw survival after arrest looks better than the control**,
  because players who get arrested *and stay employed* are selected for talent. Once era is controlled, players
  arrested from 2009 onward see slightly fewer post-arrest seasons, and a player arrested in **2015** was expected to
  play only **2.34** more seasons. **The leeway has been narrowing.**
- Arrested and non-arrested players were **nearly identical beforehand**: 50.3 vs 53.3 games played, 31.0 vs 32.8
  games started, **49.3% vs 47.9% start rate**. **Arrest is not predicted by being a marginal player.**

**The design rule this yields, stated plainly:**
> **Incidence should be roughly independent of player quality. Consequences should be steeply dependent on it.**

This is also the most interesting *game* property in the whole file, because it puts the user in an uncomfortable
seat: the sim will repeatedly ask whether a 4.05-vs-0.90 career difference should turn on the player's depth-chart
rank. **That tension is the mechanic** — not a side effect of it.

### 3.3 Draft pedigree

- Mean draft round of arrested players: **4.12** `[A]` — the modal arrested player is a **mid-to-late-round pick**,
  which again is just where the roster mass sits. No evidence of a "high-pick problem" or a "UDFA problem."
- What *does* differ by pedigree is **retention**: high picks carry sunk-cost and dead-money protection (§4). That is
  a contract mechanic, not a behaviour mechanic — keep the two separate in code.

### 3.4 Repeat offenders

Of **573 arrested players (2000–2014)** `[A]`:

| Arrest count | Players | Share of arrested | Share of all NFL players in window |
|---|---:|---:|---:|
| 1 | 440 | **77%** | 5.2% |
| 2 | 91 | **16%** | 1.1% |
| 3+ | 42 | **7%** | 0.5% |

- **131 of 574 arrested players (22.8%) were arrested more than once.** `[A]`
- The researchers' framing: *"It's a repeat behavioural problem among a very small fraction of people."* `[A]`
- **Implied escalating hazard `[B]`:** conditional on one arrest, P(second) ≈ **23%**; conditional on two,
  P(third) ≈ **32%** (42/133). Recidivism *rises* with prior count.
- **Game model `[C]`:** give each generated player a hidden latent risk trait; ~**6%** of the population carries an
  elevated value with a ~**4–5× multiplier**. That reproduces both the 77/16/7 split and the ~1.5%/season aggregate.
  Crucially, **the trait must be partially hidden from the GM** — discoverable through scouting and character grades,
  fully revealed only by an incident. This project already has the scouting-fog machinery for exactly that shape.

### 3.5 Position patterns

**Raw counts `[A]`:**
- 2000–2014: **WR 122 (most)**, CB second, **QB 14** (~1/yr), OL about half the WR rate, **K 9, C 4, P 3**.
- 2000–2024 (n = 1,065): **WR 182**, **CB 149**.

**Nobody has published these normalised by roster share**, and that caveat is decisive. WR and CB are large position
groups with young mean ages; QB, interior OL and specialists are small groups, older, and (for QB) far more
financially deterred and scrutinised. Most of the raw spread is plausibly explained by headcount and age alone. `[D]`

**Recommendation: use a position multiplier of at most 0.85×–1.20×, or none at all.** The evidence supports a
directional hint (WR/CB/LB up a little; QB, OL, K/P down a little) but not a strong effect, and a large multiplier
would be encoding a stereotype rather than a measurement.

### 3.6 Rookie vs veteran

**Not published on this axis** — no source breaks arrests down by rookie/veteran or starter/backup status. `[D]`
Defensible reasoning `[C]`:
- Rookies are likely **under**-represented in their first months: the class arrives in May, is heavily supervised
  through camp, and has the most to lose against the least banked money.
- The dangerous window opens in **years 2–5**: money has arrived, supervision relaxes, the offseason is long, and the
  player is at the median arrest age of 25.
- Pre-league incidents act on **draft position** rather than employment — a separate mechanic (§4.10).

### 3.7 A finding the game must NOT model

The study reports **111 of 117 (94.9%)** of the VAW-arrested players in its sample were Black. `[A]` The authors treat
this as evidence about **policing, reporting and media selection** — arrest databases are built from *media coverage
of arrests*, a doubly filtered signal — not about behaviour.

**This must not be encoded in the game in any form.** It is recorded here only so that nobody later rediscovers it in
a source and mistakes it for a modelling input. Generated players' incident risk must be independent of every
demographic attribute.

---

## 4. CONSEQUENCES

### 4.1 The Personal Conduct Policy — authoritative text

Source: **NFL Personal Conduct Policy, League Policies for Players, 2022 edition** (the Dec-2014 revision as
currently in force). All quotes verbatim. `[A]`

**Who it binds — wider than you'd guess, and this matters for the draft mechanic:**
> "The provisions below apply to players under contract; all rookie players selected in the NFL College Draft; all
> undrafted rookie players following the NFL College Draft; **all Draft-eligible players who attend a Scouting
> Combine**; all unsigned veterans who were under contract in the prior League Year; and all other prospective
> players once they commence negotiations with a club concerning employment."

**The standard is explicitly not the criminal standard:**
> "It is not enough simply to avoid being found guilty of a crime in a court of law. We are all held to a higher
> standard..."
> "In cases in which a player is not charged with a crime, or is charged but not convicted, he may still be found to
> have violated the Policy if the credible evidence establishes that he engaged in prohibited conduct."

**The policy's own prohibited-conduct list — a ready-made taxonomy, and it matches §1 closely:**
actual or threatened physical violence (incl. dating violence, domestic violence, child abuse, family violence) ·
assault and/or battery incl. sexual assault and other sex offences · violent or threatening behaviour in a workplace
setting · stalking, harassment, intimidation · **illegal possession of a gun or other weapon, or possession of a
weapon in any workplace setting** · illegal possession/use/distribution of alcohol or drugs · steroids/PEDs ·
**crimes involving cruelty to animals** · crimes of dishonesty (blackmail, extortion, fraud, money laundering,
racketeering) · theft-related crimes (burglary, robbery, larceny) · disorderly conduct · **crimes against law
enforcement** (obstruction, resisting arrest) · conduct posing a genuine danger to another person's safety ·
conduct undermining the integrity of the NFL.

**The 6-game baseline, quoted exactly:**
> "With regard to violations of the Policy that involve: (i) **criminal assault or battery (felony)**; (ii) **domestic
> violence, dating violence, child abuse and other forms of family violence**; or (iii) **sexual assault involving
> physical force or committed against someone incapable of giving consent**, a first violation will subject the
> violator to a **baseline suspension without pay of six games**, with possible upward or downward adjustments based
> on any aggravating or mitigating factors."

**Note the scope limit that is routinely misreported:** the baseline attaches to **felony** assault/battery. A
*misdemeanour* bar fight is not inside the 6-game baseline — which is exactly why §1.3 assault cases so often produce
zero discipline.

**Aggravating factors (verbatim list):** a prior violation of the Policy · similar misconduct **before joining the
NFL** · violence involving a weapon · **choking** · repeated striking · an act against a particularly vulnerable
person (a child, a pregnant woman, an elderly person) · or an act committed **in the presence of a child**.

**Mitigating factors (verbatim list):** prompt acceptance of responsibility and cooperation with the league
investigation · voluntary engagement with clinical resources and demonstrated compliance with counselling ·
**voluntary restitution with the victim**.

**Second violation:**
> "A second violation will result in **permanent banishment from the NFL**. An individual who has been banished may
> petition for reinstatement after one year, but there is no presumption or assurance that the petition will be
> granted."

**Discipline menu:** "a fine, a suspension for a fixed or an indefinite period of time, a combination of the two, or
banishment from the league with an opportunity to reapply," plus a probationary period with conditions.
**Players with a prior history of misconduct — including misconduct predating their NFL association — face
"enhanced and/or expedited discipline."**

**These two verbatim lists are the single most directly implementable artefact in this whole research file.**
They are literally a modifier table: seven named aggravators, three named mitigators, applied to a 6-game base.

### 4.2 What counts as "guilty" — much broader than a conviction

The policy's own definition, verbatim: `[A]`
> "**Disposition of a Criminal Proceeding**" – Includes an adjudication of guilt or admission to a criminal violation;
> a plea to a lesser included offense; a plea of nolo contendere or no contest; or the disposition of the proceeding
> through a **diversionary program, deferred adjudication, disposition of supervision, conditional dismissal,
> adjournment in contemplation of dismissal, pretrial intervention or similar arrangement**.

**This is a big deal for the game's resolution model.** The realistic "good" legal outcomes — diversion, deferred
adjudication, ACD, pretrial intervention — **all still count as a disposition** and can trigger league discipline.
So the branch "charges dropped, player walks free" should *not* automatically mean "no league consequence." The two
tracks resolve separately, and the league's is the one that costs games.

Corollary from the same section: where there *has* been a criminal disposition, "the underlying disposition may not
be challenged in a disciplinary hearing and the court's judgment and factual findings shall be conclusive and
binding, **and only the level of discipline will be at issue**."

### 4.3 The Commissioner Exempt List — the mechanic to implement

Paid administrative leave. Triggers, verbatim `[A]`:
1. **"when a player is formally charged with: (1) a felony offense; or (2) a crime of violence"** — where formal
   charge means "an indictment by a grand jury, the filing of charges by a prosecutor, or an arraignment in a
   criminal court."
2. When an investigation leads the Commissioner to believe the Policy may have been violated. Explicitly:
   "This decision will not reflect a finding of guilt or innocence and will not be guided by the same legal standards
   and considerations that would apply in a criminal trial."
3. A **limited and temporary** placement to permit a preliminary investigation, after which the player is returned to
   duty, held longer, or disciplined.

Mechanics `[A]`:
- **Player is paid in full.** He "may not practice or attend games," but with the club's permission may use the
  facility "on a reasonable basis for meetings, individual workouts, therapy and rehabilitation."
- He **does not count against the active roster** — the club can sign a replacement. (This is why the exempt list is
  attractive to clubs: it is a free roster spot with no cap relief.)
- **Appeal window: 3 business days.** The player stays on the list pending appeal.
- **Duration:** "generally last until the league makes a disciplinary decision and any appeal from that discipline is
  fully resolved" — i.e. **indefinite and tied to the criminal calendar**, which is why it runs months.
- **Games missed on exempt are credited against any later suspension**, and "the player will return any salary
  proportionate to the credited games." So exempt time is *retroactively converted* into unpaid suspension time once
  discipline lands — a clean, satisfying rule to implement.

**Verified placements (no official register exists) `[S]`:** Vick '09 · Vilma '12 · **an MVP RB '14 (~9 games)** ·
**a DE '14 (15 games)** · a K '16 (4 days) · an RB '18 · an LB '18 (~5 months) · '23 · '24 ×3 — including a safety
held **7 games who was later acquitted of assault**.

**⚠️ It is applied inconsistently, and the game should reproduce that `[S]`:** one player facing **eight felony
counts played the entire 2024 season** and was never placed; another under a **felony strangulation charge played
through a Super Bowl** (Dec 2025) and was acquitted in May 2026. Meanwhile the acquitted safety above was placed
within **4 days**. **Exempt-list placement is closer to a coin flip weighted by publicity than to a rule** — model it
as `P ≈ 0.35` on a qualifying charge, rising sharply with media volume, not as an automatic consequence.

**A pre-2015 detail that explains why the rule changed:** before the 2020 CBA's credit-and-repay provision, exempt
time was **free paid leave** — one DE collected **15 games at ~$770k/week** while not playing. `[S]`

### 4.4 Process, timelines and appeals

- **Investigation:** league office, independent investigators, or both; "the timing and scope of which will be based
  upon the particular circumstances." **Runs in parallel with, and independent of, law enforcement.** `[A]`
- **Compelled cooperation:** "Because the Fifth Amendment's protection against self-incrimination does not apply in a
  workplace investigation, the league will reserve the right to compel a player to cooperate ... even when he is the
  target of a pending law enforcement investigation." Refusal is **separate grounds for discipline**. `[A]`
- **Witness interference / retaliation is separately punishable** — including "an offer or gift of money, property or
  anything of value" to a witness. `[A]` (A ready-made "the player tried to make it go away and made it worse" branch.)
- **Decision-maker:** a **jointly selected and compensated Disciplinary Officer** (NFL + NFLPA), not the Commissioner
  directly — a 2020-CBA change that the game can use to explain why outcomes feel less arbitrary post-2020. `[A]`
- **Appeal:** either side may appeal to the Commissioner or his designee; expedited; limited to the *terms* of
  discipline; **no new evidence**; factual findings binding; the Commissioner "may overturn, reduce, modify **or
  increase**" and the decision is final and binding. `[A]`
  Separately, players have **5 business days to appeal**, and an arbitrator hears both sides. `[A]`
- **Reporting duty:** clubs **and players** must promptly report any matter that may constitute a violation —
  "broader than simply reporting an arrest" — and the obligation is **continuing**. **Failure to report is itself
  grounds for discipline.** `[A]`
  **Game hook:** this creates a genuine GM decision — concealing or slow-walking a report is a modelled risk, not a
  free action.

### 4.5 Roster, pay and cap treatment during discipline

| Mechanic | Rule | Conf |
|---|---|---|
| Suspended player's roster status | placed on **Reserve/Suspended**; **does not count against the roster limit**, so the club may sign a replacement | [A] |
| Pay | game checks forfeited for suspended games (1/18th of Paragraph 5 salary per regular-season game under a 17-game season) | [A]/[B] |
| Exempt list pay | **paid in full**, then repaid proportionately if the time is later credited against a suspension | [A] |
| Practice access while suspended | may practise with teammates but not play or attend games; **facility access restricted in the first half** of the suspension, permitted in the second half to prepare for reinstatement | [A] |
| Appeal window | 5 business days (discipline) / 3 business days (exempt-list placement) | [A] |

### 4.6 Contract and guaranteed-money consequences

**CBA Article 4, Section 9 — Forfeiture of Salary `[A]`:**
- Forfeiture reaches only **"Forfeitable Salary Allocations"** — signing bonus, roster bonus, option bonus, reporting
  bonus. **"Paragraph 5 Salary already earned may never be forfeited."**
- A **"Forfeitable Breach"** includes wilful failure to report/practise/play, **incarceration resulting in
  unavailability**, non-football injury from breaching contract terms, and voluntary retirement.
- **Forfeiture ladder:**

| Trigger | Forfeitable share |
|---|---|
| Absent 6 preseason days after camp starts | up to **15%**, +1% per additional day, **capped at 25%** |
| Missing the first regular-season game | up to **25%** |
| Absence continuing past week 4 | remaining allocations forfeit **proportionately, 1/17th per week** |
| **Second breach in the same year** | **entire remaining balance** |

- **Unearned guaranteed money can only be voided if the parties negotiated those specific circumstances separately** —
  i.e. via a **conduct clause / guarantee-void trigger written into the individual contract**, not by default. This is
  why star contracts routinely contain bespoke "personal conduct" void language and minimum deals do not.

**The club's actual termination right — NFL Player Contract, Paragraph 11, verbatim `[P]`:**
> "…or if Player has engaged in **personal conduct reasonably judged by Club to adversely affect or reflect on
> Club**, then Club may terminate this contract."

**This, not the conduct policy, is the mechanism behind every release in §4.10.** The standard is the *club's*
reasonable judgement — which is precisely why the same charge produces a 3-hour release for a UDFA and no action at
all for a starter. **Paragraph 15** separately lets the Commissioner fine, suspend indefinitely and/or terminate for
betting, fixing, or detrimental conduct after a hearing.

**⚠️ Important correction to a natural assumption `[P]`:** a **Personal Conduct suspension is *not* itself a
"Forfeitable Breach"** under Art. 4 §9. The enumerated breaches are holdout, **incarceration**, Paragraph 3
non-football injury, and retirement. **PED and substance suspensions do forfeit bonus automatically** (§9(e),
1/17 per week) — **conduct suspensions do not.** Conduct money is recovered only through **§9(g) negotiated
guarantee-voiding language**, contract by contract.

**Documented clawback outcomes `[S]`:**

| Case | Sought | Recovered |
|---|---|---|
| QB, federal conviction + prison (2008) | arbitrator awarded **$19.97M** | reversed on appeal to **$3.75M** — player kept $16.25M |
| DL, conduct (2019) | — | **$799,238** ordered repaid; club sued to enforce |
| WR, conduct (2020) | **$9M** grievance | settled |
| RB, indefinite suspension (2015) | back-pay grievance | **$3.529M** settled *to the player* |
| **QB, 11-game conduct suspension (2022)** | — | **total financial hit ≈$5.63M against a $230M guaranteed deal** — the salary had been restructured to $1.035M, so only ~$632.5k of pay was actually forfeited |

**That last row is the whole lesson: a club and player can pre-neutralise a suspension's financial bite by
restructuring salary into bonus before it lands.** If the game models contract restructuring at all, this is a real,
legal, slightly cynical interaction worth allowing.

**Design implication:** the game should treat **guarantee voids as a contract *property*, not a league rule.**
A star's deal carries a negotiated conduct-void trigger (and the agent will fight to narrow it); a minimum deal does
not need one because the club can simply release the player at near-zero cost. That asymmetry is itself a nice
negotiation lever to expose in the contract UI.

### 4.7 Legal outcomes — how often does anything actually stick?

**The headline `[A]`: of 117 NFL players arrested for violence against women 2000–2019, only 21 (17.9%) were found
guilty.** Of those, 4 pleaded to a lesser crime than originally charged and only **6 served prison time (5.1% of all
arrested)**.

Supporting figures `[A]`:
- **26.5% of database entries (204 of 769) are marked "resolution undetermined"** — a quarter of real cases never
  produce a publicly legible ending at all.
- General DV dismissal rates: **~15% of felony and ~30% of misdemeanour** family-violence cases dismissed (Texas);
  **3%–31%** across San Diego jurisdictions.
- **80–90% of DV complainants recant**, but recantation alone does not end a case — **~80% of prosecutors' offices
  say they will proceed with an uncooperative complainant**, and no-drop policies are common.
- The published caution that matters: arrest data "only captures arrests and not actual convictions, as many charges
  may be dropped, reduced, or resolved outside of court."

**Actual resolution rates, cross-tabulated from the USA TODAY database's known-resolution rows `[C]`** — this
supersedes any estimate, and it is the single most useful table in §4:

| Outcome | **All arrests** | **Domestic violence** | **DUI** | **Non-domestic assault** |
|---|---:|---:|---:|---:|
| Convicted / pleaded guilty | **47–50%** | **21–23%** | **70–71%** | ~35% |
| Dropped / dismissed / acquitted | **31%** | **37%** | ~15% | **45–48%** |
| Diversion / deferred adjudication | **13–15%** | **36–38%** | ~14% | ~18% |
| **Resolution unknown (excluded above)** | **~26% of all rows** | — | — | — |

**Three findings here that change the design:**

1. **DV: 73–76% of arrests end in no conviction** — consistent with the 17.9% guilty rate from the peer-reviewed
   VAW study, and driven far more by **diversion (36–38%)** than by outright dismissal.
2. **DUI convicts at 70–71%** — over **3× the DV rate**. The game's "minor" category is the one that actually
   sticks; the "serious" category is the one that evaporates. That inversion is counter-intuitive and worth
   surfacing to the player.
3. **A correction to the common narrative `[P]`:** national baselines (NIJ 2009, NCJ 225722 — 63.8% of DV arrests
   prosecuted × 35–48% of prosecutions convicted) give **~22–31% of US DV arrests ending in conviction**. The NFL's
   **21–23% is in line with the national baseline, not below it.** What *is* anomalous is the **diversion share**.
   Likewise BJS 2009 (75 largest counties): felony defendants convicted **66%** overall, **assault lowest at 56%**
   (35% dismissed), **driving-related highest at 84%** — the same rank ordering the NFL data shows.
   **So: do not model "NFL players get off easy" as a conviction-rate effect. Model it as a diversion-access effect.**

**⚠️ A widely repeated claim to avoid `[U]`:** "NFL players are convicted at half the rate of the general public" has
**no primary NFL source**. Its real ancestors are 1990s *athlete* studies (Benedict & Klein 1997: 31% conviction for
athlete felony sex complaints vs a 54% national baseline; 36% vs 77% for 1995 athlete DV). The "38% vs 80%" variant
is folklore. Cite as *athletes, 1990s* — or not at all.

### 4.8 Suspension-length distribution — the histogram

Parsed from the public list of NFL suspensions plus a curated notable-case set `[C]`:

| Sample | n | Mode | Median | Mean |
|---|---:|---:|---:|---:|
| Explicit Personal-Conduct rows, 2015–2018 | 23 | **1 game** (8 cases) | 3 | **3.39** |
| Curated notable finite PCP suspensions, 2014–2026 | 42 | **6 games** (21%) | 4 | **4.24** |
| **Restricted to DV / sexual assault** | 16 | **6** | **6** | **5.5** |

**The shape is bimodal: a large mass at 1–2 games and a hard spike at exactly 6.** The 6-game baseline **binds only
on the categories the policy names** (felony assault, DV, sexual assault) — everything else clusters at 1–2 games or
zero. That is precisely the §1.3 prediction, now confirmed numerically.

**Appeals matter and are not symmetric `[A]`:** in 6 contested benchmark cases the number changed in **5**. Every
change was a **reduction except one — and that one increase came because the *league* appealed** (6 → 11). Under the
2020 CBA the first-instance decision belongs to a **jointly selected, jointly paid Disciplinary Officer** with the
**NFL bearing the burden of proof** and the Commissioner barred from hearing it first — but either side may then
appeal to the Commissioner, **who may increase the discipline**, final and binding.

**Game model `[C]`:** draw from a two-component mixture — ~65% mass at 0–2 games (everything outside the named
categories), ~35% at the 6-game baseline shifted by the aggravator/mitigator counts from §4.1. Then apply an appeal
step: `P(appeal changes the number) ≈ 0.8`, of which ~85% reduce and ~15% increase.

### 4.9 Fines

- **Personal-conduct fines** are used as an alternative or supplement to suspension. The policy's menu is explicitly
  "a fine, a suspension ... a combination of the two, or banishment." `[A]`
- Benchmark for the largest conduct fine of the era: **$5M**, attached to an 11-game suspension. `[A]`
- Small-beer end: an airport gun felony pleaded down to disorderly conduct and a **$250** court fine. `[A]`
- For minor incidents the realistic league output is **no fine at all** — the cost is reputational and the money loss
  comes from lost game checks if suspended, not from a fine.

**On-field fine schedule — CBA Appendix U, first offence, 2020 base escalating +3%/yr (2025 values) `[P]`:**
contact with an official **$40,686** · fighting **$40,686** · illegal helmet use/spearing **$23,185** ·
horse collar / hit on a defenceless player / blindside block / roughing the passer **$17,389** ·
unsportsmanlike conduct **$14,491** · striking or kicking **$12,172** · face mask / late hit / taunting **$11,593**.
Second offences roughly double. Caps: a first offence is **≤10% of the player's game cap number**; +20% if egregious,
−20% if incidental; a third same-season offence is **≥ a full game check**; **25% is held in abeyance pending
remedial training**; NFLPA consultation is required above **$50,000**. Collection is capped at **$3,500 per pay
period** ($4,500 from 2026). Proceeds split **50% Players Assistance Trust / 50% charity**.

**Volume, and the ratio that matters for pacing `[S]`:** ~**460 on-field fines in 2022**, of which ~**100 were
rescinded and ~150 reduced on appeal** (i.e. **~54% of appealed fines change**) — against ~3–8 conduct suspensions a
year. **That is roughly 50–100 fines per suspension.** If the game surfaces fines at all, they are the constant
background hum and suspensions are the rare event.

### 4.10 Team response — the single most important consequence mechanic

**Finding, stated as bluntly as the evidence permits:**
> **Response speed is a function of contract leverage, not charge severity.**

This is not an impression; it survives a 32-case audit of depth-player releases 2015–2026 (agent-compiled, each with
arrest date and release date). `[A]`

**Depth / fringe / practice-squad tier — time from arrest to release:**

| Lag | Share of 32 audited cases | Conf |
|---|---:|---|
| **Same day (0 days)** | **~31%** (10 cases; fastest documented: **~3 hours**, a practice-squad LB) | [A] |
| 1 day | ~28% | [A] |
| 2–4 days | ~25% | [A] |
| 5–11 days | ~6% | [A] |
| 30+ days (slow outliers — team captains, special-teams core) | ~6% | [A] |
| Gated on indictment rather than arrest | 1 case: **120 days from arrest, 1 day from indictment** | [A] |

**Median lag for a fringe player: 1 day. ~60% are gone inside 24 hours; ~85% inside four days.** `[B]`

**Charge severity barely moves this number.** In the audited set, a journeyman was released in one day over a
**$300 marijuana bond**; another over a **suspended-licence citation**; a practice-squad player in three hours over a
misdemeanour. Meanwhile a first-round investment survived **120 days on a felony domestic-violence arrest** and was
only cut the day after a grand jury indicted him. **Dead money, not the police report, sets the clock.**

The best contemporaneous summary of the mechanism, from trade reporting on a released UDFA (May 2022):
> "Countless instances exist of players remaining with teams after DUIs, but **bottom-rung roster players are
> generally afforded fewer missteps.**"

**Star / high-investment tier — the same offences, radically different clocks `[A]`:**

| Pattern | Observed lag | Outcome |
|---|---|---|
| Franchise QB, 22+ civil suits, no criminal charge | statement in **2 days**, **no discipline, no exempt list**, held a full season | **Traded 12 months later for 3 first-round picks and given the largest fully guaranteed contract in league history** |
| Star WR, child-abuse investigation | barred from team activities in **~1 day**; league declined discipline at **84 days** | **Extension signed 133 days later**; later traded for a $120M deal |
| Star RB, DV allegations | **team imposed nothing**; league suspension came ~13 months later | **Six-year, $90M extension signed after the suspension** |
| Pro Bowl specialist, 16 accusers via investigative reporting | held **~95 days**, then released — and **the release statement never mentioned the allegations**, framing it as a roster move | 10-game suspension a month later |
| Star pass rusher, two felony gun arrests | played through; **won a Super Bowl in between**; suspension landed **492 days after the arrest** | retained |
| Star WR, 119-mph multi-car crash | **no team or league discipline that season**; played the next four games | guilty plea **474 days** later; 6-game suspension the following season |
| Recent first-round pick facing potential life sentence (kidnapping/armed robbery) | released in **5 days** | **The exception that proves the rule — the ceiling on "leverage protects you" is a life sentence.** |

**The mechanism the game should actually implement — teams do not act, they wait for an external forcing function.**
In every audited case where a valuable player was released, one of exactly four triggers fired first `[A]`:

1. **Video or documents became public.** The strongest trigger by far. The canonical case: a February arrest produced
   a two-game suspension; **a September video of the same act ended the career**. Coverage volume — and therefore
   team action — tracked footage availability, not legal severity.
2. **An indictment landed** (as distinct from an arrest). One case: 120 days of inaction after the arrest, released
   **one day** after the grand jury acted.
3. **The league placed the player on the Commissioner Exempt List**, removing the team's option to keep playing him.
4. **Sponsors moved.** One team deactivated a star, **reinstated him three days later**, and only put him on the
   exempt list two days after that when sponsor pressure became public.

**Absent one of those four, the observed default is: keep playing the player.** Multiple 2024–2026 cases show
starters with active felony charges taking the field the following week with no team action at all.

**Recommended implementation `[C]`:** compute a `leverage` score from dead money + depth-chart rank + contract years
remaining, then

- `leverage` low (PS, UDFA, minimum deal, no dead money) → **release rolls in 0–4 days, ~85% probability, regardless of severity**;
- `leverage` mid (rotational, some dead money) → **statement, 0–2 games deactivated, release only if a forcing function fires**;
- `leverage` high (starter/star, large guarantees) → **statement only; release requires a forcing function AND severity above a high threshold** (the life-sentence ceiling).

That single rule reproduces the entire observed distribution, and it is uncomfortable in exactly the way the real
league is — which is the point of putting it in a management game rather than smoothing it away.

### 4.11 The team statement — a four-move script

The public statement is formulaic enough to generate procedurally. Observed structure, in order `[A]`:

**acknowledge** → **"gathering more information"** → **"we take these matters (very) seriously"** → **"ongoing legal
matter / no further comment at this time."**

Verbatim exemplars (paraphrase these into fictional-team voice; do not ship the originals):
> "We are aware of an incident involving [player] in [city]. We are in the process of gathering more information and
> will not have any further comment on an open legal matter at this time."

> "We are aware of the incident regarding [player], and we take these matters very seriously. Due to this being an
> ongoing legal situation, we cannot comment further at this time."

The full release statement folds all four moves plus the decision into one paragraph:
> "Following our review of today's indictment against [player], we have decided to release [player] immediately. As we
> have previously said, we take these matters very seriously and condemn all forms of domestic violence. Due to the
> ongoing legal nature of this matter, we are unable to provide further comment."

**Three tells worth modelling because they carry information:**
- **The omission tell.** A release statement that **never mentions the allegations** and frames the move as a roster
  decision is a distinct, observed variant used for high-profile players.
- **The due-diligence justification**, used to *defend acquiring* a player with a history: "extensive investigative,
  legal and reference work."
- **The structural asymmetry.** Fringe players do not get the four-clause statement at all — they get a one-line
  transaction note or a single social post. One first-round player's release was announced as a **single tweet**.
  **In-game: statement length should scale with player value.** That alone communicates the hierarchy without a
  word of exposition.

### 4.12 Media arc length

No published quantitative media-volume dataset was found. `[D]` What follows is **measured arc length from documented
event chronologies**, which is defensible and more useful for pacing anyway. `[A]`

| Arc type | Duration | Distinct coverage peaks |
|---|---|---|
| Fringe player, minor charge, no footage | **1–2 days** (often just a transaction note) | 1 |
| Fringe player, serious charge | **3–7 days** | 1–2 |
| Starter, DUI or single arrest | **1–2 weeks**, revived at each court date | 2–3 |
| Star, DV arrest with a legal process | **~10–14 months** | 3–5 |
| Star, serial accusers via investigative reporting | **~5 months** of drip, each new accuser count a fresh peak | 4–5 |
| Franchise QB, ongoing civil docket | **~43 months**, at least **7 distinct peaks** | 7+ |

**The structural rule the cases support `[B]`:** duration scales with
**(a) availability of video or documents, (b) the player's snap count, and (c) the number of discrete new filings.**
A single arrest with no footage and no follow-on filings is a one-to-two day story. Video, or serial accusers, makes
it months. An open civil docket attached to a franchise quarterback makes it years.

**The most important sub-finding for a game: coverage volume tracks *footage availability*, not legal severity.**
The same act produced a two-game suspension in February and ended a career in September — the only variable that
changed was that video became public. **A "does evidence leak?" roll is a more faithful driver of story length than a
severity lookup**, and it is a far more interesting one to play against.

Minor but characterful `[A]`: releases cluster on **Fridays and holidays** — a documented Memorial Day arrest-and-cut,
a Memorial Day release, a Friday arrest-and-same-day-cut. Free news-cycle burial. Cheap flavour, real behaviour.

### 4.13 Market and contract impact

**Draft-slide costs, normalised against the 2026 rookie salary scale (4-year total value) `[A]`:**
pick 1 **$58.19M** · pick 5 $48.59M · pick 10 $31.42M · pick 13 $25.77M · pick 20 $21.09M · pick 32 $16.99M ·
**pick 33 $13.53M** · pick 48 $10.40M · pick 64 $7.93M · pick 100 $5.71M · pick 185 $4.70M.

| Documented slide | Projected → actual | Cost `[B]` |
|---|---|---:|
| Video posted to a hacked account **10 minutes before the draft** | No. 1 overall → **13** | **≈ $32.4M** |
| Named in a murder investigation (never a suspect) | top-10 → **undrafted**; signed 3yr/**$1.599M** | **≈ $30M** |
| Pre-draft assault video | high 1st → **60** | ≈ $23M |
| Assault video, **denied a Combine invitation** | 1st round → **48** | ≈ $10.7M |
| Pending assault charge (dropped 3 weeks after the draft) | early 2nd → **185** | ≈ $8.8M |

**The counter-intuitive shape worth encoding:** the **1st-to-2nd-round cliff is small** (pick 32 → 33 is only $3.5M),
but **falling out of the top ten is enormous** (pick 1 → 13 is $32.4M). **A red flag that moves a top-5 player to
mid-first costs more absolute money than one that moves a Day 2 player to Day 3.** Most games get this backwards.

**Pre-draft machinery that is real and citable `[A]`:**
- **"Off the board" is a literal mechanism**, not a euphemism — multiple teams removed specific prospects entirely,
  and in one case two teams with a glaring need at exactly that position both passed.
- **The Combine is a gate.** The league has **denied Combine invitations** to prospects with violent histories,
  forcing them to Pro Days — a pre-draft sanction with direct market consequence.
- **Teams run counter-investigations.** One club **administered a polygraph** days before the draft and took the
  player at 24 when he passed; a grand jury later declined to charge and a civil jury found him not liable. Another
  GM **interviewed the prosecutor** and needed **owner sign-off** to make the pick.
- **Some owners hold an explicit no-DV line**, on the record: *"playing in the NFL is a privilege, not a right … I
  believe that privilege is lost for men who have a history of abusing women."*
- **A documented numeric "character grade" rubric could not be found.** `[D]` Treat any specific scale as invented —
  build your own, but don't claim it's the league's.

**Veteran-market outcomes — a genuinely bimodal distribution `[A]`:**

| Path | Cases | Shape |
|---|---|---|
| **Full recovery to top-of-market** | 6+ documented (the draft-sliders above, plus stars who were retained) | reach top-of-position extensions *after* the incident |
| **Comeback at the minimum, partial climb** | several | released → signed off the exempt list by a new team → 8-game suspension → modest extension → back to minimum/practice squad within 4–5 years |
| **Total evaporation** | 4+ documented | never signed again at any price, including a 27-year-old who won his appeal, settled a **$3.529M back-pay grievance**, and publicly offered to donate a full season's salary to charity |

**Talent is the sorting variable.** The players who returned to top-of-market money were all high performers; the
ones who never played again were declining, older, or replaceable — the same 4.5× starter-vs-backup spread from §3.2,
observed on the money axis instead of the seasons axis.

**One documented contract-timing detail worth stealing `[A]`:** a team released a star **hours before his salary
became guaranteed**, and separately fined him **$215,000**. Guarantee-vesting dates are a real lever teams use under
conduct pressure, and they are exactly the kind of grubby detail that makes a management sim feel authentic.

### 4.14 On-field performance after an incident — bimodal, not a uniform decline

The peer-reviewed finding is the anchor `[A]`: on a matched-pairs Bayesian negative-binomial model of all 117 VAW
arrests 2000–2019 —
> "the effect of an arrest on player careers is **negligible**, though it has become slightly more detrimental over
> time. **Player value and performance are stronger predictors of post-arrest career trajectories, and average or
> better performance negates any detrimental impact of an arrest.**"

Documented individual before/after `[A]`:

| Position | Absence | Result |
|---|---|---|
| RB, MVP-calibre | lost a full season (exempt + suspension) at age 29 | **Led the league in attempts, yards and rushing TDs the very next year** |
| RB, elite | 6-game suspension | dipped to 4.1 Y/A in the suspension year, then **led the league in rushing again the following year** |
| RB, Pro Bowl | 3-game suspension | essentially unchanged (3.7 → 4.0 → 4.2 Y/A across the incident) |
| RB, former rushing champion | 8-game suspension | **never regained rookie efficiency** — 4.9 Y/A before, 3.0–3.8 since (age/usage confounded) |
| WR, 1,300-yard | full year lost | recovered to ~1,000 yards but **not to peak** |
| **QB, franchise** | ~2 years (no games one season + 11-game suspension) | **severe and permanent**: 112.4 rating / 8.9 Y/A before → 79.1 / 84.3 / 79.0 and 5.3 Y/A after. Never close to prior form. |

**Model this as bimodal by position, not as a flat decay `[B]`:**
- **RB / WR / DEF: long absences mostly recover fully.** Three of the biggest names returned to league-leading
  production immediately after losing a full season or most of one.
- **QB: does not recover.** Timing, reps and offensive continuity compound; the one franchise-QB case in the data is
  a permanent, severe decline.
- **Team-level "distraction" effect: no supporting evidence found.** `[D]` One club won a Super Bowl in the 16 months
  between a star's felony gun arrest and his eventual suspension. **Do not implement a locker-room performance
  penalty for having a player under investigation** — it would be inventing an effect the record does not show.

---

## 5. ARCHETYPAL CASE PATTERNS (anonymized templates)

Twelve templates, each with the real case(s) behind it named in the citation line **for verification only**.
**Ship none of the real names, teams, or verbatim statements** — these are shape references. Frequencies are given as
expected occurrences per league-year at λ = 38 incidents/yr. `[C]` unless a specific figure is marked otherwise.

---

### A1 — "The 24-Hour Cut"
**Frequency: ~8–10 per league-year** (the single most common pattern in the whole system)

- **Profile:** practice-squad, UDFA, or minimum-deal depth player. **No dead money.**
- **Trigger:** any charge at all — the severity genuinely does not matter.
- **Timeline:** arrest (usually 1–4am, usually offseason) → booked → **released within 0–24 hours.**
  Fastest documented: **~3 hours.**
- **Team response:** a one-line transaction note or a single social post. **No four-clause statement.**
- **League response:** none. The player is off the roster before any process begins.
- **Legal outcome:** typically a plea to a reduced charge months later, unreported.
- **Media arc:** **1 day, often zero** — a transaction line.
- **Market:** signs elsewhere at minimum within weeks if he has any value; otherwise out of the league.
- *Behind it:* a Steelers PS LB released ~3 hours after a Dec 2023 DV call; a Jets journeyman cut in 1 day over a
  **$300 marijuana bond** (Jun 2024); a Bucs UDFA with zero career snaps cut 1 day after a misdemeanour DUI (May 2022);
  a Cowboys PS WR cut over a suspended-licence charge (Jun 2023).
- **Game parameters:** `P(release) ≈ 0.85`, `lag = 0–1 days`, `media_days = 1`, `league_discipline = none`,
  `reputation_hit = minimal` (nobody notices).

---

### A2 — "The Quiet Cutdown Delay"
**Frequency: ~3–4 per league-year**

- **Profile:** rotational player with modest dead money — worth keeping *if* the case evaporates.
- **Trigger:** mid-severity charge (assault, DV misdemeanour, drugs).
- **Timeline:** arrest → **team takes no action for ~60 days** → parked on IR or the exempt list through camp →
  **waived on cutdown day**, framed as a football decision. Total elapsed: up to **14 months.**
- **Team response:** silence, then a roster move indistinguishable from a normal cut.
- **League response:** exempt list possible; suspension often never materialises.
- **Media arc:** 2 days at arrest, **0 days at release** — nobody connects them.
- *Behind it:* a Titans RB arrested for aggravated assault by strangulation (Jun 30 2023) → no team action for 60
  days → IR Aug 28 → exempt list Aug 29 → **waived Aug 27 2024 on cutdown day**.
- **Game parameters:** `P(release) ≈ 0.6` but `lag = 60–400 days`; the release is **reported as a football move**.
  This is the template that teaches the user that the roster page and the news feed do not always agree.

---

### A3 — "The Starter's DUI That Costs Nothing"
**Frequency: ~4–5 per league-year**

- **Profile:** established starter, mid-market contract.
- **Trigger:** DUI or extreme-speed arrest, no injury to anyone.
- **Timeline:** arrest → **head coach publicly confirms he will play that week** → plays → season ends → free agency
  barely reacts → a league suspension may arrive **a year later**.
- **Team response:** statement, **no deactivation, no discipline.**
- **League response:** 0 games in year one; possibly 3 games the following season under the alcohol track.
- **Legal outcome:** plea, probation, fine.
- **Media arc:** ~1 week, revived briefly at each court date.
- **Market:** essentially unaffected — one such player signed a **2yr/$9.5M** deal in the following offseason with a
  second DUI in between.
- *Behind it:* a Rams WR arrested at >100 mph with "objective signs of alcohol impairment" hours after a Nov 2024
  loss; the head coach said publicly he would not be suspended and would play the next week; second DUI Jan 2025;
  signed with San Francisco Mar 2025; league suspension 3 games in 2025.
- **Game parameters:** `P(release) ≈ 0.05`, `deactivations = 0`, `league_games = 0 now / 3 later (30%)`,
  `market_multiplier ≈ 0.97`.

---

### A4 — "The Airport Gun Charge"
**Frequency: ~4–5 per league-year** *(observed: 17 gun arrests in 39 months)* `[A]`

- **Profile:** any tier. Genuinely uncorrelated with player quality.
- **Trigger:** firearm found in a carry-on or checked bag, usually at a strict-permit-state airport where the
  player's home-state permit is not valid.
- **Timeline:** arrest → charged with **felony criminal possession** → 2–8 months → **pleads down to a violation or
  disorderly conduct with a token fine.**
- **Team response:** statement; **no release for a valuable player**; A1 rules apply if he is fringe.
- **League response:** usually **none**, occasionally a token suspension. Exempt list available but rarely used.
- **Legal outcome:** one documented case went from **two felonies to a plea to disorderly conduct and a $250 fine.**
- **Media arc:** 2 days.
- *Behind it:* a Jets DT at LaGuardia (2020) → disorderly conduct plea, $250; a Patriots CB at Boston Logan (2023),
  two firearms in carry-on; a Packers OL at LaGuardia (2026); an Eagles LB at Miami.
- **Game parameters:** high embarrassment, near-zero football cost. `reputation_hit = moderate`,
  `league_games = 0 (80%) / 1–2 (20%)`, `resolution = plea-down (75%)`.

---

### A5 — "The Indictment Trigger"
**Frequency: ~1–2 per league-year**

- **Profile:** recent high draft pick with real dead money. The team **wants** to keep him.
- **Trigger:** felony DV arrest.
- **Timeline:** arrest → **team does nothing for ~4 months** → **grand jury indicts** → **released the next day.**
- **Team response:** the full four-clause statement, deployed only at the release.
- **League response:** moot — he is off the roster.
- **Media arc:** 2 days at arrest, 3 days at indictment.
- **Market:** typically out of the league.
- *Behind it:* a Vikings 2020 first-round CB — arrested Apr 5 2021, **indicted Aug 2 2021, released Aug 3 2021:
  120 days from arrest, 1 day from indictment.**
- **Game parameters:** the cleanest demonstration of the forcing-function rule. `P(release | arrest) ≈ 0.1` but
  `P(release | indictment) ≈ 0.9`, `lag_from_indictment = 0–1 days`.

---

### A6 — "The Video Detonation"
**Frequency: ~0.5–1 per league-year** — rare, but the highest-impact single event in the system

- **Profile:** any tier, but the drama scales with value.
- **Trigger:** an incident occurs and is initially handled quietly — modest coverage, modest or no discipline.
  **Then footage becomes public weeks or months later.**
- **Timeline:** incident → small story → **[gap of weeks to 10 months]** → video published → **release within hours**,
  discipline escalated to indefinite.
- **Team response:** same-day release, full statement, sometimes a public apology for the earlier handling.
- **League response:** original discipline **replaced** with an indefinite suspension.
- **Media arc:** the second peak dwarfs the first — **months**.
- *Behind it:* an RB whose Feb 2014 arrest produced a **2-game suspension**, and whose **Sep 2014 video of the same
  act** produced same-day release, indefinite suspension, a jersey-exchange programme, and the end of his career at
  27 — he later won his appeal and settled a **$3.529M** back-pay grievance and **still never signed anywhere**.
  Also an RB released within hours of a Nov 2018 video publication (never arrested at all), 8-game suspension, signed
  by another club ~10 weeks later **directly onto the exempt list**.
- **Game parameters:** implement as a **deferred `evidence_leak` roll** on any incident, resolving 1–10 months later
  with `P ≈ 0.05–0.10`. On success: `severity × 3`, `P(release) → 0.95`, `media_days × 10`,
  `market_value → ~0`. **This one mechanic does more for the system's texture than any severity table.**

---

### A7 — "The Star Who Gets Extended"
**Frequency: ~1–2 per league-year**

- **Profile:** genuine star, cheap contract, enormous surplus value.
- **Trigger:** serious allegation, often without a criminal charge ever being filed.
- **Timeline:** allegation → **barred from team activities in ~1 day** (a gesture, not a punishment) → league
  investigation → **declines discipline at ~84 days** → **extension signed at ~133 days.**
- **Team response:** temporary distancing, then full commitment.
- **League response:** **0 games.**
- **Media arc:** ~3 months, then gone.
- **Market:** *rises.* The player later commanded a **$120M** deal on a subsequent trade.
- *Behind it:* a Chiefs WR — barred Apr 26 2019, league declined discipline Jul 19 2019, **3yr/$54M extension
  Sep 6 2019**; traded 2022 for **4yr/$120M, $72.2M guaranteed**.
- **Game parameters:** `P(release) ≈ 0.05`, `league_games = 0`, `market_multiplier ≈ 1.0–1.1`,
  `fan_reputation_hit = large and persistent` — the cost lands on the **franchise**, not the player. That split is
  the interesting part: the GM pays a reputation price for a football win.

---

### A8 — "The Sponsor Reversal"
**Frequency: ~0.5 per league-year**

- **Profile:** marquee, nationally-known player — the tier where sponsors have exposure.
- **Trigger:** indictment in a case with strong public salience (child abuse, DV).
- **Timeline:** indicted → deactivated for one game → **REINSTATED 3 days later** → **placed on the exempt list
  2 days after that** when sponsors publicly move.
- **Team response:** visibly incoherent — and that incoherence is the authentic part.
- **League response:** exempt list, then suspension for the remainder of the season; reinstated the following spring.
- **Market:** retained, then released two years later; production **fully recovered** (led the league in rushing the
  season after losing a year).
- *Behind it:* a Vikings RB, Sep 2014: indicted Sep 12 → deactivated → **reinstated Sep 15** → **exempt list Sep 17.**
- **Game parameters:** a two-stage decision where the GM's first choice is **overturned by an external actor**.
  Excellent for teaching that the GM is not sovereign. `sponsor_pressure` fires on `player_fame × severity`.

---

### A9 — "The Franchise QB Civil Docket"
**Frequency: ~once per 5–10 league-years** — a save-defining event

- **Profile:** franchise quarterback on a large extension.
- **Trigger:** **civil suits, no criminal charge ever.** Accuser count climbs over weeks (1 → 22 → 27).
- **Timeline:** first suit → **team statement in 2 days, then nothing** → holds him a **full season** (he plays zero
  games) → grand juries **decline to indict** → **traded for three first-round picks** and given the **largest fully
  guaranteed contract in league history** → **11-game suspension + $5M fine + mandated treatment.**
- **Media arc:** **~43 months, 7+ distinct peaks.**
- **Performance:** **permanent, severe decline** — 112.4 rating / 8.9 Y/A before, 79–84 rating / 5.3–6.5 Y/A after.
- **Aftermath:** the acquiring owner later called it publicly *"a big swing and a miss."*
- *Behind it:* a Texans → Browns QB, Mar 2021 – Jan 2025.
- **Game parameters:** the "no arrest, still a catastrophe" class. Runs on the **civil-suit track, not the arrest
  track**; `criminal_charge = never`; `league_games = 11`; `fine = $5M`; `QB performance penalty = permanent`;
  `trade market = still active` — which is the genuinely uncomfortable, genuinely true part.

---

### A10 — "The Draft-Day Slide"
**Frequency: ~2–4 prospects per draft class**

- **Profile:** a top-50 prospect. **Note the policy covers all Combine attendees — they are in scope before they
  are ever employed.** `[A]`
- **Trigger:** a red flag surfaces days, or **minutes**, before the draft.
- **Timeline:** flag surfaces → some clubs **remove him from the board entirely** → falls → signs a much smaller
  rookie deal → often fully exonerated within weeks.
- **Cost:** **$8.8M – $32.4M** of rookie money, per the 2026 scale.
- **Counter-play (all documented):** clubs run their **own investigation**, **administer a polygraph**, or the GM
  **interviews the prosecutor** and needs **owner sign-off** to make the pick.
- **Market:** **most fully recover** — several reached top-of-position extensions 4–5 years later.
- *Behind it:* an OT who fell **No. 1-projected → 13** on a video posted to his hacked account 10 minutes before the
  draft (≈$32.4M); an OL who went **top-10-projected → completely undrafted** while never a suspect in the
  investigation, signing **3yr/$1.599M** (≈$30M); an RB denied a Combine invitation who fell **1st round → 48**
  (≈$10.7M); a DT who fell **early 2nd → 185** on a charge dropped three weeks after the draft (≈$8.8M).
- **Game parameters:** operates on **draft position**, not employment. `slide = 1–3 rounds` scaled by severity and
  recency; `P(some teams blacklist entirely) ≈ 0.3`; **investigation actions available to the GM at a scouting cost**
  — this is the natural tie-in to the project's existing scouting/character-grade machinery.

---

### A11 — "The Slow Federal Death"
**Frequency: ~0.5–1 per league-year**

- **Profile:** any tier; frequently a recently-retired or fringe player.
- **Trigger:** federal financial-crime indictment — fraud, PPP/relief conspiracy, money laundering.
- **Timeline:** indictment → **12–36 months** → sentencing → prison.
- **Team response:** none needed; the player is usually already unsigned.
- **League response:** none — he is not on a roster. (The conduct policy's *"crimes of dishonesty"* bullet covers it
  if he is.) `[A]`
- **Media arc:** one story at indictment, one at sentencing. **Two peaks, 18 months apart.**
- **Contract note:** **incarceration resulting in unavailability is an enumerated "Forfeitable Breach"** under CBA
  Art. 4 §9 — bonus allocations can be clawed back. `[A]`
- *Behind it:* a WR charged in a **$24M** PPP conspiracy (~90 fraudulent applications, 42 funded for ~$17.4M,
  ~$1.2M personally) → **37 months federal prison**.
- **Game parameters:** the only quiet career death. `P(release) = n/a`, `unavailable_seasons = 1–3`,
  `bonus_clawback = up to 100% of unearned allocations`, `media_days = 2 peaks`.

---

### A12 — "The Escalating Repeat Offender"
**Frequency: ~2–3 active cases per league-year** — driven by the hidden-risk cohort (§3.4)

- **Profile:** a player carrying the elevated latent risk trait. **~6% of the population, ~23% recidivism after one
  incident, ~32% after two.** `[A]`/`[B]`
- **Trigger:** a cluster — **three or four arrests inside 11 months** is documented.
- **Timeline:** each individual incident is survivable; the team absorbs #1 and #2; **the cut comes on the one that
  crosses a public line** (a charge involving a vulnerable person, a weapon, or a third strike).
- **Team response:** progressive. Statement → statement → deactivation → same-day release.
- **League response:** **the policy escalates automatically** — prior violations are an enumerated **aggravating
  factor**, "players with a prior history of misconduct … will be subject to enhanced and/or expedited discipline,"
  and a **second qualifying violation is permanent banishment** with a one-year petition window. `[A]`
- **Market:** evaporates. Nobody signs a documented cluster.
- *Behind it:* an RB with **four arrests in 11 months**, released the same day as the fourth (aggravated battery on a
  pregnant person — an enumerated aggravator); a veteran DL cut one day after a **third** DUI.
- **Game parameters:** the payoff mechanic for the hidden risk trait. Each incident **partially reveals** the trait to
  the GM and to rival scouts; the escalation ladder is deterministic (policy tariff) while each individual incident is
  stochastic. **This is the archetype that makes character scouting worth paying for.**

---

### Two further patterns worth having, in brief

- **A13 — "The Animal Case."** ~1 per 3 league-years. Low legal severity, **disproportionate public reaction**,
  near-automatic release within days regardless of value. Enumerated in the policy as *"crimes involving cruelty to
  animals."* `[A]` *Behind it:* a Falcons LB charged with aggravated animal cruelty (May 2015), released within days.
  **The one category where reputation cost >> legal cost.**
- **A14 — "The Catastrophic Vehicle."** ~1 per 3–5 league-years. Star + extreme speed + alcohol + a fatality →
  **released the same day**, felony case, multi-year prison, career over. *Behind it:* a Raiders WR, Nov 2021,
  156 mph, guilty plea, **3-to-10 years**. Note the team issued the standard *"gathering information"* statement
  hours **before** releasing him the same night — the script runs even when the outcome is already certain.

---

## 6. SYNTHESIS — implementation spec

### 6.1 The event pipeline (state machine)

```
                     ┌─ monthly weight (§2.3) ─┐
league-year draw ────┤ NegBin(μ=38, var≈64)    ├──► INCIDENT
                     └─ team culture 0.5–2.0×  ┘      │
                                                      ├─ category roll (§1.0b)
                                                      ├─ player pick: uniform over roster
                                                      │   × hidden risk trait (6% cohort, 4–5×)
                                                      ▼
                                              ┌─── ARREST / ALLEGATION ───┐
                                              │                            │
                            ┌─────────────────┴──────────┐        (civil-suit track:
                            ▼                            ▼         no arrest, §1.8 / A9)
                    TEAM DECISION                 LEAGUE PROCESS
                    (leverage-gated, §4.10)        (independent, §4.1)
                            │                            │
        ┌───────────────────┼──────────────┐             ├─ exempt list? (felony OR crime
        ▼                   ▼              ▼             │   of violence formally charged)
   release 0–4d       statement only   deactivate        ├─ investigation (weeks–months)
   (low leverage)     (high leverage)   1–2 games        ├─ Disciplinary Officer decision
                            │                            ├─ 6-game baseline × aggravators
                            │                            │   ÷ mitigators (§4.1)
                            ▼                            └─ appeal (5 business days)
                   ⟨ FORCING FUNCTION? ⟩                          │
                   evidence leak (5–10%, 1–10 mo)                 ▼
                   indictment                              SUSPENSION / FINE
                   exempt-list placement                   (exempt time credited back,
                   sponsor pressure                         salary repaid pro rata)
                            │
                            └──► release even at high leverage
                            
   LEGAL TRACK (parallel, §4.7): dropped / diversion / plea-down / conviction / acquittal
                                 / **never resolved (~25%)**
```

**Three structural rules that carry most of the fidelity:**
1. **The legal track and the league track resolve independently.** "Charges dropped" ≠ "no suspension" — diversion
   and deferred adjudication are explicitly *dispositions* under the policy (§4.2).
2. **Teams do not act on severity; they wait for a forcing function** (§4.10). Absent one, the default is to keep
   playing the player.
3. **Incidence is flat across player quality; consequences are steeply stratified by it** (§3.2).

### 6.2 Master tuning table

| Parameter | Recommended value | Source |
|---|---|---|
| League incidents per year | **NegBin(mean 38, var 64)** | §2.1 |
| Per-player-season probability | **1.5%** (53-man + PS denominator) | §2.2 |
| Per-team-year expectation | **1.21** | §2.6 |
| Team culture multiplier range | **0.5× – 2.0×** (hard cap) | §2.6 |
| Position multiplier | **none, or 0.85×–1.20×** | §3.5 |
| Hidden risk cohort | **6% of players at 4–5× base rate** | §3.4 |
| Recidivism after 1 incident / 2 incidents | **23% / 32%** | §3.4 |
| Monthly weights | Jan .60 · Feb 1.05 · Mar 1.15 · Apr 1.15 · **May 1.80** · Jun 1.65 · Jul 1.45 · Aug .95 · Sep–Dec .55 | §2.3 |
| Category mix | DUI 26 · DV 14 · assault 12 · weapons 12 · drugs 9 · disorder 9 · theft 4 · reckless 4 · sex 2 · homicide 1 · animal 0.8 · other 6.2 | §1.0b |
| Conduct baseline (felony assault / DV / sexual assault) | **6 games**, second violation = **permanent banishment** | §4.1 |
| Aggravators (each shifts up) | prior violation · pre-NFL similar misconduct · weapon · **choking** · repeated striking · vulnerable victim · **in presence of a child** | §4.1 |
| Mitigators (each shifts down) | prompt acceptance + cooperation · voluntary clinical engagement · **victim restitution** | §4.1 |
| Suspension length, non-DV categories | **mode 1 game, median 3, mean 3.39** | §4.8 |
| Suspension length, DV / sexual assault | **mode 6, median 6, mean 5.5** | §4.8 |
| Shape | **bimodal — mass at 1–2 games + hard spike at exactly 6** | §4.8 |
| Appeal changes the number | **~80%** of contested cases; ~85% reduce, ~15% increase | §4.8 |
| Modal league outcome of any given incident | **0 games** | §0 |
| Conviction rate — all arrests / DV / DUI | **47–50% / 21–23% / 70–71%** | §4.7 |
| Diversion rate — all / DV | **13–15% / 36–38%** | §4.7 |
| Cases never publicly resolved | **~26%** | §4.7 |
| Exempt-list placement on a qualifying charge | **P ≈ 0.35**, publicity-driven, not automatic | §4.3 |
| On-field fines per conduct suspension | **~50–100** | §4.9 |
| Release lag, low leverage | **median 1 day; 60% ≤24h; 85% ≤4 days; P(release) ≈ 0.85** | §4.10 |
| Release lag, high leverage | **months to never**; requires a forcing function | §4.10 |
| Evidence-leak roll | **5–10%**, resolving 1–10 months later, `severity × 3` | §4.12 |
| Media arc | 1 day (fringe) → 1–2 weeks (starter) → 5–14 months (star) → 43 months (franchise QB + civil docket) | §4.12 |
| Draft slide cost | **$8.8M – $32.4M**; steepest penalty for falling *out of the top ten*, not out of round 1 | §4.13 |
| Post-incident career length by role | starter **4.05** seasons · rotational **1.95** · non-starter **0.90** | §3.2 |
| Age effect on post-incident career | **−9% expected seasons per year of age** | §3.1 |
| Performance after a long absence | RB/WR/DEF **recover fully**; **QB does not**; no team-level distraction effect | §4.14 |

### 6.3 What the evidence says NOT to model

Recording these explicitly, because each is an intuitive design choice that the data contradicts:

1. **Do not make incidents frequent.** ~1.2 per team-year, 30% of teams clean. The "players are always in trouble"
   trope is false — NFL players are arrested **less** than demographically comparable men on every charge except
   weapons (§2.5).
2. **Do not use the "one arrest every 2–3 days" figure.** It is an offseason-month statistic misapplied annually and
   will over-produce events ~3× (§2.3).
3. **Do not tie release probability primarily to charge severity.** It tracks contract leverage (§4.10).
4. **Do not implement a team-level "distraction" performance penalty.** No supporting evidence found (§4.14).
5. **Do not apply a uniform post-suspension performance decay.** The effect is bimodal by position (§4.14).
6. **Do not use a strong position multiplier.** Unnormalised raw counts only; a strong multiplier encodes a
   stereotype (§3.5).
7. **Do not correlate risk with any demographic attribute** (§3.7).
8. **Do not resolve every case.** ~25% of real cases never produce a legible ending (§4.7).
9. **Do not treat "charges dropped" as "no league consequence."** Diversion is a disposition (§4.2).
10. **Do not suspend for marijuana in a post-2020 setting.** The CBA removed it (§1.5).
11. **Do not treat a conduct suspension as automatically voiding bonus money.** It is *not* a Forfeitable Breach;
    only negotiated guarantee-void language reaches it (§4.6).
12. **Do not model "NFL players get off easy" as a conviction-rate effect.** Their DV conviction rate (21–23%) is
    in line with the national baseline (~22–31%). The real anomaly is **diversion access** (§4.7).
13. **Do not make exempt-list placement automatic on a qualifying charge.** Real usage is inconsistent and tracks
    publicity (§4.3).

### 6.4 Content-safety notes for the fictional implementation

- **Everything ships fictionalized.** Generate fictional player names, fictional team names, fictional outlet names,
  and paraphrased statement templates. The verbatim quotes in §4.11 are shape references, not shippable strings.
- **The four heaviest categories (DV, sexual misconduct, child-related, homicide) need an editorial decision the
  research cannot make for you.** They are the highest-frequency-weighted *and* the highest-risk content. Options:
  include with restrained, non-graphic copy; abstract them to "a serious off-field incident" with the mechanical
  consequences intact; or omit and redistribute their probability mass. **Recommendation: keep DV in the model as a
  consequence generator but never render incident detail** — the game needs the 6-game baseline and the star-vs-depth
  divergence, and it needs none of the specifics.
- **Age rating:** on-screen depiction of criminal conduct affects App Store rating. Text-only news-item framing with
  no depiction is the low-risk path; the existing press/news machinery in this project already provides that shape.
- Never reference the real league, the real policy by name, or real personnel in shipped strings — the existing
  trademark guard already enforces this and should be extended to cover any new life-event string tables.

### 6.5 Gaps and open questions

| Gap | Status |
|---|---|
| Full-year arrest totals for 2024, 2025, 2026 | **Not published.** Row-counts off the live database are undercounts. |
| Monthly distribution for the modern (post-2020) era | Only n=20 available; historical 80/20 may no longer hold (§2.3) |
| Arrests broken down by starter/backup or rookie/veteran | **Never published on either axis** (§3.6) |
| Position arrest rates normalised by roster share | **Never published** (§3.5) |
| Quantitative media-volume data (Google Trends / coverage counts) | Not obtained; §4.12 arcs are event-chronology measurements |
| A documented numeric "character grade" rubric | **Does not appear to exist publicly** (§4.13) |
| Complete list of league discipline outcomes 2015–2026 with games per case | **CLOSED** — histogram now in §4.8 (n=23 / n=42 / n=16 DV) |
| Aggregate count of league discipline imposed with no criminal charge | **No published figure.** A 16-case benchmark set shows charges never filed in 6, dropped in 4, conviction/plea in 3 |
| Last published full Personal Conduct Policy text | **2022 edition** — later amendments known only via reporting |

**Highest-value follow-up if this gets another research pass:** modern-era (post-2020) **monthly** arrest
distribution. It is now the weakest quantified link in the chain — §2.3 rests on 2007–13 data plus an n=20 modern
sample, and the recommended 2.2× offseason ratio is an explicit compromise rather than a measurement. Everything
else in this file is either directly sourced or derived from sourced numbers.

---

## 7. SOURCE INDEX

**Databases & compilations**
- USA TODAY NFL player arrests database — `databases.usatoday.com/nfl-arrests/` (live; entries through Jun 2026;
  maintained by Brent Schrotenboer). Predecessor: *San Diego Union-Tribune* database, 2000–2014.
- Kaggle "NFL Arrests 2000-2017" (Patrick Murphy), 850 records — via `student.elon.edu/etobe/NFLarrest/`
- CNS Maryland, "Crime in the NFL" — `cnsmaryland.org/interactives/Crime-In-NFL/`

**Per-year series and league figures**
- ESPN, 9 Oct 2024, "NFL executive: Arrests down 'by half' since Ray Rice case" —
  `espn.com/nfl/story/_/id/41208399/` — **the 2011–2023 year-by-year table and the DV-cases-reported series**
- NYT Upshot (Sep 2014) charge-type table, n=713 — via `ramsondemand.com/threads/...30167/`
- Deadspin, "What Do Arrests Data Really Say About NFL Players and Crime" — per-1,000 rate comparison vs FBI UCR

**Academic**
- Sailofsky, D. (2022). "More Talent, More Leeway: Do Violence Against Women Arrests Really Hurt NFL Player Careers?"
  *Violence Against Women*. **DOI 10.1177/10778012221092477** — `pmc.ncbi.nlm.nih.gov/articles/PMC10090526/`
- Leal, W., Gertz, M., & Piquero, A.R. (2015). "The National Felon League?: A comparison of NFL arrests to general
  population arrests." *Journal of Criminal Justice*. **DOI 10.1016/j.jcrimjus.2015.08.001**
- Piquero, Leal & Gertz, *Deviant Behavior* — 774 arrests / 573 players, 27% violent, 77/16/7 repeat split —
  `news.utdallas.edu/?p=11472`

**Policy & CBA (primary)**
- **NFL Personal Conduct Policy, League Policies for Players, 2022** —
  `nflpaweb.blob.core.windows.net/website/Departments/Salary-Cap-Agent-Admin/2022-NFL-Personal-Conduct-Policy.pdf`
  (full text extracted; §§ I–IX quoted in §4.1–4.4 above)
- CBA Article 4 §9, Forfeiture of Salary — `overthecap.com/collective-bargaining-agreement/article/4`
- CBA Article 46 (discipline/appeals) — `overthecap.com/collective-bargaining-agreement/article/46`
- 2020 CBA substance-of-abuse changes — NBC Sports PFT / InsideHook / Yahoo Sports coverage, Feb–Mar 2020
- Suspension tariffs by track — `profootballnetwork.com/how-do-nfl-suspensions-work/`
- 2026 rookie salary scale — `overthecap.com/draft`

**Case reporting** (used only as anonymized shape references in §5)
- Team statements: nfl.com, si.com, cbssports.com, espn.com, vikings.com official releases, 2015–2026
- Release-lag audit: profootballrumors.com, espn.com, nfl.com transaction reporting, 2015–2026
- Gun-arrest count: `outkick.com/sports/nfl-has-at-least-17-gun-arrests-since-march-2020` (21 Jun 2023)
- Federal fraud case: justice.gov press releases; espn.com sentencing report
- Animal cases: justice.gov; cnn.com (5 Aug 2025); foxnews.com (2015)
- 2026 offseason DV cluster: foxnews.com/sports (Jun 2026)

**Discipline, fines and contract mechanics (primary, added in the final pass)**
- NFL Personal Conduct Policy, **Dec 10 2014** edition — `workplacebullying.org/multi/pdf/NFL-Conduct.pdf`
- 2020 CBA Art. 46 §1(e) (jointly selected Disciplinary Officer) and §5 (exempt-list credit-and-repay)
- **CBA Appendix A, NFL Player Contract ¶11 and ¶15** (club termination right; Commissioner authority)
- **CBA Appendix U** — on-field fine schedule, escalation, caps, collection limits, proceeds split
- USA TODAY PED-suspension database — `databases.usatoday.com/nfl-performance-enhancing-drug-suspensions/`
- ESPN, "What is the NFL commissioner exempt list?" — `espn.com/nfl/story/_/id/41125210/`
- SI, 7 Aug 2023 — 2023 PCP disclosure amendment
- Villanova Sports Law Journal blog, 8 Apr 2026, "Benched Before Proven Guilty" — exempt-list inconsistency

**Legal-outcome baselines (primary)**
- NIJ 2009, **NCJ 225722** (Garner & Maxwell) — DV prosecution/conviction pipeline
- BJS 2009, **NCJ 243777** — felony defendants in the 75 largest counties
- Benedict & Klein 1997; Withers, *Harvard JSEL* 2010 and Jul 2015
- Blumstein & Benedict, *CHANCE* 12(3), 1999
- Morris/FiveThirtyEight, 31 Jul 2014 + 2 Oct 2014 follow-up + Apr 2015 revision — **recovered via Wayback**

**Rejected sources**
- **SporViz** NFL arrests timeline — category counts irreconcilable with the NYT/USA TODAY figures (Gun-Related 254
  vs 38; Theft/Burglary 200 vs 21). Do not use.
- FiveThirtyEight, "The Rate of Domestic Violence Arrests Among NFL Players" (Jul 2014) — **article delisted**, now
  301-redirects. **Full text since recovered via Wayback**, so §1.2's figures are confirmed: NFL overall arrest rate
  **13–14% of the national average for men 25–29**; DV relative rate **55.4%**; DV = **48% of NFL violent-crime
  arrests vs ~21% nationally**. Cite the Wayback snapshot, not the live URL. Note the author's own Oct 2014 follow-up
  calls the 55.4% figure "misleading… out of context" — quote it with that caveat attached.

*End of R1.*
