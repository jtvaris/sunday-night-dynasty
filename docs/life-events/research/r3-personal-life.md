# R3 — Personal Life, Distractions & Non-Football Events in the NFL (~2015–2026)

**Purpose.** Grounding research for a *fictional* life-events system in Sunday Night Dynasty.
**Hard rule for downstream implementation:** every real name below is a **citation only**. Nothing here ships as
in-game text. The shipping system must use generated fictional names, generated team names, and paraphrased
event copy. `tools/trademark_guard.sh` must stay green.

**Scope split.** Two sibling agents cover (a) arrests/legal and (b) league-policy suspensions (PED, gambling,
substance, personal-conduct). This report covers everything *else* — the "life happens" spectrum.

**Confidence markers used below:**
- `[V]` verified this session against a fetched source (URL in §10)
- `[R]` recalled/widely-reported, consistent with fetched sources but not individually re-verified here
- `[E]` my estimate/derivation, not a published statistic

**Population base for all frequencies:** ~1,696 active roster spots (32 × 53) + ~544 practice squad
(32 × 17) ≈ **2,240 roster slots**, and **~2,900–3,200 distinct players** touch an NFL roster in a
league-year once you count camp bodies (90-man camp rosters = 2,880 alone). "Per league-year" below means
across that whole population unless stated.

---

## 1. RELATIONSHIPS & FAMILY

### 1.1 High-profile relationships / celebrity media circus

