import Foundation

// MARK: - StaffTemplate
//
// A staff hiring plan that OUTLIVES the career that produced it.
//
// The gap this closes: a manager who has spent a career working out which
// chairs he pays for, and which temperaments he wants around his head coach,
// had no way to carry any of that into the next save. Auto-Hire
// (`CoachingStaffView.runAutoHire`) fills an empty building in one tap, but it
// always fills it the SAME way — the authored `CoachRole.salaryRange` averages,
// and the best fit-adjusted rating each allocation can buy. It has no memory of
// what the user actually did.
//
// ## Why it stores seats and not men
//
// A `Coach` row belongs to one save. The 61-year-old defensive coordinator a
// user loved in his last career does not exist in the next one — he was rolled
// by `CoachingEngine.generateCoachCandidates` against that league's seed and
// that team's budget. So a template records what is portable:
//
//   * which seats the plan fills,
//   * what SHARE of each pot the seat was paid (salary ÷ that career's
//     envelope), so the plan re-scales onto a richer or poorer owner rather
//     than carrying dollar figures that mean nothing in a new league,
//   * the ``PersonalityArchetype`` the seat held, so the re-apply can shop for
//     the same temperament around the head coach.
//
// ## Why it is NOT in `CareerScopedDefaults.keys`
//
// That list is the career-state purge set: every key on it is suffixed with the
// save's uuid and deleted with the save. A template that died with the career
// that produced it would be the one thing this feature must not be. The key
// here is deliberately global and deliberately unsuffixed. (A full "reset all
// data" in Settings still removes it, along with every other default — that is
// the user asking for exactly that.)

/// One saved staff plan, portable across careers.
struct StaffTemplate: Codable, Identifiable, Equatable {

    /// Which of the three owner envelopes a seat is paid from. Mirrors
    /// `CoachingStaffView.StaffPot`, resolved through ``StaffLedger/medicalRoles``
    /// so the split cannot drift from the ledger's.
    enum Pot: String, Codable, CaseIterable, Hashable {
        case coaching, medical, scouting

        var displayName: String {
            switch self {
            case .coaching: return "coaching"
            case .medical:  return "medical"
            case .scouting: return "scouting"
            }
        }
    }

    /// One chair in the plan.
    struct Seat: Codable, Equatable, Identifiable, Hashable {

        enum Kind: String, Codable, Hashable { case coach, scout }

        var kind: Kind
        /// `CoachRole.rawValue` or `ScoutRole.rawValue`. Stored as the raw
        /// string so a template written by an older build survives a role
        /// being added to either enum — an unknown seat simply stops resolving
        /// and is skipped rather than failing the whole decode.
        var roleRaw: String
        /// What the seat was paid in the career this was captured from, in
        /// thousands. Never shown as money for the NEW career: it is the
        /// numerator of ``StaffTemplate/share(of:)``.
        var salary: Int
        /// `PersonalityArchetype.rawValue` of the man who held the seat.
        /// `nil` for every scout seat — `Scout` carries no archetype — and for
        /// a coach seat whose row could not be read.
        var personalityRaw: String?

        var id: String { "\(kind.rawValue)-\(roleRaw)" }

        var coachRole: CoachRole? {
            kind == .coach ? CoachRole(rawValue: roleRaw) : nil
        }

        var scoutRole: ScoutRole? {
            kind == .scout ? ScoutRole(rawValue: roleRaw) : nil
        }

        var personality: PersonalityArchetype? {
            personalityRaw.flatMap(PersonalityArchetype.init(rawValue:))
        }

        /// `false` when neither enum recognises `roleRaw` — a seat from a build
        /// that had a title this one does not.
        var isResolvable: Bool { coachRole != nil || scoutRole != nil }

        var displayName: String {
            coachRole?.displayName ?? scoutRole?.displayName ?? roleRaw
        }

        var abbreviation: String {
            coachRole?.abbreviation ?? scoutRole?.abbreviation ?? roleRaw
        }

        var pot: Pot {
            if let role = coachRole {
                return StaffLedger.medicalRoles.contains(role) ? .medical : .coaching
            }
            return .scouting
        }
    }

