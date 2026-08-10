# SwiftData Migration Plan (#171)

**Written 2026-08-10** against the tree at `775cae0`. Every claim below is anchored to `file:line`
in `dynasty/dynasty/`.

**Status: plan only.** Nothing in this document has been implemented. No `.swift` file was changed
to produce it. It exists because #171 gates the beta: the moment a build goes to a tester, that
tester's save is a thing the project has promised not to destroy, and today the project has no
mechanism — and no stated policy — for keeping that promise.

---

## Bottom line

Three facts, in order of how much they should worry you:

1. **There is no schema versioning at all.** `VersionedSchema`, `SchemaMigrationPlan` and
   `MigrationStage` appear **zero times** in the tree. The store is opened against an unversioned
   `Schema` literal (`Data/Persistence/DataContainer.swift:6-36`) and SwiftData is left to infer
   what changed. Inference works for the changes the house has been making — and only those.

2. **When inference fails, the app dies before the first frame.**
   `DataContainer.swift:38-42` wraps the open in `do { … } catch { fatalError(...) }`, and
   `DynastyApp.swift:8` creates the container in a **stored-property initializer**, which runs
   before `init()` and therefore before `CrashReportStore.shared.start()` on `DynastyApp.swift:20`.
   The failure mode is: crash on launch, every launch, deterministically, with no alert, no
   diagnostic surface, no export path, and possibly no useful MetricKit payload. On TestFlight the
   tester's only available action is delete-and-reinstall — which destroys exactly the save this
   task exists to protect.

3. **The dangerous surface is not the SwiftData columns; it is the 27 `Data?` JSON blobs and the
   nine Codable composite attributes.** SwiftData cannot migrate inside them, and the read bridges
   swallow decode failures (`try? … else { return [] }`, e.g. `Domain/Models/Career.swift:616-627`).
   A blob that stops decoding does not crash — the getter returns empty, the next write persists
   empty, and the entire inbox / news feed / hall of fame is gone silently. **This is the loss mode
   most likely to actually happen**, because it is invisible in review and invisible in QA unless
   somebody opens an old save specifically to look.

The plan: freeze today's shape as **V1** (§3), adopt the decision tree (§3.4), write the policy
down so it is enforceable in review (§4), build the old-store fixture harness that is the only real
proof any of this works (§5), and land it in five stages (§6).

---

## 1 · Inventory

### 1.1 The 29 `@Model` types

All 29 are registered in `DataContainer.swift:7-35`. Columns: **stored** = stored properties
(computed excluded); **dflt** = of those, how many carry an inline default (the house convention,
§2); **blob** = `Data?` JSON columns; **idx** = has an `#Index`; **careerID** = multi-save scope
column (`Data/Persistence/CareerScope.swift:12-42`).

| Model | Declared at | stored | dflt | blob | idx | careerID |
|---|---|---:|---:|---:|:--:|---|
| `Career` | `Domain/Models/Career.swift:4` | 68 | 46 | 24 | – | *(the root — none)* |
| `Player` | `Domain/Models/Player/Player.swift:4` | 70 | 38 | 2 | ✔ `:14` | `UUID?` |
| `CollegeProspect` | `Domain/Models/Scouting/CollegeProspect.swift:5` | 75 | 26 | 0 | ✔ `:15` | `UUID?` |
| `Coach` | `Domain/Models/Coach/Coach.swift:4` | 40 | 13 | 0 | ✔ `:14` | `UUID?` |
| `PlayerSeasonHistory` | `Domain/Models/Player/PlayerSeasonHistory.swift:31` | 35 | 25 | 1 | ✔ `:41` | `UUID?` |
| `TeamSeasonArchive` | `Domain/Models/League/TeamSeasonArchive.swift:85` | 25 | 3 | 0 | ✔ `:96` | `UUID?` |
| `Contract` | `Domain/Models/Contract/Contract.swift:19` | 22 | 4 | 0 | ✔ `:30` | `UUID?` |
| `Owner` | `Domain/Models/Team/Owner.swift:4` | 21 | 11 | 0 | – | `UUID?` |
| `Team` | `Domain/Models/Team/Team.swift:4` | 20 | 6 | 0 | ✔ `:14` | `UUID?` |
| `DraftPick` | `Domain/Models/Draft/DraftPick.swift:4` | 19 | 2 | 0 | ✔ `:14` | `UUID?` |
| `DraftPickGrade` | `Domain/Models/Draft/DraftPickGrade.swift:7` | 18 | 1 | 0 | – | `UUID?` |
| `Scout` | `Domain/Models/Scouting/Scout.swift:4` | 18 | 4 | 0 | – | `UUID?` |
| `TradeRecord` | `Domain/Models/League/TradeRecord.swift:33` | 16 | 1 | 0 | – | `UUID?` |
| `CareerArcState` | `Domain/Models/Draft/CareerArcState.swift:10` | 14 | 1 | 0 | – | `UUID?` |
| `FABid` | `Domain/Models/FreeAgency/FABid.swift:12` | 14 | 1 | 0 | – | `UUID?` |
| `DraftEvent` | `Domain/Models/Draft/DraftEvent.swift:7` | 11 | 1 | 0 | – | `UUID?` |
| `RosterCut` | `Domain/Models/Camp/RosterCut.swift:6` | 11 | 1 | 0 | – | `UUID?` |
| `Holdout` | `Domain/Models/FreeAgency/Holdout.swift:10` | 10 | 3 | 0 | – | `UUID?` |
| `VoluntaryWorkout` | `Domain/Models/Camp/VoluntaryWorkout.swift:6` | 10 | 1 | 0 | – | `UUID?` |
| `FAStorylineEvent` | `Domain/Models/FreeAgency/FAStorylineEvent.swift:8` | 9 | 1 | 0 | – | `UUID?` |
| `Game` | `Domain/Models/League/Game.swift:4` | 9 | 1 | 0 | ✔ `:14` | `UUID?` |
| `PositionBattle` | `Domain/Models/Camp/PositionBattle.swift:7` | 9 | 1 | 0 | – | `UUID?` |
| `TrainingPlan` | `Domain/Models/Camp/TrainingPlan.swift:7` | 9 | 1 | 0 | – | `UUID?` |
| `WorkloadEvent` | `Domain/Models/Camp/WorkloadEvent.swift:6` | 9 | 2 | 0 | ✔ `:16` | `UUID?` |
| `FAVisit` | `Domain/Models/FreeAgency/FAVisit.swift:8` | 8 | 1 | 0 | – | `UUID?` |
| `HardKnocksEvent` | `Domain/Models/Camp/HardKnocksEvent.swift:6` | 8 | 1 | 0 | – | `UUID?` |
| `League` | `Domain/Models/League/League.swift:4` | 7 | 1 | 0 | – | `UUID?` |
| `OpponentPrepWeek` | `Domain/Models/Camp/OpponentPrepWeek.swift:6` | 7 | 1 | 0 | – | `UUID?` |
| `DraftReputation` | `Domain/Models/Draft/DraftReputation.swift:11` | 7 | 0 | 0 | – | **`UUID` (non-opt)** |

