# App Store Compliance & IP Audit

**Audited 2026-08-07** against the tree at `fa12446`.

> **Not legal advice.** This is an engineering risk assessment. Everything in category (a) warrants
> a real IP lawyer before shipping. `RELEASE_CHECKLIST.md` §7 has required this since it was
> written; it is still uncleared and it is the longest-lead-time item in the project.
>
> The Finnish/EU angle matters, but NFL Properties and NFLPA/OneTeam enforce in the US, which is
> where the App Store exposes you.

Go-to-market lives in [`MARKETING_AND_LAUNCH_PLAN.md`](MARKETING_AND_LAUNCH_PLAN.md).

---

## Bottom line

**It cannot ship as-is.** But you are far closer than the screenshots suggest, because the
fictionalisation machinery is already built — it just isn't on the default path.

### The structural surprise: the league picker is inverted

| Picker option | What it builds | Status |
|---|---|---|
| **"Generated"** — the default (`NewCareerView.swift:34`) | `LeagueGenerator.swift:156` → `for teamDef in NFLTeamData.allTeams` → **all 32 real club names** | ❌ Infringing |
| **"Fixed 2026"** (publish template) | `LeagueTemplateImporter.swift:145` → Arizona Sunspires, Dallas Longriders, Kansas City Stockyards, Pittsburgh Steelworks… | ✅ **Already fully fictional** |
| **"Fixed 2026 (Dev)"** | Real clubs, owners, players | ✅ Correctly excluded from Release (verified) |

`league_2026_publish.json` already carries **32 invented nicknames, 32 invented head coaches, ~1,700
invented players**. It reads `NFLTeamData` only for `mediaMarket` and a conference/division fallback
(`LeagueTemplateImporter.swift:117`).

**The single source of the club-name problem is 49 lines in one file: `NFLTeamData.swift:125-173`.**

"Ship only the generated league" — the intuitive safe answer — is **backwards**: the generated path
is the one calling `NFLTeamData.allTeams`.

---

## 1 · Findings by exposure

### (a) Hard blockers

**a1 · All 32 real club names/cities/abbreviations on the default path.**
`Data/Import/NFLTeamData.swift:125-173` — `NFLTeamDefinition(name: "Bills", city: "Buffalo",
abbreviation: "BUF", …)` ×32. Consumers: `LeagueGenerator.swift:156`, `TeamBrowseCatalog.swift:97,124`,
`LeagueTemplateImporter.swift:117`. Stragglers: `TopNavigationBar.swift:220` (preview),
**`CoachingTreeView.swift:344` — `"HC at Green Bay Packers"`, shipping data, not a preview.**
*Trademark: likelihood of confusion + implied endorsement, in the exact goods class the NFL licenses
to EA. Guideline 5.2.*

**a2 · Eight real, living journalists by name with employer attribution.**
`Engine/Media/PressConferenceEngine.swift:217-226` — Adam Schefter (ESPN), Ian Rapoport (NFL
Network), Jay Glazer (FOX Sports), Josina Anderson (CBS Sports), Tom Pelissero (NFL Network), Diana
Russini (The Athletic), Mike Garafolo (NFL Network), Albert Breer (SI). They are *characters who ask
you questions*.
*Right of publicity — strongest for living people, and all eight are living. Name + employer +
occupation in a commercial product is the core case, not the edge.* **Cheapest fix, most dangerous
finding: 10 lines, and the one that would most obviously read as bad faith in court.**

**a3 · Real broadcaster marks as in-game brands, with fabricated quotes.**
`MockDraftView.swift:470,483,496` · `InboxEngine.swift:272,624,929` · `WeekAdvancer.swift:3094` ·
`PressEngine.swift:1034` · `FACompleteView.swift:983,990,997` (`"NFL Network: 'The \(teamName)…'"`).
*Trademark + false attribution. Inventing editorial content in a real outlet's mouth is worse than
naming it.*

**a4 · "NFL" as a literal UI string — 50 sites.** Including **`MainMenuView.swift:146`
`Text("NFL FOOTBALL MANAGER")`** and `:493`, `DraftDayView.swift:33`, `CombineResultsView.swift:475`,
`SeasonPhase.swift:73,76`, `InboxMessage.swift:93`. *The main-menu tagline is the worst — it is your
App Store screenshot, claiming league affiliation on the title screen.*