    var id: UUID
    /// What the user called it. Renameable.
    var name: String
    /// "Marcus Hale · 2031" — whose staff it was and the season it was taken in.
    /// Descriptive only; nothing keys off it.
    var sourceLabel: String
    var savedAt: Date
    /// The three envelopes as they stood at capture, in thousands. These are the
    /// DENOMINATORS behind every share, which is why they are stored rather
    /// than the shares themselves: a percentage rounded at capture and rounded
    /// again at apply drifts, and the raw pair does not.
    var coachingBudget: Int
    var medicalBudget: Int
    var scoutingBudget: Int
    var seats: [Seat]

    init(
        id: UUID = UUID(),
        name: String,
        sourceLabel: String,
        savedAt: Date = Date(),
        coachingBudget: Int,
        medicalBudget: Int,
        scoutingBudget: Int,
        seats: [Seat]
    ) {
        self.id = id
        self.name = name
        self.sourceLabel = sourceLabel
        self.savedAt = savedAt
        self.coachingBudget = coachingBudget
        self.medicalBudget = medicalBudget
        self.scoutingBudget = scoutingBudget
        self.seats = seats
    }

    // MARK: - Readings of the template itself

    /// The envelope this template was captured against, in thousands.
    func envelope(_ pot: Pot) -> Int {
        switch pot {
        case .coaching: return coachingBudget
        case .medical:  return medicalBudget
        case .scouting: return scoutingBudget
        }
    }

    /// Seats in a pot.
    func seats(in pot: Pot) -> [Seat] { seats.filter { $0.pot == pot } }

    /// What the plan's seats cost in the career it came from, in thousands.
    func committed(_ pot: Pot) -> Int {
        seats(in: pot).reduce(0) { $0 + $1.salary }
    }

    /// The fraction of its pot a seat was paid, or `nil` when no envelope was
    /// recorded for that pot (an owner who had not resolved a budget). A `nil`
    /// share is the reason ``StaffTemplatePlan`` falls back to the recorded
    /// salary rather than inventing a percentage of zero.
    func share(of seat: Seat) -> Double? {
        let env = envelope(seat.pot)
        guard env > 0 else { return nil }
        return Double(seat.salary) / Double(env)
    }

    /// Share of a whole pot the plan spent, `nil` when that pot had no envelope.
    func potShare(_ pot: Pot) -> Double? {
        let env = envelope(pot)
        guard env > 0 else { return nil }
        return Double(committed(pot)) / Double(env)
    }
}

// MARK: - StaffTemplatePlan

/// What a template works out to for ONE career: which of its seats are open
/// here, and how much of this club's money each of them gets.
///
/// Every figure a template card prints comes from this type. It is built by
/// ``StaffTemplatePlan/build(template:vacantCoachRoles:vacantScoutRoles:envelopes:available:)``
/// and nothing else computes a per-seat allocation, so the number in the
/// summary line and the cap the hiring pass actually offers are the same number.
struct StaffTemplatePlan {

    /// One open seat and the money set aside for it, in thousands.
    struct Entry: Identifiable, Equatable {
        let seat: StaffTemplate.Seat
        let allocation: Int
        var id: String { seat.id }
    }

    /// Open seats, richest allocation first, except that the head coach is
    /// hoisted to the front: everyone else's fit is measured against him
    /// (`CoachingEngine.coachChemistry`), so he has to be in the chair before
    /// the rest are judged.
    let entries: [Entry]

    /// Template seats this career cannot use: already filled, not a seat this
    /// career owns (a GM+HC occupies the head-coach chair himself), or a title
    /// this build does not recognise.
    let skippedSeats: [StaffTemplate.Seat]

    /// What the plan sets aside per pot, in thousands. Sums `entries`.
    let planned: [StaffTemplate.Pot: Int]

    /// What each pot still holds in THIS career, in thousands, as handed in.
    let available: [StaffTemplate.Pot: Int]

    /// Pots whose seats had to be scaled down to fit the money left. Named on
    /// the card, because a scaled plan buys a cheaper man than the template did
    /// and the user should be told before he taps rather than after.
    let scaledPots: Set<StaffTemplate.Pot>