**Totals: 599 stored properties, 198 of them with an inline default, 27 JSON blob columns.**
That 198 is the size of the evidence base for §2: a third of the schema arrived after its model
first shipped, and every one of those arrivals was made migration-safe the same way.

`DraftReputation` is the one model with a **non-optional** `careerID` (`DraftReputation.swift:15`),
because it shipped correct from day one — documented at `CareerScope.swift:49-52`. It is therefore
absent from the `CareerScoped` conformance list but present in `cascadeDelete` (`:286`).

### 1.2 Current schema state

* **No versioning.** Grep for `VersionedSchema|SchemaMigrationPlan|MigrationStage|migrationPlan|Schema.Version`
  across the whole tree: **no hits**. Every launch since the project began has relied on SwiftData's
  automatic inference.
* **Two hand-maintained copies of the model list.** The real one at `DataContainer.swift:7-35`, and
  a duplicate inside the DEBUG harness at `Engine/Simulation/MultiSeasonSmokeTest.swift:33-42`. They
  are kept in sync by hand and nothing enforces it. (Today they agree — all 29, verified.) A
  `VersionedSchema` gives both a single `models` array to point at; that alone is worth the change.
* **Default on-disk store.** `ModelConfiguration(isStoredInMemoryOnly: false)` on
  `DataContainer.swift:37` passes no `url:` and no `name:`, so the store lands at SwiftData's
  default path in the app's Application Support directory (`default.store` plus its `-wal`/`-shm`
  siblings — *exact filename to be confirmed on device during stage 1, §6*). Nothing in the tree
  ever names, copies, backs up or deletes that file. There is no second store and no fallback.
* **No CloudKit, no `@Attribute`.** Zero `@Attribute` / `@Transient` in the tree, so no `.unique`,
  no `.externalStorage`, no `originalName` anywhere yet. The 27 blobs are inline BLOB columns.
* **Ten `#Index` declarations, all on `careerID`** (`Player.swift:14`, `PlayerSeasonHistory.swift:41`,
  `Contract.swift:30`, `TeamSeasonArchive.swift:96`, `CollegeProspect.swift:15`, `Coach.swift:14`,
  `DraftPick.swift:14`, `WorkloadEvent.swift:16`, `Game.swift:14`, `Team.swift:14`).
* **Three `@Relationship`s in the entire schema:** `League.teams` `.cascade` (`League.swift:16`),
  `Team.owner` `.nullify` (`Team.swift:24`), `Team.players` `.nullify` (`Team.swift:47`). Everything
  else is joined by bare `UUID` columns. This is *why* `CareerScope.cascadeDelete`
  (`CareerScope.swift:257-316`) has to enumerate 28 tables by hand. For migration it is good news:
  there is almost no relationship graph for a migration to get wrong.
* **Nine Codable composite attributes** (value types stored inside a row):
  `Player.physical` / `.mental` / `.positionAttributes` / `.personality`
  (`Player.swift:22-26`), `Coach.personality` (`Coach.swift:84`), `Career.legacy` (`:27`),
  `Career.coachingTree` (`:32`), `Career.seasonGoals` (`:40`), `Career.hcGMRelationship` (`:155`).
  One of them, `PositionAttributes` (`Domain/Models/Player/PlayerAttributes.swift:158-166`), is an
  **enum with associated values** — nine cases each wrapping a different struct. That is the single
  most fragile persisted shape in the project.
