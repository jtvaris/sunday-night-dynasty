import Foundation
import SwiftData

@Model
final class Scout {
    var id: UUID
    var firstName: String
    var lastName: String
    var teamID: UUID?
    var positionSpecialization: Position?
    var accuracy: Int
    var personalityRead: Int
    var potentialRead: Int
    var experience: Int

    /// Annual salary in thousands (e.g. 200 = $200K).
    var salary: Int

    /// The scout's role in the scouting department hierarchy.
    var scoutRole: ScoutRole

    /// Number of Pro Days attended this year (max 5 per scout).
    var proDaysAttended: Int = 0

    /// Colleges this scout has been sent to for Pro Days.
    var proDayColleges: [String] = []

    /// How many seasons this scout has been in their current role/region.
    /// Scouts with 2+ seasons get a familiarity accuracy bonus.
    var seasonsInRole: Int = 0

    /// Specific position to focus scouting on. nil = general (all positions).
    var focusPosition: Position?

    /// Attribute category to focus scouting on. nil = general.
    var focusAttributeRaw: String?

    var focusAttribute: ScoutFocusAttribute? {
        get { focusAttributeRaw.flatMap { ScoutFocusAttribute(rawValue: $0) } }
        set { focusAttributeRaw = newValue?.rawValue }
    }

    /// R27: Which slice of the consensus draft board this scout is assigned to
    /// watch during the college season. nil = whole assigned region.
    /// Optional stored field → lightweight SwiftData migration.
    var assignmentPoolRaw: String?

    var assignmentPool: ScoutAssignmentPool? {
        get { assignmentPoolRaw.flatMap { ScoutAssignmentPool(rawValue: $0) } }
        set { assignmentPoolRaw = newValue?.rawValue }
    }

    // MARK: - Computed Properties

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Short display label for the scout's specialty/focus area.
    var specialtyLabel: String {
        if let pos = positionSpecialization {
            return "\(pos.rawValue) Specialist"
        }
        if let focus = focusAttribute {
            return "\(focus.label) Focus"
        }
        return scoutRole.isChief ? "Chief Scout" : "General"
    }

    /// Maximum pro days this scout can attend, based on role.
    var maxProDays: Int {
        scoutRole.maxProDays
    }

    /// Whether this scout can attend more pro days.
    var canAttendProDay: Bool {
        proDaysAttended < maxProDays
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        teamID: UUID? = nil,
        positionSpecialization: Position? = nil,
        accuracy: Int = 50,
        personalityRead: Int = 50,
        potentialRead: Int = 50,
        experience: Int = 1,
        salary: Int = 100,
        scoutRole: ScoutRole = .regionalScout1
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.teamID = teamID
        self.positionSpecialization = positionSpecialization
        self.accuracy = accuracy
        self.personalityRead = personalityRead
        self.potentialRead = potentialRead
        self.experience = experience
        self.salary = salary
        self.scoutRole = scoutRole
    }
}