    var totalPlanned: Int { planned.values.reduce(0, +) }

    /// Nothing to do: every seat the template holds is already filled here.
    var isEmpty: Bool { entries.isEmpty }

    // MARK: - Build

    /// Works the template out against one club's books.
    ///
    /// - Parameters:
    ///   - vacantCoachRoles: `StaffLedger.vacantCoachRoles` for this career —
    ///     seats this career OWNS and has not filled.
    ///   - vacantScoutRoles: `StaffLedger.vacantScoutRoles`.
    ///   - envelopes: this club's three budgets, thousands (`StaffLedger`).
    ///   - available: what each pot still has unspent, thousands.
    ///
    /// The arithmetic, in full:
    ///
    /// 1. A seat's target is its captured SHARE re-spent on this club's
    ///    envelope — `round(share × envelopes[pot])`. A seat whose template pot
    ///    had no envelope (share `nil`) carries its recorded salary instead,
    ///    which is the only figure that exists for it.
    /// 2. If a pot's targets sum past what the pot still holds, every target in
    ///    that pot is multiplied by `available ÷ requested` and FLOORED. Floor,
    ///    not round: the sum of the scaled targets can then only come in under
    ///    the wallet, never a thousand over it.
    /// 3. Nothing is redistributed. Money a seat does not spend stays in the
    ///    pot rather than being handed to the next seat — this plan is a
    ///    budget, and a second pass that re-offered the remainder would be
    ///    spending more of the user's money than the card told him it would.
    static func build(
        template: StaffTemplate,
        vacantCoachRoles: Set<CoachRole>,
        vacantScoutRoles: Set<ScoutRole>,
        envelopes: [StaffTemplate.Pot: Int],
        available: [StaffTemplate.Pot: Int]
    ) -> StaffTemplatePlan {

        var open: [StaffTemplate.Seat] = []
        var skipped: [StaffTemplate.Seat] = []

        for seat in template.seats {
            guard seat.isResolvable else { skipped.append(seat); continue }
            if let role = seat.coachRole {
                vacantCoachRoles.contains(role) ? open.append(seat) : skipped.append(seat)
            } else if let role = seat.scoutRole {
                vacantScoutRoles.contains(role) ? open.append(seat) : skipped.append(seat)
            }
        }

        // Step 1 — the target each open seat asks for.
        var requested: [String: Int] = [:]
        for seat in open {
            if let share = template.share(of: seat) {
                let envelope = max(0, envelopes[seat.pot] ?? 0)
                requested[seat.id] = Int((share * Double(envelope)).rounded())
            } else {
                requested[seat.id] = max(0, seat.salary)
            }
        }

        // Step 2 — scale each pot down to what it can actually pay.
        var allocation: [String: Int] = [:]
        var scaled: Set<StaffTemplate.Pot> = []
        for pot in StaffTemplate.Pot.allCases {
            let potSeats = open.filter { $0.pot == pot }
            guard !potSeats.isEmpty else { continue }
            let wallet = max(0, available[pot] ?? 0)
            let asked = potSeats.reduce(0) { $0 + (requested[$1.id] ?? 0) }
            if asked <= wallet || asked == 0 {
                for seat in potSeats { allocation[seat.id] = requested[seat.id] ?? 0 }
            } else {
                scaled.insert(pot)
                let factor = Double(wallet) / Double(asked)
                for seat in potSeats {
                    allocation[seat.id] = Int((Double(requested[seat.id] ?? 0) * factor).rounded(.down))
                }
            }
        }

        // Head coach first, then the biggest cheques. See `entries`.
        let ordered = open.sorted { a, b in
            let aIsHC = a.coachRole == .headCoach
            let bIsHC = b.coachRole == .headCoach
            if aIsHC != bIsHC { return aIsHC }
            let (av, bv) = (allocation[a.id] ?? 0, allocation[b.id] ?? 0)
            if av != bv { return av > bv }
            return a.id < b.id
        }

        var planned: [StaffTemplate.Pot: Int] = [:]
        for seat in open { planned[seat.pot, default: 0] += allocation[seat.id] ?? 0 }

        return StaffTemplatePlan(
            entries: ordered.map { Entry(seat: $0, allocation: allocation[$0.id] ?? 0) },
            skippedSeats: skipped,
            planned: planned,
            available: available,
            scaledPots: scaled
        )
    }
}