* **Persisted enums, two dialects.** 49 stored properties are `…Raw: String` with a typed computed
  bridge (`Player.rosterStatusRaw:244`, `Career.gameModeRaw:272`, `DraftReputation.mediaNarrativeRaw:20`,
  `TeamSeasonArchive.conferenceRaw:109`, …), and ~19 are the enum type directly
  (`Player.position: Position` `:18`, `Career.currentPhase: SeasonPhase` `:23`,
  `Team.conference/division/mediaMarket` `:20-22`, `Coach.role/offensiveScheme/defensiveScheme/personality`
  `:19-21,84`, `Player.injuryType` `:118`, …). The raw-string dialect is the newer one and it is the
  safe one, because its read side already defends against unknown values
  (`CareerGameMode(rawValue:) ?? .standard`, `Career.swift:505-508`). The directly-stored dialect has
  no such defence.

### 1.3 The `fatalError` risk, precisely

```swift
// Data/Persistence/DataContainer.swift:37-42
let config = ModelConfiguration(isStoredInMemoryOnly: false)
do {
    return try ModelContainer(for: schema, configurations: [config])
} catch {
    fatalError("Failed to create ModelContainer: \(error)")
}
```

Called from `DynastyApp.swift:8`:

```swift
let container = PerfLog.time("data_container_create") { DataContainer.create() }
```

Consequences, in order:

* This is a **stored property with an initializer**, so it runs when `DynastyApp` is initialised —
  *before* the body of `init()` on `DynastyApp.swift:12-21`. `CrashReportStore.shared.start()` is on
  line 20. A migration failure therefore crashes **before MetricKit is subscribed**, so the one
  crash class that most needs a report is the one least likely to produce a useful one. (#172's
  store is otherwise the right receiver for this — see §3.5.)
* There is no window yet, so there is no possibility of showing the user anything.
* The `NSError` SwiftData throws is stringified into the `fatalError` message. That is the only
  copy of the diagnosis, and it goes to a crash log the tester has to be walked through exporting.
* **The recovery advice you will be forced to give is "delete the app".** That is the outcome this
  whole task is meant to prevent.

Note also `UI/Career/FiredSummaryView.swift:231` calls `DataContainer.create()` a second time inside
a preview — harmless today, but it means the function is not a strict singleton and a future
"open the store once, carefully" refactor has to account for it.

---

## 2 · The house convention, and where it runs out

### 2.1 The rule as practised

> **Any property added to a `@Model` after that model first shipped is declared with an inline
> default and is never added to `init`.**

It is not folklore; it is written down 107 times in `Domain/Models/` (grep for
`lightweight migration|never an init parameter`), and restated in engine code at
`Engine/Camp/WorkloadEngine.swift:56-59`. Canonical statement, `Career.swift:82-83`:

```
/// Inline default → SwiftData lightweight migration; never an init parameter.
var lastRolloverSeason: Int = 0
```

### 2.2 Why it works

SwiftData's automatic lightweight migration can add a column **only if it can produce a value for
every row already on disk**. An `Optional` supplies `nil`; a non-optional with an inline default
supplies the literal. Both are inferable, so the store opens without a plan.

Keeping the property out of `init` buys two further things:

1. **The diff stays inside one file.** No call site changes, so a schema addition cannot
   accidentally become a 40-file refactor that hides the schema change in the noise.
2. **Old rows and new rows agree.** The value an existing row is migrated to and the value a
   freshly-inserted row is born with are the *same literal*. There is no "migrated saves behave
   differently" class of bug, which is the class that survives QA.

### 2.3 The other half: derive and self-heal instead of migrating

The convention is paired with a second habit — where a new field needs *meaning* for old rows, the
project does not write a data migration; it makes `0`/`nil` mean "unknown" and re-derives:

* `Career.lastRolloverSeason = 0` means "the rollover has never run" (`Career.swift:60-83`), so a
  save that predates the field is correct by construction.
* `Career.draftPrepStepSeason = 0` plus `derivedPrepStepFloor` (`Career.swift:425-483`) rebuilds the
  draft-prep stage from counters that were written by the actions themselves. The doc comment calls
  it *"Self-healing migration"* in as many words (`:427`).
* `careerID: UUID? = nil` plus a one-shot idempotent adoption pass
  (`CareerScope.adoptLegacyRowsIfNeeded`, `CareerScope.swift:89-227`), gated by a version stamp on
  the row (`Career.schemaBackfillVersion`, `Career.swift:332-338`; `CareerScope.swift:62`,
  set on `:218`). Invoked from `UI/Career/CareerShellView.swift:2147`.
* `prospectBandRepairVersion` (`CareerShellView.swift:2285-2290`, checked `:2356-2357`) — a
  bump-to-rerun data repair for a bug an earlier build wrote *into* saves.

**This is the project's real migration engine and it should stay.** Note where it runs, though:
`loadShellData` (`CareerShellView.swift:2136`) — i.e. **when a career is opened**, after the UI
exists, per save, not at container creation. That property matters in §3.5.

### 2.4 Where the convention stops being enough

The convention covers exactly one operation: *add a column*. It says nothing about the other eight
things a schema change can be, and every one of them is currently unguarded:

