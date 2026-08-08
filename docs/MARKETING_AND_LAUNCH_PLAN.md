# Marketing & Launch Plan — Sunday Night Dynasty

**Written 2026-08-07.** Target launch **mid-March 2027**. Solo developer, iPad-first, offline.

This document is the marketing and go-to-market authority. Release *readiness* — the IP,
privacy and App Review blockers that gate a submission at all — lives in
[`APP_STORE_COMPLIANCE_AUDIT.md`](APP_STORE_COMPLIANCE_AUDIT.md). Read that one first: no
amount of audience building survives a legal problem with the league content.

---

## 0 · What the product actually is

Evidence-led, from the repo, because the plan is only worth as much as its picture of the product.

- **237,393 lines of Swift, 353 files, 274 SwiftUI `View` structs.** 375 commits since 2026-03-15.
- **13 TODO/FIXME comments in 237k lines. Zero `try!`. Two `fatalError`. No "coming soon" strings.**
  Unusually disciplined for a solo project, and a fact worth using in press outreach.
- 32 teams, 1,807 hand-shaped players in the shipping template, **350 prospects per draft class**
  (224 draftable, `Engine/Scouting/DraftClassBuilder.swift:69`), 65 offensive + 24 defensive play
  calls across 8×7 schemes, 31 music tracks, 34 SFX, **7,540 faces**, **39 mocap clips** as `.usdc`.
- **Completely offline.** Zero `URLSession`, zero CloudKit, zero third-party SPM packages.
  Local SwiftData only. English only.
- **No monetisation code of any kind.** Zero `import StoreKit`, no paywall, no IAP, no ads, no
  analytics, no crash reporting, no `SKStoreReviewController`.

### The five things not on the App Store

1. **The press-conference promise ledger** (`Engine/Media/PressEngine.swift:853-1060`). Answer
   aggressively and the game parses "parade" / "title" / "playoff" into a typed
   `PressPromiseRecord`, persists it on `Career.pressPromiseLedger`, and settles it at exactly one
   site at season end (`WeekAdvancer.swift:6073`) against your real record — then prints your own
   quote next to your final standings. **No football game tracks what you said.**
2. **Fog-of-war scouting** (`UI/Draft/Components/ProspectFog.swift`, 844 lines). `trueOverall` is
   architecturally unreachable from the view layer, and **the sort key is fogged too**, so the board
   cannot leak through ordering. Confidence ladder 0.40 → 0.90 across nine rationed instruments.
3. **Scheme familiarity as a playable stat** — per-player, per-scheme 0–100, consumed by the play
   resolver (`PlaySimulator.familiarityBustChance`). A free agent who doesn't know your system
   visibly blows the assignment. Madden has this as a cosmetic badge.
4. **A real 3D match view with skinned mocap** (`FootballFieldScene.swift` 6,147 lines,
   `SkeletalFigure.swift` retargeting 39 USD clips onto `SCNSkinner`, 9 position-specific stances).
5. **A contract negotiation dialogue system** — ~470 authored lines across 7 agent personas × 8
   derived player desires, deterministic so a conversation replays word for word.

### Blocking gaps

Zero tests · no SwiftData migration plan (30 `@Model` types) · no crash reporting · no iCloud sync ·
dead Settings toggles · onboarding is 5 tips for a 274-screen game.

---

## 1 · Positioning

> **Sunday Night Dynasty is Football Manager for American football on iPad: you scout prospects you
> can't see clearly, build your own draft board, and the league remembers everything you promised at
> the podium.**

Short form: **"You never see a true rating. Neither does a real GM."**

### The wedge — one thing

**Information scarcity is the game.** Every football title on the App Store hands you a number.
This one refuses to, architecturally, then makes you spend a finite budget across nine instruments
to narrow a letter-grade band. Everything else is proof, not wedge:

- the **promise ledger** is the shareable hook
- the **3D match view** is the visual credibility hook — it kills the "spreadsheet" objection that
  this genre's screenshots normally fail
