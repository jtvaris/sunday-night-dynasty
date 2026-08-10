import SwiftUI
import SwiftData

// MARK: - OwnerMeetingView — the surviving owner screen (#105 Wave 5a)
//
// UI_REDESIGN_VISION §4 Wave 5: *"Merge … the two owner screens, then restyle
// the survivors."* This is the survivor. Everything it draws about the owner now
// comes out of `OwnerBriefing` — the shared vocabulary this wave extracted from
// here and from `IntroSequenceView.OwnerMeetingStep`, which drew the same man a
// second time with better explainers and no live state.
//
// What is left in this file is the part that is genuinely this screen's:
//
//   * the **fetch** (team → owner, pending whim, live-evaluated season goals);
//   * the **whim**, which only exists mid-season and only here;
//   * the two **destinations** (goal tracker, budget reallocation), which exist
//     only because this screen lives inside a `NavigationStack`;
//   * the empty state.
//
// **The whim response is now the screen's one commit (§2.5 / P5).** It used to
// be a pair of hand-rolled rounded rectangles in the middle of a scroll of
// cards, i.e. the most consequential control on the screen placed where a long
// page could scroll it out of sight — the exact finding §2.5 exists to fix. The
// card states the request; the bar commits to it, with the standard
// primary/secondary pair and the cost line beside them.

struct OwnerMeetingView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var owner: Owner?
    @State private var team: Team?

    // R31: pending whim + evaluated season goals for the current season.
    @State private var pendingWhim: OwnerPersonaEngine.OwnerWhim?
    @State private var seasonGoals: [SeasonGoal] = []

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if let owner {
                VStack(spacing: 0) {
                    briefing(owner)

                    // §2.5: the one commit surface, and it appears only when
                    // there is something to commit to.
                    if let whim = pendingWhim {
                        whimBar(whim, owner: owner)
                    }
                }
            } else {
                DSEmptyState(
                    density: .study,
                    icon: "building.2",
                    title: "No owner data",
                    message: "Owner information appears once a team is selected."
                )
            }
        }
        .navigationTitle("Owner Relations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadOwner() }
    }

    // MARK: - The briefing

    private func briefing(_ owner: Owner) -> some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                OwnerBriefingHeader(
                    career: career,
                    owner: owner,
                    teamName: team?.fullName ?? "Owner"
                )

                if let whim = pendingWhim {
                    whimCard(whim)
                }

                if !briefingGoals.isEmpty {
                    OwnerGoalsCard(
                        goals: briefingGoals,
                        link: OwnerBriefingLink(title: "View full goal tracker") {
                            OwnerGoalsView(career: career)
                        }
                    )
                }

                OwnerBudgetCard(
                    owner: owner,
                    link: OwnerBriefingLink(title: "Reallocate budget") {
                        OwnerBudgetView(career: career)
                    }
                )

                OwnerSatisfactionCard(owner: owner, career: career)
                OwnerPatienceCard(owner: owner, career: career)

                // The explainers the hub never had — merged in from the intro
                // screen, which is the only place they used to exist.
                OwnerPrioritiesCard(owner: owner)
                OwnerQuoteCard(owner: owner)

                if let review = career.ownerSeasonReview {
                    OwnerLastReviewCard(review: review)
                }

                if owner.satisfaction < 60 {
                    OwnerWarningCard(owner: owner, career: career)
                }
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: DSLayout.contentMeasure)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    /// The live goals, in the briefing's own vocabulary. The evaluation stays in
    /// `OwnerGoalsEngine`; this only picks the four the card shows.
    private var briefingGoals: [OwnerBriefingGoal] {
        seasonGoals.prefix(4).map { goal in
            OwnerBriefingGoal(
                id: goal.id.uuidString,
                title: goal.title,
                priorityLabel: goal.priority == .primary
                    ? "Primary"
                    : (goal.priority == .secondary ? "Secondary" : "Bonus"),
                isPrimary: goal.priority == .primary,
                progress: goal.target.map { (done: goal.progress, target: $0) },
                isAchieved: goal.isAchieved
            )
        }
    }

    // MARK: - Whim (R31)

    /// What he is asking for. The *answer* lives on the action bar.
    private func whimCard(_ whim: OwnerPersonaEngine.OwnerWhim) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "envelope.open.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.warning)
                Text("THE OWNER HAS A SUGGESTION")
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.warning)
                Spacer(minLength: DSSpacing.xs)
                Text("WEEK \(whim.week)")
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiaryReadable)
            }

            Divider().overlay(Color.surfaceBorder)

            Text(whim.title)
                .font(DSType.text(14, .bold))
                .foregroundStyle(Color.textPrimary)

            Text("\u{201C}\(whim.request)\u{201D}")
                .font(DSType.text(14, .regular, prose: true))
                .italic()
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Complying keeps the owner happy. Pushing back stings now \u{2014} but stand your ground AND deliver a strong season, and your reputation grows.")
                .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                .foregroundStyle(Color.textTertiaryReadable)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.warning.opacity(0.5), lineWidth: 1.5)
                )
        )
    }

    private func whimBar(_ whim: OwnerPersonaEngine.OwnerWhim, owner: Owner) -> some View {
        DSActionBar(
            explainer: .init(
                title: "Answer the owner",
                message: "**\(whim.title)** \u{00B7} Complying keeps him happy; pushing back costs satisfaction now."
            ),
            secondary: .init(
                title: "Push back",
                handler: { respondToWhim(whim, comply: false, owner: owner) }
            ),
            primary: .init(
                title: "You got it",
                handler: { respondToWhim(whim, comply: true, owner: owner) }
            )
        )
    }

    private func respondToWhim(
        _ whim: OwnerPersonaEngine.OwnerWhim,
        comply: Bool,
        owner: Owner
    ) {
        let updated = OwnerPersonaEngine.respond(to: whim, comply: comply, owner: owner)
        var whims = career.ownerWhims
        if let index = whims.firstIndex(where: { $0.id == whim.id }) {
            whims[index] = updated
        }
        career.ownerWhims = whims
        try? modelContext.save()
        withAnimation(.easeInOut(duration: 0.25)) {
            pendingWhim = nil
        }
    }

    // MARK: - Data

    private func loadOwner() {
        guard let teamID = career.teamID else { return }
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first
        owner = team?.owner

        // R31: pending whim + live-evaluated season goals
        pendingWhim = career.ownerWhims.first {
            $0.seasonYear == career.currentSeason && $0.status == .pending
        }
        if let fetchedTeam = team {
            let stored = career.ownerSeasonGoals
            if !stored.isEmpty {
                seasonGoals = OwnerGoalsEngine.evaluateGoalProgress(
                    goals: stored,
                    team: fetchedTeam,
                    career: career
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Alex Reid", role: .gm, capMode: .simple)
    NavigationStack {
        OwnerMeetingView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Owner.self], inMemory: true)
}