| Operation | Inferable? | What actually happens today |
|---|---|---|
| Add optional / defaulted property | ✅ yes | The convention. Safe. |
| Add a whole `@Model` type | ✅ yes | New table. Safe. |
| Add / remove an `#Index` | ✅ yes | Index rebuild. Safe. |
| Add an enum case (raw-string column) | ✅ n/a | Not a schema change at all — the column is a `String`. Safe. |
| **Rename** a property | ❌ no | Inference sees *drop + add*. The old column's data is discarded. There is no `@Attribute(originalName:)` in the tree to say otherwise. |
| **Remove** a property | ⚠️ partially | Column dropped. Silent, irreversible data loss. |
| **Change a property's type** | ❌ no | Not inferable. Best case the open throws → §1.3 `fatalError`. |
| **Change a Codable blob's shape** | ❌ **not even attempted** | SwiftData does not look inside the blob. §2.5. |
| **Rename / delete an enum raw value** | ❌ no | The stored string no longer maps. Raw-string columns degrade to the `?? .default` fallback; directly-stored enums fail the row's decode. |

### 2.5 The blob problem, in detail

Two families, both opaque to SwiftData:

**(a) The 27 explicit `Data?` JSON columns** — `Career` × 24 (`:46,52,143,162,170,181,187,193,199,210,214,221,226,233,237,241,252,257,263,267,298,321,326,330`),
`Player.seasonStatLineData:444` and `.injuryHistoryData:513`, `PlayerSeasonHistory.postStatLineData:139`.
Every one is read through a bridge of exactly this shape (`Career.swift:616-627`):

```swift
var inbox: [InboxMessage] {
    get {
        guard let data = inboxData,
              let messages = try? JSONDecoder().decode([InboxMessage].self, from: data) else {
            return []          // ← a decode failure is indistinguishable from "empty"
        }
        return messages
    }
    set { inboxData = try? JSONEncoder().encode(Array(newValue.suffix(200))) }
}
```

`InboxMessage` (`Domain/Models/League/InboxMessage.swift:8-19`) has synthesized `Codable` and eight
non-optional stored properties. **Add one non-optional field to it and every message in every beta
save stops decoding.** No throw reaches a call site. The getter returns `[]`. The next append writes
`[]` back. The mailbox is gone, permanently, silently. The identical failure is available in
`newsLog` (`:677-688`), `seasonSummaries` (`:841-852`), `hallOfFame` (`:856-867`),
`pressPromiseLedger` (`:728-741`), `tradeThreads` (`:586-597`), `coachCarouselLog` (`:762-773`),
`developmentReports` (`:636-647`), `lockerRoomLog` (`:930-941`) and the rest.

Two clean escapes exist and both are cheap:

* Declare every new blob field **`Optional` (or `var x: T = default`)**. Synthesized decoders use
  `decodeIfPresent` for optionals, so a missing key is `nil` rather than a throw.
* Or hand-write `init(from:)` with `decodeIfPresent(…) ?? default` for the new key.

Removing a key from a blob type is the benign direction for the *decoder* (unknown keys are ignored)
but it is still a one-way data destruction the moment any row is re-encoded.

**(b) The nine Codable composite attributes**, above all
`PositionAttributes` (`PlayerAttributes.swift:158-166`) — an enum with nine associated-value cases,
carried by every one of the ~3,000+ `Player` rows in a save and every one of the ~350 rows in each
draft class (`Engine/Scouting/DraftClassBuilder.swift:69`). Its synthesized `Codable` keys off the
case name. **Renaming a case, deleting a case, or renaming a field inside any of the nine wrapped
structs invalidates the attribute for every affected row**, and unlike the `Data?` blobs there is no
`try?` in front of it — the failure surfaces during SwiftData's own decode, where the project has no
handler. Treat this type as frozen (§4.3).

---

## 3 · Proposed: `VersionedSchema` V1 baseline + `SchemaMigrationPlan`

### 3.1 New file — `Data/Persistence/DynastySchema.swift`

```swift
import Foundation
import SwiftData

// MARK: - V1 — the shape shipped in <build tag>, frozen
//
// V1 IS TODAY'S SHAPE. It is a snapshot, not a design: whatever the 29 models
// looked like the day this file landed is what V1 means, forever. Nothing in
// this enum may ever be edited again — a schema change adds V2 and a stage
// beside it. Editing V1 in place silently redefines what every existing store
// is assumed to have been, which is the one mistake this file exists to make
// impossible.
enum DynastySchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// THE model list. `DataContainer` and `MultiSeasonSmokeTest` both read it
    /// from here — today they maintain two hand-synced copies
    /// (`DataContainer.swift:7-35`, `MultiSeasonSmokeTest.swift:33-42`).
    static var models: [any PersistentModel.Type] {
        [
            Career.self, League.self, Team.self, Player.self, Owner.self,
            Coach.self, Game.self, Contract.self, Scout.self,
            CollegeProspect.self, DraftPick.self, DraftEvent.self,
            DraftPickGrade.self, DraftReputation.self, CareerArcState.self,
            PlayerSeasonHistory.self, FABid.self, FAVisit.self,
            FAStorylineEvent.self, Holdout.self, TrainingPlan.self,
            WorkloadEvent.self, PositionBattle.self, RosterCut.self,
            OpponentPrepWeek.self, VoluntaryWorkout.self, HardKnocksEvent.self,
            TradeRecord.self, TeamSeasonArchive.self,
        ]
    }
}

// MARK: - Migration plan

/// The ordered history of the save format.
///
/// `schemas` is every version that has ever shipped, oldest first. `stages` is
/// one entry per adjacent pair. A release that changes the schema adds BOTH —
/// a new `DynastySchemaV<n>` and the `V<n-1> -> V<n>` stage — in the same commit.
enum DynastyMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [DynastySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []      // nothing to migrate yet: V1 is the baseline
    }
}
```