**a5 · The NFL shield is in the artwork.**
`Assets.xcassets/BgDraft.imageset/bg_draft.jpg` — **four legible NFL shields plus the "NFL DRAFT"
wordmark**, live at `DraftDayView.swift:123`. Also `bg_press.jpg` (shield-form crest, live on both
press screens) and Nike/adidas/Puma logos across `bg_locker.jpg`, `bg_locker3.jpg`,
`bg_combine.jpg/2/3/5`, `bg_training3.jpg`.
*Copyright **and** trademark. AI-generated art reproduced real marks; every existing release gate is
a text scan and would never catch it.* **16 of 30 imagesets are unreferenced anyway** — deleting
them kills five of the marked files at zero product cost.

**a6 · "Super Bowl" (60 hits) and "Pro Bowl" (46).** `TimelineTasksPanel.swift:769-770` ·
`SeasonPhase.swift` · `CalendarSidebarView.swift:434-435` · `MainMenuView.swift:213-214` ·
`CareerDashboardView.swift:4442`. Plus "Senior Bowl" (36).
*"Super Bowl" is among the most aggressively policed marks in existence — advertisers say "the big
game" for a reason.*

**a7 · Official club colour values.** `UI/Match/TeamColors.swift:50-84` — `"KC": rgb(227,24,55)` is
`#E31837`, the Chiefs' exact brand red; `"BUF": rgb(0,51,141)` is `#00338D`.
`TeamSelectionView.swift:1147-1191` annotates every case with the real club (`// Steelers black`).
*Trade dress. Colour alone is weak; colour + real abbreviation + real city + right divisions is a
strong composite. Drops to (b) once the names go fictional — but **the source comments document
intent**, which is the awkward part.*

