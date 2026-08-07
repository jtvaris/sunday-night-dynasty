import SwiftUI
import SwiftData

// MARK: - Scout Notes (#105)
//
// WHAT THE BOARD ADDS UP TO.
//
// Two blocks used to sit at the top of the Big Board's own `List`, above the
// first tier: "Recommendations" (your #1 need, the best man at it, the best man
// on the board, your remaining picks) and "Position Depth Analysis" (on-board
// against needed at each hole, your #1 against the media's #1, the odds your #1
// is still there when you pick).
//
// Neither is the board. They are READS over it — four to eight lines of prose
// derived from the same 350 rows the user came to that screen to work — and
// they were between him and row #1 on every single visit. This is the surface
// that says what they say, once, where a man goes to ask "so what does all this
// add up to" rather than "who is next".
//
// ## Nothing is computed twice
//
// Every number here comes off `ScoutBoardReads`, the same value the Big Board
// builds in its own `refreshNeedReads()`. A second copy of the fogged
// best-by-read walk is precisely the defect this split had to avoid: two walks
// over ~350 prospects is two tie-breaks to drift, and the day they drift the
// board's NEED chip and this screen's "your #1 need" name different positions.
//
// ## Fog discipline
//
// Nothing on this screen reads `trueOverall`, and nothing sorts on the raw
// `scoutedOverall` integer. Every grade printed beside a name is
// `ScoutBoardReads.gradeText`, i.e. `ProspectFog.read` with its confidence
// widening intact, and it prints "—" rather than a number for a man this
// building has not filed on. The "best" answers are ordered by the MIDPOINT of
// that same fogged band — see `ScoutBoardReads.BoardReadKey` — so the name and
// the grade beside it are one claim, not two.
//
// ## Chrome
//
// It sits under the hub's own header, which prints the surface title. No
// navigation title, no repeated "SCOUT NOTES" bar: the hub said it already.

struct ScoutNotesView: View {

    let career: Career
    /// The class as the hub holds it. Filtered to the men this building has
    /// filed on inside `ScoutBoardReads.make`, never here.
    let prospects: [CollegeProspect]
    /// The club's roster, for the need read. Handed down rather than fetched so
    /// the hub's one fetch serves every tab.
    let teamRoster: [Player]
    /// Lets the empty state hand the user back to another Scouting tab. Optional
    /// so standalone call sites and previews can omit it.
    var onSwitchTab: ((ScoutingTab) -> Void)? = nil
    /// Hands one man to the interview room (#125). Supplied by the hub ONLY when
    /// the room is honestly open, exactly as it is to the board — so this screen
    /// never has to know the interview economy and can never offer an action the
    /// room would refuse. `nil` here means the button is not drawn at all.
    var onInterview: ((CollegeProspect) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    /// The user's own priorities from Roster Evaluation — the counterpoint to
    /// the scouts' need call. Career-scoped, written by that screen, read here.
    @CareerScopedStorage("rosterPriorities") private var rosterPrioritiesJSON: String = "{}"

    @State private var reads = ScoutBoardReads.empty
    @State private var teamDraftPicks: [DraftPick] = []
    /// The top of the user's own board. `UserDraftBoard` is the ONE reader of
    /// the persisted order — the Big Board, the Mock Draft, the war room and
    /// this screen all print the same "#1", rather than each inventing one.
    @State private var myTopProspect: CollegeProspect?
    @State private var isLoading = true

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentGold)
                    Text("Reading the board...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if scoutedProspects.isEmpty {
                emptyState
            } else {
                List {
                    recommendationsSection
                    depthAnalysisSection
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // The consensus board is a per-session cache, not a save, and every
            // market-rank tie-break below reads it. Publishing here means this
            // tab answers the same as the Big Board whichever one the user
            // opened first; the population is normalised inside, so republishing
            // it cannot narrow anyone else's board.
            DraftIntel.refreshConsensusBoard(for: prospects)
            rebuild()
            isLoading = false
        }
        // The hub reloads the class after a sheet dismiss (a combine trip files
        // reports on the board), and the count is the cheapest proof the array
        // it handed down is a different one.
        .onChange(of: prospects.count) { _, _ in rebuild() }
        // The need read is cached off the ROSTER, which the hub can reload under
        // a screen that never left it (a signing, a cut, the week advancing).
        .onChange(of: teamRoster.count) { _, _ in rebuild() }
    }