### 3.2 `DataContainer.create()`, rewritten

```swift
enum DataContainer {

    /// The schema the binary was compiled against — always the newest version.
    static var currentSchema: Schema { Schema(versionedSchema: DynastySchemaV1.self) }

    static func create() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        // Stage 2 (§6): copy the store aside before a version bump can touch it.
        StoreBackup.backupIfSchemaVersionChanged()

        do {
            return try ModelContainer(
                for: currentSchema,
                migrationPlan: DynastyMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // NOT fatalError. The app must reach a frame so it can say what
            // happened and offer the backup. See §3.5.
            StoreOpenFailure.record(error)
            return degradedInMemoryContainer()
        }
    }

    /// Last resort: an EMPTY in-memory store built from the schema this binary
    /// was compiled against. It cannot fail for migration reasons — there is no
    /// store on disk to disagree with it — so `try!` here is honest.
    private static func degradedInMemoryContainer() -> ModelContainer {
        try! ModelContainer(
            for: currentSchema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
```

`MultiSeasonSmokeTest.swift:33-42` then becomes
`Schema(versionedSchema: DynastySchemaV1.self)` and the duplicate list disappears.

### 3.3 What a future V2 looks like

Illustrative — the `pressPromises` retirement from §4.4:

```swift
enum DynastySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { DynastySchemaV1.models }   // same types, changed shapes
}

enum DynastyMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [DynastySchemaV1.self, DynastySchemaV2.self]
    }

    static var stages: [MigrationStage] { [v1toV2] }

    /// Custom, not lightweight: the change is INSIDE `Career.legacy`, a Codable
    /// composite attribute, so SwiftData's inference has nothing to infer and
    /// `willMigrate` is the only place the old payload is still readable.
    static let v1toV2 = MigrationStage.custom(
        fromVersion: DynastySchemaV1.self,
        toVersion: DynastySchemaV2.self,
        willMigrate: { context in
            // Old shapes are visible here. Fold anything worth keeping into a
            // column that survives into V2, then save.
            //   let careers = try context.fetch(FetchDescriptor<Career>())
            //   for c in careers { … c.pressPromiseLedgerData = … }
            try context.save()
        },
        didMigrate: nil
    )
}
```

**Two API constraints to design around** (both are why the recipes in §3.4 are two-release recipes):

* `willMigrate` sees the *old* schema, `didMigrate` the *new* one. You cannot hold both shapes at
  once, so "read old column, write new column" has to happen in a version where **both columns
  exist** — that is what makes rename a two-release operation.
* A `.custom` stage **materialises rows**. It runs synchronously inside `ModelContainer(...)`, which
  runs inside a stored-property initializer on `DynastyApp.swift:8` — i.e. on the main thread before
  the first frame. A save carries 32 × 53-man rosters (`Data/Import/LeagueGenerator.swift:7-17,177`)
  plus practice squads, retirees and the free-agent pool, a ~350-man draft class per cycle
  (`DraftClassBuilder.swift:69`), one `Game` row per matchup per season and one
  `PlayerSeasonHistory` row per player per season — all of which grow with dynasty length. **Keep
  custom stages O(rows actually touched), and push anything heavier into the per-career self-heal
  hook** (`CareerShellView.loadShellData:2136`), which already runs after the UI exists and is
  already the home of `adoptLegacyRowsIfNeeded` and the band repair. That split — *stage does the
  minimum to make the store openable, self-heal does the rest* — is the recommended architecture.

### 3.4 Decision tree: lightweight, custom, or two-release

Work top to bottom; the first row that matches is the answer.

| The change you want | Verdict | Recipe |
|---|---|---|
| Add a property with an inline default or `Optional` | **No stage.** | The §2 convention, unchanged. Still bump `versionIdentifier` (minor) so the store carries a truthful version stamp. |
| Add a new `@Model` type | **No stage.** | Add to `DynastySchemaV<n>.models`. |
| Add / remove an `#Index` | **`.lightweight`** | Declare the stage; nothing to write. |
| Add a case to a `…Raw: String` enum | **Not a schema change.** | The column is a `String`. Verify the read bridge has a `?? .default`. |
| Add a field to a `Data?` blob's Codable type | **No stage, but a hard rule.** | The new field **must** be `Optional` or carry a default in a hand-written `init(from:)`. §4.2. |
| Rename a property | **Two releases.** | R1: add the new property with a default + backfill from the old one in the self-heal hook; both columns live. R2: drop the old one. Never a bare rename. |
| Change a property's type | **Two releases.** | Same shape: add `newFieldV2: NewType?`, backfill, retire the old column a release later. |
| Remove a property that still holds data | **`.custom` + a written decision.** | `willMigrate` either exports/folds the data or the plan states, in this document, that it is worthless. §4.4. |
| Change a Codable composite attribute's shape (`Player.physical`, `PositionAttributes`, `Career.legacy`, …) | **`.custom`, and think again first.** | SwiftData cannot reach inside. Prefer adding a *new sibling column* over editing the composite. |
| Rename / delete an enum raw value, or a case of `PositionAttributes` | **Forbidden.** | Add a new case; leave the old one in place as deprecated. §4.3. |
| Add a case to a directly-stored enum (`Position`, `SeasonPhase`, `Conference`, …) | **Safe to add.** | But convert the *property* to the `…Raw: String` dialect when you next touch it. §4.5. |

### 3.5 Replacing the `fatalError` (this is the actual beta blocker)