// MARK: - StaffTemplateStore

/// Where saved templates live: one global `UserDefaults` key, JSON, no career
/// suffix. See the header of this file for why it is deliberately outside
/// ``CareerScopedDefaults/keys``.
///
/// Deliberately NOT `@MainActor`: it is handed to a view as a default property
/// value (`@ObservedObject private var store = StaffTemplateStore.shared`),
/// which is evaluated outside any actor. `UserDefaults` is thread-safe and every
/// mutation here comes from a tap, exactly as `CareerScopedDefaultsStore` is
/// written one file over.
final class StaffTemplateStore: ObservableObject {

    static let shared = StaffTemplateStore()

    /// GLOBAL on purpose. Do not add this to `CareerScopedDefaults.keys`.
    static let defaultsKey = "staffTemplates"

    /// A hard ceiling so a user who taps Save every offseason does not end up
    /// scrolling twenty near-identical cards. The oldest is dropped first.
    static let maxTemplates = 12

    @Published private(set) var templates: [StaffTemplate] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.templates = Self.load(from: defaults)
    }

    // MARK: Mutations

    /// Inserts a new template, or replaces the one with the same id.
    func save(_ template: StaffTemplate) {
        var next = templates
        if let idx = next.firstIndex(where: { $0.id == template.id }) {
            next[idx] = template
        } else {
            next.insert(template, at: 0)
        }
        next.sort { $0.savedAt > $1.savedAt }
        if next.count > Self.maxTemplates { next = Array(next.prefix(Self.maxTemplates)) }
        commit(next)
    }

    func delete(id: UUID) {
        commit(templates.filter { $0.id != id })
    }

    func rename(id: UUID, to name: String) {
        var next = templates
        guard let idx = next.firstIndex(where: { $0.id == id }) else { return }
        next[idx].name = name
        commit(next)
    }

    // MARK: Storage

    private func commit(_ next: [StaffTemplate]) {
        templates = next
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> [StaffTemplate] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([StaffTemplate].self, from: data)
        else { return [] }
        return decoded.sorted { $0.savedAt > $1.savedAt }
    }
}

// MARK: - Capture

extension StaffTemplate {

    /// Reads a club's CURRENT staff into a portable plan.
    ///
    /// One row per seat, taken off the seat lists the ledger owns, so a
    /// duplicate coach row cannot put the same chair in the template twice and
    /// a chair this career does not own (the GM+HC's own) is never captured.
    /// Empty chairs are not captured either: a template is what the user built,
    /// not what he left open.
    static func capture(
        name: String,
        sourceLabel: String,
        ledger: StaffLedger,
        coaches: [Coach],
        scouts: [Scout]
    ) -> StaffTemplate {
        var seats: [Seat] = []

        for role in ledger.coachRoles {
            // Dearest row wins where a seat somehow has two, exactly as
            // `StaffLedger` charges the pot, so the captured salary and the
            // committed figure on screen are the same money.
            guard let coach = coaches.filter({ $0.role == role })
                .max(by: { $0.salary < $1.salary }) else { continue }
            seats.append(Seat(
                kind: .coach,
                roleRaw: role.rawValue,
                salary: coach.salary,
                personalityRaw: coach.personality.rawValue
            ))
        }

        for role in ledger.scoutRoles {
            guard let scout = scouts.filter({ $0.scoutRole == role })
                .max(by: { $0.salary < $1.salary }) else { continue }
            seats.append(Seat(
                kind: .scout,
                roleRaw: role.rawValue,
                salary: scout.salary,
                personalityRaw: nil
            ))
        }

        return StaffTemplate(
            name: name,
            sourceLabel: sourceLabel,
            coachingBudget: ledger.coachingBudget,
            medicalBudget: ledger.medicalBudget,
            scoutingBudget: ledger.scoutingBudget,
            seats: seats
        )
    }
}