- **scheme familiarity** is the depth proof for the Football Manager crowd

Lead with the wedge. Prove with the hooks. Never lead with a feature list.

### Audience, in descending conversion likelihood

1. **Madden franchise-mode refugees** — largest, angriest, most reachable. Operation Sports,
   r/Madden, the EA franchise forums. Verified inbound signal: the 2026 cycle around
   community-authored draft classes. People are hand-building 250-prospect classes because the
   shipped ones are boring; you generate 350 with a scouting economy.
2. **/r/NFL draftniks** — highest passion density, sharpest seasonality (Jan–Apr). The only audience
   for whom the core loop needs no explanation.
3. **OOTP / Front Office Football / text-sim veterans** — small, highest willingness to pay, highest
   review-writing rate, no good iPad option today.
4. **Football Manager players** — most likely to understand the fog-of-war pitch instantly.
5. **Fantasy football sickos in the offseason** — worthless in September, valuable Jan–May.

**Not your audience:** anyone who wants to *play* football. Say "watch your plays run", never "play
football", or you earn one-star reviews from people expecting Madden.

### Competition

| Competitor | Where you win | Where they win |
|---|---|---|
| **Pocket GM 3** ($2.99) | Depth, 3D, scouting uncertainty, faces, press/owner systems | Price, iPhone, install base, existing community |
| **Ultimate Pro Football GM** (free+IAP) | Simulation fidelity, presentation, writing | Free = discovery, broad device support |
| **Blitz Football Franchise 2026** | Everything about depth | Annual cadence, niche name recognition |
| **Football Coach: College Dynasty** | Pro league, scouting economy, presentation | College is arguably a hotter niche; they own it |
| **Madden NFL Mobile** | You are the anti-Madden-Mobile. Say so. | Infinite budget, the license |

**The sentence to memorise:** *"Every other football GM app hands you a number. This one hands you a
scouting budget."*

---

## 2 · Pre-launch — where this is won

Seven months of runway. **The entire job is to manufacture 100–300 people who have played it and
will say "this is the real thing" on launch day.** Nothing else matters as much.

### Cadence

**One post per week, same day, forever. Thursday.** One post is sustainable at ~90 minutes; three
is not, and an abandoned devlog is worse than none. Rotate four types:

1. **A mechanic with a screenshot** — the band narrowing across three scouting stages. This *is* the
   marketing.
2. **A confession** — a balance bug, a system deleted. `28fc46d chore(ui): delete the dead code
   (1967 lines)` is a post. Sim audiences infer honesty about the simulation from honesty about the
   process.
3. **A number** — from the balance harness. `docs/BALANCE_REPORT_2026-07.md` is a year of content
   and **no competitor in this space can post it.**
4. **A GIF** — 6–10 s, the 3D field, a play running the assignment that was called.

### Channels

**Tier 1:** Operation Sports forums (the single highest-value venue; their editorial side reviews
sports games and runs the *Press Row Podcast*) · r/Madden (useful posts only, never link drops) ·
r/NFL_Draft + r/NFLDraft (hold until Jan–Feb 2027, then go hard) · r/footballmanagergames (one
high-effort cross-genre post) · r/iosgaming (best subreddit for premium iOS, and it likes devs) ·
Bluesky (the sports-media diaspora) · X (still where April draft discourse happens).

**Tier 2:** r/OOTP + OOTP Developments forums · Front Office Football Central · **gmgames.org** (the
only outlet that exists specifically for this genre on mobile) · r/DynastyFF + r/fantasyfootball
(January onward) · **your own Discord — opened at TestFlight, not before.** An empty Discord is a
negative signal.

**Tier 3 — skip:** TikTok, Reels, Shorts. The format cannot carry the information density and the
buyers are not there.

> **TouchArcade shut down in 2024.** Do not build a press plan around it. Pocket Tactics survives.

### Screenshot discipline

