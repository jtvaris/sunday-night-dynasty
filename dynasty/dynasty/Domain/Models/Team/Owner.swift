import Foundation
import SwiftData

@Model
final class Owner {
    var id: UUID
    var name: String
    var avatarID: String

    /// How many bad seasons the owner will tolerate before firing the coach (scale 1–10).
    var patience: Int

    /// Willingness to spend money (scale 1–99).
    var spendingWillingness: Int

    /// How much the owner interferes with football decisions (scale 1–99).
    var meddling: Int

    /// Whether the owner prioritises winning immediately over rebuilding.
    var prefersWinNow: Bool

    /// Current owner satisfaction with the franchise (0–100).
    var satisfaction: Int

    /// Total coaching & scouting staff budget in thousands (e.g. 25000 = $25M).
    /// Derived from spendingWillingness when the owner is created.
    var coachingBudget: Int

    /// Previous season's coaching budget in thousands, for showing budget change in UI.
    var previousCoachingBudget: Int

    /// R27: Dedicated scouting department budget in thousands (e.g. 4000 = $4M).
    /// Separate pot from `coachingBudget` — scout salaries draw from this one.
    /// Default keeps old saves valid (lightweight migration).
    var scoutingBudget: Int = 4_000

    /// R27: Previous season's scouting budget, for showing change in UI.
    var previousScoutingBudget: Int = 0

    init(
        id: UUID = UUID(),
        name: String,
        avatarID: String = "owner_m1",
        patience: Int = 5,
        spendingWillingness: Int = 50,
        meddling: Int = 30,
        prefersWinNow: Bool = false,
        satisfaction: Int = 70,
        coachingBudget: Int = 20_000,
        previousCoachingBudget: Int = 0,
        scoutingBudget: Int = 4_000,
        previousScoutingBudget: Int = 0
    ) {
        self.id = id
        self.name = name
        self.avatarID = avatarID
        self.patience = patience
        self.spendingWillingness = spendingWillingness
        self.meddling = meddling
        self.prefersWinNow = prefersWinNow
        self.satisfaction = satisfaction
        self.coachingBudget = coachingBudget
        self.previousCoachingBudget = previousCoachingBudget
        self.scoutingBudget = scoutingBudget
        self.previousScoutingBudget = previousScoutingBudget
    }
}