**a8 · Trademarked fan-culture phrases.** `NFLTeamData.swift:122` — `"Passionate 12th Man fan base"`
(Texas A&M's registered mark, licensed to Seattle) and `"America's Team"` (registered to Dallas).

### (b) Grey areas — judgement calls

- **Real US city names** — geographic, not ownable. "Buffalo Blizzard" is how every unlicensed
  sports game does it. Keep.
- **Real abbreviations (BUF, KC, SF)** — geographic shorthand. Fine alone; the risk was the pairing.
- **"AFC"/"NFC"** (`Conference.swift:4-5`) — these *are* NFL marks but borderline-descriptive.
  **Rename anyway**: two-line enum change, costs nothing.
- **Real university names** — `ScoutingEngine.swift:8-17` (40 schools) + **205 in the publish
  template**. School names are trademarks and the NCAA/schools do license them. But this is thin,
  non-branded biography with no logos or colours. **Medium risk, not a blocker.** Front Office
  Football and Draft Day Sports ship generic descriptors instead. Swap eventually, not in wave 1.
- **Generic football vocabulary** — down, snap, blitz, Cover 3, scheme names. Safe, descriptive
  terms of art.
- **Real team strengths/records/pick trades** in the template — facts about the world.
  `ANONYMIZATION_SPEC.md` reasons about this correctly.

### (c) Safe — and genuinely well done

- **No club logos or wordmarks exist as bitmaps anywhere.** Club identity is `Circle().fill(color)` +
  abbreviation text (`TeamSelectionView.swift:1123-1140`, `TopNavigationBar.swift:96-115`);
  `uniform_0…5.png` are flat-colour atlases. **The right architectural call, and it saves you
  enormously.**
- **No real player names on rosters**, no real stadium names anywhere (Arrowhead/Lambeau/MetLife/SoFi:
  zero hits).
- **`docs/ANONYMIZATION_SPEC.md`** is strong — reasons from *Keller/Davis v. EA*, treats
  identifiability as a *stack* rather than a name check, enforces Levenshtein ≥3 plus a name-pool
  cross-product guard. `scan_bundle.py` gate E catches runtime-composed names, a hole most people miss.
- **Audio is exemplary.** `tools/audio/LICENSES.md` (1,019 lines) covers all 65 shipped files with
  per-file provenance. **One live obligation:** the Stability Community License terminates above
  **$1M annual revenue** (`LICENSES.md:252-272`) — diarise it.
- **`league_2026_dev.json` gating works** — triple-gated and empirically verified absent from a real
  Release product.

### Provenance gaps — not infringement, but you cannot prove non-infringement

| Asset class | Status |
|---|---|
| Audio (65 files) | ✅ Full ledger |
| League JSON | ✅ Full spec + automated gate |
| **Faces (7,540 HEIC)** | ⚠️ FLUX-schnell/Replicate known; licence asserted in one unversioned line of `FACE_GENERATION_PLAN.md` §4. Prompts correctly forbid public figures. |
| **3D mesh + mocap (47 files)** | ❌ The entire record is the word **"bought"** (`ANIMATION_OVERHAUL_PLAN.md:45-48`). No vendor for the 21-clip pack, no redistribution clause, and Adobe Mixamo ships in `juke_a`. **Weakest link.** |
| **30 background JPGs** | ❌ **No provenance at all** — and 10 carry third-party marks. |

---

## 2 · App Review readiness (separate from IP)

**The DEBUG panel does not ship.** `CareerDashboardView.swift:2906` is `#if DEBUG`, both call sites
(`:671-673`, `:744-746`) are independently gated, and Release defines no
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` with no `.xcconfig` to reintroduce it. Every other debug
affordance is gated too.

**Privacy is the easiest label you will ever fill in:** zero networking, zero third-party SDKs, no
IDFA/ATT, no GameKit/StoreKit/CloudKit. Declare **"Data Not Collected"** across the board.

### Must fix before submission

1. **No `PrivacyInfo.xcprivacy`**, but a required-reason API is called in Release:
   `MainMenuView.swift:316` reads a file modification date (`NSPrivacyAccessedAPICategoryFileTimestamp`,
   reason `C617.1`), plus 171 `UserDefaults` sites (`CA92.1`). *Simplest fix:* `#if DEBUG` the build
   stamp at `:314-322` (it is a dev QA aid), then declare UserDefaults only.
2. **`TARGETED_DEVICE_FAMILY = "1,2"`** (`project.pbxproj:312`) ships Universal, so Apple reviews on
   iPhone. `CareerDashboardView.swift:509` branches only on `verticalSizeClass`; the portrait layout
   pins a 300 pt rail (`:697`), leaving ~89 pt of content on a 390 pt iPhone. **Set it to `2`.**
3. **No privacy policy exists in the repo.** ASC requires the URL even for "Data Not Collected".
4. **Settings ships six dead controls** — Haptics (`SettingsView.swift:228`), Simulation Speed
   (`:280`), Difficulty (`:289`), Theme (`:341`, app is hardcoded dark), four Notification toggles
   (`:358,365,373,381`; `UserNotifications` never imported). Worse, `:334` **states as fact** that
   *"Difficulty affects AI roster construction, trade valuation, and free-agent competition"* —
   nothing reads the key. **Reviewers always open Settings. This is the likeliest non-IP rejection.**
5. **`playoffsHeroCard` is 100% hardcoded** (`CareerDashboardView.swift:4017-4033`, reachable at
   `:3781`) — always "Wild Card", "Vs Seed #5", "Vegas line -3.5". Delete the Vegas line while there.
6. **Cap Scenario buttons lie** — `RosterEvaluationView.swift:2467` is a `TODO(#252)` stub rendering
   a green checkmark and *"will be released after FA. Confirm in Free Agency"*. Nothing is queued.

### Should fix

`ITSAppUsesNonExemptEncryption` absent (CryptoKit SHA512 for seeding is exempt, but you will be
re-prompted every upload) · app icon is a **JPEG** · launch screen is white while the app forces dark ·
name mismatch "Dynasty" vs "Sunday Night Dynasty" · `DataContainer.swift:41` `fatalError` with 30
`@Model` types and **no `SchemaMigrationPlan`** — fine for 1.0, a crash risk on the first *update*.

### Age rating

Expect **4+/9+**. No gambling mechanic (all "betting" hits are negotiation idiom). No alcohol/drugs/
profanity. Text-only arrest/misconduct events (`EventTemplates.swift:130-145`) and clinical injury
vocabulary → answer *Infrequent/Mild realistic violence*. No UGC, no links out, no social features.

### Accessibility (note only)

262 `accessibilityLabel` + 83 `accessibilityElement` — genuinely good for a solo project.
**Gap: Dynamic Type unsupported** — 2,301 hardcoded `.font(.system(size:))`, zero `ScaledMetric`, and
117 `minimumScaleFactor` calls that *shrink* text, the opposite of what a low-vision user needs.

---

## 3 · The remediation plan

### Wave 1 — the shippable minimum (~1 day, no game logic touched)

| # | Change | Files | Cost to feel |
|---|---|---|---|
| 1 | Swap 32 `name:` values for the publish template's nicknames | `NFLTeamData.swift:125-173` | **Zero** — you already play with these names in Fixed 2026 |
| 2 | Delete the 8 real reporters; keep the 3 fictional locals at `:227-231` | `PressConferenceEngine.swift:217-226` | Zero |
| 3 | Invented outlets ("National Sports Network", "The Gridiron Weekly") | ~15 sites, see a3 | Zero |
| 4 | "NFL" → invented league name; "Super Bowl" → "The Championship"; "Pro Bowl" → "All-Star Game"; "NFL Combine" → "The Combine"; "Senior Bowl" → "The Showcase" | ~200 edits, mostly via `SeasonPhase.swift:73-76` | Zero — reads *more* like your own game |
| 5 | Delete `bg_draft.jpg`, `bg_press.jpg`, `bg_locker.jpg`, `bg_combine.jpg` + all 16 unreferenced imagesets | `Assets.xcassets` | 4 screens need a replacement background |
| 6 | Fix "12th Man" and "America's Team" | `NFLTeamData.swift:75-123` | Zero |
| 7 | `TARGETED_DEVICE_FAMILY = 2` · `#if DEBUG` the build stamp · `PrivacyInfo.xcprivacy` · `ITSAppUsesNonExemptEncryption` | `project.pbxproj`, `MainMenuView.swift:314-322` | Zero |
| 8 | Delete the 6 dead Settings controls + the false footer claim | `SettingsView.swift` | Zero — they do nothing today |
| 9 | Fix `playoffsHeroCard` + Cap Scenario buttons | see must-fix 5, 6 | Positive |
| 10 | Write + host a privacy policy | new | Zero |

**Nothing in wave 1 touches game logic.** The 72 files referencing `abbreviation`/`.city` read from
`Team`, which reads from the table — they do not care what the strings say. Rename `NFLTeamData` →
`LeagueTeamData` in the same pass so the source stops advertising intent.

**Note the side effect:** this makes the *Generated* league fictional too, and Generated and Fixed
2026 finally agree with each other — which is arguably a bug fix regardless of law. It is a
user-facing change of every team name in the default mode, so the **timing is a product decision.**

### Wave 2 — hardening (~2–3 days)

- Extend `tools/league-data/scan_bundle.py` with an **artwork + trademark gate**: blocklist "NFL",
  "Super Bowl", the 32 real nicknames, the 8 reporters, the outlet names, scanned over the Release
  binary. Add as gate 8 in `RELEASE_CHECKLIST.md`. **The existing gates are text-and-player-names
  only — they would have passed every finding above.**
- Rename `Conference.AFC/.NFC`.
- Perturb the colour palettes off the exact brand hexes; strip the `// Steelers black` comments.
- **Write `docs/ASSET_LICENSES.md`** to the standard `tools/audio/LICENSES.md` already sets, covering
  faces, 3D and images. Highest-value single doc available; there is a working model in-repo.
- **Resolve the 3D licence question** — name the Studio Ochi vendor and the 21-clip pack vendor,
  record each EULA's redistribution clause, record Adobe Mixamo's terms for `juke_a`.

### Wave 3 — post-launch

Swap real universities for invented schools (`ScoutingEngine.swift:8-17` + the 205 in the template;
needs a `make_templates.py` regen) · Dynamic Type · sub-44 pt tap targets.

---

## 4 · Recommendation

**Do wave 1 exactly as scoped, then pay for two hours of a US IP lawyer's time before the first
public build.** `RELEASE_CHECKLIST.md:27-29` already requires it, and `REALISTIC_LEAGUE_PLAN.md:66-67`
already reached the right conclusion — *"NFL team names/logos and the 'NFL' mark are trademarks —
game keeps its own team branding."* **The gap is purely that the generated path never got the memo.**

**The smallest change that makes the app shippable is item 1: 32 strings in
`NFLTeamData.swift:125-173`.** Items 2 and 5 are the next two hours and remove the most egregious
findings — eight living people by name, and the NFL shield rendered on your draft screen.