Never post a placeholder, a debug overlay or lorem text — one bad screenshot costs more than ten
good ones earn. One idea per GIF, under 10 seconds. **Crop to the interesting rectangle**; a full
iPad screenshot at thumbnail size is unreadable. Automate a canonical capture set (the
`dynasty-sim-qa` skill plus the simulator MCP tools) so 20 clean assets take 30 minutes.
**Hold back the 3D field** and reveal it once, deliberately, around the mailing-list opening.

### The funnel

1. **One-page site** on your own domain. Hero GIF, pitch, email field, three screenshots. 1 day.
   Every post everywhere links here.
2. **Email capture** — Buttondown / ConvertKit / Beehiiv. Pick in an hour, never revisit.
3. **TestFlight public link** as the signup reward. Apple allows 10,000 external testers. **You want
   100–300 who will finish a season.** Gate lightly with "what's your favourite football game and
   why" — it filters tourists and gives you positioning language in their own words.
4. **Two waves:** ~30 hand-picked (December 2026), ~200–500 open (February 2027, timed to the Combine).
5. **Convert testers into launch-day reviewers.** One email on launch day, one ask.

**Hard dependency:** crash reporting must exist before the beta. TelemetryDeck (privacy-first, EU,
one SPM package, no IDFA, no ATT prompt) preserves the "no tracking" story.

---

## 3 · Store presence (ASO)

### Name

**Do not ship as "Dynasty."** Generic, unsearchable, contested — and the app currently disagrees
with itself (`MainMenuView.swift:140` renders `DYNASTY`, `:289` says "Sunday Night Dynasty").

- **App name (30):** `Sunday Night Dynasty` (20)
- **Subtitle (30):** `Pro Football GM & Draft Sim` (27)

Apple indexes name + subtitle + keywords as one corpus. **Never repeat a word across them.**

### Keyword field (100)

```
manager,franchise,scout,gridiron,front office,mock,combine,roster,coach,season,team,league
```

**Never** put `NFL`, `Madden` or any club name in metadata — competitor trademarks violate the
guidelines, and it would undo the work in `ANONYMIZATION_SPEC.md`. No plurals (Apple stems), no
spaces after commas.

### Screenshots — the first two frames do the work

1. **"This is not a spreadsheet."** 3D night stadium, mid-play. *"Coach the play. Or sim the season."*
   No text-sim competitor can produce this image. It goes first.
2. **"This is deeper than you assume."** The fogged prospect card. *"You never see a true rating."*
3. Press conference, promise about to be made. *"They'll remember you said that."*
4. War room mid-draft. *"Your board. Your call. 350 prospects a class."*
5. FA negotiation with the agent's dialogue visible. *"Work out what he wants from how his agent talks."*
6–8. Cap sheet, coaching staff/scheme, ten-season league history.

**The asset competitors cannot match:** faces. 7,540 of them, and the same player visibly ages
(`AgedFaceCatalog.swift`). A "drafted 2027 → 2034 Hall of Fame" before/after communicates *dynasty*
in one image.

### Preview video

25 s, iPad, no voiceover, **muted-first** (text overlays carry all meaning): 0–4 s a play running
its called route · 4–10 s the band narrowing across three stages · 10–16 s draft night · 16–21 s
the promise, hard cut to the February headline quoting it · 21–25 s title card, "iPad. Offline. No ads."

### Description — first three lines

> **You never see a true rating. Neither does a real GM.**
>
> Sunday Night Dynasty is a deep, offline pro-football management sim for iPad. Scout prospects
> through fog, build your own draft board, negotiate with agents who won't tell you what they want,
> and coach the games that matter — play by play, in 3D.
>
> Everything you say at the podium is written down.

Below the fold: hard numbers. Close with **no ads, no IAP after the unlock, no account, no internet,
one price.**

---

## 4 · Launch

### Timing — mid-March 2027, the new league year