**Canonical case: the Kelce–Swift arc (2023 → 2026).** `[V]`
- Relationship began 2023; engagement announced **August 2025** (announced on his own podcast; one of
  Instagram's top-10 most-liked posts ever); married **July 3, 2026** at Madison Square Garden.
- Documented *league-level* effects: ~**$331.5M in brand value** generated for the NFL; credited with a
  **20% increase in sponsorships** for the 2023 season ($2.35B revenue); viewership **+53% among teenage
  girls**, **+24% among 18–24**. Nicknamed "the Taylor Swift effect."
- Documented *team-level handling*: the Chiefs deliberately **did not** play her music at Arrowhead, "to be
  respectful" of Kelce; team president said "we never showed Taylor Swift" on the videoboard; the player
  himself asked the club not to market the relationship. Mahomes' public line: it was "a bigger deal to the
  fan bases than to the guys in the building."
- Documented *friction*: broadcast criticism (cameras cutting to the suite instead of the field); by 2024 she
  reduced sideline-camera exposure. Locker-room gossip stories appeared around the 2026 wedding (tabloid-tier
  sourcing — treat as "anonymous-source rumor" archetype rather than fact).
- **Design read:** a celebrity-relationship event should raise *team revenue/marketability* and *player
  fame*, add a persistent *media-pressure* modifier, and create a small chance of a "distraction" narrative
  that only bites if the team is losing. Note the asymmetry: when the team won, the story was an asset; the
  "distraction" framing only appeared in loss weeks.

**Other celebrity-relationship reference points** `[R]`: quarterback–pop-star, RB–supermodel, QB–actress
pairings recur roughly **1–3 new "circus-tier" couplings per league-year**, almost always involving a
top-25-fame player. Sub-circus tier (local celebrity, reality TV, influencer) is far more common.

**Frequency `[E]`:** circus-tier: **1–3 per league-year**, star-only. Notable engagement/wedding coverage
for a recognizable player: **10–25 per league-year**.

### 1.2 Marriages & weddings

- NFL weddings cluster hard in **late June–July** (post-minicamp, pre-camp) and **February–March**
  (post-season, pre-offseason program). An in-season wedding is essentially unheard of for a starter. `[R]`
- Honeymoons produce their own injury tail — e.g. a linebacker injured his hand **exiting a pool on his
  honeymoon in Greece (2017)**. `[V]`
- **Design read:** weddings are an offseason-window event; they should produce a small positive morale bump
  and a tiny non-football-injury risk roll.

### 1.3 Divorce mid-season

**Canonical case: the QB divorce season (2022).** `[V]`
- An **11-day excused absence from training camp** for "personal reasons" (spent on a family vacation)
  preceded months of speculation; divorce filed and finalized **late October 2022**, mid-season.
- Team effect on record: his former head coach said publicly that his personal life played a role in the
  team's struggles that year — *"it wasn't the real [him] out there"* — while crediting him for playing
  through it. The team went from Super Bowl contender to a losing regular season.
- Media arc: **~4 months** of continuous speculation before the announcement, then a **~2-week** acute spike,
  then a season-long "is he distracted?" undertone.
- **Design read:** the mechanic that matters isn't the divorce — it's the **camp absence + season-long
  performance-vs-expectation gap + reporter question every week**. Model as: multi-week attribute
  suppression (5–15% on composure/decision-making), permanent-for-the-season media pressure, and a
  coach-relationship strain roll.

**Frequency `[E]`:** publicly-reported divorces of recognizable players: **3–8 per league-year**; ones that
become an in-season storyline: **0–2 per league-year**.

### 1.4 Child births (the paternity-absence canon)

This is the single most *frequent* legitimate "player is not here today" event, and it has a rich,
well-documented decision structure — perfect for a game choice.

Verified/reported instances `[V]` unless noted:
| Player | Team | Year | Decision |
|---|---|---|---|
| CB, veteran | Bears | 2012 | Stated intent to miss a game for the birth; national debate followed |
| LB, veteran | Vikings | 2012 | Flagged as possible Thursday-game absence for 4th child |
| QB, starter | Ravens | 2013 | **Chose to play**, missed the birth of his second child |
| K, specialist | — | 2015 | (see §3, kickball) |
| RB, rotational | Patriots | 2019 | Missed a regular-season game for the birth |
| LB, starter | Patriots | 2019 | Missed the **season opener** for the birth |
| QB, young starter | Vikings | 2024 | Missed **practice** (not a game) for the birth |
| C, starter | Eagles | Feb 2023 | `[R]` Brought his wife's OB-GYN to the **Super Bowl** as a contingency (38 weeks pregnant) — the extreme version of the same dilemma |

- A notable talk-radio/columnist arc exists around this: the "should he miss a game?" debate has been
  re-litigated at least three times (2012, 2019, 2024), including a prominent commentator publicly reversing
  his own position. Great flavor for a media-reaction system. `[V]`
- **Contract/roster mechanics:** there is **no** paternity list in the NFL (unlike MLB's). Absence is simply
  an excused absence at the coach's discretion; the player stays on the 53. `[R]`

**Frequency `[E]`:** with ~2,240 roster players skewed male age 22–32, **150–250 births per league-year** is
plausible; those causing a *missed practice* — **40–80/yr**; those causing a **missed regular-season game** —
**3–10/yr**, and 1–2 of those become a national talk-show cycle.
**Timing:** uniform across the calendar, so ~60% land in-season (Sept–Jan) purely by calendar share.
**Who:** all tiers, skews age 24–30. Star QB births generate 20× the coverage of a backup guard's.

### 1.5 Family deaths & bereavement

Documented patterns `[V]`:
- **QB, Browns, Sept 2024** — announced his father's death **two days before the Week 1 opener**; status for
  the opener was in question.
- **LB, Buccaneers, Nov 2022** — learned of his father's death *as he was boarding the team plane* for an
  international game; played anyway and produced a career game (9 tackles, 2 sacks), saying afterward "it was
  very hard to play."
- **RB, Patriots, Sept 2020** — father killed and mother critically injured in a car crash; **missed two
  games**, returned in week three; the story dominated the team's media week on his return.
- **Former player, 2023** — his mother's death was ruled a homicide while he himself was missing; an extreme
  tail case showing the category's worst end.

**Team handling pattern:** excused absence, no roster move for short absences (≤2 games); "reserve/personal"
is not a real NFL list — teams simply list the player as out/excused. For long absences, the **Reserve/Did
Not Report** or a release/re-sign is used. `[R]`

**Frequency `[E]`:** family deaths affecting an NFL player (parent/sibling/child/grandparent close enough to
trigger an absence): **20–40 per league-year** league-wide; ones that reach national reporting: **5–15/yr**;
ones causing a **missed game**: **3–8/yr**.
**Who:** all tiers equally — this is the most tier-neutral event in the whole taxonomy.
**Media arc:** 2–5 days, plus a "first game back" beat that is almost always framed as heroic/positive.
**Performance effect:** *bimodal in the reporting* — either a visibly diminished performance or a
"dedication game" outlier. Both narratives are well attested; that bimodality is itself a good game mechanic.

### 1.6 Sick family members / caregiving

**Canonical case: the daughter-with-cancer arc (2014–15).** `[V]`
- A DT was cut from the 53 during his daughter's **Stage 4 neuroblastoma** treatment; the club **signed him
  to the practice squad specifically so he would keep his health insurance** to pay for her care.
- The club then sold replica jerseys and **donated 100% of proceeds to pediatric cancer research** — one of
  the highest-profile positive team/player PR events of the decade.
- Arc: diagnosis (June 2014) → 296 days → remission (March 2015) → "no evidence of disease" (Dec 2015). A
  **~18-month** storyline.
- **Design read:** this is a *combined* event — negative availability + hugely positive fanbase/owner
  relations if the club handles it generously, and a reputation hit if it doesn't. Perfect for a
  player-facing decision with an ethics dimension.

**Frequency `[E]`:** serious illness in an immediate family member causing missed team time: **10–25 per
league-year**; ones that become a league-wide story: **1–3/yr**.

---

## 2. TRAGEDY & ACCIDENTS

### 2.1 Player deaths

**Active or recently-active NFL player deaths, 2015–2026** (non-exhaustive, verified subset):

| Year | Player | Status | Cause `[V]` unless noted |
|---|---|---|---|
| 2016 | DE | Former (retired 2012) | `[R]` Shot in a road-rage incident, New Orleans |
| 2016 | RB | Former | `[R]` Shot in a road-rage incident, Louisiana |
| 2018 | LB | **Active** (Colts) | `[R]` Struck by a wrong-way drunk driver while standing on a highway shoulder |
| 2021 | WR | Recently retired | Complications of a **seizure disorder**; posthumous **CTE Stage 2** diagnosis |
| Apr 2022 | QB | **Active** (Steelers) | Struck by a dump truck while walking on an interstate; BAC 0.20, ketamine present; family litigation alleged he had been robbed/blackmailed beforehand |
| May 2022 | CB | **Active** (Cardinals) | Car crash, Dallas |
| Jun 2022 | LB | **Active** (Ravens) | Combined **fentanyl and cocaine** toxicity, found at home |
| Nov 2023 | CB | Former (1st-round pick) | Car crash, Houston; two former college teammates also killed |
| Jul 2024 | CB | **Active rookie** (Vikings, drafted 3 months earlier) | Run off the road by an alleged drunk driver; two former teammates also killed |
| Nov 2025 | DE, 24 | **Active** (Cowboys) | **Suicide** (self-inflicted gunshot) following a police pursuit; had expressed suicidal intent; had scored his first NFL TD **three days earlier** |

**Frequency `[E]`:** **~1–3 active-or-recent player deaths per league-year**, i.e. roughly **0.05–0.13% of
the active population annually**. Dominant causes, in order: **motor-vehicle (≈50%)**, **firearm/violence
incl. suicide (≈25%)**, **overdose (≈10%)**, **medical (≈15%)**.
**Timing:** motor-vehicle deaths skew **offseason (Apr–Jul)**; the in-season ones are the most disruptive.
**Who:** skews **young (22–27)** and **non-star** — the death list is dominated by rotational/young players,
not superstars, which is a counter-intuitive but consistent pattern.
**Team effect (documented):** league-wide profile-picture changes, moment of silence, helmet decal, jersey
patch for the season, game postponement in extreme cases, grief counselors made available. Media arc **7–14
days acute**, plus anniversary/tribute beats all season.

### 2.2 The Damar Hamlin event — mass-trauma template `[V]`

Jan 2, 2023: a safety went into **cardiac arrest (commotio cordis)** on the field on Monday Night Football.
CPR + AED for 10 minutes on the field. **The game was suspended and never resumed** — the NFL cancelled a
regular-season game outright and altered playoff seeding rules to compensate.
- Recovery: sedated/ventilated Jan 3–5 → awake and neurologically intact Jan 5 → extubated Jan 6 →
  discharged Jan 9/11 → **fully cleared to play April 18, 2023** and returned the following season.
- **Charity surge:** his dormant toy-drive GoFundMe (goal $2,500) reached **>$8.7M in ~10 days**; funded
  scholarships named after the medical staff who saved him.
- Both teams' players received on-site counseling; opponents and the league unified publicly.
- **Design read:** the single best template for a "league-wide shock" event — suspends a game, applies a
  short league-wide morale/performance modifier to *both* involved rosters, generates enormous positive
  goodwill afterwards, and resolves into an inspirational return arc.

### 2.3 Serious car crashes (non-fatal)

`[R]` Recurring pattern, several per year: single-vehicle high-speed crashes (frequently with a criminal
overlay — that half belongs to the sibling arrests report), passenger-injury crashes, and being struck as a
pedestrian. Notable structural detail: a crash that is **the player's fault while committing a crime** can
trigger both a legal track *and* an NFI/salary track simultaneously.
**Frequency `[E]`:** crashes serious enough to cost practice/game time: **5–12 per league-year**.

### 2.4 House fires `[V]`

| Year | Player | Detail |
|---|---|---|
| Jan 2024 | WR, Dolphins | ~$6.9M mansion; **>$2M in damage**; 20 firefighters; family evacuated safely; player was at the facility and **left practice**; cause ruled accidental — **a 4-year-old playing with a lighter** |
| Jun 2024 | WR, recently retired | Nashville home fire; family "lucky to be alive," all escaped |
| — | DB, former | Home a **"total loss"**; he and two family members escaped after seeing smoke |

**Frequency `[E]`:** **1–3 reported NFL-player house fires per league-year**. Cost is usually *emotional +
one practice*, not games. But the "player leaves practice mid-session" beat is very usable.

### 2.5 Home burglaries — the 2024–25 organized-crew wave `[V]`

This is the strongest recent *systemic* event in the whole dataset and deserves a dedicated game mechanic.

- **FBI issued a formal warning** to the leagues after **at least nine pro athletes** were burglarized
  **September–November 2024**.
- NFL victims named publicly: **Chiefs QB (Oct 2024)**, **Chiefs TE (Oct 2024)**, **Bengals QB (Dec 2024)**,
  an **unnamed Buccaneers player (Oct 2024)**; NBA victims included a Mavericks guard, a Bucks forward and a
  Grizzlies guard. An **Eagles RB's** home was hit in a separate 2024 invasion (family unharmed).
- **Method (FBI):** South American organized theft groups; **pre-surveillance using public schedules and
  social media**; **strike specifically while the player is at an away game**; bypass alarms; **Wi-Fi jammers**
  to kill cameras; cover lenses; obfuscate identity; in and out fast. Target set: watches, jewelry, designer
  bags, cash, safes.
- **Charges:** Feb 19, 2025, **seven Chilean nationals** charged federally in Tampa with conspiracy to commit
  interstate transportation of stolen property (10-year max); **>$2M combined** taken. Evidence photos showed
  suspects posing with stolen safes — one wearing a Chiefs shirt.
- **League response:** NFL security alert to all 32 clubs; NBA advised players to get **guard dogs** and
  upgrade alarms; FBI advised inventorying valuables and **not posting home interiors or real-time travel**.

**Frequency:** pre-2024 baseline `[E]` **1–3 NFL burglaries/yr**; the **2024–25 spike ≈ 5–10 NFL players in a
~4-month window** `[V/E]`. This is a genuine *wave* — model it as an era/epoch event, not an i.i.d. roll.
**Who:** **stars only** — the crews explicitly target high-net-worth, high-visibility players.
**Timing:** **in-season, during road games.** Beautiful mechanic: the risk is a function of *being on the road*.
**Effect:** almost no games missed; effect is **morale, focus, security spending, and a week of media**.

### 2.6 Robbery / violence victims `[V]`

- **Rookie WR, 49ers, Aug 31, 2024** — shot **through the chest** during an attempted Rolex robbery in
  downtown San Francisco by a 17-year-old; struggle over the gun. No surgery required. Placed on
  **reserve/NFI Sept 2**, activated **Oct 19** — **missed ~6 weeks / the first 6 games**. Appeared on the
  sideline **9 days after being shot** to present jerseys to the officer and surgeon who treated him. Debuted
  Week 7; finished the rookie year 31 rec / 400 yds / 3 TD. **One of the best single archetype templates in
  this entire report.**
- **Two Browns players, 2023** — robbed at gunpoint by **six masked men** in a parking lot after leaving a
  nightclub; no injuries.
- **A Jets player, ~2024** — stalked and robbed at gunpoint in a targeted hit in his NJ town.
- `[R]` A former CB's home was robbed at gunpoint with family present.

**Frequency `[E]`:** armed-robbery victimization of NFL players: **3–8 per league-year**; ones producing an
actual injury: **0–1/yr**.
**Timing:** clusters **late night** and around **nightlife/travel**; season-agnostic.
**Who:** skews **young players with visible jewelry**, plus stars.

---

## 3. NON-FOOTBALL INJURIES — the offseason canon

### 3.1 The rules that make this a *game system*, not just flavor `[V]`

1. **Reserve/NFI (non-football injury) and Reserve/NFI-illness** are real roster designations for injuries
   or illnesses **not sustained in NFL games or practices**.
2. **Teams are not obligated to pay base salary** to a player on reserve/NFI. (Contrast: **PUP** players are
   paid in full; **IR** players are paid in full.) The contract year still burns.
3. **Camp-start NFI:** a player who begins the season on reserve/NFI is **ineligible to practice or play for
   the first 6 weeks**, may practice after week 6, cannot be activated until the club has played **8 games**,
   then a **3-week activation window** opens; miss it and he's out for the year. **Max 2 returns per team.**
4. **The 2021 memo:** the NFL formally reminded clubs that **any** injury — *including workout and
   conditioning injuries* — occurring **away from the team facility** counts as non-football.
5. **Standard contract language:** guarantees can be **voided** if the player is injured in an activity with
   "a significant risk of injury." Commonly enumerated: **hang gliding, rock climbing, skiing/snowboarding,
   jet skiing, ATV/motorcycle riding, fireworks, skydiving, and basketball.** First-round rookie deals
   frequently add bespoke prohibitions.
6. **The basketball clause is near-universal:** most guaranteed-money contracts void future guarantees if a
   basketball injury prevents the player from practicing/playing — **for the remainder of the deal**, not just
   the missed period.
7. **Signing-bonus forfeiture** applies too — a 2017 second-round DT **forfeited ~$800,000** of signing bonus
   after an ATV crash.
8. **Coaching philosophy varies and is a legitimate design axis:** some HCs explicitly police it (one coach
   "retired" his star DE from pickup basketball after a record extension); others trust players; one DB coach
   *encourages* basketball because it sharpens ball skills.

### 3.2 Mechanism catalogue (25 distinct real mechanisms)

| # | Mechanism | Case (year) `[V]` unless noted | Outcome |
|---|---|---|---|
| 1 | **Fireworks** | Giants DE, Jul 4 2015 | **Right index finger amputated**, thumb broken. Giants **pulled a ~$60M offer**; he played 2015 on a **$14.8M franchise tag** structure reduced to **$2.55M base / $1.5M guaranteed** with sack incentives capping him at $8.7M. A second player (DE, Packers) lost fingers in the same July 2015 window. **The single most expensive non-football injury on record.** |
| 2 | **Jet ski** | Bills RB, Jul 2 2023 | Sitting on a jet ski, hit by another rider: **torn ACL + MCL**, **entire season lost before it began**; placed on NFI; paid **$3.98M instead of full contract**. `[R]` Earlier: a Saints RB tore a hole in his thigh on a handlebar after jumping a wave. |
| 3 | **ATV** | Giants S, bye week Nov 2022 | Broken hand, **reserve/NFI, missed 7 games (Wk 10–16)**. Separately, a Seahawks DT, 2017: **concussion**, forfeited ~**$800K** bonus, never played that season. |
| 4 | **Motorcycle** | Steelers QB, Jun 2006 | Helmetless crash: **jaw broken in two places, broken nose**; played 15 games the next season but had a poor year. `[R]` Browns TE, 2005: **torn ACL + staph infection, entire season lost.** |
| 5 | **Pickup basketball** | Ravens OLB, 2012 | **Torn Achilles**, missed 8 games. The reason the basketball clause exists. |
| 6 | **Paintball** | Redskins S, 2007 — shot in the groin in a **team-building** paintball outing, missed a 3-day minicamp. Cowboys LB, 2016 — **hit in the eye**, missed most of camp. | Two independent cases, one of which was *organized by the team* |
| 7 | **Dog / pet incident** | Lions TE, 2014 `[R]` | Tripped rushing to stop his **puppy** urinating indoors; **ankle sprain, missed games** |
| 8 | **Fondue pot** | Two Jaguars specialists, 2002 | Overturned fondue pot; **1st/2nd-degree burns** to hands and ankle; recovered for camp |
| 9 | **Fire pit / gasoline burns** | Browns TE, Sept 29 2023 | Burns to **face and arms** lighting a fire pit at home; listed questionable Wk 4, played wearing protection |
| 10 | **Slipping on trash** | Broncos WR, Mar 2008 | Slipped on a **McDonald's bag**, hand through an entertainment center: **severed artery, vein and nerve** in the forearm; surgery; lost most of the offseason |
| 11 | **Flag football (charity/YMCA)** | Panthers WR, 2010 | **Broken arm**, plate and screws; returned for the regular season |
| 12 | **Golf** | Titans WR, 2003 | **Fractured bone** hitting the ground on a tee shot at his own charity tournament; ~1 month |
| 13 | **Kickball (team activity)** | Dolphins K, 2015 | **Quad injury to the plant leg** during a team kickball event; missed minicamp |
| 14 | **Punching/kicking through glass** | Vikings QB, 2016 | Locked out of his house, kicked through a **glass door**: **severed tendon in the foot**, ~3 months |
| 15 | **Fall on wet concrete / saving a phone** | Cowboys RB, 2016 | **Broken elbow** over Memorial Day weekend diving to save a dropped phone; "at least a couple of months" |
| 16 | **Pool / vacation slip** | Eagles LB, 2017 | Hand injury **exiting a pool on his honeymoon** in Greece |
| 17 | **Bicycle** | Steelers S `[R]` | Wrist injury falling off a bike on vacation |
| 18 | **Snowboarding** | Colts QB `[R]` | Aggravated an existing shoulder injury; contributed to a lost season |
| 19 | **Spider bite** | Panthers DE, 2003 | Severe arm swelling; **4 days hospitalized**, IV antibiotics |
| 20 | **Cryotherapy** | Raiders WR, Aug 2019 | **Severe frostbite to both feet** in a cryo chamber; missed most of camp; became part of a season-destroying media saga |
| 21 | **Slip on a wet mat at the facility** | Bills QB, 2013 | Minor knee injury in a **tunnel between drills**; back in days but lost the depth-chart battle — the "small injury, big career consequence" template |
| 22 | **Solo workout away from the facility** | Broncos OT, May 4 2021 | **Torn Achilles** training at a non-team facility → placed on reserve/NFI May 7 → **released May 14** → filed a **$15M grievance** → signed elsewhere June 10. **>$10M would have been guaranteed had it happened in the building.** This case directly triggered the league-wide memo. |
| 23 | **Self-inflicted gunshot** | Giants WR, Nov 2008 | Gun discharged in a nightclub into his own leg; suspended for the season, 2-year sentence. (Overlaps the legal track.) |
| 24 | **Pro wrestling / stunts** | Patriots TE, WrestleMania 33 (2017) — approved, no injury. A Lions LB did a **wing-walk** stunt (2015). A Seahawks TE flies **stunt planes** with team approval. | Shows the *approval* dimension: teams sometimes say yes |
| 25 | **Celebration injuries** `[R]` | Cardinals K, Dec 2001 — **torn ACL landing from a celebratory jump after a made 42-yd FG**. Redskins QB, 1997 — **sprained neck head-butting a padded stadium wall** after a TD. | The purest comedy tier; both cost real time |

Bonus non-injury NFI/illness uses: a Patriots OL began his 2011 rookie year on **reserve/non-football
illness** while finishing **chemotherapy for non-Hodgkin lymphoma**; a Bills RB spent his entire 2003 rookie
season on NFI after a **college bowl-game knee injury**. `[V]`

### 3.3 Frequency & shape

- **NFI at the start of camp: ~13 players league-wide** (verified count from a recent camp tracker: 13 across
  30 reporting teams). Compare **~80+ on PUP** and **~20+ on IR** at the same moment. So NFI is roughly
  **0.5% of the camp population** `[V]`.
- Most camp-NFI cases are **rookies with college injuries or illnesses**, not exotic accidents `[E]`.
- **Genuinely exotic offseason accidents that cost regular-season time: ~2–5 per league-year** `[E]`.
- **Season-ending offseason accidents: ~0–2 per league-year** `[E]`.
- **Timing:** brutally concentrated. **July 4th week** (fireworks), **June–July** (watercraft, ATV, vacation),
  **the bye week** (mid-season ATV case above), and **late-June weddings/honeymoons**.
- **Who:** skews **young and mid-career (22–28)**, skews toward players who just got paid (new money → new
  toys), and skews toward **skill/edge positions** in the reporting.
- **Media arc:** **3–7 days**, extremely high mockery coefficient, and a permanent nickname attached to the
  player. Unlike most categories, the tone is **derisive**, and it lingers in the player's reputation.

---

## 4. MENTAL HEALTH

### 4.1 League infrastructure `[V]`

- **2019 NFL–NFLPA joint agreement**: every club **must retain a Behavioral Health Team Clinician**, and must
  create and **annually rehearse a Mental Health Emergency Action Plan**.
- A **Comprehensive Mental Health and Wellness Committee** builds programs for players, coaches, staff *and
  family members*.
- **NFL Life Line**: free, confidential, independently operated 24/7 counselor line for current and former
  players.
- Critique in the literature `[V]`: teams still label mental-health absences **"personal reasons"**, which
  researchers argue perpetuates stigma by implying mental health isn't as "real" as a physical injury. This
  is directly usable — a game can offer the club a *choice of public framing*.

### 4.2 Case studies

**Stepping away mid-season — the cleanest template.** `[V]`
- **Eagles All-Pro RT, Oct 2021.** Missed **3 consecutive games** listed as a "personal matter"; went home to
  Oklahoma. On return he **published a statement**: "Depression and anxiety are things I've dealt with for a
  long time and have kept hidden from my friends and family. If you're reading this and struggling, please
  know that you are not alone."
  - Prior history: nearly missed a **London game in 2018** due to pregame anxiety, reported at the time as
    vague "personal issues" while also playing hurt — i.e. **the event had a precursor that was mislabelled**.
  - Outcome: full return, continued elite play for years, later described nearly quitting football. Team
    handled it with public support and no roster move.
  - **Arc length: ~3 weeks out, ~1 week of coverage on return, then a durable positive-reputation shift.**

**Disclosure without absence.** `[V]`
- **TE, 1st-round pick, 2018 →** disclosed a **college suicide attempt** and long-running anxiety plus
  substance abuse; sober since 2016. Founded a **family foundation** for youth/adolescent/military mental
  health. Support came primarily from family ("always just a phone call away"), not the club.
- **DL, 1st-round pick →** disclosed depression following **his sister's suicide**; founded a mental-health
  and suicide-prevention foundation. Both now appear in official league mental-health programming — i.e. the
  disclosure converted into a **league-endorsed positive-reputation asset**.
- `[R]` The seminal earlier case: a WR publicly disclosed **borderline personality disorder** in 2011 and
  became the league's first prominent mental-health advocate.

**The worst outcome.** `[V]` The Nov 2025 death of a 24-year-old Cowboys DE by suicide, three days after his
first NFL touchdown, produced a league-wide mental-health conversation and explicit references back to earlier
player advocacy. Teams brought in counselors; the player's family issued a public statement.

### 4.3 Frequency, timing, who

- **Publicly disclosed mental-health absences: ~1–3 per league-year** `[E]`. Disclosures **without** absence
  (interviews, podcasts, foundation launches): **10–25 per league-year** `[E]` — this category has grown
  steadily 2015→2026.
- **Absence length:** typically **2–4 games**; occasionally a full season; occasionally retirement.
- **Timing:** **in-season**, disproportionately weeks 3–8 (grind onset) and after a public failure.
- **Who:** all tiers; disclosures skew **veteran and star** (they have the standing to say it), while the
  worst outcomes skew **young and marginal**.
- **Team handling menu (all real):** excused absence with "personal matter" framing → excused absence with
  honest framing → club-provided clinician → NFI-illness if long → release. The *framing choice* measurably
  changes fan and locker-room reaction.
- **Return performance:** documented cases show **full return to prior level**. That is important for a game:
  mental-health events should NOT permanently nerf a player. They cost availability and produce a fork toward
  either a strong positive reputation arc or a slow drift out of the league.

---

## 5. DRAMA & MEDIA

### 5.1 Holdouts and hold-ins `[V]`

**Mechanics that make it a system:**
- Under the **2020 CBA**, camp-absence fines are **mandatory and non-waivable**: **$50,000/day** for veterans,
  **$40,000/day** for players on rookie deals. Plus **1/18th of base salary per preseason game missed** for
  UFA-signed players and first-rounders on a fifth-year option.
- Because the fines can no longer be forgiven, **the hold-in replaced the holdout** as the dominant tactic:
  report, pass physical, collect no fines, and simply **don't practice** (or "practice" at 30%).
- Missing regular-season games also forfeits **game checks (1/18th of base per game)**.

**Named arcs:**
| Year | Player | Shape | Outcome |
|---|---|---|---|
| 2018 | RB, Steelers | **Sat out the entire season** rather than play a 2nd franchise tag | Forfeited **~$14M**; left in FA; the cautionary tale of the era |
| 2019 | RB, Chargers | Held out through **preseason + first 4 games** | Backup emerged as the starter; player left in FA and publicly regretted the tactic |
| 2019 | OT, Washington | Full-season holdout | Never played for the team again; later got **record $48M guaranteed** elsewhere. His team went **0–5** without him before replacement |
| 2023 | DE, 49ers | Camp holdout into September | Signed **5yr/$170M ($34M/yr)**, highest-paid non-QB, days before Week 1 |
| 2023 | DT, Chiefs; G, Cowboys | Camp holdouts | Both resolved; DT missed Week 1 |
| 2024 | WR, Cowboys | Holdout to force an extension | Signed; nearly forced a trade first |
| 2024 | OLB, Jets | Holdout + **public trade request**, immediately rejected by the GM | Missed most of the season's early arc |
| 2024 | WR, 49ers | **~4 months** of trade-request drama, hold-in from the sideline | Signed **4yr/$120M** |
| 2025 | Edge, Cowboys | Public trade request → dragged into the season | **Traded** for a DT + **two 1sts**; signed **4yr/$188M, $136M guaranteed** — largest non-QB guarantee ever |
| 2026 | RB (Lions), RB (Falcons), DT (Bucs) | **Hold-ins** rather than holdouts | The tactic is now default |

**Perspective quotes worth paraphrasing into game copy:**
- GM view: a holdout is *"a toothache"* that never goes away and forces you to prepare for the worst case.
- HC view: *"It's really out of your hands."*
- Agent view: *"You're a counselor, therapist, police officer"* — managing media, the player's family, and
  social-media pressure simultaneously.
- Player view: "frustrating," "antsy" — the *loss of camaraderie* is cited as much as the money.

**Frequency `[E]`:** **3–8 notable holdouts/hold-ins per league-year**, of which **1–3 reach national saga
status**. **Timing:** starts at the camp-report date (late July), peaks in the final week of August, and
resolves 60–70% of the time by Week 1.
**Who:** **stars in contract years or years 4–5 of a rookie deal**, plus tagged players. Almost never role
players (they have no leverage).
**Team effects (documented):** measurable when the player is a premium-position starter (the 0–5 example);
negligible for RBs, where replacement was immediate in two separate cases. That positional asymmetry is real
and should be modelled.

### 5.2 Trade requests

Distinct from holdouts: a **public trade request** is a discrete, dateable media event. 2024–2026 produced at
least four (WR/49ers, OLB/Jets, Edge/Cowboys, WR/49ers again in 2026). `[V]`
- Typical arc: leak → player's cryptic social post → agent statement → GM public rejection ("he's our
  player") → 4–16 weeks of speculation → resolution as extension (~60%) or trade (~40%) `[E]`.
- 2026 escalation seen in reporting: a club **voided a player's future guaranteed money** after he stopped
  reporting to the facility post-injury, and the GM said publicly *"he has played his last snap here."* `[V]`
- **Frequency `[E]`: 2–5 public requests per league-year.**

### 5.3 Public criticism of teammates/coaches, and family proxies

- **WR, Browns, Nov 2021** `[V]`: his **father posted a video** compiling plays where the QB missed him. The
  team **excused him from two practices**, then **released him three days later** (Nov 5 statement, waived
  Nov 8). **A family member's social-media post ended a star's tenure in under a week** — one of the fastest
  destruct sequences on record and a superb game template.
- **WR, Steelers/Raiders, 2017–2019** `[V]`: the full canon — **Facebook Live streaming the head coach's
  private post-playoff-win locker-room speech (Jan 2017)**; deactivated for the 2018 finale after a practice
  incident; traded for 3rd + 5th; then in 2019 a **cryo frostbite** injury, a **helmet-certification grievance**
  (lost twice) and threats not to play, a GM publicly demanding he "be all in or all out," and release in
  September. **A ~30-month, multi-team, multi-mechanism decay arc.**
- **QB vs HC, Jets, Sept 2024** `[V]`: QB **refused a celebratory gesture** from the HC on the sideline after
  a TD; **the coach was fired five days later**; the QB publicly denied involvement.

### 5.4 Sideline blowups `[V]` (all 2024 unless noted)

| Incident | Public handling |
|---|---|
| Star DE **two-hand shoves a position coach** in the chest during a blowout loss | Called it a **"love push"**; blamed the camera angle; "we do that all the time" |
| WR **shoves the long snapper in the throat** while confronting the kicker after a 3rd missed FG | HC called it an **"overreaction"**, said it was "squashed" |
| HC **taunts opposing fans** in the final seconds of a narrow win | Defended it as "excitement," then **apologized the next day** |
| HC publicly **berates his rookie QB** on the sideline | Called it his **"love language"**; team's offense struggled the following week |
| Star WR **rips a teammate's helmet off** in a training-camp brawl (2026) | "Not a good look" national reaction |

**Frequency `[E]`:** **8–20 nationally-covered sideline incidents per league-year**; **media arc 24–72 hours**
unless the team keeps losing, in which case it becomes evidence in a "locker room has lost the coach" story.

### 5.5 Training-camp fights

Near-universal — every camp has them; only a few escalate. `[V]`
- Root causes cited: **consecutive practices without pads-off days, August heat, 6+ straight days**, and
  joint practices with another team.
- Escalation ladder: scuffle → **coach ejects a player from practice** → **team-wide brawl** → **joint
  practice terminated early** → **league fines both clubs $200,000** (happened to two clubs in 2022).
- 2026 examples: star WR vs. his own CB; star DE vs. the veteran QB (both held out of the next practice by
  the HC); a rookie DE **ejected from practice by the HC for throwing a punch** at his own RT, followed by
  another fight at the same camp days later.
- Counter-narrative in the coverage: *"Training camp fights are back — that's exactly what the NFL needed."*
  Fights read as **positive intensity** when a team is expected to be good and as **dysfunction** when it isn't.
  Same event, opposite valence, determined by context — an excellent mechanic.

**Frequency `[E]`:** **30–60 reported camp fights per league-year**; **5–15** become national items; **1–3**
produce discipline or fines.

### 5.6 Podcast / interview controversies `[V]`

- The **weekly-podcast era** (2020→) made players their own media outlet. A QB used a weekly show as his
  primary platform and generated a multi-year controversy: at a preseason presser he said he was
  **"immunized"** rather than vaccinated (Nov 2021), tested positive, **missed a game under the 10-day
  unvaccinated protocol**, **lost a 9-year healthcare endorsement**, and the story recurred **annually for
  four-plus years**, including his own later admission of regret about the word choice.
- The same platform later produced **darkness-retreat**, political and public-figure controversies — i.e. a
  single player generating an evergreen media-pressure source unrelated to play.
- Podcasts also produce **positive** shocks: the same medium carried the Kelce–Swift album/engagement
  announcements that generated hundreds of millions in league brand value.

**Design read:** "player has a podcast" should be a *trait*, not an event — it raises both the positive and
negative variance of every other media event, and raises fame independent of performance.

### 5.7 Social media — old posts resurfacing `[V]`

- **QB, 2018 draft** — racist tweets he wrote **at ages 15–16** surfaced **the night before the draft**,
  went viral. He apologized publicly that night, was projected to go #1, and **fell to #7**. He apologized
  again at his introductory presser, saying he hoped teammates wouldn't judge him.
- **QB, Dec 2018** — homophobic tweets written at **14–15** surfaced **within hours of him winning the
  Heisman**; apologized on Twitter the same night. Went #1 overall four months later.
- Pattern: **surfacing is timed to the player's peak visibility moment** (draft eve, award night, first Pro
  Bowl). Arc **48–96 hours**, plus a permanent asterisk in profile pieces.
- **Frequency `[E]`: 2–6 per league-year**, overwhelmingly at the **draft**.

### 5.8 Livestream / broadcast mistakes `[V]`

The Facebook-Live locker-room stream (2017) is the canonical case: a player broadcast his HC's private
post-win speech, including remarks about the next opponent. Cost: a **fine, a public apology, and the first
crack in a relationship that ended in a trade two years later.**
**Frequency `[E]`: 1–3 per league-year.**

### 5.9 Anonymous-source stories

- Structural pattern: "sources say the locker room has lost faith in X," typically appearing **Weeks 8–14**
  of a losing season, sourced to unnamed players. Preseason variants are the "five locker rooms that could
  explode this summer" genre. `[V]`
- Anatomy: anonymous report → player/coach denial → teammate-support quotes → 2–5 day arc → either fades or
  becomes the epitaph in the eventual firing story.
- **Frequency `[E]`: 10–25 per league-year**, concentrated on **teams with losing records and a hot-seat
  coach**. Almost never appears on a 12-win team.

---

## 6. POSITIVE EVENTS

### 6.1 Walter Payton NFL Man of the Year `[V]`

- **Structure:** each of the 32 clubs nominates **one** player → a panel including the Commissioner, the
  **previous winner**, and former players selects one winner. **Winner: $250,000** charitable donation in his
  name; **each of the other 31 finalists: $50,000** (nominee-level donations reported as up to $40,000 in one
  source; the league also states $250K/$50K).
- Winner is announced at NFL Honors the night before the Super Bowl; the winner wears a gold **"WPMOY"**
  patch on his jersey for the rest of his career.
- **Winners 2015–2025:** 2015 WR/49ers · 2016 **co-winners** WR/Cardinals + QB/Giants · 2017 DE/Texans ·
  2018 DE/Eagles · 2019 DE/Jaguars · 2020 QB/Seahawks · 2021 OT/Rams · 2022 QB/Cowboys · 2023 DT/Steelers ·
  2024 DE/Jaguars · 2025 LB/Commanders.
- **Note the position distribution:** 5 of 11 were **defensive linemen**; only 3 QBs. This award is *not*
  a proxy for on-field stardom — great news for a game that wants role players to have a path to prestige.

### 6.2 Disaster relief / mega-philanthropy `[V]`

- **DE, Texans, Aug–Sept 2017:** started a Hurricane Harvey fund with **$100,000 of his own money** and a
  **$200,000 goal**; raised **>$37M (reported as "upwards of $40M")** in weeks. Won **Walter Payton MOY** and
  **Sports Illustrated Sportsperson of the Year** (shared). His own framing: the season "was always about more
  than football."
- **S, Bills, Jan 2023:** a dormant **$2,500** toy-drive GoFundMe reached **>$8.7M in ~10 days** after his
  on-field cardiac arrest, then funded scholarships named for the medics who saved him.
- `[R]` **DE, Eagles, 2017:** donated **his entire base salary** (first 6 game checks to scholarships, final
  10 to educational equity), and won Walter Payton MOY the same year.
- **DT, Bengals, 2014:** club sold his jersey and gave **100% of proceeds** to pediatric cancer research
  during his daughter's treatment. `[V]`

**Frequency `[E]`:** mega-events (**>$1M raised by a single player**) **0–2 per league-year**, tightly coupled
to a **natural disaster or a shocking on-field incident**. Foundation launches: **20–40 per league-year**.

### 6.3 Viral positive moments, milestones and returns

Recurring beats visible across the whole dataset:
- **The comeback game** — first game back after a bereavement, an injury, or a shooting. The 49ers rookie
  presenting jerseys to his surgeon and the responding officer **nine days after being shot** is the archetype. `[V]`
- **The medical-miracle return** — cleared to play **3.5 months** after a cardiac arrest; met the President to
  advocate for AED access in schools. `[V]`
- **The remission announcement** — 296 days from diagnosis to remission, announced by the player himself. `[V]`
- **Milestone celebrations** — game balls, ceremonial helmet-decal handoffs, ring-of-honor inductions,
  first-TD ball preserved (poignantly, the Cowboys DE scored his first NFL TD **three days before his death**). `[V]`
- **Community awards** — every team nominates one player annually, so there are **32 positive local stories
  per league-year** guaranteed by structure.

### 6.4 Contract-year motivation

- Structural fact, not a single citation: the entire holdout/hold-in economy exists because **years 4–5 of a
  rookie deal and the final year of a veteran deal** are when leverage peaks. A 2023 All-Pro season directly
  produced a **$120M** extension; a franchise-tag year produced a **$170M** deal; a public trade request
  produced a **$188M / $136M guaranteed** record. `[V]`
- The inverse is equally documented: a **fireworks accident during a franchise-tag offseason** vaporized a
  **~$60M offer**, and a **solo-workout Achilles tear** vaporized **>$10M in guarantees**. `[V]`
- **Design read:** contract year should be a *variance amplifier* in both directions — a motivation bonus,
  a holdout/trade-request risk, and an amplified consequence for any non-football injury.

---

## 7. CROSS-CUTTING MATRIX — timing, incidence, effects, arc length

| Category | Peak window | Rough freq / league-year | Who it hits | Games missed (typ.) | Media arc | Perf. / chemistry effect |
|---|---|---|---|---|---|---|
| Child birth | Uniform (≈60% in-season) | 150–250 births; 3–10 cost a game | All tiers, 24–30 | 0–1 | 1–3 d (24–72 h if a star) | ~0; occasional "dedication game" |
| Family death | Uniform | 20–40; 3–8 cost a game | **Tier-neutral** | 0–2 | 2–5 d + return beat | Bimodal: −10% or outlier game |
| Sick family / caregiving | Uniform | 10–25 | All tiers | 0–many | Long tail (months) | Availability risk; huge goodwill upside |
| Divorce | Announcement anytime; camp absence in Jul–Aug | 3–8; 0–2 in-season sagas | Stars (visibility) | 0 (but camp absences) | 2 wk acute / season-long undertone | Documented multi-month decline |
| Celebrity relationship | Anytime; peaks at engagement/wedding | 1–3 circus-tier | **Top-25 fame only** | 0 | Continuous | Revenue ↑↑, media pressure ↑; "distraction" only when losing |
| Player death | Motor-vehicle skews Apr–Jul | 1–3 | Skews **young, non-star** | Team-wide | 7–14 d + season tributes | League-wide morale event |
| House fire | Uniform | 1–3 | Stars (big houses get covered) | 0–1 (practice) | 2–4 d | Small morale hit |
| Burglary (organized crew) | **In-season, during away games** | 1–3 baseline; **5–10 in the 2024–25 wave** | **Stars only** | 0 | 3–7 d | Focus/security; league-level policy response |
| Robbery/violence victim | Late night; season-agnostic | 3–8; 0–1 with injury | Young + flashy, plus stars | 0–6 | 3–7 d + return beat | Return story is overwhelmingly positive |
| Non-football injury | **Jul 4 / Jun–Jul / bye week** | ~13 on camp NFI; 2–5 cost regular-season time | Young/newly-paid, 22–28 | 0–17 | 3–7 d, **derisive**, sticky nickname | Salary/guarantee loss is the real damage |
| Mental health absence | In-season, Wk 3–8 | 1–3 absences; 10–25 disclosures | All tiers; disclosures skew veteran | 2–4 | 1 wk out, 1 wk back | **Full recovery documented**; reputation ↑ after |
| Holdout / hold-in | **Late Jul → Week 1** | 3–8; 1–3 sagas | **Stars in contract years** | 0–17 | 4–8 wk | Big for premium positions; ~0 for RB |
| Trade request | Feb–Mar and Jul–Aug | 2–5 | Stars | 0 | 4–16 wk | Locker-room split; GM credibility at stake |
| Camp fight | **Aug, days 6+, joint practices** | 30–60; 5–15 national | Everyone | 0 | 24–48 h | Valence flips on team expectation |
| Sideline blowup | **In-season, blowout losses** | 8–20 | Stars + coaches | 0 | 24–72 h | Feeds "lost the room" narrative |
| Old posts resurfacing | **Draft eve; award nights** | 2–6 | **Prospects/newly-famous** | 0 | 48–96 h | Draft-slot cost (documented: #1 → #7) |
| Anonymous-source story | **Wk 8–14 of a losing season** | 10–25 | Losing teams, hot-seat coaches | 0 | 2–5 d | Accelerates firings |
| Podcast/interview controversy | Anytime | 3–8 | Players with platforms | 0–1 | Days → **years** | Endorsement loss; recurring pressure |
| Community award (WPMOY) | Dec (nominees) / Feb (winner) | **32 nominees, 1 winner** | **DL over-represented**; veterans | 0 | 1 wk | Morale/reputation ↑, permanent patch |
| Mega-philanthropy | Coupled to disasters/shocks | 0–2 | Stars | 0 | 2–4 wk | Team + league goodwill ↑↑ |

---

## 8. ANONYMIZED ARCHETYPAL CASE TEMPLATES

Each template is written as it could be modelled: **trigger → roll → effects → resolution fork**. Names
stripped; citations point at the real grounding case.

---

**T1 — "The Fourth of July"** *(non-football injury, catastrophic)*
Trigger: offseason week containing a national holiday; player is a **franchise-tagged or extension-pending
star**. Effect: permanent minor attribute loss (hand/grip/dexterity), **pending contract offer withdrawn**,
guarantees void, plays the year on a **reduced incentive-laden deal**, misses ~8 games, returns at ~85%.
Resolution: 3-year reputation shadow, but a full career is still possible.
*Grounding: Giants DE, July 4 2015 — finger amputation, $60M offer pulled, $2.55M base / $1.5M guaranteed.*
`[V]` https://www.espn.com/nfl/story/_/id/18932305/ · https://www.cbssports.com/nfl/news/giants-reportedly-use-franchise-tag-to-keep-jason-pierre-paul-off-the-market

---

**T2 — "The Watercraft"** *(non-football injury, season-ending, contractually punitive)*
Trigger: July, player in year 1–2 of a new deal, high "risk appetite" trait. Roll: ACL+MCL. Effect:
**reserve/NFI, base salary NOT paid**, receives only guaranteed portion, entire season lost, no accrued
season toward the contract goal. Locker-room reaction: mild resentment. Media: 4 days, mocking.
*Grounding: Bills RB, July 2 2023 — torn ACL/MCL on a jet ski, NFI, paid $3.98M instead of full contract.*
`[V]` https://www.nfl.com/news/browns-rb-nyheim-hines-says-he-s-learned-my-lessons-following-jet-ski-accident-recovery-on-track · https://buffalonews.com/sports/bills/in-wake-of-nyheim-hines-injury-heres-what-standard-nfl-contracts-say-about-banned-off/article_1baaff32-2a4d-11ee-9d04-23173a879dde.html

---

**T3 — "The Bye-Week Toy"** *(non-football injury, mid-season)*
Trigger: **bye week**, starter, age <26. Roll: broken hand from an ATV. Effect: **reserve/NFI mid-season**,
7 games missed, salary withheld for the period, coach makes a pointed public comment, teammates' morale −1.
Resolution: activated in Week 17, no long-term loss.
*Grounding: Giants S, bye week Nov 2022 — 7 games (Wk 10–16) on reserve/NFI.* `[V]` https://en.wikipedia.org/wiki/Xavier_McKinney

---

**T4 — "Away From The Building"** *(the salary-forfeiture trap)*
Trigger: May, veteran on a big non-guaranteed-after-injury deal, trains at his own facility. Roll: Achilles.
Effect: placed on **reserve/NFI within 72 h**, **released within 10 days**, **>$10M in guarantees void**,
player files a **$15M grievance**, signs elsewhere for the minimum a month later. League then issues a memo.
*Grounding: Broncos OT, May 4–14 2021; $15M grievance; league memo that any away-from-facility injury —
including conditioning — is non-football.* `[V]` https://en.wikipedia.org/wiki/Ja%27Wuan_James · https://www.espn.com/nfl/story/_/id/31395983/

---

**T5 — "The Away-Game Break-In"** *(era/wave event, star-only)*
Trigger: **road game**, player fame ≥ 90th percentile, era flag `organized_crew_wave` active. Effect:
$0.3–2.0M in goods stolen; **no games missed**; −focus for 1–2 weeks; player invests in security (cost);
**league issues a security memo to all 32 clubs**; if ≥4 players are hit within 8 weeks, a **federal task
force** storyline fires and the wave decays after ~6 months.
*Grounding: FBI warning, ≥9 pro athletes Sept–Nov 2024; Chiefs QB + TE (Oct), Bengals QB (Dec), unnamed Bucs
player (Oct); 7 Chilean nationals charged Feb 19 2025; >$2M total; Wi-Fi jammers, pre-surveillance, strike
during away games.* `[V]` https://abcnews.com/US/fbi-issues-warning-burglaries-pro-athletes-homes/story?id=117197676 · https://new.cbssports.com/nfl/news/seven-men-charged-with-burglarizing-homes-of-patrick-mahomes-travis-kelce-other-nfl-stars/ · https://www.nfl.com/news/nfl-issues-security-alert-to-teams-regarding-recent-home-burglaries

---

**T6 — "Shot Before Week One"** *(victim of violence → redemption arc)*
Trigger: late August, rookie or young player, urban market, visible luxury item. Roll: gunshot wound, non-
surgical. Effect: **reserve/NFI**, ~6 weeks out, activated in October, debuts Week 7. Team-wide morale −2 for
one week then **+3 on his return**; fanbase affinity **+large**; player gains a permanent "resilient" trait.
Optional beat: appears on the sideline 9 days later to thank the responders.
*Grounding: 49ers rookie WR, Aug 31 2024 — shot through the chest in an attempted watch robbery; NFI Sept 2,
activated Oct 19, debut Week 7, 31/400/3 as a rookie.* `[V]` https://en.wikipedia.org/wiki/Ricky_Pearsall

---

**T7 — "The Fire Pit / The Lighter"** *(household accident)*
Trigger: any week; roll on a household-hazard table (fire pit + accelerant, child + lighter, kitchen, glass
door). Effect A (player injured): facial/arm burns, **questionable** for one game, plays with protection.
Effect B (house destroyed, player unhurt): **$1–3M damage**, leaves practice mid-session, 1 week of −focus,
family safe.
*Grounding: Browns TE, Sept 29 2023 (fire pit, face and arm burns, played Wk 4). Dolphins WR, Jan 2024
(>$2M damage; 4-year-old with a lighter; family evacuated; player left practice).* `[V]`
https://en.wikipedia.org/wiki/David_Njoku · https://www.cbssports.com/nfl/news/tyreek-hill-leaves-dolphins-practice-after-fire-breaks-out-at-florida-home-family-safe

---

**T8 — "Two Days Before Week One"** *(bereavement, star)*
Trigger: any week; parent death. Effect: player announces it publicly; **game status in doubt**; if he plays,
roll bimodal — 60% chance of a −15% performance week, 40% chance of a career-outlier "dedication game."
Return week generates a **positive** media beat regardless. Coach relationship +1 if the club excuses him.
*Grounding: Browns QB, Sept 2024 (father died 2 days before the opener); Buccaneers LB, Nov 2022 (learned of
his father's death boarding the team plane; 9 tackles, 2 sacks in the game); Patriots RB, Sept 2020 (missed
2 games).* `[V]` https://www.cbssports.com/nfl/news/deshaun-watson-announces-death-of-father-two-days-before-cleveland-browns-season-opener/ · https://www.cbssports.com/nfl/news/bucs-devin-white-reflects-on-huge-performance-vs-seahawks-after-fathers-death-it-was-very-hard-to-play

---

**T9 — "The Delivery Room Decision"** *(player-facing choice, in-season)*
Trigger: player's partner is due within ±5 days of a game. **Present the user a choice** (as GM: grant or
deny the excused absence; as the player's advocate: advise). Outcomes: (a) grants leave → player misses 1
game, morale +3, national talk-radio debate for 48 h, backup performs at −; (b) denies/player chooses to play
→ morale −2, small chance of a persistent "resentment" flag, no roster cost. Both are real and both were
publicly praised and criticised.
*Grounding: Bears CB 2012, Vikings LB 2012 (debate era); Ravens QB 2013 (chose to play, missed the birth);
Patriots RB + LB 2019 (missed games incl. an opener); Vikings QB 2024 (missed practice only).* `[V]`
https://profootballtalk.nbcsports.com/2012/11/07/players-missing-games-for-babies-being-born-raises-plenty-of-questions/ · https://www.espn.com/nfl/story/_/id/27673918/pats-rb-white-missing-game-child-birth · https://www.cbsnews.com/minnesota/news/vikings-qb-mccarthy-misses-practice-for-birth-of-son/

---

**T10 — "The Diagnosis"** *(sick child; club-ethics fork)*
Trigger: offseason or camp; player's young child diagnosed with a serious illness. **GM choice:** (a) cut him
outright — saves cap, **fanbase −large, locker-room −large**; (b) **cut but sign to the practice squad so he
keeps team health insurance** — cap-cheap, **fanbase +large, locker-room +large**; (c) keep on the 53 at full
cost. Optional follow-on: club sells his jersey and donates 100% of proceeds → **league-wide positive story**,
sponsorship revenue +. Multi-season arc with a ~50% remission resolution beat.
*Grounding: Bengals DT, 2014–15 — practice squad for insurance; jersey proceeds to pediatric cancer research;
296 days to remission.* `[V]` https://www.bengals.com/news/leah-and-devon-still-return-to-rule-the-jungle-again · https://www.si.com/extra-mustard/2015/03/25/devon-still-leah-cancer-remission-cincinnati-bengals

---

**T11 — "Stepping Away"** *(mental health, in-season)*
Trigger: Weeks 3–8; higher probability if the player has a prior "personal issues" flag (the real cases
almost always have a mislabelled precursor). Effect: **absent 2–4 games**, listed at the club's choice as
"personal matter" or honestly. **Framing choice matters:** honest framing → short-term media +1 week,
long-term reputation **+**, league programme invitation; vague framing → speculation, rumour rolls, and a
higher chance of a repeat event. Return: **no permanent attribute loss**, +1 leadership.
*Grounding: Eagles OT, Oct 2021 — 3 games, statement on return, elite play afterwards; 2018 precursor
mislabelled as "personal issues." Plus the 2019 NFL–NFLPA requirement that each club retain a Behavioral
Health Team Clinician.* `[V]` https://www.washingtonpost.com/sports/2021/10/18/lane-johnson-depression-anxiety/ · https://www.nfl.com/playerhealthandsafety/health-and-wellness/mental-health/ · https://www.statnews.com/2025/09/21/nfl-injury-list-sports-betting-athlete-medical-privacy/

---

**T12 — "The Hold-In"** *(contract drama, modern form)*
Trigger: camp report date; star with ≥2 years' production above his contract. **He reports** (avoiding
$50K/day fines) but doesn't practice. Weekly rolls: agent statement → GM public counter → national ranking
of "who blinks" → 60–70% resolve before Week 1 with an extension, 20% carry into the season, 10% force a
trade. If unresolved into the season and he plays a **premium position**, apply a real team penalty; if he's
a **running back**, apply almost none and let the backup emerge.
*Grounding: 2023 DE ($170M), 2024 WR ($120M), 2024 WR/Cowboys, 2025 Edge (traded for two 1sts + $188M),
2026 hold-ins by two RBs and a DT; 2019 OT holdout → team 0–5 without him; 2019 RB holdout → backup took
the job permanently; $50K/$40K per-day mandatory fines.* `[V]`
https://www.espn.com/nfl/story/_/id/45789518/ · https://www.cbssports.com/nfl/news/agents-take-inside-look-at-the-consequences-and-dynamics-facing-nick-bosa-zack-martin-and-other-holdouts/ · https://www.cbssports.com/nfl/news/2024-nfl-training-camp-holdout-hold-in-tracker-latest-on-ceedee-lamb-trent-williams-haason-reddick-others/

---

**T13 — "The Family Video"** *(third-party social media destroys a tenure)*
Trigger: star skill player whose usage is below his expectation for 4+ weeks. Roll: a **family member** posts
a public compilation criticising the QB/coach. Effect: club **excuses him from practice** within 48 h;
**releases him within 5 days**; he clears waivers or is claimed; signs with a contender and — critically —
often **thrives there**, which retro-frames the original club as the villain.
*Grounding: Browns WR, Nov 2021 — father's video, excused from 2 practices, release announced Nov 5, waived
Nov 8, won a Super Bowl elsewhere that season.* `[V]` https://en.wikipedia.org/wiki/Odell_Beckham_Jr.

---

**T14 — "The Long Decay"** *(multi-season star-implosion arc)*
Trigger: elite producer, high ego trait, contract dissatisfaction. Stage 1: **livestreams the coach's private
locker-room speech** (fine + apology). Stage 2: practice blow-up, **deactivated for a meaningful game**.
Stage 3: **traded for a discounted return** (3rd + 5th). Stage 4: **bizarre offseason injury** (cryotherapy
frostbite). Stage 5: **equipment/officiating grievance**, threatens not to play, loses twice. Stage 6: GM
issues a public ultimatum. Stage 7: released before Week 1. Each stage should be individually escapable.
*Grounding: WR, Steelers→Raiders, Jan 2017–Sept 2019.* `[V]`
https://www.si.com/nfl/2019/09/07/antonio-brown-raiders-drama-timeline-helmet-fines-release · https://www.cbssports.com/nfl/news/antonio-brown-timeline-how-he-wore-out-his-welcome-in-pittsburgh-oakland-new-england-and-tampa-bay/

---

**T15 — "The Refusal"** *(sideline moment that ends a coaching tenure)*
Trigger: veteran star + coach on the hot seat + a win that doesn't look good. Roll: player **visibly refuses**
the coach's celebration on camera. Effect: 72 h media arc; if the club loses the next game, **coach fired
within 7 days**; player publicly denies involvement; a "who really runs this team" storyline attaches to the
star for the rest of the season.
*Grounding: Jets QB/HC, Sept 2024 — celebration refused, coach fired 5 days later.* `[V]`
https://www.theglobeandmail.com/sports/football/article-spats-shoves-snubs-and-snapbacks-have-ruled-the-nfl-sidelines-in-2024/

---

**T16 — "The Wave of Grief"** *(league-level shock)*
Trigger: an active player dies, or suffers a life-threatening on-field event. Effect: **suspend/cancel the
game** (real precedent), league-wide tribute, helmet decals and a season-long patch for the club, grief
counselors, **both involved rosters take a 1–3 week morale/performance modifier**. If the player survives:
recovery beats at ~1 week, ~3 months, full clearance at ~3.5 months, and a **charity surge** (a dormant
$2.5K fundraiser reaching **$8.7M in 10 days**) that converts the tragedy into the biggest positive-reputation
event available in the game.
*Grounding: Jan 2 2023 cardiac arrest — game never resumed, cleared April 18 2023, $8.7M raised; Nov 2025
active-player death by suicide, three days after his first NFL TD.* `[V]`
https://en.wikipedia.org/wiki/Damar_Hamlin · https://www.cnn.com/2025/11/06/sport/football-nfl-dallas-cowyboys-marshawn-kneeland-dead · https://abcnews.com/Sports/cowboys-defensive-end-marshawn-kneeland-dies-24/story?id=127257376

---

**T17 — "The Circus"** *(celebrity relationship, positive-dominant)*
Trigger: star with fame ≥95th percentile enters a relationship with a national-tier celebrity. Effect:
**club revenue +, league revenue +, merchandise +, a new demographic of fans**; broadcast focus complaints;
a **persistent media-pressure modifier**; the club gets a **choice**: monetise it (revenue ++, player
relationship −) or shield the player (revenue +, player relationship ++). "Distraction" narrative only
activates on a losing streak. Engagement and wedding are separate, larger spikes.
*Grounding: 2023–2026 — $331.5M brand value, +20% sponsorships / $2.35B, +53% teen-girl viewership; club
declined to play her music or show her on the videoboard "out of respect"; player asked not to be marketed.*
`[V]` https://en.wikipedia.org/wiki/Taylor_Swift_and_Travis_Kelce · https://www.cbssports.com/nfl/news/chiefs-chose-not-to-play-taylor-swift-music-in-arrowhead-stadium-to-be-respectful-of-travis-kelce · https://sports.yahoo.com/articles/never-showed-taylor-swift-chiefs-033206137.html

---

**T18 — "Draft Eve"** *(reputation shock at peak visibility)*
Trigger: **the night before the draft** (or an award night), prospect with a top-10 grade. Roll: old
adolescent social-media posts surface. Effect: same-night apology; **draft slot falls 3–8 picks** (a real
case fell from projected #1 to #7); permanent minor "character" flag; teams that pass are later shown to have
been wrong. Full recovery is the norm.
*Grounding: QB, April 25 2018 — tweets from ages 15–16, projected #1, taken #7; QB, Dec 2018 — tweets
surfaced hours after the Heisman, went #1 overall the next spring.* `[V]`
https://www.espn.com/nfl/story/_/id/23321086/josh-allen-apologizes-offensive-tweets-high-school-resurface · https://www.si.com/college/2018/12/09/kyler-murray-heisman-trophy-oklahoma-homophobic-tweets-apology

---

**T19 — "The Nominee"** *(guaranteed positive, structural)*
Trigger: **every December, every club nominates exactly one player.** Effect: +$50K to his charity, local
media week, morale +1 for him and +small for the club; if he wins the league award (1/32): **$250K**, a
permanent jersey patch, fanbase affinity ++, and a durable +reputation that helps in free agency and in
post-career coaching/front-office paths. Design note: the real winners skew **defensive linemen and
veterans**, not QBs — use that to give unglamorous players a prestige path.
*Grounding: WPMOY structure and 2015–2025 winner list.* `[V]`
https://en.wikipedia.org/wiki/Walter_Payton_NFL_Man_of_the_Year · https://www.nfl.com/honors/man-of-the-year/

---

**T20 — "The Disaster Fund"** *(mega-philanthropy, coupled event)*
Trigger: a natural disaster hits the club's metro area (or a shocking on-field incident occurs). Roll on the
roster's highest-charisma star. Effect: he seeds a fund with his own money and a modest goal; it overshoots
by **100–400×**; national coverage for 3–4 weeks; **Walter Payton MOY and a national sportsperson award**;
club and league goodwill ++; the player's post-career value ++. His on-field season may be unremarkable and
it does not matter.
*Grounding: Texans DE, Aug–Sept 2017 — $100K seed, $200K goal, >$37M raised, WPMOY + SI Sportsperson.* `[V]`
https://en.wikipedia.org/wiki/J._J._Watt

---

## 9. DESIGN NOTES FOR THE FICTIONAL SYSTEM

1. **Calendar-driven, not uniform.** The strongest signal in the whole dataset is *when* things happen.
   Fireworks/watercraft/ATV in late June–early July. Holdouts at the camp-report date. Camp fights on days
   6+ of camp and at joint practices. Anonymous-source stories in Weeks 8–14 of a losing season. Burglaries
   during away games. Old tweets on draft eve. Bereavement and births uniformly. Build the roll table off the
   calendar node, not off a flat per-week chance.

2. **Two damage channels, not one.** Real non-football events damage (a) **availability** and (b) **money /
   contract status**. The NFI mechanic — *no base salary owed*, *6 weeks minimum*, *8 games before activation*,
   *3-week window*, *max 2 returns per club*, *guarantees voidable*, *bonus forfeitable* — is a fully-formed
   game system already. Implement it; it makes the offseason risk *matter* to a GM, not just to a player.

3. **Valence is contextual.** A camp fight on a contender reads as "intensity"; the identical event on a
   4-win team reads as "dysfunction." A celebrity girlfriend is revenue when you're 11-2 and a distraction
   when you're 4-9. Do not hard-code valence; compute it from record + expectation.

4. **Framing is a decision.** "Personal matter" vs. an honest mental-health statement; monetise the circus
   vs. shield the player; cut the caregiver vs. practice-squad him for insurance. These are all real,
   documented, binary club decisions with opposite reputational outcomes. They are the best interaction
   surface in this entire dataset.

5. **Positive events must be structurally guaranteed, not rare.** 32 community-award nominees every single
   year is a built-in positive drip. Comeback games, remission announcements, and milestone balls are free.
   Without them the system reads as pure punishment.

6. **Bimodal outcomes where the record is bimodal.** Bereavement games and post-trauma returns are genuinely
   bimodal in the reporting — model the outlier, don't average it away.

7. **Waves, not i.i.d. rolls.** The 2024–25 burglary wave is an *epoch*: onset, escalation, federal response,
   decay. So is the rise of player-owned podcasts (2020→) and the rise of mental-health disclosure (2019→).
   An era-flag layer over the per-event rolls produces much better long-dynasty texture than independent rolls.

8. **Positional asymmetry in holdout consequences is real.** One club went 0–5 without a franchise LT; two
   separate RB holdouts cost their teams essentially nothing and cost the *players* their jobs. Encode it.

9. **Recovery is the norm.** Mental-health absences, robbery-victim recoveries, cardiac-arrest recovery,
   bereavement — every well-documented case returned to prior level. Reserve permanent attribute damage for
   amputations and catastrophic joint injuries only.

10. **Do not ship any of these names.** Everything above is grounding. The shipping system takes the
    *mechanisms, timings, frequencies, decision forks and consequence shapes* — never the identities.

---

## 10. SOURCE LIST

**Non-football injury / contract mechanics**
- https://en.wikipedia.org/wiki/Non-football_injury_and_illness
- https://www.nfl.com/news/nfl-training-camp-roster-faqs-defining-injured-reserve-pup-list-nfi-and-more
- https://www.espn.com/nfl/story/_/id/31395983/nfl-sends-memo-reminding-clubs-league-not-pay-players-suffer-injuries-away-facilities
- https://www.espn.com/nfl/story/_/id/40342801/what-nfl-players-allowed-do-offseason
- https://www.nbcsports.com/nfl/profootballtalk/rumor-mill/news/most-contracts-contain-language-voiding-guarantees-for-basketball-injuries
- https://buffalonews.com/sports/bills/in-wake-of-nyheim-hines-injury-heres-what-standard-nfl-contracts-say-about-banned-off/article_1baaff32-2a4d-11ee-9d04-23173a879dde.html
- https://www.si.com/nfl/injury-tracker-full-list-players-training-camp-pup-nfi-ir  *(NFI headcount: 13)*
- https://au.sports.yahoo.com/bizarre-nfl-offseason-injuries-160215161.html  *(13 mechanisms, 2002–2017)*
- https://www.thescore.com/nfl/news/1270573
- https://en.wikipedia.org/wiki/Ja%27Wuan_James · https://en.wikipedia.org/wiki/Xavier_McKinney · https://en.wikipedia.org/wiki/David_Njoku
- https://www.foxnews.com/sports/paintball-injury-sidelines-cowboys-wilson-to-start-camp
- https://www.nfl.com/news/browns-rb-nyheim-hines-says-he-s-learned-my-lessons-following-jet-ski-accident-recovery-on-track
- https://www.espn.com/nfl/story/_/id/18932305/jason-pierre-paul-new-york-giants-agree-four-year-contract · https://www.complex.com/sports/a/adam-caparell/jason-pierre-paul-accident-cost-him-millions

**Tragedy / accidents / crime**
- https://abcnews.com/US/fbi-issues-warning-burglaries-pro-athletes-homes/story?id=117197676
- https://new.cbssports.com/nfl/news/seven-men-charged-with-burglarizing-homes-of-patrick-mahomes-travis-kelce-other-nfl-stars/
- https://www.nfl.com/news/nfl-issues-security-alert-to-teams-regarding-recent-home-burglaries
- https://www.fortune.com/2024/12/30/fbi-crime-gangs-stalking-nfl-nba-stars-social-media-travis-kelce-luka-doncic-burglary
- https://en.wikipedia.org/wiki/Ricky_Pearsall · https://www.foxnews.com/sports/two-browns-players-robbed-gunpoint-six-masked-men
- https://en.wikipedia.org/wiki/Damar_Hamlin
- https://www.cnn.com/2025/11/06/sport/football-nfl-dallas-cowyboys-marshawn-kneeland-dead · https://abcnews.com/Sports/cowboys-defensive-end-marshawn-kneeland-dies-24/story?id=127257376
- https://www.npr.org/2022/05/24/1100954853/dwayne-haskins-legally-drunk-drugs-autoposy · https://www.npr.org/2022/05/31/1102097190/jeff-gladney-died-car-crash-arizona-cardinals · https://www.nbcsports.com/nfl/profootballtalk/rumor-mill/news/jaylon-fergusons-death-was-caused-by-fentanyl-and-cocaine-autopsy-finds · https://www.espn.com/nfl/story/_/id/34354073/demaryius-thomas-died-seizure-disorder-complications-according-autopsy-report · https://www.essence.com/news/nfl-rookie-khyree-jackson-killed-in-car-crash/
- https://www.cbssports.com/nfl/news/tyreek-hill-leaves-dolphins-practice-after-fire-breaks-out-at-florida-home-family-safe · https://www.cnn.com/2024/06/27/sport/randall-cobb-nfl-house-fire-spt-intl

**Family / relationships**
- https://profootballtalk.nbcsports.com/2012/11/07/players-missing-games-for-babies-being-born-raises-plenty-of-questions/ · https://www.espn.com/nfl/story/_/id/27673918/pats-rb-white-missing-game-child-birth · https://www.cbsnews.com/minnesota/news/vikings-qb-mccarthy-misses-practice-for-birth-of-son/ · https://www.nbcsports.com/nfl/profootballtalk/rumor-mill/news/flacco-misses-birth-of-child
- https://www.cbssports.com/nfl/news/deshaun-watson-announces-death-of-father-two-days-before-cleveland-browns-season-opener/ · https://www.cbssports.com/nfl/news/bucs-devin-white-reflects-on-huge-performance-vs-seahawks-after-fathers-death-it-was-very-hard-to-play · https://www.cbssports.com/nfl/news/james-white-opens-up-about-fathers-tragic-death-after-first-game-back-since-fatal-car-accident/
- https://www.cbssports.com/nfl/news/bruce-arians-says-tom-bradys-personal-life-played-a-role-in-buccaneers-struggles-in-2022 · https://www.espn.com/nfl/story/_/id/34896047/tom-brady-gisele-bundchen-announce-divorce-13-years · https://www.cbsnews.com/boston/news/tom-brady-bahamas-vacation-buccaneers-absence-final-nfl-season-retirement/
- https://en.wikipedia.org/wiki/Taylor_Swift_and_Travis_Kelce · https://www.cbssports.com/nfl/news/chiefs-chose-not-to-play-taylor-swift-music-in-arrowhead-stadium-to-be-respectful-of-travis-kelce · https://sports.yahoo.com/articles/never-showed-taylor-swift-chiefs-033206137.html
- https://www.bengals.com/news/leah-and-devon-still-return-to-rule-the-jungle-again · https://www.si.com/extra-mustard/2015/03/25/devon-still-leah-cancer-remission-cincinnati-bengals

**Mental health**
- https://www.nfl.com/playerhealthandsafety/health-and-wellness/mental-health/
- https://www.washingtonpost.com/sports/2021/10/18/lane-johnson-depression-anxiety/ · https://www.inquirer.com/eagles/lane-johnson-depression-anxiety-eagles-20211018.html · https://www.espn.com/nfl/story/_/id/35526673/eagles-lane-johnson-mental-health-football-journey
- https://www.skysports.com/nfl/news/12118/12758694/hayden-hurst-cincinnati-bengals-tight-end-on-his-battle-with-anxiety-and-attempt-to-take-his-own-life · https://nflpa.com/posts/hayden-hurst-athleteand-mental-health-advocate
- https://www.statnews.com/2025/09/21/nfl-injury-list-sports-betting-athlete-medical-privacy/  *("personal reasons" stigma critique)*

**Drama / media**
- https://www.espn.com/nfl/story/_/id/45789518/nfl-training-camp-holdouts-trey-hendrickson-terry-mclaurin
- https://www.cbssports.com/nfl/news/agents-take-inside-look-at-the-consequences-and-dynamics-facing-nick-bosa-zack-martin-and-other-holdouts/
- https://www.cbssports.com/nfl/news/2024-nfl-training-camp-holdout-hold-in-tracker-latest-on-ceedee-lamb-trent-williams-haason-reddick-others/
- https://bleacherreport.com/articles/10132134-nfls-7-most-explosive-holdouts-and-contract-disputes-since-2015
- https://www.nfl.com/news/brandon-aiyuk-team-fits-five-potential-landing-spots-after-san-francisco-49ers-receiver-s-trade-request
- https://www.theglobeandmail.com/sports/football/article-spats-shoves-snubs-and-snapbacks-have-ruled-the-nfl-sidelines-in-2024/
- https://www.si.com/nfl/2019/09/07/antonio-brown-raiders-drama-timeline-helmet-fines-release · https://www.cbssports.com/nfl/news/antonio-brown-timeline-how-he-wore-out-his-welcome-in-pittsburgh-oakland-new-england-and-tampa-bay/
- https://en.wikipedia.org/wiki/Odell_Beckham_Jr.
- https://www.espn.com/nfl/story/_/id/23321086/josh-allen-apologizes-offensive-tweets-high-school-resurface · https://www.si.com/college/2018/12/09/kyler-murray-heisman-trophy-oklahoma-homophobic-tweets-apology
- https://www.espn.com/nfl/story/_/id/40821786/aaron-rodgers-says-regrets-2021-comment-was-immunized · https://www.cbssports.com/nfl/news/packers-aaron-rodgers-loses-endorsement-deal-with-healthcare-group-after-q-a-regarding-covid-19-vaccine
- https://www.profootballnetwork.com/nfl-stunned-bengals-training-camp-brawl/ · https://www.yardbarker.com/nfl/articles/chiefs_raiders_training_camp_brawls_spark_response_from_mahomes_kubiak/s1_17812_44159652 · https://www.essentiallysports.com/nfl-active-news-brian-schottenheimer-throws-cowboys-star-out-of-practice-after-punching-teammate/
- https://www.cbssports.com/nfl/news/nfl-locker-rooms-five-situations-that-could-explode/

**Positive**
- https://en.wikipedia.org/wiki/Walter_Payton_NFL_Man_of_the_Year · https://www.nfl.com/honors/man-of-the-year/ · https://www.espn.com/nfl/story/_/id/47392288/who-won-nfl-man-year-award-all-winners-list
- https://en.wikipedia.org/wiki/J._J._Watt

---

*Research note: this session's WebSearch quota was exhausted partway through (shared across parallel research
agents); the back half of the report was assembled via targeted WebFetch on sources surfaced by the earlier
searches. Gaps I would close with more search budget: (a) hard counts of players placed on reserve/NFI
mid-season across 2015–2025, (b) publicly-reported in-season divorces beyond the one canonical case, (c) a
systematic list of active-player deaths rather than the verified subset above, (d) contract-year performance
studies. Items marked `[R]` and `[E]` should be treated as design-grade, not citation-grade.*
