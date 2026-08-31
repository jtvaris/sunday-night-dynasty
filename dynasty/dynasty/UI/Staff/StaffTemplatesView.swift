import Foundation
import SwiftUI
import SwiftData

// MARK: - Staff Templates
//
// Save the staff you built, re-apply the plan behind it in a later career.
//
// The shipped escape hatch for an empty building is Auto-Hire
// (`CoachingStaffView.runAutoHire`): one tap, every chair, the authored
// `CoachRole.salaryRange` averages, best fit-adjusted rating each allocation can
// buy. It is the same staff every time, in every save, because it remembers
// nothing. This screen is the memory — the seats a manager pays for, the share
// of each pot he pays them, and the temperaments he wants around his head coach,
// carried across careers by ``StaffTemplate``.
//
// It hires the SAME market Auto-Hire and the manual sheets hire from: the
// league's own out-of-work bench (`CoachMarketEngine.availableBench`) plus
// `CoachingEngine.generateCoachCandidates`, and the seeded scout pool
// (`CoachingEngine.generateScoutCandidates`). There is no parallel pool and no
// invented staff. What the template changes is the CAP each seat is offered and
// WHICH affordable man is preferred inside it.

struct StaffTemplatesView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @ObservedObject private var store = StaffTemplateStore.shared

    // `@Query` cannot take a runtime predicate off a stored property, so the
    // store-wide result is narrowed to this save here — the same shape
    // `CoachingStaffView` uses, and for the same reason.
    @Query private var allCoachesUnscoped: [Coach]
    @Query private var allScoutsUnscoped: [Scout]
    @Query private var allTeamsUnscoped: [Team]

    /// Name the user is typing for a new capture.
    @State private var draftName: String = ""
    /// What the last apply actually did. Replaces the card list's quiet.
    @State private var lastResult: ApplyResult?
    /// Template whose delete is awaiting confirmation.
    @State private var pendingDeleteID: UUID?
    /// Template whose seat list is expanded.
    @State private var expandedID: UUID?

    // MARK: - Scoped populations

    private var allCoaches: [Coach] { allCoachesUnscoped.filter { $0.careerID == career.id } }
    private var allScouts: [Scout] { allScoutsUnscoped.filter { $0.careerID == career.id } }
    private var allTeams: [Team] { allTeamsUnscoped.filter { $0.careerID == career.id } }

    private var team: Team? {
        guard let teamID = career.teamID else { return nil }
        return allTeams.first { $0.id == teamID }
    }

    private var coaches: [Coach] {
        guard let teamID = career.teamID else { return [] }
        return allCoaches.filter { $0.teamID == teamID }
    }

    private var scouts: [Scout] {
        guard let teamID = career.teamID else { return [] }
        return allScouts.filter { $0.teamID == teamID }
    }

    /// THE staff reading for this club — seats, all three pots. Built exactly
    /// as `CoachingStaffView` builds it so the money on this screen and the
    /// money on that one are one number.
    private var ledger: StaffLedger {
        StaffLedger(careerRole: career.role, coaches: coaches, scouts: scouts, owner: team?.owner)
    }

    private var filledSeatCount: Int {
        ledger.filledCoachRoles.count + ledger.filledScoutRoles.count
    }

    private var totalSeatCount: Int {
        ledger.coachRoles.count + ledger.scoutRoles.count
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    introCard
                    captureCard
                    if let lastResult { resultCard(lastResult) }
                    savedSection
                }
                .padding(DSSpacing.md)
                .frame(maxWidth: DSLayout.contentMeasure)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Staff Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Intro

    private var introCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("What a template carries")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text("A template stores seats, not men. The coaches you hired here do not exist in another save, so what it keeps is the chairs you filled, the share of each budget you paid them, and the personality each chair held. Applying it in a new career offers those shares to your open seats and shops for the same temperaments.")
                .font(.system(size: DSType.Size.footnote))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Templates outlive the career that made them — deleting a save does not delete them.")
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .stroke(Color.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Capture

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Save this staff")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            if !ledger.isResolved {
                Text("Your owner has not set the staff budgets yet. A template is stored as a share of each budget, so there is nothing to take a share of until he does.")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if filledSeatCount == 0 {
                Text("No seats are filled yet. Hire a staff first — a template records what you built, not the chairs you left open.")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(filledSeatCount) of \(totalSeatCount) seats filled — $\(millions(ledger.committedCoaching))M coaching, $\(millions(ledger.committedMedical))M medical, $\(millions(ledger.committedScouting))M scouting.")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Template name", text: $draftName)
                    .font(.system(size: DSType.Size.body))
                    .textFieldStyle(.plain)
                    .padding(DSSpacing.xs)
                    .background(
                        Color.backgroundTertiary,
                        in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    )
                    .foregroundStyle(Color.textPrimary)

                Button {
                    captureTemplate()
                } label: {
                    Text("Save as template")
                        .font(.system(size: DSType.Size.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.xs)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.backgroundPrimary)
                .background(
                    Color.accentGold,
                    in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                )
            }
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .stroke(Color.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Saved templates

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Saved templates")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            if store.templates.isEmpty {
                Text("None yet. Save one from a staff you are happy with and it will be here in every career you start afterwards.")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(store.templates) { template in
                    templateCard(template)
                }
            }
        }
    }

    @ViewBuilder
    private func templateCard(_ template: StaffTemplate) -> some View {
        let readout = plan(for: template)

        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(template.name)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(template.seats.count) seats")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
            }

            Text("\(template.sourceLabel) · saved \(template.savedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)

            // What it was, in the career it came from.
            ForEach(StaffTemplate.Pot.allCases, id: \.self) { pot in
                if !template.seats(in: pot).isEmpty {
                    Text(capturedLine(template, pot))
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.4))

            // What it works out to here.
            Text(planHeadline(readout))
                .font(.system(size: DSType.Size.footnote, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(StaffTemplate.Pot.allCases, id: \.self) { pot in
                if let line = plannedLine(readout, pot) {
                    Text(line)
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(
                            readout.scaledPots.contains(pot) ? Color.warning : Color.textSecondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if expandedID == template.id {
                seatList(readout)
            }

            HStack(spacing: DSSpacing.xs) {
                Button {
                    apply(template)
                } label: {
                    Text("Apply to open seats")
                        .font(.system(size: DSType.Size.footnote, weight: .semibold))
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xxs)
                }
                .buttonStyle(.plain)
                .foregroundStyle(readout.isEmpty ? Color.textTertiary : Color.backgroundPrimary)
                .background(
                    readout.isEmpty ? Color.backgroundTertiary : Color.accentGold,
                    in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                )
                .disabled(readout.isEmpty)

                Button {
                    expandedID = expandedID == template.id ? nil : template.id
                } label: {
                    Text(expandedID == template.id ? "Hide seats" : "Show seats")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.accentGold)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    if pendingDeleteID == template.id {
                        store.delete(id: template.id)
                        pendingDeleteID = nil
                    } else {
                        pendingDeleteID = template.id
                    }
                } label: {
                    Text(pendingDeleteID == template.id ? "Confirm delete" : "Delete")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.dangerText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .stroke(Color.surfaceBorder, lineWidth: 1)
        )
    }

    /// Per-seat breakdown: what this club would offer for the chair, and the
    /// personality the plan will shop for first.
    private func seatList(_ plan: StaffTemplatePlan) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text("Seat · personality wanted · what this club offers")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(Color.textTertiary)

            if plan.entries.isEmpty {
                Text("Every seat this template holds is already filled here.")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textSecondary)
            }
            ForEach(plan.entries) { entry in
                HStack(spacing: DSSpacing.xs) {
                    Text(entry.seat.abbreviation)
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 44, alignment: .leading)

                    Text(entry.seat.displayName)
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    if let personality = entry.seat.personality {
                        Text(personality.shortLabel)
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Text(entry.allocation > 0 ? coachSalaryText(entry.allocation) : "no room")
                        .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                        .foregroundStyle(entry.allocation > 0 ? Color.textPrimary : Color.dangerText)
                }
            }
            if !plan.skippedSeats.isEmpty {
                Text("\(plan.skippedSeats.count) template seat\(plan.skippedSeats.count == 1 ? "" : "s") skipped — already filled here, or not a chair this career fills.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DSSpacing.xxs)
    }

    // MARK: - Result

    private func resultCard(_ result: ApplyResult) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(result.headline)
                .font(.system(size: DSType.Size.callout, weight: .semibold))
                .foregroundStyle(result.hired == 0 ? Color.dangerText : Color.success)

            Text(result.detail)
                .font(.system(size: DSType.Size.footnote))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Leaves $\(millions(max(0, ledger.remainingCoaching)))M coaching, $\(millions(max(0, ledger.remainingMedical)))M medical and $\(millions(max(0, ledger.remainingScouting)))M scouting. You can still replace anybody by hand.")
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .stroke(Color.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Copy

    /// "Coaching · 15 seats · $31.0M, 81% of that career's $38.4M budget"
    ///
    /// Every figure comes off the template's own arithmetic: `committed(pot)`
    /// sums the captured salaries, `potShare(pot)` divides it by the envelope
    /// stored beside them.
    private func capturedLine(_ template: StaffTemplate, _ pot: StaffTemplate.Pot) -> String {
        let seats = template.seats(in: pot).count
        let spent = template.committed(pot)
        let base = "\(pot.displayName.capitalized) · \(seats) seat\(seats == 1 ? "" : "s") · $\(millions(spent))M"
        guard let share = template.potShare(pot) else {
            return base + ", no budget recorded"
        }
        return base + ", \(Int((share * 100).rounded()))% of that career's $\(millions(template.envelope(pot)))M"
    }

    private func planHeadline(_ plan: StaffTemplatePlan) -> String {
        guard !plan.entries.isEmpty else {
            return "Nothing to apply — every seat it holds is already filled here."
        }
        let named = plan.entries.filter { $0.seat.personality != nil }.count
        // "Sets aside", not "fills": this is the plan's budget, and each seat is
        // then offered the best man that cap can buy — a chair the market prices
        // above its allocation stays open and its money is not spent.
        var line = "Sets aside $\(millions(plan.totalPlanned))M for \(plan.entries.count) open seat\(plan.entries.count == 1 ? "" : "s")"
        if named > 0 {
            line += ", shopping \(named) of them for the personality the template held"
        }
        return line + "."
    }

    /// "Coaching · plans $28.4M of the $34.0M you have left"
    private func plannedLine(_ plan: StaffTemplatePlan, _ pot: StaffTemplate.Pot) -> String? {
        let planned = plan.planned[pot] ?? 0
        guard planned > 0 || plan.entries.contains(where: { $0.seat.pot == pot }) else { return nil }
        let wallet = max(0, plan.available[pot] ?? 0)
        var line = "\(pot.displayName.capitalized) · plans $\(millions(planned))M of the $\(millions(wallet))M you have left"
        if plan.scaledPots.contains(pot) {
            line += " — scaled down to fit, so these chairs buy cheaper than the template did"
        }
        return line
    }

    private func millions(_ thousands: Int) -> String {
        String(format: "%.1f", Double(thousands) / 1_000.0)
    }

    // MARK: - Planning

    private func plan(for template: StaffTemplate) -> StaffTemplatePlan {
        let book = ledger
        return StaffTemplatePlan.build(
            template: template,
            vacantCoachRoles: Set(book.vacantCoachRoles),
            vacantScoutRoles: Set(book.vacantScoutRoles),
            envelopes: [
                .coaching: book.coachingBudget,
                .medical: book.medicalBudget,
                .scouting: book.scoutingBudget
            ],
            available: [
                .coaching: book.remainingCoaching,
                .medical: book.remainingMedical,
                .scouting: book.remainingScouting
            ]
        )
    }

    // MARK: - Capture action

    private func captureTemplate() {
        let book = ledger
        guard book.isResolved, filledSeatCount > 0 else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = "\(career.playerName) · \(career.currentSeason)"
        let template = StaffTemplate.capture(
            name: trimmed.isEmpty ? label : trimmed,
            sourceLabel: label,
            ledger: book,
            coaches: coaches,
            scouts: scouts
        )
        store.save(template)
        draftName = ""
        expandedID = template.id
    }

    // MARK: - Apply action

    /// What one apply pass did. Every field is counted in the loop below.
    private struct ApplyResult {
        var hired: Int
        var seatsPlanned: Int
        var spent: Int
        /// Seats whose template personality the signed man actually has.
        var personalityMatched: Int
        /// Seats that named a personality at all — the denominator for the above.
        var personalityAsked: Int
        /// Seats the market could only fill with a man the staff screen will
        /// badge ✗ Conflict against the head coach.
        var conflicts: Int
        /// Seats filled by a man the staff screen will badge ⚠ Tension. Counted
        /// and said out loud separately from `conflicts`, which is the ✗ band
        /// alone — the same repair `CoachingStaffView` already carries
        /// (`tensionHires`, and the note at its result sheet): a line reading
        /// "every planned seat was filled" sat directly over a coordinator row
        /// wearing a warning triangle. It matters more here than there, because
        /// `bestCoach` narrows to the template's wanted archetype before
        /// ranking, so the tension penalty in `rank` cannot steer the pick off
        /// a temperament the template asked for.
        var tensionHires: Int

        var unfilled: Int { max(0, seatsPlanned - hired) }

        var headline: String {
            hired == 0
                ? "Nobody hired"
                : "\(hired) hired for $\(String(format: "%.1f", Double(spent) / 1_000.0))M"
        }

        var detail: String {
            guard hired > 0 else {
                return "Nothing on the market came in under what the template set aside for these chairs."
            }
            var parts: [String] = []
            if personalityAsked > 0 {
                parts.append("\(personalityMatched) of \(personalityAsked) seats got the personality the template held")
            }
            if unfilled > 0 {
                parts.append("\(unfilled) stayed open — no affordable candidate inside the plan")
            }
            if conflicts > 0 {
                parts.append("\(conflicts) clash with your head coach — nobody else was affordable for those chairs")
            }
            if tensionHires > 0 {
                parts.append("\(tensionHires) sit in tension with your head coach — a workable fit, not a clash")
            }
            return parts.isEmpty ? "Every planned seat was filled." : parts.joined(separator: ". ") + "."
        }
    }

    /// Fills this career's open seats to the template's plan.
    ///
    /// Seat order comes from ``StaffTemplatePlan`` — head coach first, then the
    /// largest allocations — because everyone else is judged for fit against
    /// the head coach who will actually be in the building.
    private func apply(_ template: StaffTemplate) {
        guard let teamID = career.teamID else { return }
        let book = ledger
        let readout = plan(for: template)
        guard !readout.isEmpty else { return }

        var wallet: [StaffTemplate.Pot: Int] = [
            .coaching: max(0, book.remainingCoaching),
            .medical: max(0, book.remainingMedical),
            .scouting: max(0, book.remainingScouting)
        ]

        // Who the rest of the staff is measured against. Tracked locally rather
        // than re-read off the `@Query` between hires, which does not refresh
        // inside this loop — the identical reason `runAutoHire` carries it.
        var hcPersonality = referencePersonality(in: book)

        var result = ApplyResult(
            hired: 0,
            seatsPlanned: readout.entries.count,
            spent: 0,
            personalityMatched: 0,
            personalityAsked: readout.entries.filter { $0.seat.personality != nil }.count,
            conflicts: 0,
            tensionHires: 0
        )

        for entry in readout.entries {
            let pot = entry.seat.pot
            let cap = min(wallet[pot] ?? 0, entry.allocation)
            guard cap > 0 else { continue }

            if let role = entry.seat.coachRole {
                // Auto-Hire's own pool for a coaching chair, unchanged: the
                // league's real out-of-work men of this exact title, then the
                // generated field priced against the coaching envelope.
                let pool = CoachMarketEngine.availableBench(allCoaches).filter { $0.role == role }
                    + CoachingEngine.generateCoachCandidates(
                        role: role,
                        count: 20,
                        teamBudget: book.coachingBudget,
                        teamWins: team?.wins ?? 8,
                        teamReputation: career.reputation
                    )
                guard let pick = bestCoach(
                    in: pool,
                    cap: cap,
                    role: role,
                    wanted: entry.seat.personality,
                    hcPersonality: hcPersonality
                ) else { continue }

                hire(coach: pick.coach, teamID: teamID)
                if pick.matchedPersonality { result.personalityMatched += 1 }
                if pick.wasConflict { result.conflicts += 1 }
                // Read BEFORE `hcPersonality` moves below: every man is judged
                // against the head coach he will work for, and for the head
                // coach's own chair that is nobody yet.
                if !pick.wasConflict, band(pick.coach, hcPersonality) == .tension {
                    result.tensionHires += 1
                }
                if role == .headCoach { hcPersonality = pick.coach.personality }
                wallet[pot] = (wallet[pot] ?? 0) - pick.coach.salary
                result.spent += pick.coach.salary
                result.hired += 1

            } else if let role = entry.seat.scoutRole {
                let pool = CoachingEngine.generateScoutCandidates(
                    role: role,
                    count: 20,
                    seed: CoachingEngine.scoutPoolSeed(
                        teamID: teamID,
                        role: role,
                        season: career.currentSeason
                    )
                )
                guard let pick = bestScout(in: pool, cap: cap) else { continue }
                hire(scout: pick, teamID: teamID)
                wallet[pot] = (wallet[pot] ?? 0) - pick.salary
                result.spent += pick.salary
                result.hired += 1
            }
        }

        try? modelContext.save()
        lastResult = result
    }

    // MARK: - Candidate selection

    private struct CoachPick {
        let coach: Coach
        let matchedPersonality: Bool
        let wasConflict: Bool
    }

    /// The personality every hire is judged for fit against: the user himself
    /// when he coaches the team, otherwise whoever holds the head-coach chair.
    ///
    /// The same reference the staff rows' ✓ / ⚠ / ✗ badge uses, so this pass
    /// cannot sign a man the staff screen then flags as a clash.
    private func referencePersonality(in book: StaffLedger) -> PersonalityArchetype? {
        if book.careerRole == .gmAndHeadCoach {
            return Self.coachingStylePersonality(career.coachingStyle)
        }
        return coaches.first { $0.role == .headCoach }?.personality
    }

    /// Mirrors `CoachingStaffView.coachingStylePersonality`, which is private to
    /// that file. Both exist so a GM+HC career — who has no head-coach ROW — is
    /// still something the chemistry model can measure a staff against.
    private static func coachingStylePersonality(_ style: CoachingStyle) -> PersonalityArchetype {
        switch style {
        case .tactician:      return .quietProfessional
        case .motivator:      return .fieryCompetitor
        case .playersCoach:   return .mentor
        case .innovator:      return .feelPlayer
        case .disciplinarian: return .steadyPerformer
        }
    }

    private func band(
        _ coach: Coach,
        _ hcPersonality: PersonalityArchetype?
    ) -> CoachingEngine.ChemistryBand? {
        guard let hcPersonality else { return nil }
        return CoachingEngine.chemistryBand(
            score: CoachingEngine.coachChemistry(coachA: hcPersonality, coachB: coach.personality)
        )
    }

    /// The attribute a chair is actually hired for. Same split
    /// `CoachingStaffView.autoHireSpecialty` uses — a coordinator who cannot
    /// call plays is not a good coordinator at any price, and the twelve-way
    /// mean gives his defining skill one twelfth of the say.
    private func specialty(_ coach: Coach, role: CoachRole) -> Int? {
        switch role {
        case .offensiveCoordinator, .defensiveCoordinator:
            return (coach.playCalling * 2 + coach.gamePlanning) / 3
        case .qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach:
            return coach.playerDevelopment
        case .specialTeamsCoordinator:
            return (coach.playCalling + coach.discipline) / 2
        default:
            return nil
        }
    }

    /// Role-weighted rating, adjusted for the head coach he would work for.
    /// `CoachingEngine.coachOverallRating` is the twelve-attribute mean every
    /// other staff surface prints.
    private func rank(
        _ coach: Coach,
        role: CoachRole,
        hcPersonality: PersonalityArchetype?
    ) -> Int {
        let ovr = CoachingEngine.coachOverallRating(coach)
        let base = specialty(coach, role: role).map { (ovr + $0 * 2) / 3 } ?? ovr
        switch band(coach, hcPersonality) {
        case .good:     return base + 2
        case .tension:  return base - 4
        case .conflict: return base - 9
        case nil:       return base
        }
    }

    /// Best man `cap` can buy for one chair, preferring the template's
    /// personality.
    ///
    /// Three tiers, in order, and the template only ever reorders the FIRST
    /// two — it can never raise a bid:
    ///
    /// 1. affordable, does not clash with the head coach, AND holds the
    ///    personality the template recorded;
    /// 2. affordable and does not clash — the template's temperament simply was
    ///    not on this market at this price;
    /// 3. affordable but clashing, reported rather than taken quietly, because
    ///    an EMPTY coordinator chair costs efficiency and development every
    ///    week where a clash costs harmony the user can fix by replacing one
    ///    man.
    ///
    /// Tier 1 narrows to the wanted archetype BEFORE ranking, so every survivor
    /// shares one personality and therefore one chemistry band: the `-4` tension
    /// penalty in ``rank(_:role:hcPersonality:)`` is uniform across them and
    /// cannot steer the pick off a temperament the template asked for. Asking
    /// for a temperament that sits in tension with this head coach is the user's
    /// own instruction, so it is honoured — and counted into
    /// `ApplyResult.tensionHires` and named in the result card rather than
    /// swallowed.
    private func bestCoach(
        in pool: [Coach],
        cap: Int,
        role: CoachRole,
        wanted: PersonalityArchetype?,
        hcPersonality: PersonalityArchetype?
    ) -> CoachPick? {
        let affordable = pool.filter { $0.salary <= cap }
        guard !affordable.isEmpty else { return nil }

        func best(_ candidates: [Coach]) -> Coach? {
            candidates.max { a, b in
                let (ra, rb) = (
                    rank(a, role: role, hcPersonality: hcPersonality),
                    rank(b, role: role, hcPersonality: hcPersonality)
                )
                if ra != rb { return ra < rb }
                // Cheaper of two equals.
                return a.salary > b.salary
            }
        }

        let workable = affordable.filter { band($0, hcPersonality) != .conflict }

        if let wanted, let pick = best(workable.filter { $0.personality == wanted }) {
            return CoachPick(coach: pick, matchedPersonality: true, wasConflict: false)
        }
        if let pick = best(workable) {
            return CoachPick(coach: pick, matchedPersonality: false, wasConflict: false)
        }
        guard let pick = best(affordable) else { return nil }
        return CoachPick(
            coach: pick,
            matchedPersonality: wanted != nil && pick.personality == wanted,
            wasConflict: true
        )
    }

    /// Scouts rank on evaluation accuracy — the hire sheet's own default sort,
    /// and `Scout` carries no personality for a template to have recorded.
    private func bestScout(in pool: [Scout], cap: Int) -> Scout? {
        pool.filter { $0.salary <= cap }
            .max { a, b in
                if a.accuracy != b.accuracy { return a.accuracy < b.accuracy }
                if a.potentialRead != b.potentialRead { return a.potentialRead < b.potentialRead }
                return a.salary > b.salary
            }
    }

    // MARK: - Hiring

    /// Signs a coach. Mirrors `CoachingStaffView.hire(coach:teamID:)` —
    /// including the face claim, without which the next hire in this same pass
    /// could be handed the same portrait — minus the role-clearing delete,
    /// since every chair this pass touches is vacant by construction.
    private func hire(coach candidate: Coach, teamID: UUID) {
        candidate.teamID = teamID
        candidate.careerID = career.id
        candidate.hireSeasonYear = career.currentSeason
        candidate.contractYearsRemaining = 3
        // Task #133 — see `Coach.signedThisOffseason`. Without this the rival
        // poaching pass on the very next advance takes men off the board before
        // they have coached a practice.
        candidate.signedThisOffseason = true
        candidate.unemployedSeasons = 0
        candidate.faceID = FaceLibrary.shared.claimFace(
            candidate.faceID,
            personID: candidate.id,
            role: .coach,
            age: candidate.age,
            position: nil,
            gender: FacePersonGender(tag: candidate.gender)
        )
        if candidate.modelContext == nil {
            modelContext.insert(candidate)
        }

        // R30: every coaching hire joins the tree; medical staff sit outside it.
        guard !StaffLedger.medicalRoles.contains(candidate.role) else { return }
        var tree = career.coachingTree
        CoachRelationshipEngine.updateCoachingTree(
            tree: &tree.entries,
            coach: candidate,
            event: "hired",
            season: career.currentSeason
        )
        career.coachingTree = tree
    }

    /// Signs a scout. Mirrors `CoachingStaffView.hire(scout:teamID:)`.
    private func hire(scout candidate: Scout, teamID: UUID) {
        candidate.teamID = teamID
        candidate.careerID = career.id
        modelContext.insert(candidate)
    }
}

// MARK: - Entry point

/// The one line the Staff screen needs to reach this feature.
///
/// Kept here rather than written into `CoachingStaffView` so the templates
/// screen ships as a self-contained pair of files: drop
/// `StaffTemplatesLink(career: career)` into that screen's toolbar or its
/// hiring rail and the feature is reachable.
struct StaffTemplatesLink: View {

    let career: Career

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Staff Templates", systemImage: "square.on.square")
                .font(.system(size: DSType.Size.footnote, weight: .semibold))
        }
        .tint(Color.accentGold)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                StaffTemplatesView(career: career)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isPresented = false }
                                .tint(Color.accentGold)
                        }
                    }
            }
        }
    }
}