`fatalError` is not a policy, it is the absence of one. Minimum viable replacement, in the order the
work should land:

1. **Boot anyway.** Degraded in-memory container (§3.2). The app reaches a frame.
2. **Say what happened.** `ContentView` checks `StoreOpenFailure` and shows a plain screen instead of
   the main menu: *"Your saved careers could not be opened."* + the underlying error text + a
   **Copy diagnostics** button. English only, per house rule.
3. **Do not delete anything.** No "reset store" button on the first version of that screen. A tester
   who taps Reset at 1am has destroyed the evidence and the save. If a reset is ever offered it goes
   behind a typed confirmation and only after a backup exists.
4. **Report it.** Route `StoreOpenFailure` into `CrashReportStore` (#172) — and note it must be
   recorded through a path that does not depend on `CrashReportStore.shared.start()` having run,
   because it hasn't yet (`DynastyApp.swift:8` vs `:20`). A `UserDefaults` breadcrumb written in the
   `catch` and drained on the next successful launch is enough.
5. **Back up first.** `StoreBackup.backupIfSchemaVersionChanged()`: on any launch where the
   binary's `versionIdentifier` is newer than the one last recorded in `UserDefaults`, copy
   `default.store` + `-wal` + `-shm` to `default.store.backup-v<n>` before opening. Keep one
   generation. This converts every migration failure from *save destroyed* into *save recoverable*,
   and it is perhaps fifty lines. **Open question for stage 1:** the store URL is needed *before* a
   successful open — `ModelConfiguration().url` should give the default path without opening
   anything, but that must be verified on device rather than assumed.

---

## 4 · Beta-save survival policy

The list a reviewer can check a diff against. "Beta save" means: a store written by any build that
has been handed to a tester.

### 4.1 Free — change these without ceremony

* **Add** a stored property to any `@Model`, with an inline default or `Optional`, not in `init`.
  (The §2 convention. 198 existing properties prove it works.)
* **Add** a new `@Model` type.
* **Add / remove** an `#Index`.
* **Add** a case to any enum whose *persisted* form is a raw `String`.
* **Change** anything computed: computed properties, the typed bridges over `…Raw` columns, all
  engine logic, all UI. None of it is in the store.
* **Change** the *content* of strings that happen to be persisted (team names, copy). Relevant to
  the parked #167 anonymisation wave: renaming clubs is a **data** change, not a schema change, and
  needs no stage. (`TeamSeasonArchive.teamAbbr:106` / `.teamName:108` are deliberate string snapshots.)

### 4.2 Needs a stage — or at minimum a written decision in this file

* **Any change to a `Data?` blob's Codable type.** Adding a field is only safe when the field is
  `Optional` or defaulted in a custom `init(from:)`. Adding a *non-optional* field silently empties
  the entire blob for every existing save (§2.5). Affected types include `InboxMessage`, `NewsItem`,
  `SeasonSummary`, `HallOfFameEntry`, `TradeProposal`, `TradeNegotiationThread`,
  `DevelopmentReport`, `ReturnDecision`, `LeagueNarrativeState`, `LockerRoomEvent`,
  `CoachCarouselEngine.CarouselMove`, `OwnerPersonaEngine.OwnerWhim`/`OwnerSeasonReview`,
  `SeasonGoal`, `PressConferenceEngine.PressPromiseRecord`, `FaceAssignmentRegistry`,
  `TrainingFocusEngine.SeasonBreakoutCounts`, `GamePlan`, `DepthChart`, `MockDraftPick`,
  `InjuryRecord`, and the two stat-line payloads.
* **Any rename or type change** of a stored property. Two-release recipe (§3.4).
* **Any change to a Codable composite attribute** (`Player.physical`, `.mental`,
  `.positionAttributes`, `.personality`; `Coach.personality`; `Career.legacy`, `.coachingTree`,
  `.seasonGoals`, `.hcGMRelationship`).
* **Any change to relationship semantics** on the three `@Relationship`s.
* **Removing a model type.** Also requires removing it from `CareerScope.cascadeDelete` and both
  DEBUG audits (`CareerScope.swift:257-316`, `:342-376`, `:384-447`) — that is a correctness change
  in its own right, not bookkeeping.

### 4.3 Forbidden on a live beta store

* **Renaming or deleting a raw value of any persisted enum.** Add a case, deprecate the old one.
  This applies with special force to the raw values of `Position` (`Domain/Enums/Position.swift:46+`)
  and `SeasonPhase` (`Domain/Enums/SeasonPhase.swift:3+`) — both are stored directly, on every
  player row and on `Career`/`League` respectively.
* **Renaming or deleting a case of `PositionAttributes`** (`PlayerAttributes.swift:158-166`), or
  renaming a field inside any of the nine wrapped attribute structs
  (`QBAttributes`/`WRAttributes`/…/`KickingAttributes`, `PlayerAttributes.swift:57-153`). This shape
  is carried by every player and every prospect and has no `try?` in front of it. **Frozen.**
* **A bare property rename** in any `@Model`, ever. There is no `@Attribute(originalName:)` in this
  codebase; inference will read it as drop + add.
* **Editing `DynastySchemaV1` after it ships.** It stops being a description of what is on disk.
* **Shipping a schema change and the V1 baseline in the same build** (§6 stage 1).

### 4.4 The recorded case: `Career.legacy.pressPromises`

Already logged into #171 by the #131 dead-code sweep (`TODO.md:4067`), which correctly refused to
delete it. Restated with the evidence:

* `LegacyTracker.pressPromises: [PressPromise]` — `Domain/Models/League/LegacyTracker.swift:6`.
* `PressPromise.isDelivered: Bool?` — `:30`.
* **One writer, zero readers.** Appended at `LegacyTracker.swift:81-85`; no other file in the tree
  mentions `pressPromises` or `isDelivered`. `isDelivered` is never even written — it is `nil` on
  every record ever created. The comment at `:76-79` says so outright: the authoritative ledger is
  now `Career.pressPromiseLedger` (`Career.swift:253-257`, `:728-741`).
* It is *not* dead code in the disposable sense: `LegacyTracker` is `Career.legacy`
  (`Career.swift:27`), a persisted composite attribute. Deleting the field changes the persisted
  shape of every `Career` row in every beta save.

**Ruling.** Deleting a key is the benign direction for a decoder (unknown keys are ignored) — but
that tolerance belongs to *SwiftData's* composite-attribute encoder, not to a `JSONDecoder` we
control, and it is undocumented. It is exactly what the §5.2 fixture test is built to answer.
So:

1. Do **not** delete it in the V1 baseline build.
2. Delete it in the first V2 that has another reason to exist, as an explicit `.custom` stage.
3. In `willMigrate`, first fold any surviving promises into `pressPromiseLedger` — or, if that is
   judged not worth the code (the two shapes differ: `PressPromise{id, statement, season, isDelivered}`
   at `LegacyTracker.swift:26-42` vs `PressConferenceEngine.PressPromiseRecord` at
   `PressEngine.swift:853+`, which carries a typed `Kind` and a settlement that cannot be
   reconstructed from a free-text statement) — **record that decision here, in this file, with the
   date.** A discarded field with a written reason is a decision; a discarded field without one is a
   bug somebody will find in a year.

### 4.5 Standing recommendation

**New persisted enum-typed properties use the `…Raw: String` + typed-bridge dialect.** The project
has already made this move on its own — 49 raw-string columns versus ~19 direct ones, with the
raw-string ones concentrated in the newer models and the direct ones in `Player`/`Team`/`Coach`/`Career`
from the earliest days. The bridge is four lines (`Career.swift:505-508`) and it buys forward
compatibility for free: an unknown raw value degrades to a default instead of failing the row.
Converting the existing ~19 is **not** proposed — each conversion is a two-release rename (§3.4) and
they are not worth it — but no new one should be added.

---

## 5 · Test plan

There is **no test target in the project** (`dynasty.xcodeproj` has a single `PBXNativeTarget`; no
`*Tests` directory, no `.xctestplan`). Verification here has always been in-app DEBUG harnesses run
under `simctl launch --console-pty` with an env var — `PERF_SMOKE_SEASONS`, `LEAGUE_TEMPLATE_VALIDATE`,
`FACE_BUNDLE_AUDIT`, `CAREERID_AUDIT` (`ContentView.swift:13-42`, `CareerShellView.swift:2157-2159`).
The migration harness follows that pattern rather than inventing a second one.

### 5.1 Fixture: capture an old store

Manual, once per shipped schema version, and the artefact is committed:

1. Boot the sim, install the build whose schema you want to freeze.
2. Play a career far enough to populate the awkward tables — at minimum: past one draft (fills
   `CollegeProspect`, `DraftPick`, `DraftEvent`, `DraftPickGrade`, `DraftReputation`), past one
   free-agency phase (`FABid`, `FAVisit`, `Holdout`), past one training camp (`TrainingPlan`,
   `WorkloadEvent`, `PositionBattle`, `RosterCut`, `HardKnocksEvent`, `VoluntaryWorkout`), through
   one Super Bowl (`PlayerSeasonHistory`, `TeamSeasonArchive`, `seasonSummaries`), and with the
   press room, inbox and trade centre all exercised so the `Career` blobs are non-empty.
   **Create a second career** as well — multi-save is the shape `CareerScope` is about.
3. `xcrun simctl get_app_container booted com.brewcrow.dynasty data`, then copy
   `Library/Application Support/default.store*` out.
4. Commit as `docs/fixtures/store-v1/` (a few MB; if it is larger than is comfortable in git, keep
   it out of the repo and record the capture recipe here instead — the recipe is the important part).

### 5.2 Harness: `StoreMigrationCheck` (DEBUG, new file, env-gated)

Add one env var to the `ContentView.swift:13-42` block, e.g. `STORE_MIGRATION_CHECK=1`. On launch
the harness:

1. Copies the fixture out of the bundle into a temp directory (never touches the live store).
2. Opens it with `ModelContainer(for: currentSchema, migrationPlan: DynastyMigrationPlan.self,
   configurations: [ModelConfiguration(url: fixtureCopyURL)])` — **the open itself is assertion #1.**
   Today this is the step that would `fatalError`; the harness must report it instead.
3. Prints a row-count census per model — reuse `CareerScope.debugAuditCounts`
   (`CareerScope.swift:384-447`), which already prints per-career counts, an `ORPHANED` column and a
   `NIL` tripwire, and compares against a committed expected-counts file. **Any table that reads 0
   where the fixture had rows is a failure**, and this is the check that catches a silently dropped
   column or table.
4. **Blob census** — the check the row counts cannot make. For each of the 27 blob bridges and the
   nine composite attributes, decode and count:
   `inbox`, `newsLog`, `seasonSummaries`, `hallOfFame`, `pressToneHistory`, `pressPromiseLedger`,
   `tradeThreads`, `pendingTradeOffers`, `developmentReports`, `coachCarouselLog`, `ownerSeasonGoals`,
   `ownerWhims`, `lockerRoomLog`, `announcedMilestoneKeys`, `gamePlan`, `depthChartData`,
   `faceRegistryData`, `leagueNarrative`, plus `Player.physical/.mental/.positionAttributes/.personality`
   and `Career.legacy/.coachingTree/.hcGMRelationship` sampled over N players.
   **A blob that decodes to empty where the fixture had content is the exact silent-loss failure of
   §2.5, and this census is the only thing that can see it.** It is the single most valuable check
   in this document.
5. **Smoke** — run `MultiSeasonSmokeTest` (`Engine/Simulation/MultiSeasonSmokeTest.swift:29`)
   **against the migrated fixture** rather than a freshly generated league, one or two seasons. It
   already asserts roster floors, retirement counts, OVR drift and watchdog timings, so it answers
   "does a migrated save still *play*", which the census does not.
6. Run `CareerScope.debugUnscopedRows` (`:342`) — a migration that loses `careerID` produces a save
   that opens fine and renders as an empty league.
7. Print one `MIGRATION:` verdict line, PASS/FAIL, in the smoke test's house style.

### 5.3 Manual gate before any beta build

Not automatable and not optional:

* Install the **previous** beta build, create a career, advance a few weeks, quit.
* Install the **new** build over it (upgrade install, not a fresh one).
* Open the save. Walk: dashboard → roster → depth chart → inbox → news → scouting/big board →
  trade centre → owner/press. Anything that reads empty and should not is a blob loss.
* Then create a *new* career on the same install and confirm both saves coexist
  (`CAREERID_AUDIT=1` prints the census).

### 5.4 Fixture rotation

One fixture per shipped schema version, kept for as long as any tester could still be on that
version. The harness runs the **whole chain** — V1 fixture → current, V2 fixture → current — because
a tester who skips two updates exercises a path nobody else does.

---

## 6 · Rollout

Five stages. Stages 1-3 are the beta gate; 4-5 are hygiene that can follow.

**Stage 1 — Freeze V1. Nothing else in the build.**
`DynastySchema.swift` with `DynastySchemaV1` (exactly today's 29 models, no shape changes),
`DynastyMigrationPlan` with an empty `stages`, `DataContainer` and `MultiSeasonSmokeTest` both
pointed at it. **No other schema change may ride along** — if the models change in the same build,
V1 is not a description of any store that exists and the inference is doing the work unsupervised
anyway. Verify on device that an existing pre-V1 store still opens (this is the assumption the whole
plan rests on: an unversioned store matched against a byte-identical V1 should be a no-op open, but
it is an assumption until §5.2 says otherwise), and confirm the default store URL for stage 2.

**Stage 2 — Make failure survivable.**
`StoreOpenFailure` + degraded in-memory container + the recovery screen + the `UserDefaults`
breadcrumb into `CrashReportStore`, and `StoreBackup.backupIfSchemaVersionChanged()`. Delete the
`fatalError` on `DataContainer.swift:41`. **This stage is what actually unblocks the beta** — after
it, a migration bug costs a tester an afternoon instead of a dynasty.

**Stage 3 — Build the harness.**
Capture the V1 fixture (§5.1), write `StoreMigrationCheck` (§5.2), wire the env var, commit the
expected-counts file. Run it green against V1→V1 (a no-op migration, which is the right first test
because it must be *perfectly* lossless).

**Stage 4 — Write the policy into review.**
Add §4 as a checklist item in `docs/RELEASE_CHECKLIST.md`, and a short note at the head of
`DynastySchema.swift` pointing here. The policy is only worth anything if a diff gets checked
against it.

**Stage 5 — First real V2, when there is a reason.**
The `pressPromises` retirement (§4.4) is the obvious candidate and a good rehearsal: small, custom
(because it is inside a composite attribute), and with a real "fold or discard" decision to record.
Do it as the *second* schema-changing release, not the first — the first one should be something
lightweight, so the machinery is proven on an easy case before it is trusted with a hard one.

---

## Open questions

Flagged rather than guessed, because this document is only useful if it is honest about what has
been verified against the code and what has not. None of these can be settled without building and
running, which was out of scope for this task.

1. Does an existing **unversioned** store open cleanly against a byte-identical `VersionedSchema`
   V1? Assumed yes; §5.2 is the test. If the answer is no, stage 1 needs a `.custom` stage from
   nothing, and the plan changes shape.
2. Exact default store filename and URL, and whether `ModelConfiguration().url` yields it without
   opening the store (needed by `StoreBackup`).
3. How SwiftData actually serialises Codable **composite attributes** — keyed like `JSONEncoder`
   (extra keys ignored on decode) or positionally? §4.4's ruling and the whole "removing a blob key
   is the benign direction" assumption depend on it.
4. Whether a `.custom` stage's `willMigrate` context can fetch `Career` **blob columns** as raw
   `Data?` — it should, since they are plain `Data` columns, but the `pressPromises` fold in §3.3
   depends on it.
5. Fixture size. If `default.store` for a two-career, one-full-season save is too large to commit,
   the fixture becomes a documented capture recipe plus a checked-in expected-counts file.