| Peak | Date | Fit |
|---|---|---|
| Season kickoff | ~10 Sep | **Worst.** Everyone is playing actual football; Madden owns the airspace. |
| **New league year / FA** | **~mid-Mar** | **Best.** The news cycle is literally cap space and roster building. Competition quiet. |
| The Draft | late Apr | Best for the wedge, worst for launch day — you'd spend the peak with zero reviews. |

**Launch mid-March 2027; treat the Draft six weeks later as the amplification event** into an app
that already has reviews and word of mouth.

### Press and creators

**Who covers this:** Operation Sports (+ *Press Row Podcast*) · Sports Gamers Online · Pastapadre ·
gmgames.org · Pocket Tactics · the Madden-franchise YouTube ecosystem — **prioritise 5k–80k subs**,
big enough to matter, small enough to answer email.

**The pitch email, exactly:**

- Subject is a **claim**: `A football GM sim where you never see a player's true rating`
- Line 1: what it is, iPad, price, date. Line 2: the wedge. Line 3: the weird credibility detail —
  *"Every promise you make in a press conference is parsed, stored, and quoted back to you next to
  your final record."* That sentence gets replies.
- **A 20-second GIF inline.** Not attached, not a Drive link.
- **A TestFlight code in the first email, unrequested.** Friction is why indie pitches get ignored.
- A press-kit link. **Under 150 words.** Send 4 weeks out, follow up **once**.

Realistic: 40 emails → 6 replies → 2 pieces. Plan a launch that survives zero coverage.

### Apple featuring

App Store Connect → **Featuring → Nominations**, type **"App Launch"**. Editorial plans **8–12 weeks
ahead** — **submit 8 weeks out (mid-January 2027)**. A two-week nomination is a wasted form.

They look for, in order: design quality and platform fit · Apple technologies · a story worth
editorial copy · timeliness · accessibility · launch timing.

**Your angles:** iPad-first design using the large canvas · SceneKit + skinned USD skeletal
animation on-device · SwiftData · **fully offline, no ads, no tracking, no account** · a solo
European dev with a seven-month public build history.

**Fix before nominating:** the app icon is a **JPEG** with dark/tinted slots empty · no Dynamic Type
(2,301 hardcoded `.font(.system(size:))`, zero `ScaledMetric`) · hard-pinned `.preferredColorScheme(.dark)`.
Also submit an **In-App Event** for Draft Week — a separate, under-used surface Apple can feature.

### Launch week

- **T-8w** nomination submitted, press kit live, store page finished
- **T-4w** press/creator emails with builds; pre-orders enabled
- **T-2w** final TestFlight to the whole list; announce the date
- **T-1w** the "final devlog" — seven months condensed. Most-shared post; a story, not an ad.
- **Launch day (Tuesday)** — 09:00 live + GIF · 09:15 email the beta list, one ask: review today ·
  10:00 r/iosgaming, Operation Sports · **answer every comment for 72 hours.** Ship a hotfix within
  72 h regardless; it signals life.
- **T+6w (Draft Week)** the second launch: update + In-App Event + second press wave.

---

## 5 · Monetisation

**Free to download, one non-consumable "unlock the full career" IAP at €/$14.99.**

**The gate: play free from career creation through the end of your first regular season. The unlock
is required to enter the playoffs and the offseason.** Perfect for this game — the offseason *is*
the wedge. You are not giving away the good part; you are giving away the part that proves it exists.

Why: the App Store's discovery machine is built for free apps · your central problem is **disbelief**
that a mobile football game is this deep, and screenshots cannot fix it but ten hours of play can ·
it costs about a day (StoreKit 2, one product, `Transaction.currentEntitlements`, restore) · no
live-service burden, consistent with the zero-network architecture.

**Enroll in the App Store Small Business Program.** Under $1M/yr, 30% → 15%. On €14.99 that is
€12.74 net instead of €10.49 — **a 21% revenue increase for one form.** Highest-ROI hour in the plan.

**Rejected:** premium up-front (right model, wrong moment — no reputation to sell on; revisit in year
two) · subscription (nothing to keep paying for, and this audience reads it as betrayal — it would
poison the positioning that is your main asset) · free with consumables/ads (fatal to the wedge).