    // MARK: - Rebuild

    private var scoutedProspects: [CollegeProspect] {
        prospects.filter { $0.scoutedOverall != nil }
    }

    private func rebuild() {
        teamDraftPicks = ScoutBoardReads.teamPicks(career: career, in: modelContext)
        reads = ScoutBoardReads.make(
            prospects: prospects,
            teamRoster: teamRoster,
            teamDraftPicks: teamDraftPicks
        )
        myTopProspect = UserDraftBoard.sorted(scoutedProspects).first
    }

    private var rosterPriorities: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterPrioritiesJSON.utf8))) ?? [:]
    }

    // MARK: - Recommendations Section (#216)

    private var recommendationsSection: some View {
        Section {
            if let need = reads.topNeed {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.warning)
                        .font(.caption)
                    Text("Your #1 need: **\(need.rawValue)** (weakest group)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            if let prospect = reads.bestAtTopNeed, let need = reads.topNeed {
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .foregroundStyle(Color.success)
                        .font(.caption)
                    // The BAND, not the tier. These two lines pick their man by
                    // the midpoint of the fogged read now, so printing
                    // `scoutedTier` — a bucketing of the raw scouted integer —
                    // put a second, tighter yardstick on the same line as the
                    // first: the depth list three rows down already prints the
                    // band, for the same prospect, off the same instrument.
                    Text("Best available at \(need.rawValue): **\(prospect.fullName)** (\(reads.gradeText(prospect)))")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 0)
                    interviewButton(for: prospect)
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            if let prospect = reads.bestAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color.accentGold)
                        .font(.caption)
                    Text("Best player available: **\(prospect.fullName)** (\(reads.gradeText(prospect)))")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 0)
                    interviewButton(for: prospect)
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            // #71: Show team's draft picks
            HStack(spacing: 10) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.accentBlue)
                    .font(.caption)
                Text("Your picks: \(reads.picksSummary)")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
            }
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            Label("Recommendations", systemImage: "lightbulb.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .textCase(nil)
        }
    }

    /// The one action this screen offers on a man it names.
    ///
    /// Drawn only when the hub handed down `onInterview`, which it does only
    /// while the room is open and there are slots left on the 60-a-cycle ration.
    /// A screen that names the best man at your biggest hole and then offers no
    /// way to act on him is a dead end; a button that would be refused is worse.
    @ViewBuilder
    private func interviewButton(for prospect: CollegeProspect) -> some View {
        if let onInterview {
            Button {
                onInterview(prospect)
            } label: {
                Label("Interview", systemImage: "bubble.left.and.bubble.right")
                    .labelStyle(.iconOnly)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Interview \(prospect.fullName)")
        }
    }

    // MARK: - Depth Analysis (#227)

    /// The media's own #1: the board sorted by `draftProjection` (lowest =
    /// best). Public information, and the only half of the comparison below
    /// that is not the user's own work.
    private var mediaTopProspect: CollegeProspect? {
        prospects
            .filter { $0.draftProjection != nil }
            .sorted { ($0.draftProjection ?? Int.max) < ($1.draftProjection ?? Int.max) }
            .first
    }

    /// User's priority positions from Roster Evaluation, formatted for display.
    ///
    /// HIGH only, top-3: Auto-Set Priorities stamps every group with SOME
    /// priority, so listing everything non-"none" would read "Priority QB,
    /// RB, WR, TE, OL, DL, LB, DB, ST" — a signal with no information in it.
    /// This line is the counterpoint to the scouts' top-3 need call above it.
    private var userPriorityPositions: [String] {
        Array(
            rosterPriorities
                .filter { $0.value == "high" }
                .map { $0.key }
                .sorted()   // dictionary order is unstable frame to frame
                .prefix(3)
        )
    }

    private var depthAnalysisSection: some View {
        Section {
            // Staff vs User needs comparison
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scout: Need \(reads.needs.map { $0.rawValue }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                    if userPriorityPositions.isEmpty {
                        Text("You: Set your priorities in Roster Evaluation")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text("You: Priority \(userPriorityPositions.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Color.accentBlue)
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)

            // Position depth summary
            ForEach(reads.depthItems) { item in
                HStack(spacing: 8) {
                    Text(item.position.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 32)

                    Text("\(item.onBoard) on board (need \(item.needed))")
                        .font(.caption)
                        .foregroundStyle(item.isSufficient ? Color.success : Color.warning)

                    Text(item.isSufficient ? "\u{2713}" : "\u{26A0}\u{FE0F}")
                        .font(.caption)

                    // #72: Best available prospect for this position need
                    if let best = reads.best(at: item.position) {
                        Text("Best: \(best.lastName) (\(reads.gradeText(best)))")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }

                    let groupID = ScoutBoardReads.positionGroupID(for: item.position)
                    if let userPriority = rosterPriorities[groupID], userPriority != "none" {
                        Text("You: \(userPriority)")
                            .font(.caption2)
                            .foregroundStyle(userPriority == "high" ? Color.danger : userPriority == "medium" ? Color.warning : Color.accentBlue)
                            .padding(.horizontal, 4)
                            .background(Color.backgroundTertiary, in: Capsule())
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            // Your #1 vs Media #1 comparison (#15)
            if let myTop = myTopProspect, let mediaTop = mediaTopProspect {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(Color.accentBlue)

                        if myTop.id == mediaTop.id {
                            Text("Your #1 matches media consensus: **\(myTop.fullName)**")
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                        } else {
                            Text("Your #1: **\(myTop.fullName)** vs Media #1: **\(mediaTop.fullName)**")
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                    // Media projection for #1 (#15)
                    if let proj = mediaTop.draftProjection {
                        Text("Media projects \(mediaTop.lastName) at Pick #\(proj <= 3 ? proj : proj * 5)")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.leading, 26)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            // Available at your pick probability (#18)
            if let myTop = myTopProspect,
               let prob = reads.availableAtPickProbability(for: myTop),
               let firstPick = reads.firstPick {
                HStack(spacing: 8) {
                    Image(systemName: "percent")
                        .font(.caption)
                        .foregroundStyle(Color.accentBlue)
                    Text("**\(myTop.lastName)** available at Rd \(firstPick.round) #\(firstPick.pickNumber): \(Int(prob * 100))%")
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
        } header: {
            Label("Position Depth Analysis", systemImage: "chart.bar.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentBlue)
                .textCase(nil)
        }
    }

    // MARK: - Empty state

    /// This page is a read over the board, so it is empty for exactly one
    /// reason and it says so, plus the two doors out. A screen that renders
    /// blank because its input is blank tells the user nothing about which of
    /// the two he is looking at.
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text("No Notes Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Scout Notes reads your board back to you \u{2014} your biggest hole, the best man at it, how deep this class is where you are thin. Nobody in your building has filed on the class yet, so there is nothing to read. Order film study on the Big Board: every report you pay for puts a man on the board and a line on this page.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                emptyStateButton(
                    title: "Big Board",
                    systemImage: "list.number",
                    isPrimary: true
                ) { onSwitchTab?(.board) }

                emptyStateButton(
                    title: "Scout Team",
                    systemImage: "binoculars",
                    isPrimary: false
                ) { onSwitchTab?(.scouts) }
            }
            .padding(.top, 4)
            .opacity(onSwitchTab == nil ? 0 : 1)
            .disabled(onSwitchTab == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.backgroundPrimary : Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .fill(isPrimary ? Color.accentGold : Color.backgroundTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(isPrimary ? Color.clear : Color.surfaceBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
