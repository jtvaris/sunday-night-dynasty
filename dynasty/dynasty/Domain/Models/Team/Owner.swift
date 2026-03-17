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

    init(
        id: UUID = UUID(),
        name: String,
        avatarID: String = "owner_m1",
        patience: Int = 5,
        spendingWillingness: Int = 50,
        meddling: Int = 30,
        prefersWinNow: Bool = false,
        satisfaction: Int = 70
    ) {
        self.id = id
        self.name = name
        self.avatarID = avatarID
        self.patience = patience
        self.spendingWillingness = spendingWillingness
        self.meddling = meddling
        self.prefersWinNow = prefersWinNow
        self.satisfaction = satisfaction
    }
}