**Price:** run **€11.99 for launch week**, then step to €14.99. Never launch high and discount — the
sale becomes the only price. If you flinch, launch at €11.99 and raise; Apple lets you raise prices
and existing owners keep their purchase.

### The annual-edition question

**One SKU, forever.** The App Store has **no upgrade pricing** — a "2028" edition is a separate app
with reviews from zero, and every existing customer sees abandonment. A single app accumulating
2,000 reviews over four years outranks four apps with 500 each, every time. Instead: a free "2028
season" content update each spring, base price +€2–3 a year as the game deepens, and if year three
brings something genuinely large, sell it as **one expansion inside the same app.**

---

## 6 · Post-launch

**Monthly, on a published date, for the first year.** For sim audiences cadence *is* the product —
they have all been burned by abandoned sims. Write patch notes the way this repo writes commit
messages, and **publish balance-harness numbers in them.** Nobody else in the genre can.

| Real NFL moment | Your beat |
|---|---|
| Kickoff (Sep) | "Week 1" update, In-App Event, a takeover scenario |
| Trade deadline (Nov) | Trade-system update, deadline scenario |
| Black Monday (Jan) | Coaching-carousel content |
| Combine (Feb) | Scouting update — **highest-affinity moment** |
| New league year (Mar) | Cap/FA update, launch anniversary, annual price step |
| **The Draft (Apr)** | **Biggest beat of the year.** New class generation, In-App Event, shared-seed mock challenge |
| OTAs/camp (May–Jul) | Camp and development update; quiet period for engine work |

**The single best retention mechanic, and it is free:** publish a **shared draft-class seed** each
April. Everyone drafts the same 350 prospects; people post their boards and argue. Generation is
already deterministic. It turns a single-player offline game into a communal event on the exact week
the football internet is most excited.

### The two features that most affect retention

1. **A name/team editor or community draft-class import.** Your league is fictional; an editor lets
   players re-add real names themselves — solving the biggest audience objection **without you ever
   shipping a licensed name** — and turns users into content producers. *(Get this specific question
   in front of the same IP lawyer as `ANONYMIZATION_SPEC.md`; user-generated names are a materially
   different position from shipped ones.)*
2. **iCloud save sync.** A ten-season dynasty lost to a device upgrade is a one-star review and a
   lost customer. For a game whose value proposition is longevity, this is a retention bug.

### Reviews

There is no review prompt in the codebase. Add one and **place it after the player wins a playoff
game or completes their first draft** — the moment of maximum satisfaction — gated behind at least
one completed season. Answer every App Store review for six months; almost nobody does, and
prospective buyers read the replies.

---

## 7 · The 90-day plan (7 Aug – 6 Nov 2026)

Marketing should consume **20–25% of working time** — roughly **6–10 h/week**. If a week slips, drop
the "if time" item, never the devlog.

### Phase A — Foundations (weeks 1–4)

| Week | Do | Hours |
|---|---|---|
| 1 | Decide the name, make the app agree with itself · **contact an IP lawyer** (longest lead time in the project) · **decide iPhone in or out** (almost certainly `TARGETED_DEVICE_FAMILY = "2"` for v1) · reserve the name in ASC, buy the domain | ~5 |
| 2 | Build the **capture ritual** (script → 20 screenshots + 4 GIFs; you will run it 50 times) · devlog #1: the fogged prospect card | 6 |
| 3 | One-page site + email capture · devlog #2: a balance-harness number | 7.5 |
| 4 | Press kit v1 · devlog #3: the promise ledger · **register for the Small Business Program** | 5 |

### Phase B — Presence (weeks 5–8)

