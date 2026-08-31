import Foundation
import SwiftData

// MARK: - Save-format policy
//
// The rules a schema change has to obey live in `docs/SWIFTDATA_MIGRATION_PLAN.md`
// §3.4 (the decision tree) and §4 (what is free, what needs a stage, what is
// forbidden on a live beta store). Read §4 before editing ANY `@Model`.
//
// The short version:
//   * Adding a property with an inline default (never an init parameter) or an
//     `Optional` is free — that is the house convention and it needs no stage.
//   * Adding a new `@Model` type is free; add it to the NEWEST schema version's
//     `models` list.
//   * A rename, a type change, or any change to a `Data?` blob's Codable shape
//     or to a Codable composite attribute (`Player.physical`, `PositionAttributes`,
//     `Career.legacy`, …) is NOT free. It needs a new `DynastySchemaV<n>` and a
//     `MigrationStage`, and in most cases a two-release recipe.
//   * Renaming or deleting a persisted enum raw value is forbidden.

// MARK: - V1 — the shape shipped in the #171 baseline build, frozen

/// V1 IS THE SHAPE THAT WAS ON DISK THE DAY THIS FILE LANDED. It is a snapshot,
/// not a design: whatever the 29 models looked like at that moment is what V1
/// means, forever.
///
/// **Nothing in this enum may ever be edited again.** A schema change adds a
/// `DynastySchemaV2` and a stage beside it. Editing V1 in place silently
/// redefines what every existing store is assumed to have been, which is the one
/// mistake this file exists to make impossible.
///
/// The baseline is deliberately a *pure* freeze: it shipped with no model shape
/// change riding along, so an unversioned pre-V1 store and V1 describe byte for
/// byte the same tables and SwiftData's open is a no-op (verified against a
/// two-career pre-change store — see the #171 report).
enum DynastySchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// THE model list. `DataContainer` reads it from here so there is exactly
    /// one place a new `@Model` type has to be registered.
    ///
    /// `Engine/Simulation/MultiSeasonSmokeTest.swift` still keeps a hand-synced
    /// duplicate of this list for its in-memory container; that file is outside
    /// this wave's ownership and pointing it here is a one-line follow-up.
    static var models: [any PersistentModel.Type] {
        [
            Career.self,
            League.self,
            Team.self,
            Player.self,
            Owner.self,
            Coach.self,
            Game.self,
            Contract.self,
            Scout.self,
            CollegeProspect.self,
            DraftPick.self,
            DraftEvent.self,
            DraftPickGrade.self,
            DraftReputation.self,
            CareerArcState.self,
            PlayerSeasonHistory.self,
            FABid.self,
            FAVisit.self,
            FAStorylineEvent.self,
            Holdout.self,
            TrainingPlan.self,
            WorkloadEvent.self,
            PositionBattle.self,
            RosterCut.self,
            OpponentPrepWeek.self,
            VoluntaryWorkout.self,
            HardKnocksEvent.self,
            TradeRecord.self,
            TeamSeasonArchive.self,
        ]
    }
}

// MARK: - V2 — coach season history

/// V1 plus one new table, `CoachSeasonHistory`.
///
/// Adding a `@Model` type is one of the free changes (`§4.1`, and the decision
/// tree's "Add a new `@Model` type → **No stage**"). It gets a version of its
/// own anyway, because V1 is a frozen snapshot of what was on disk and must not
/// be edited in place — a new table is still a different set of tables, and the
/// store's version stamp should say so. The stage below is `.lightweight`
/// precisely because there is nothing to write: no existing row changes shape,
/// and the new table starts empty.
///
/// There is deliberately no backfill of the new table, here or in the self-heal
/// hook. A `Coach` row carries only his CURRENT job, so a past season cannot be
/// reconstructed from it; the book opens at the next season rollover and
/// `CoachCareerHistoryCard` says so rather than inventing a career.
enum DynastySchemaV2: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }

    /// THE model list. Spelled as V1's list plus the addition, so the two can
    /// never drift: a type added to V1 by a future reader of this file cannot
    /// go missing from the version the app actually opens.
    static var models: [any PersistentModel.Type] {
        DynastySchemaV1.models + [
            CoachSeasonHistory.self,
        ]
    }
}

// MARK: - Migration plan

/// The ordered history of the save format.
///
/// `schemas` is every version that has ever shipped, oldest first. `stages` is
/// one entry per adjacent pair. A release that changes the schema adds BOTH — a
/// new `DynastySchemaV<n>` and the `V<n-1> -> V<n>` stage — in the same commit.
///
/// Two API constraints to design around (both are why most recipes in the plan's
/// §3.4 are two-release recipes):
///
///  * `willMigrate` sees the OLD schema, `didMigrate` the NEW one. You cannot
///    hold both shapes at once, so "read old column, write new column" has to
///    happen in a version where both columns exist.
///  * A `.custom` stage materialises rows and runs synchronously inside
///    `ModelContainer(...)`, i.e. on the main thread before the first frame.
///    Keep custom stages O(rows actually touched) and push anything heavier into
///    the per-career self-heal hook (`CareerShellView.loadShellData`), which
///    already runs after the UI exists.
enum DynastyMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [DynastySchemaV1.self, DynastySchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            // V1 -> V2 adds the `CoachSeasonHistory` table and changes no
            // existing row. Nothing to write, so the stage is declared purely
            // so the version history has an entry per adjacent pair.
            .lightweight(fromVersion: DynastySchemaV1.self, toVersion: DynastySchemaV2.self),
        ]
    }
}

// MARK: - Version stamp helpers

extension Schema.Version {
    /// `1.0.0` — for `UserDefaults` stamps and log lines.
    var dotted: String { "\(major).\(minor).\(patch)" }
}