| Week | Do | Hours |
|---|---|---|
| 5 | Ride NFL kickoff (10 Sep) with your best 3D GIF · devlog #4 | 3.5 |
| 6 | Introduce yourself properly on Operation Sports; answer every reply for a week · devlog #5 | 5.5 |
| 7 | **Add crash reporting** (beta prerequisite) · devlog #6 | 7.5 |
| 8 | **Add the StoreKit 2 unlock** — now, not February; payment bugs at launch are fatal · devlog #7 | 9.5 |

### Phase C — Beta machinery (weeks 9–13)

| Week | Do | Hours |
|---|---|---|
| 9 | **Write the SwiftData migration plan** — highest-risk item in the project; must exist before testers create saves · devlog #8 | 13+ |
| 10 | Fix the dead Settings toggles · onboarding pass · devlog #9 | 13 |
| 11 | Open the Discord + TestFlight signup · **hand-recruit 30 testers by DM** · devlog #10 | 8.5 |
| 12 | Ship the first TestFlight build · live in the Discord all week · devlog #11 | 10.5 |
| 13 | Triage feedback into blockers / **positioning language** / rest · devlog #12: the 90-day retrospective | 7 |

**After day 90:** Nov–Dec UI redesign + hardening · **January: Apple nomination (8 weeks out)**,
press kit v2, draft-community warm-up · February (Combine): open beta 200–500, press emails ·
**mid-March: launch** · late April (Draft): the second launch.

---

## 8 · Ruthless priority

### The three that matter

1. **Get 100–300 real people playing before launch and turn them into launch-day reviewers.**
   Everything else serves this. Trust in this genre is transmitted person-to-person on Operation
   Sports and Reddit, not by advertising.
2. **Free-to-try, €14.99 unlock gated at the end of the first regular season, Small Business
   Program.** Lets the product do its own convincing. One day of code, roughly doubles effective
   conversion versus paid-up-front while preserving premium economics.
3. **Launch mid-March 2027 and make fog-of-war scouting the entire message** — stated identically in
   the subtitle, the second screenshot, the first line of the description, and every press email.

### The three wastes of time

1. **Short-form video.** A management sim cannot be communicated in nine vertical seconds, and €15
   football-sim buyers do not discover software there.
2. **Paid user acquisition.** Break-even CPI on a €12.74-net unlock at 3–8% trial conversion is a
   few tens of cents — unachievable for a niche iPad sim. (Narrow later exception: defensive Apple
   Search Ads on your own brand name, *after* you have a brand worth defending.)
3. **Localisation, Android, Mac — for v1.** 2,516 string keys with only ~204 `String(localized:)`
   call sites means localisation is a months-long project. All three are legitimate year-two moves
   and catastrophic year-one distractions.

---

## 9 · The honest caveat

**The biggest risk to this launch is not marketing.** It is the uncleared IP review in
`RELEASE_CHECKLIST.md` §7 and the absent save-migration plan. Both are on the 90-day plan above
(weeks 1 and 9) for exactly that reason. See
[`APP_STORE_COMPLIANCE_AUDIT.md`](APP_STORE_COMPLIANCE_AUDIT.md).

---

## Sources

[gmgames.org iPad](https://gmgames.org/section/ipad/) ·
[Pocket GM 3](https://apps.apple.com/us/app/pocket-gm-3-football-sim/id1645791169) ·
[Ultimate Pro Football GM](https://apps.apple.com/us/app/ultimate-pro-football-gm/id1530542938) ·
[Blitz Football Franchise 2026](https://apps.apple.com/us/app/blitz-football-franchise-2026/id1573378462) ·
[Operation Sports](https://www.operationsports.com/) ·
[Madden 26 community draft classes](https://www.1v1me.com/blog/madden-26-community-draft-classes-franchise-mode) ·
[Apple: nominate your app for featuring](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/) ·
[TechCrunch on featuring nominations](https://techcrunch.com/2024/06/13/apple-gives-developers-a-way-to-nominate-their-apps-for-editorial-consideration-on-the-app-store) ·
[TouchArcade (closed 2024)](https://en.wikipedia.org/wiki/TouchArcade) ·
[Pocket Tactics](https://www.pockettactics.com/)
