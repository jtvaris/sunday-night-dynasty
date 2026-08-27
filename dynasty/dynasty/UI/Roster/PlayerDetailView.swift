import SwiftUI
import SwiftData

// MARK: - The study-density detail layout (UI_REDESIGN_VISION §4 Wave 4)
//
// **One layout, not three forks.** `PlayerDetailView`, `ProspectDetailView` and
// `CoachDetailView` are the same screen wearing three costumes: a subject, a
// pile of grouped facts about him, and a short list of things you can do to
// him. Before this wave they were an `.insetGrouped` `List` (coach), an
// `.insetGrouped` `List` with a bespoke bottom bar (prospect), and an
// `.insetGrouped` `List` behind a *three-way* responsive `if` that shipped four
// different section orders (player). Section headers came out of
// `Section("String")`, `Section(header:)` and hand-rolled `HStack`s in the same
// file.
//
//   hero        the subject, on `backgroundPlate`, full-bleed
//   columns     grouped cards, 3 / 2 / 1 by available width
//   DSActionBar the one commit surface (§2.5, P5)
//
// These types are deliberately declared here rather than in `UI/Common/`: wave
// 4 owns exactly these three files, and the promotion to a shared
// `UI/Common/DSDetailLayout.swift` is a file-move with no behaviour in it. They
// are `internal`, so `ProspectDetailView` and `CoachDetailView` use them today.

/// Available content width → number of card columns.
///
/// Width, not size class. The three screens used `verticalSizeClass == .compact`
/// to mean "landscape", which is true on iPhone and **false on every iPad in
/// every orientation** — so the player card's three-column landscape branch was
/// dead code on the only device this game ships for, and its iPad-portrait
/// branch was rendering in landscape too.
enum DSDetailGrid {
    /// 1000 — three columns. iPad Pro 11" landscape (1194) and up.
    static let threeColumnWidth: CGFloat = 1000
    /// 680 — two columns. iPad portrait (834) and split-screen 2/3.
    static let twoColumnWidth: CGFloat = 680

    static func columns(for width: CGFloat) -> Int {
        if width >= threeColumnWidth { return 3 }
        if width >= twoColumnWidth { return 2 }
        return 1
    }
}

private struct DSDetailWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The detail page's measured content width, published by ``DSDetailPage``
    /// and read by ``DSDetailColumns``.
    var dsDetailWidth: CGFloat {
        get { self[DSDetailWidthKey.self] }
        set { self[DSDetailWidthKey.self] = newValue }
    }
}

/// The page frame: plate-backed hero, then the card columns, on the page
/// surface. Mount `DSActionBar` with `.safeAreaInset(edge: .bottom)` at the
/// call site so it pins rather than scrolls (P5 — the audit found the advance
/// on draft prep parked inside a header a 350-row list scrolled away).
struct DSDetailPage<Hero: View, Cards: View>: View {
    /// The page surface. `.clear` lets a call site paint its own backdrop
    /// behind the page — the coach card's locker-room plate is the one screen
    /// that does, and an unconditional opaque fill here painted straight over
    /// it (the image was in the tree and invisible).
    var surface: Color = .backgroundPrimary
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var cards: () -> Cards

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        hero()
                        cards()
                            .padding(.horizontal, DSSpacing.md)
                    }
                    .padding(.bottom, DSSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .environment(\.dsDetailWidth, geo.size.width)
        }
    }
}

/// The subject strip. Full-bleed on `backgroundPlate` — §2.11's value floor, so
/// the working area below reads as lit from within rather than as one flat
/// grey-blue.
struct DSDetailHero<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundPlate)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.surfaceBorder).frame(height: 1)
            }
    }
}

/// Three column slots that collapse by width.
///
///   3 columns   lead | middle | trail
///   2 columns   lead | middle + trail
///   1 column    lead, middle, trail stacked
///
/// The *order within a column* is therefore the same at every width, which is
/// what stops the "same screen, four section orders" problem the player card
/// had. `lead` is where the screen's subject card goes.
struct DSDetailColumns<Lead: View, Middle: View, Trail: View>: View {
    @Environment(\.dsDetailWidth) private var width
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder var lead: () -> Lead
    @ViewBuilder var middle: () -> Middle
    @ViewBuilder var trail: () -> Trail

    /// Falls back to the size class for the first layout pass, before the
    /// geometry reader has published a width — so an iPad opens on two columns
    /// and settles to three rather than snapping up from one.
    private var columnCount: Int {
        width > 0 ? DSDetailGrid.columns(for: width) : (horizontalSizeClass == .regular ? 2 : 1)
    }

    var body: some View {
        switch columnCount {
        case 3:
            HStack(alignment: .top, spacing: DSSpacing.md) {
                column { lead() }
                column { middle() }
                column { trail() }
            }
        case 2:
            HStack(alignment: .top, spacing: DSSpacing.md) {
                column { lead() }
                column { middle(); trail() }
            }
        default:
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                lead(); middle(); trail()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func column<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One grouped card. `SectionHeaderText` head, optional one-line explainer
/// (§2.4 — what this card is and what it does), panel surface, **no border**.
///
/// `isSubject` marks the single bordered, `DSElevation.card`-lifted insert the
/// screen is about (§2.11): the contract on the player card, the scouting
/// report on the prospect card, the projected impact on the coach card. Exactly
/// one per screen.
struct DSDetailCard<Content: View>: View {
    let title: String
    var icon: String?
    var explainer: String?
    var isSubject: Bool = false
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        icon: String? = nil,
        explainer: String? = nil,
        isSubject: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.explainer = explainer
        self.isSubject = isSubject
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xxs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                }
                SectionHeaderText(title: title)
                Spacer(minLength: 0)
            }
            if let explainer {
                // `LocalizedStringKey`, so `**…**` emphasises the load-bearing
                // noun the way §2.4 asks and the way `DSActionBar.Explainer`
                // already does. Rendered as a plain `String` the asterisks
                // printed literally — two of the shipped explainers were
                // already written with them.
                Text(LocalizedStringKey(explainer))
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(DSActionBar.Explainer.spoken(explainer))
            }
            content()
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
        )
        .overlay {
            if isSubject {
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .strokeBorder(Color.accentGold.opacity(0.45), lineWidth: 1)
            }
        }
        .dsElevation(isSubject ? .card : .none)
    }
}

/// `label —————— value`, the one label/value line inside a card.
///
/// Replaces `LabeledContent`, whose `.insetGrouped` chrome is exactly the
/// "stock form" look wave 4 takes off the coach card.
struct DSDetailRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Text(label)
                .font(.system(size: DSType.Size.body))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DSSpacing.xs)
            value()
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 26)
        .accessibilityElement(children: .combine)
    }
}

extension DSDetailRow where Value == Text {
    /// The plain form: a string value in one tint.
    init(_ label: String, _ text: String, tint: Color = .textPrimary, weight: Font.Weight = .semibold) {
        self.label = label
        self.value = {
            Text(text)
                .font(.system(size: DSType.Size.body, weight: weight).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}

/// The small "what this means" line under a figure. Icon + prose in
/// `textTertiaryReadable` — the quietest tier that still clears AA (§2.11).
struct DSDetailNote: View {
    let text: String
    var icon: String = "info.circle"
    var tint: Color = .textTertiaryReadable

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiaryReadable)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Attribute Color Helper

/// Color codes attribute values on the **shared rating ladder**.
///
/// Was a bespoke four-band `switch` (80 green / 60 gold / 40 yellow / red) —
/// one of the 21 rating→Color functions §4 wave 4 retires. It disagreed with
/// `Color.forRating` about every value between 60 and 80, which is where most
/// of a roster lives, so the same 72 was gold in the attribute grid and blue in
/// the OVR circle five inches above it.
private func colorForAttribute(_ value: Int) -> Color {
    Color.forRating(value)
}

// MARK: - Position Compatibility Matrix (#176)

/// Defines which positions a player can realistically convert to based on football sense.
/// Only positions in this map are shown as viable; others are hidden as unrealistic.
private let positionCompatibilityMap: [Position: Set<Position>] = [
    .QB:  [.WR, .RB],
    .WR:  [.RB, .CB, .FS, .SS, .TE],
    .RB:  [.WR, .FB, .FS, .SS],
    .FB:  [.RB, .TE],
    .TE:  [.WR, .FB],
    .LT:  [.LG, .RT, .RG, .C],
    .LG:  [.LT, .C, .RG, .RT],
    .C:   [.LG, .RG],
    .RG:  [.LG, .C, .RT, .LT],
    .RT:  [.RG, .LT, .LG, .C],
    .DE:  [.OLB, .DT],
    .DT:  [.DE],
    .OLB: [.DE, .MLB, .SS],
    .MLB: [.OLB, .SS],
    .CB:  [.FS, .SS, .WR],
    .FS:  [.SS, .CB, .OLB, .WR],
    .SS:  [.FS, .CB, .OLB],
    .K:   [.P],
    .P:   [.K],
]

/// Returns true if converting from `primary` to `target` is a realistic football move.
private func isRealisticConversion(from primary: Position, to target: Position) -> Bool {
    guard let compatible = positionCompatibilityMap[primary] else { return false }
    return compatible.contains(target)
}

// MARK: - Hometown Formatting

/// USPS codes for the states `HometownGenerator` draws from, so the header can
/// say "From Long Beach, CA" instead of spending half the identity line on
/// "California". Presentation only — `HometownDetector` keys its regions off the
/// full state names, which is why the model keeps storing those.
///
/// Anything not in this table (a hand-authored league template, a future state)
/// falls back to its full name rather than being dropped.
private let usStateAbbreviations: [String: String] = [
    "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR",
    "California": "CA", "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE",
    "District of Columbia": "DC", "Florida": "FL", "Georgia": "GA", "Hawaii": "HI",
    "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA",
    "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME",
    "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN",
    "Mississippi": "MS", "Missouri": "MO", "Montana": "MT", "Nebraska": "NE",
    "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM",
    "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH",
    "Oklahoma": "OK", "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI",
    "South Carolina": "SC", "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX",
    "Utah": "UT", "Vermont": "VT", "Virginia": "VA", "Washington": "WA",
    "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
]

/// "From Long Beach, CA" from a city/state pair, or `nil` when there is nothing
/// worth printing. Tolerates either half being missing: pre-hometown saves left
/// both nil, and imported templates sometimes carry a state with no city.
private func hometownDisplayText(city rawCity: String?, state rawState: String?) -> String? {
    let city = rawCity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let state = rawState?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let stateCode = state.isEmpty ? "" : (usStateAbbreviations[state] ?? state)

    switch (city.isEmpty, stateCode.isEmpty) {
    case (false, false): return "From \(city), \(stateCode)"
    case (false, true):  return "From \(city)"
    case (true, false):  return "From \(stateCode)"
    case (true, true):   return nil
    }
}

struct PlayerDetailView: View {
    let player: Player

    // #178: Use @Query to fetch all players for league ranking context
    @Query private var allLeaguePlayersUnscoped: [Player]

    /// All coaches in the league — used to detect scheme mismatch vs the player's team HC.
    @Query private var allCoachesUnscoped: [Coach]

    /// All teams — used together with coaches to look up the player's team scheme.
    @Query private var allTeamsUnscoped: [Team]

    /// All season-history rows in the store. Filtered to this player by
    /// `playerSeasonHistory` below. Recorded by WeekAdvancer at end of week 18.
    @Query(sort: \PlayerSeasonHistory.season) private var allSeasonHistoryUnscoped: [PlayerSeasonHistory]

    /// All persisted draft pick grades. Filtered to this player to render the
    /// Public/True/Gem badge row in the header.
    @Query private var allDraftPickGradesUnscoped: [DraftPickGrade]

    /// Detailed deals, so the cut preview prices a real `Contract` when one
    /// exists rather than always falling back to the engine's proxy.
    @Query private var allContractsUnscoped: [Contract]

    /// The save this screen belongs to — read off the player row itself, so no
    /// career has to be threaded into this view (it is pushed from six places).
    /// `@Query` cannot take a runtime predicate from a stored property, so every
    /// store-wide result above is narrowed here. The league-percentile ranks in
    /// particular were computed against BOTH saves' players before this.
    private var scopeCareerID: UUID? { player.careerID }

    /// The salary cap every money surface on this screen is denominated in
    /// (task #87 / F3, F10): the player's own club's, falling back to the
    /// league's. It used to be three different numbers on one card — a
    /// hardcoded $260M in the Cap-% pill, no cap at all in the Market and
    /// Value pills (`PlayerValueEngine` never took one), and the real cap
    /// only once the user tapped through to `ContractNegotiationView`.
    private var contextSalaryCap: Int {
        allTeams.first { $0.id == player.teamID }?.salaryCap
            ?? allTeams.first?.salaryCap
            ?? ContractEngine.openingSalaryCap
    }
    private var allLeaguePlayers: [Player] { allLeaguePlayersUnscoped.filter { $0.careerID == scopeCareerID } }
    private var allCoaches: [Coach] { allCoachesUnscoped.filter { $0.careerID == scopeCareerID } }
    private var allTeams: [Team] { allTeamsUnscoped.filter { $0.careerID == scopeCareerID } }
    private var allSeasonHistory: [PlayerSeasonHistory] { allSeasonHistoryUnscoped.filter { $0.careerID == scopeCareerID } }
    private var allDraftPickGrades: [DraftPickGrade] { allDraftPickGradesUnscoped.filter { $0.careerID == scopeCareerID } }

    /// This player's detailed deal, when one was ever minted for him.
    private var playerContract: Contract? {
        allContractsUnscoped.first { $0.careerID == scopeCareerID && $0.playerID == player.id }
    }

    /// The career, for the one thing the stat surfaces cannot do without: which
    /// season is being played right now. Week 18 snapshots a season into
    /// `PlayerSeasonHistory` BEFORE the offseason clears
    /// `Player.seasonStatLine`, so without the season number the two sources
    /// would double-count the same year.
    @Query(sort: \Career.currentSeason, order: .reverse) private var careersUnscoped: [Career]

    /// THIS player's save, never "whichever career sorted first".
    private var careers: [Career] { careersUnscoped.filter { $0.id == scopeCareerID } }

    /// TRACK B — true while this man is a rookie from the draft the user just
    /// ran and the calendar has not reached training camp. Read off the save
    /// itself rather than the environment: this screen is pushed from six
    /// places, and the profile is exactly where a curious user would go looking
    /// for the number the roster row is withholding.
    ///
    /// Presentation only. The depth chart, the auto-set, the sim and the
    /// development pass all keep reading his real ratings throughout.
    private var isRookieFogged: Bool {
        guard let career = careers.first else { return false }
        return RookieFog.isFogged(player, season: career.currentSeason, phase: career.currentPhase)
    }

    // Width, not size class, decides the layout (see ``DSDetailGrid``). The
    // horizontal class survives for the two *content* calls below;
    // `verticalSizeClass` is gone with the branches that misread it as
    // "landscape".
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Needed by the contract close: booking a negotiated deal writes the club's
    /// cap ledger and the player's detailed `Contract` row, not just two fields
    /// on the player.
    @Environment(\.modelContext) private var modelContext
    /// The release pops this page. The man is off the roster the moment it
    /// commits, so the list row that pushed us here is gone too — staying put
    /// would leave the user reading a profile of somebody who no longer plays
    /// for him, with a "Cut / Release" bar still on it.
    @Environment(\.dismiss) private var dismiss

    @State private var showCutConfirmation = false

    /// **The one sheet slot on this screen** — an enum, not a `Bool`.
    ///
    /// Repeat bug class: several screens shipped two `.sheet(isPresented:)`
    /// modifiers on one node, SwiftUI honoured only the last written, and the
    /// others dismissed silently. One `item:`-driven slot makes a second sheet
    /// unrepresentable rather than silently resolved.
    private enum CardSheet: String, Identifiable {
        case positionChange
        /// F-58 — the shopping poll. Shares the one slot rather than adding a
        /// second `.sheet` modifier, which is the whole point of the enum.
        case shop
        var id: String { rawValue }
    }

    @State private var activeSheet: CardSheet?

    /// **Which contract conversation is open** (#127).
    ///
    /// Was a bare `showContractNegotiation: Bool` behind a single "Contact
    /// Agent" button. There are two different conversations a club has with its
    /// own player — *pay me less on the deal I have* and *pay me for the years
    /// after it* — and folding them into one door meant the roster card could
    /// only ever open the extension. The pay-cut mode existed (`#102`) but was
    /// reachable from the Cap Compliance workspace alone, so a GM who simply
    /// wanted to reprice a contract had to be over the cap first.
    ///
    /// An `Identifiable` mode rather than two booleans so the presentation stays
    /// on the `item:` form: two `isPresented:` covers on one screen is the shape
    /// that produces a blank sheet when both flip in the same frame.
    private enum ContractTalk: String, Identifiable {
        /// Ask the man already under contract to take less — `#102`'s consent
        /// model, the same one the compliance workspace opens.
        case renegotiate
        /// Buy the years after the current deal — the original Contact Agent
        /// flow.
        case extension_

        var id: String { rawValue }

        var negotiationType: NegotiationType {
            switch self {
            case .renegotiate: return .payCut
            case .extension_:  return .extend
            }
        }
    }

    @State private var contractTalk: ContractTalk?

    /// Real cap space (thousands) for this player's team, used to seed the
    /// agent's opening demand in contract negotiation. Falls back to a nominal
    /// value only if the team can't be resolved.
    private var negotiationCapSpace: Int {
        guard let teamID = player.teamID,
              let team = allTeams.first(where: { $0.id == teamID }) else {
            return 50_000
        }
        return max(0, team.availableCap)
    }

    /// Team accent for the header portrait ring. Falls back to the neutral
    /// border (`nil`) for free agents and unknown clubs.
    private var teamRingColor: Color? {
        guard let teamID = player.teamID,
              let team = allTeams.first(where: { $0.id == teamID }) else { return nil }
        return TeamColors.color(for: team.abbreviation)
    }

    /// True for iPad-class widths. Kept only for the handful of *content*
    /// decisions that still want it (whether the hometown fits on the identity
    /// line); the page's column count comes from ``DSDetailGrid``, measured
    /// width, not from a size class.
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    /// Columns inside an attribute card. Two once there is room, one when the
    /// card is in a single-column page.
    private var attributeColumns: Int {
        isWideLayout ? 2 : 1
    }

    var body: some View {
        DSDetailPage {
            playerHero
        } cards: {
            DSDetailColumns {
                // LEAD — who he is under contract to and what he is worth.
                // The contract card is this screen's subject (§2.11).
                schemeMismatchCard
                contractCard
                overviewCard
                if !isRookieFogged { tradeValueCard }
            } middle: {
                // MIDDLE — what he has done and where he is going.
                developmentCard
                seasonStatsCard
                careerStatsCard
                injuryHistoryCard
            } trail: {
                // TRAIL — what he is made of.
                //
                // TRACK B: a rookie who has not reported to camp has no exact
                // numbers to show, so the whole attribute stack is replaced by
                // the scouting report until he does. The fog gate lives here
                // once, not once per responsive branch.
                if isRookieFogged {
                    preCampScoutingReportCard
                } else {
                    physicalAttributesCard
                    mentalAttributesCard
                    positionAttributesCards
                }
                personalityCard
                schemeFitCard
                versatilityCard
            }
        }
        .safeAreaInset(edge: .bottom) { playerActionBar }
        .navigationTitle(player.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // The default scroll-edge appearance is fully transparent, so scrolling
        // slid the attribute rows straight under the title and they read as
        // colliding with the player's name. Pin an opaque bar in the page's own
        // background colour: content now passes cleanly behind it, and because
        // the colour matches `backgroundPrimary` the bar is invisible at rest.
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: PlayerStatsView(
                    player: player,
                    history: playerSeasonHistory,
                    currentSeason: currentSeason,
                    currentWeek: currentWeek
                )) {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
            }
        }
        .alert("Release Player", isPresented: $showCutConfirmation) {
            // #208 G1: the dialog cannot be the last word on a block — it is
            // re-evaluated here because the roster can move while it is open.
            Button("Release", role: .destructive) { releasePlayer() }
                .disabled(cutBlockReason != nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let reason = cutBlockReason {
                Text("\(reason). Releasing \(player.fullName) would leave the room empty.")
            } else {
                Text("Are you sure you want to release \(player.fullName)? This will remove them from your roster and incur a dead cap hit.")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .positionChange: positionChangeSheet
            case .shop:
                // `careers` is already narrowed to this save, so `first` is the
                // open career and not a guess. No career means no club to shop
                // from, and the button that opens this is gated on the same
                // condition.
                if let career = careers.first {
                    ShopPlayerSheet(
                        player: player,
                        career: career,
                        allPlayers: allLeaguePlayers
                    )
                }
            }
        }
        .fullScreenCover(item: $contractTalk) { talk in
            // ContractNegotiationView supplies its own "Close" toolbar item, so
            // the wrapper must NOT add a second one (that produced "Close Close").
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: talk.negotiationType,
                    teamCapSpace: negotiationCapSpace,
                    onDealCompleted: { offer in
                        // Extension: ADD new years to the existing contract.
                        // Routed through the engine because the two lines this
                        // used to be never touched `team.currentCapUsage`, never
                        // charged the negotiated signing bonus and never updated
                        // the detailed `Contract` row.
                        ContractEngine.applyNegotiatedDeal(
                            player: player,
                            team: allTeams.first(where: { $0.id == player.teamID }),
                            offer: offer,
                            application: .extendExisting,
                            capMode: careers.first?.capMode ?? .simple,
                            careerID: careers.first?.id ?? player.careerID,
                            modelContext: modelContext
                        )
                        try? modelContext.save()
                        // Deliberately NOT dismissing: the agent's closing line and
                        // the signed card render inside the thread, and the user
                        // closes the conversation with the Done button when he has
                        // read them. Auto-exiting here is exactly what made the
                        // handshake invisible before this wave.
                    },
                    // #102's pay-cut payoff, wired the same way the Cap
                    // Compliance workspace wires it: `applyPayCut` is the ONE
                    // place a cut is booked, and the morale delta comes through
                    // from the agent's verdict rather than being re-derived here.
                    onPayCutAgreed: { newSalary, moraleDelta in
                        ContractEngine.applyPayCut(
                            player: player,
                            team: allTeams.first(where: { $0.id == player.teamID }),
                            contract: playerContract,
                            capMode: careers.first?.capMode ?? .simple,
                            salaryCap: contextSalaryCap,
                            newAnnualSalary: newSalary,
                            moraleDelta: moraleDelta
                        )
                        try? modelContext.save()
                    }
                )
            }
        }
    }

    // MARK: - Hero (§4 wave 4)

    /// The subject strip. One hero, one order, at every width — the four
    /// responsive `List` branches this replaces each printed a different one.
    private var playerHero: some View {
        DSDetailHero {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.md) {
                    PersonFaceView(player: player, size: .large, ringColor: teamRingColor)

                    // The screen's one hero numeral (§2.10: the most important
                    // number on a screen is the biggest one on it).
                    VStack(spacing: DSSpacing.xxs) {
                        ZStack(alignment: .topTrailing) {
                            Circle()
                                .strokeBorder(
                                    isRookieFogged
                                        ? RookieFog.source(for: player).tint
                                        : Color.forRating(player.overall),
                                    lineWidth: 3
                                )
                                .frame(width: 76, height: 76)
                            VStack(spacing: 0) {
                                if isRookieFogged {
                                    // The band his scouts filed, not a number
                                    // nobody in the building has earned yet.
                                    Text(RookieFog.bandText(for: player))
                                        .font(.system(size: DSType.Size.title2, weight: .heavy))
                                        .foregroundStyle(RookieFog.source(for: player).tint)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                        .padding(.horizontal, DSSpacing.xxs)
                                    Text("GRADE")
                                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(Color.textTertiaryReadable)
                                } else {
                                    Text("\(player.overall)")
                                        .font(.system(size: DSType.Size.title1, weight: .heavy).monospacedDigit())
                                        .foregroundStyle(Color.forRating(player.overall))
                                    Text("OVR")
                                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(Color.textTertiaryReadable)
                                }
                            }
                            .frame(width: 76, height: 76)

                            // Career trend arrow — shows whether the player is rising,
                            // in prime, or declining based on age vs position peak window.
                            Image(systemName: careerTrendArrow.icon)
                                .font(.system(size: DSType.Size.caption, weight: .heavy))
                                .foregroundStyle(Color.backgroundPlate)
                                .padding(DSSpacing.xxs)
                                .background(careerTrendArrow.color, in: Circle())
                                .accessibilityLabel("Career trend: \(careerTrendArrow.label)")
                                .offset(x: 4, y: -4)
                        }
                        // League ranking (#33). Withheld while the rookie is
                        // fogged: "#3 QB" is the hidden number read back out
                        // through the league sort.
                        if let rankInfo = leagueRanking, !isRookieFogged {
                            Text(rankInfo)
                                .font(.system(size: DSType.Size.caption, weight: .heavy))
                                .foregroundStyle(Color.backgroundPlate)
                                .padding(.horizontal, DSSpacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.accentGold, in: Capsule())
                        }
                    }

                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        HStack(spacing: DSSpacing.xs) {
                            positionLabel
                            developmentBadge
                        }

                        Text(player.fullName)
                            .font(.system(size: DSType.Size.title2, weight: .bold))
                            .foregroundStyle(Color.textPrimary)

                        // WHOSE player this is. The league browser makes every
                        // one of the ~1 700 players in the save reachable here,
                        // and until this chip existed a rival's page was pixel-
                        // identical to one of our own — same layout, same top
                        // bar still reading our abbreviation — so the screen
                        // silently implied Joe Burrow was on our roster.
                        teamAffiliationChip

                        HStack(spacing: DSSpacing.sm) {
                            Label("Age \(player.age)", systemImage: "calendar")
                            Label(
                                player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro)yr pro",
                                systemImage: "figure.american.football"
                            )
                            // iPad has the width to keep "where he's from" on the
                            // same identity line; compact widths would truncate
                            // both it and "9yr pro", so there it drops below.
                            if isWideLayout {
                                hometownLabel
                            }
                        }
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)

                        if !isWideLayout {
                            hometownLabel
                                .font(.system(size: DSType.Size.footnote))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                // Draft grade badges (Public / True / Hidden Gem) — only shown
                // when the player was actually drafted and has a persisted grade.
                draftBadgeRow

                // Health is the ONLY figure left in the hero strip.
                //
                // Morale, motivation, salary and contract used to sit here too,
                // and all four were restated ~35pt below in the Overview and
                // Contract cards — in a DIFFERENT encoding (hero "68" vs card
                // "OK"), so the same fact read as two facts that disagreed.
                // They now live only in their cards; health is the one hero
                // number no card repeats.
                healthPill
            }
        }
    }

    /// The club this player is actually under contract to. `nil` for a free agent.
    private var playerTeam: Team? {
        guard let teamID = player.teamID else { return nil }
        return allTeams.first { $0.id == teamID }
    }

    /// True when this page is showing somebody ELSE's player — the case the
    /// header has to say out loud. False for our own men and (deliberately)
    /// for saves that have no team yet, where "rival" means nothing.
    private var isRivalPlayer: Bool {
        guard let userTeamID = careers.first?.teamID,
              let teamID = player.teamID else { return false }
        return teamID != userTeamID
    }

    /// Team affiliation, printed only when it is NOT the obvious one: a rival's
    /// club (team-coloured, named in full, with their record) or free agency.
    /// Our own players get nothing — the whole screen is already ours.
    @ViewBuilder
    private var teamAffiliationChip: some View {
        if isRivalPlayer, let team = playerTeam {
            let tint = TeamColors.color(for: team.abbreviation)
            HStack(spacing: 6) {
                Text(team.abbreviation)
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                Text(team.fullName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(team.record)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .strokeBorder(tint.opacity(0.55), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Plays for \(team.fullName), record \(team.record)")
        } else if player.teamID == nil {
            Text("FREE AGENT")
                .font(.system(size: DSType.Size.micro, weight: .heavy))
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentGold, in: Capsule())
        }
    }

    /// The hero strip's one surviving figure (see `playerHero`).
    private var healthPill: some View {
        HStack(spacing: 6) {
            Image(systemName: player.isInjured ? "cross.case.fill" : "heart.fill")
                .font(.system(size: DSType.Size.micro, weight: .bold))
            Text(
                player.isInjured
                    ? "Injured — \(player.injuryWeeksRemaining) wk\(player.injuryWeeksRemaining == 1 ? "" : "s") out"
                    : "Healthy"
            )
            .font(.caption.weight(.bold))
            Spacer(minLength: 0)
            Text("HEALTH")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
        }
        .foregroundStyle(player.isInjured ? Color.danger : Color.success)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
        .accessibilityElement(children: .combine)
    }

    /// Where the player is from, for the header identity block. Renders nothing
    /// at all when no hometown is recorded — the field only started being written
    /// recently, so every player in an older save still has it nil and must not
    /// leave a stray pin icon behind.
    @ViewBuilder
    private var hometownLabel: some View {
        if let hometown = hometownDisplayText(city: player.hometownCity, state: player.hometownState) {
            Label(hometown, systemImage: "mappin.and.ellipse")
                .lineLimit(1)
                .accessibilityLabel("Hometown: \(hometown.dropFirst("From ".count))")
        }
    }

    // MARK: - Draft Grade Badges (Vaihe 5)

    /// Badge row showing Public Grade, True Grade and Hidden-Gem indicator for
    /// drafted players. Hidden when the player wasn't drafted or has no
    /// persisted `DraftPickGrade` entry.
    @ViewBuilder
    private var draftBadgeRow: some View {
        if player.draftPickNumber != nil,
           let grade = allDraftPickGrades.first(where: { $0.playerID == player.id }) {
            HStack(spacing: 12) {
                gradeBadge(label: "Public", grade: grade.publicGrade)
                if let trueGrade = grade.trueGrade {
                    gradeBadge(label: "True", grade: trueGrade)
                }
                if grade.isGem {
                    Text("💎 Hidden Gem")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.draftStealGold.opacity(0.25))
                        .foregroundStyle(Color.draftStealGold)
                        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                }
                if grade.isBust {
                    Text("BUST")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.draftReachRed.opacity(0.25))
                        .foregroundStyle(Color.draftReachRed)
                        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                }
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func gradeBadge(label: String, grade: PickGrade) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(grade.rawValue)
                .font(.caption.weight(.heavy))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor(grade))
                .foregroundStyle(Color.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.tight))
        }
    }

    private func badgeColor(_ grade: PickGrade) -> Color {
        switch grade {
        case .stealAPlus, .hofTrack: return Color.draftStealGold
        case .smartA:                return Color.success
        case .solid:                 return Color.draftSolidNeutral
        case .reach:                 return Color.warning
        case .bigReach:              return Color.draftReachRed
        }
    }

    private var quickStatDivider: some View {
        Rectangle()
            .fill(Color.surfaceBorder)
            .frame(width: 1, height: 24)
    }

    // MARK: - Overview + Contract (#39, #31)

    /// Where he is on the roster right now.
    private var overviewCard: some View {
        DSDetailCard(
            "Overview",
            icon: "person.text.rectangle",
            explainer: "How he feels about the building, and what that is doing to him."
        ) {
            overviewCardBody
        }
    }

    /// The screen's **subject** (§2.11): the deal. This is the one bordered,
    /// lifted insert on the player card — every management action on the bar
    /// below spends against it.
    private var contractCard: some View {
        DSDetailCard(
            "Contract",
            icon: "doc.text",
            explainer: "What he costs the cap, what the market says he is worth, and what is still owed.",
            isSubject: true
        ) {
            contractCardBody
        }
    }

    private var overviewCardBody: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                if isRookieFogged {
                    compactInfoPill(
                        label: "Grade",
                        value: RookieFog.bandText(for: player),
                        color: RookieFog.source(for: player).tint
                    )
                } else {
                    compactInfoPill(label: "OVR", value: "\(player.overall)", color: Color.forRating(player.overall))
                }
                compactInfoPill(label: "Morale", value: moraleDisplayLabel, color: moraleColor)
                // Motivation sits beside morale on purpose: morale is how he
                // feels about the building, motivation is what he does about it
                // (plan §2.10). This card renders in all three layouts.
                motivationPill
                compactInfoPill(label: "Age", value: "\(player.age)", color: .textPrimary)
                compactInfoPill(label: "Exp", value: player.yearsPro == 0 ? "R" : "\(player.yearsPro)yr", color: .textSecondary)
            }

            // Morale impact tooltip — explains how the morale score affects gameplay (#40).
            DSDetailNote(text: moraleImpactDescription)

            // What his motivation state actually means for development.
            DSDetailNote(
                text: player.motivationState.summary,
                icon: player.motivationState.icon,
                tint: motivationColor
            )

            if player.isInjured {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "cross.circle.fill")
                        .font(.system(size: DSType.Size.caption))
                    Text("Injured — \(player.injuryWeeksRemaining) wk\(player.injuryWeeksRemaining == 1 ? "" : "s")")
                        .font(.system(size: DSType.Size.footnote, weight: .semibold))
                }
                .foregroundStyle(Color.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contractCardBody: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                compactInfoPill(
                    label: "Years",
                    value: "\(player.contractYearsRemaining)",
                    color: player.contractYearsRemaining <= 1 ? .warning : .textPrimary
                )
                compactInfoPill(label: "Salary", value: formattedSalary, color: .textSecondary)
                compactInfoPill(label: "Cap %", value: capPercentageText, color: capPercentageColor)
                compactInfoPill(label: "Market", value: estimatedMarketValue, color: marketValueComparison.color)
                compactInfoPill(label: "Value", value: marketValueComparison.label, color: marketValueComparison.color)
            }

            // The gap between the Market and Salary pills, and the band the
            // Value pill is testing them against.
            if let marketGapNote {
                DSDetailNote(
                    text: marketGapNote,
                    icon: marketValueComparison.icon,
                    tint: marketValueComparison.color
                )
            }

            // Market comparables strip — contextualizes the player's salary against
            // top-N peers at the same position (#39).
            if let comparables = marketComparablesText {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                    Text(comparables)
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            // Year-by-year cap hit breakdown for multi-year contracts.
            // Approximated from base salary with a typical 6%/yr escalator until a
            // full Contract object is wired through to this view.
            let yearly = yearByYearCapHits
            if !yearly.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiary)
                        Text("Year-by-Year")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    ForEach(yearly, id: \.year) { row in
                        HStack(spacing: 4) {
                            Text("Yr \(row.year)")
                                .font(.system(size: DSType.Size.micro))
                                .foregroundStyle(Color.textTertiary)
                                .frame(width: 28, alignment: .leading)
                            // Mini bar visualizing relative cap hit.
                            GeometryReader { geo in
                                let maxHit = max(yearly.map { $0.capHitK }.max() ?? 1, 1)
                                let frac = CGFloat(row.capHitK) / CGFloat(maxHit)
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.surfaceBorder.opacity(0.4))
                                    Capsule()
                                        .fill(Color.accentGold.opacity(0.7))
                                        .frame(width: geo.size.width * frac)
                                }
                            }
                            .frame(height: 4)
                            Text(formatCapHit(row.capHitK))
                                .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 2)
            }

            // Performance clauses and how far along they are (TODO §5.5).
            incentiveProgressBlock

            if player.isFranchiseTagged {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                    // #127: the money above this line is his CURRENT deal, which
                    // the tag no longer overwrites — it runs to the end of this
                    // league year and the tag replaces it in the next one. So the
                    // badge has to name the year and the number, or a card that
                    // says "Franchise Tagged" over last season's salary reads as
                    // the tag having cost that.
                    Text(franchiseTagBadgeText)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Color.accentGold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Incentive Clauses (TODO §5.5)

    /// Live tier progress for the clauses on this player's deal.
    ///
    /// Read straight off the season the player is currently accumulating
    /// (`Player.seasonStatLine` plus the games counter), which is the same
    /// source `ContractEngine.evaluateIncentives` grades at rollover — so what
    /// the card shows in week 12 is what the settlement will pay in week 18.
    ///
    /// The playoff clause is passed `reachedPlayoffs: false` on purpose: this
    /// screen has no bracket, and a berth that has not happened yet is honestly
    /// rendered as pending rather than guessed at.
    private var incentiveClauses: [IncentiveProgress] {
        ContractEngine.liveIncentiveProgress(for: player)
    }

    @ViewBuilder
    private var incentiveProgressBlock: some View {
        let clauses = incentiveClauses
        if !clauses.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.accentGold)
                    Text("Incentives")
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    let earnedK = clauses.filter(\.isEarned).reduce(0) { $0 + $1.incentive.bonusK }
                    if earnedK > 0 {
                        Text("\(formatCapHit(earnedK)) earned")
                            .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.success)
                    }
                }

                ForEach(clauses) { progress in
                    incentiveClauseRow(progress)
                }

                // The motivation link: what chasing this money does to his head.
                if let note = MotivationState.incentiveChaseNote(for: player) {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "flame")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.accentGold)
                        Text(note)
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 1)
                }
            }
            .padding(.top, 2)
        }
    }

    private func incentiveClauseRow(_ progress: IncentiveProgress) -> some View {
        let category = progress.incentive.category
        let detail: String = category.isBinary
            ? (progress.isEarned ? "Clinched" : "Pending")
            : "\(category.format(progress.achieved)) / \(category.format(progress.incentive.threshold))"

        return HStack(spacing: 4) {
            Text(category.shortName)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 46, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.surfaceBorder.opacity(0.4))
                    Capsule()
                        .fill(progress.isEarned ? Color.success : Color.accentGold.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(progress.fraction))
                }
            }
            .frame(height: 4)

            Text(detail)
                .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                .foregroundStyle(progress.isEarned ? Color.success : Color.textSecondary)
                .frame(width: 72, alignment: .trailing)

            Text(ContractIncentive.money(progress.incentive.bonusK))
                .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.displayName): \(detail), worth \(ContractIncentive.money(progress.incentive.bonusK))")
    }

    /// Player's salary as a percentage of the league cap (#38). Reads the club's
    /// ACTUAL cap — it was hardcoded to $260M, a number that appears nowhere else
    /// in the game and over-reported by ~31 % by season five (task #87 / F10).
    /// Falls back to "—" when salary is zero.
    private var capPercentageText: String {
        guard player.annualSalary > 0 else { return "—" }
        let pct = Double(player.annualSalary) / Double(contextSalaryCap) * 100.0
        return String(format: "%.1f%%", pct)
    }

    private var capPercentageColor: Color {
        let pct = Double(player.annualSalary) / Double(contextSalaryCap) * 100.0
        if pct >= 12 { return .danger }
        if pct >= 7  { return .warning }
        return .textSecondary
    }

    /// Top-paid peers at this position for market context (#39).
    /// Returns text like "Top 5 QB: $30-55M".
    private var marketComparablesText: String? {
        let peers = allLeaguePlayers
            .filter { $0.position == player.position && $0.id != player.id && $0.annualSalary > 0 }
            .sorted { $0.annualSalary > $1.annualSalary }
            .prefix(5)
        guard peers.count >= 2 else { return nil }
        let salaries = peers.map { $0.annualSalary }
        guard let lo = salaries.last, let hi = salaries.first else { return nil }
        let loM = Double(lo) / 1_000.0
        let hiM = Double(hi) / 1_000.0
        return String(format: "Top 5 %@: $%.1fM–$%.1fM", player.position.rawValue, loM, hiM)
    }

    private func compactInfoPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Text(value)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
    }

    // MARK: - Development (#39)

    /// Where he is on the age curve, and what the staff thinks he still has.
    ///
    /// §4 wave 4 asks development/status cards to state *which* staff read this
    /// is and *what* it does, because "Coach's Projection: High Upside" over an
    /// unexplained bar told the user neither.
    private var developmentCard: some View {
        DSDetailCard(
            "Development",
            icon: developmentPhase.icon,
            explainer: developmentExplainer
        ) {
            developmentCardBody
        }
    }

    /// §4 wave 4: a development card has to name **which coach** is doing the
    /// work, not "your position coach". The man named here is the one the
    /// offseason pass actually hands the evaluation to — same lookup, so the
    /// card cannot credit a coach the engine did not consult.
    private var developmentExplainer: String {
        let curve = "Every \(player.position.rawValue) peaks between \(player.position.peakAgeRange.lowerBound) and \(player.position.peakAgeRange.upperBound). The marker is his age on that curve"
        guard let coach = positionCoach else {
            return "\(curve). With no \(player.position.rawValue) coach on staff, the projection below is the building's guess and stays a band wider than it needs to be."
        }
        return "\(curve); the projection under it is **\(coach.role.displayName) \(coach.lastName)**'s read, rewritten every camp. The better he develops players, the sooner that read narrows."
    }

    /// The coach who develops this player and writes his ceiling projection.
    ///
    /// `PlayerDevelopmentEngine.resolvePositionCoach` rather than a hand-rolled
    /// role match: it is the same call `assessedPotentialLabel` is given at
    /// camp, including its strength-coach tiebreak, so the name on the card is
    /// the evaluator whose `playerDevelopment` shrank the noise on the label
    /// printed two rows below it.
    private var positionCoach: Coach? {
        guard let teamID = player.teamID else { return nil }
        return PlayerDevelopmentEngine.resolvePositionCoach(
            coaches: allCoaches.filter { $0.teamID == teamID },
            position: player.position
        )
    }

    private var developmentCardBody: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xxs) {
                Text(developmentPhase.label.uppercased())
                    .font(.system(size: DSType.Size.caption, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(developmentPhase.color)
                Spacer(minLength: DSSpacing.xxs)
                Text("PEAK \(player.position.peakAgeRange.lowerBound)–\(player.position.peakAgeRange.upperBound)")
                    .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiaryReadable)
            }

            // The age curve: track, peak window, and where he stands on it.
            GeometryReader { geo in
                let width = geo.size.width
                let minAge = 21
                let maxAge = 40
                let range = CGFloat(maxAge - minAge)
                let peakStart = CGFloat(player.position.peakAgeRange.lowerBound - minAge) / range
                let peakEnd = CGFloat(player.position.peakAgeRange.upperBound - minAge) / range
                let currentPos = CGFloat(player.age - minAge) / range

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.backgroundTertiary)
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.success.opacity(0.4))
                        .frame(width: (peakEnd - peakStart) * width, height: 6)
                        .offset(x: peakStart * width)
                    Circle()
                        .fill(developmentPhase.color)
                        .frame(width: 10, height: 10)
                        .offset(x: min(max(currentPos * width - 5, 0), width - 10))
                }
            }
            .frame(height: 10)
            .accessibilityLabel("Age \(player.age) on a curve that peaks at \(player.position.peakAgeRange.lowerBound) to \(player.position.peakAgeRange.upperBound). \(developmentPhase.label)")

            Text(trajectoryDescription)
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiaryReadable)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Coach's Projection (plan §2.9.4 / §2.10): the STAFF's read on
            // his ceiling, not the hidden number. Noise shrinks the longer
            // he has been in the building, and a plateaued player reads a
            // band lower than his true potential suggests.
            coachProjectionRow
        }
    }

    /// The staff's ceiling projection, written every camp by the development
    /// engine. Hidden entirely until a camp has run on this player (legacy
    /// saves and just-signed free agents have nothing to show yet).
    @ViewBuilder
    private var coachProjectionRow: some View {
        if let label = assessedPotentialLabel {
            HStack(spacing: 6) {
                Image(systemName: "binoculars.fill")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.accentGold)
                Text(coachProjectionTitle)
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: DSSpacing.xxs)
                Text(label.displayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(potentialLabelColor(label))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(potentialLabelColor(label).opacity(0.15))
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            DSDetailNote(text: coachProjectionNote, icon: "binoculars")
        }
    }

    /// Whose projection this is. "Coach's Projection" over an unattributed
    /// band was the wave-4 complaint in one line: the reader could not tell
    /// whether it was a scout, the head coach or the model talking.
    private var coachProjectionTitle: String {
        guard let coach = positionCoach else { return "Staff Projection" }
        return "\(coach.role.abbreviation) \(coach.lastName)'s Projection"
    }

    /// What the band is and what moves it — a projection with no statement of
    /// its own accuracy is a verdict with no evidence.
    private var coachProjectionNote: String {
        guard let coach = positionCoach else {
            return "No position coach for this group, so the projection is the building's rough read. Hire one and it sharpens every camp."
        }
        return "His ceiling as \(coach.lastName) sees it, rewritten every camp. A stronger developer (\(coach.lastName): \(coach.playerDevelopment) player development) reads it right sooner; a player who has stopped moving reads a band low."
    }

    /// Persisted staff assessment, decoded from `Player.assessedPotential`.
    private var assessedPotentialLabel: PotentialLabel? {
        guard let raw = player.assessedPotential, !raw.isEmpty else { return nil }
        return PotentialLabel(rawValue: raw)
    }

    private func potentialLabelColor(_ label: PotentialLabel) -> Color {
        switch label {
        case .eliteCeiling:  return .success
        case .highUpside:    return .accentGold
        case .solidStarter:  return .accentBlue
        case .average:       return .textSecondary
        case .limitedUpside: return .warning
        case .unknown:       return .textTertiary
        }
    }

    // MARK: - Season Stats Summary (#36)

    /// The season the league is playing, and how far into it. `nil` only when no
    /// career row exists (previews).
    private var currentSeason: Int? { careers.first?.currentSeason }
    private var currentWeek: Int? { careers.first?.currentWeek }

    /// The finished snapshot for the current season, once week 18 has written it.
    /// While it exists, it — not the live accumulator — is the season of record.
    private var currentSeasonHistoryRow: PlayerSeasonHistory? {
        guard let currentSeason else { return nil }
        return playerSeasonHistory.last { $0.season == currentSeason }
    }

    /// This season's production. Two real sources, never both:
    /// `Player.seasonStatLine` while the season runs, the history snapshot after
    /// week 18 closes it.
    private var seasonLine: SeasonStatLine {
        currentSeasonHistoryRow?.statLine ?? player.seasonStatLine
    }

    private var seasonGamesPlayed: Int {
        currentSeasonHistoryRow?.gamesPlayed ?? player.gamesPlayedThisSeason
    }

    private var seasonGamesStarted: Int {
        currentSeasonHistoryRow?.gamesStarted ?? player.gamesStartedThisSeason
    }

    @ViewBuilder
    private var seasonStatsCard: some View {
        let line = seasonLine
        let gamesPlayed = seasonGamesPlayed
        // Genuinely empty = no appearances AND an all-zero line. A player who
        // dressed and produced nothing has a real stat line of zeros, and gets
        // the numbers rather than the "nothing recorded" note.
        let isEmpty = gamesPlayed == 0 && line.isEmpty

        DSDetailCard(
            currentSeason.map { "\(String($0)) Season Stats" } ?? "Season Stats",
            icon: "chart.bar.fill"
        ) {
            if !isEmpty {
                HStack(spacing: 0) {
                    seasonQuickStat(label: "GP", value: "\(gamesPlayed)")
                    quickStatDivider
                    seasonQuickStat(label: "GS", value: "\(seasonGamesStarted)")

                    switch player.position {
                    case .QB:
                        quickStatDivider
                        seasonQuickStat(label: "Pass Yds", value: "\(line.passYards)")
                        quickStatDivider
                        seasonQuickStat(label: "TD", value: "\(line.passTDs)", highlight: line.passTDs > 0)
                        quickStatDivider
                        seasonQuickStat(label: "INT", value: "\(line.passInts)", negative: line.passInts > 5)

                    case .RB, .FB:
                        quickStatDivider
                        seasonQuickStat(label: "Rush Yds", value: "\(line.rushYards)")
                        quickStatDivider
                        seasonQuickStat(label: "Rush TD", value: "\(line.rushTDs)", highlight: line.rushTDs > 0)
                        quickStatDivider
                        seasonQuickStat(label: "Rec", value: "\(line.receptions)")

                    case .WR, .TE:
                        quickStatDivider
                        seasonQuickStat(label: "Rec", value: "\(line.receptions)")
                        quickStatDivider
                        seasonQuickStat(label: "Rec Yds", value: "\(line.recYards)")
                        quickStatDivider
                        seasonQuickStat(label: "Rec TD", value: "\(line.recTDs)", highlight: line.recTDs > 0)

                    case .LT, .LG, .C, .RG, .RT:
                        // No counting stats exist for the interior — snaps are it.
                        quickStatDivider
                        seasonQuickStat(label: "Snaps", value: "\(line.snapsPlayed)")

                    case .DE, .DT, .OLB, .MLB:
                        quickStatDivider
                        seasonQuickStat(label: "Tackles", value: "\(line.tackles)")
                        quickStatDivider
                        seasonQuickStat(label: "Sacks", value: String(format: "%.1f", line.sacks), highlight: line.sacks > 0)
                        quickStatDivider
                        seasonQuickStat(label: "INT", value: "\(line.defInts)", highlight: line.defInts > 0)

                    case .CB, .FS, .SS:
                        quickStatDivider
                        seasonQuickStat(label: "Tackles", value: "\(line.tackles)")
                        quickStatDivider
                        seasonQuickStat(label: "INT", value: "\(line.defInts)", highlight: line.defInts > 0)
                        quickStatDivider
                        seasonQuickStat(label: "PD", value: "\(line.passesDefended)")

                    case .K:
                        quickStatDivider
                        seasonQuickStat(label: "FGM", value: "\(line.fieldGoalsMade)")
                        quickStatDivider
                        seasonQuickStat(label: "FGA", value: "\(line.fieldGoalsAttempted)")

                    case .P:
                        quickStatDivider
                        seasonQuickStat(label: "Punts", value: "\(line.punts)")
                        quickStatDivider
                        seasonQuickStat(label: "Avg", value: String(format: "%.1f", line.puntAverage))
                    }
                }
                .padding(.vertical, 6)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
            } else {
                // #179: only shown when the season really has nothing to show —
                // and it says why, so an offseason zero doesn't read as a bug.
                // Uses the shared compact empty-state so it matches every other
                // "nothing here yet" surface rather than being a bare line.
                CompactEmptyStateView(icon: "chart.bar", message: seasonEmptyNote)
            }
        }
    }

    /// Why the season summary is empty, in the user's terms.
    private var seasonEmptyNote: String {
        if let week = currentWeek, week == 0 {
            return "Season hasn't kicked off yet"
        }
        if player.isRetired {
            return "Retired — see the career table below"
        }
        return "No games played this season"
    }

    private func seasonQuickStat(label: String, value: String, highlight: Bool = false, negative: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(
                    negative ? Color.danger :
                    highlight ? Color.success :
                    Color.textPrimary
                )
            Text(label)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Career Stats by Season

    /// History rows for this player, oldest → newest. Empty only for a true
    /// rookie: every veteran opens his career with a past (a template career
    /// arc, or the random league's synthesized backstory).
    private var playerSeasonHistory: [PlayerSeasonHistory] {
        allSeasonHistory.filter { $0.playerID == player.id }
    }

    /// Rows of the career table for this player: the season in progress, every
    /// finished season, its playoff sub-line, and the career-total summary. Built
    /// by `CareerTableBuilder` so this section and `PlayerStatsView`'s "By Season"
    /// tab can never drift apart.
    private var careerTableRows: [CareerSeasonRow] {
        CareerTableBuilder.rows(
            player: player,
            history: playerSeasonHistory,
            currentSeason: currentSeason
        )
    }

    /// Per-season career table: `Season | Age | OVR | GP | <position stats>`,
    /// closed by a CAREER totals row.
    ///
    /// Always expanded — this is the page's main development story, not a detail
    /// worth hiding behind a chevron, and the single OVR column carries the trend
    /// the old bar chart used to duplicate.
    @ViewBuilder
    private var careerStatsCard: some View {
        // Built once per render pass: `playerSeasonHistory` filters every history
        // row in the store, so this is not a property to touch three times.
        let rows = careerTableRows
        if !rows.isEmpty {
            DSDetailCard("Career Stats by Season", icon: "tablecells") {
                // `CareerStatTable` keeps its FIXED column widths — they are what
                // makes the season rows line up with `PlayerStatsView`'s "By
                // Season" tab. A card column is narrower than a full-width List
                // row was, so the table gets its own horizontal scroller rather
                // than having its columns squeezed into each other (§2.13,
                // Columns gate).
                ScrollView(.horizontal, showsIndicators: false) {
                    CareerStatTable(position: player.position, rows: rows)
                        .frame(minWidth: 380, alignment: .leading)
                        .padding(.vertical, DSSpacing.xxs)
                }
                if let note = careerTableNote(rows: rows) {
                    Text(note)
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Footnote for the two row kinds that need one. Nil when the table is a
    /// plain list of finished seasons.
    private func careerTableNote(rows: [CareerSeasonRow]) -> String? {
        var parts: [String] = []
        if rows.contains(where: { $0.kind == .inProgress }) {
            parts.append("* season in progress")
        }
        if rows.contains(where: { $0.kind == .postseason }) {
            parts.append("playoff lines shown separately, not in the career total")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Trade Value (#37)

    private var tradeValueCard: some View {
        DSDetailCard(
            "Trade Value",
            icon: "arrow.left.arrow.right",
            explainer: "What the league's other 31 war rooms would give up for him — the same points `TradeValueEngine` prices a package in."
        ) {
            tradeValueCardBody
        }
    }

    private var tradeValueCardBody: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.sm) {
                VStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: DSType.Size.title2))
                        .foregroundStyle(tradeValueColor)
                    Text(tradeValueLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tradeValueColor)
                        .multilineTextAlignment(.center)
                    // The engine's actual number, in the currency the war room
                    // and the Trade Center already quote. The bucket alone was
                    // a translation of a figure the game refused to show, so a
                    // package could not be checked against it by hand.
                    Text("~\(tradeValuePoints) pts")
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(width: 90)

                VStack(alignment: .leading, spacing: 4) {
                    // Signed magnitudes, straight off the multipliers
                    // `TradeValueEngine.playerTradeValue` actually multiplies —
                    // the rows used to be three identical ⊕ marks that implied
                    // equal weight for factors worth ±30 %, ±40 % and ±25 %.
                    tradeValueFactorRow(
                        label: "Base (OVR)",
                        detail: "\(player.overall) OVR",
                        magnitude: "\(tradeValueBasePoints) pts",
                        tone: player.overall >= 75 ? .up : .flat
                    )
                    tradeValueFactorRow(
                        label: "Position",
                        detail: player.position.rawValue,
                        magnitude: multiplierText(TradeValueEngine.positionMultiplier(player.position)),
                        tone: tone(for: TradeValueEngine.positionMultiplier(player.position))
                    )
                    tradeValueFactorRow(
                        label: "Age",
                        detail: "\(player.age)yr",
                        magnitude: multiplierText(tradeValueAgeMultiplier),
                        tone: tone(for: tradeValueAgeMultiplier)
                    )
                    tradeValueFactorRow(
                        label: "Contract",
                        detail: "\(player.contractYearsRemaining)yr / \(formattedSalary)",
                        magnitude: multiplierText(tradeValueContractMultiplier),
                        tone: tone(for: tradeValueContractMultiplier)
                    )
                    if player.isInjured {
                        tradeValueFactorRow(
                            label: "Injury",
                            detail: "\(player.injuryWeeksRemaining) wk out",
                            magnitude: "untradeable",
                            tone: .down
                        )
                    }
                }
            }

            // F-58: the way out of this card.
            //
            // The card has priced him for two waves and offered no way to act on
            // the price — "Trade For" exists on a RIVAL's card and there was
            // nothing at all on one of your own, so shopping your own player
            // meant guessing a partner in the Trade Center's partner-first
            // builder first. This asks all 31 clubs instead.
            //
            // It sits in the card rather than on the action bar deliberately:
            // the bar's four slots are the four things that CHANGE this player's
            // situation (release, position, and the two contract conversations),
            // and a poll changes nothing. It belongs next to the valuation it
            // acts on (P5 — the bar is for commits).
            if isUserRosterPlayer {
                Divider().overlay(Color.surfaceBorder)
                Button { activeSheet = .shop } label: {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: DSType.Size.footnote, weight: .semibold))
                        Text("Shop \(player.lastName)")
                            .font(DSType.text(DSType.Size.body, .semibold))
                        Spacer(minLength: 0)
                        if TradeBlockStore.shared.isListed(player.id) {
                            DSStatusPill(label: "On the block", tone: .info, showsDot: false)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .foregroundStyle(Color.accentBlue)
                    .padding(.horizontal, DSSpacing.xs)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shop \(player.fullName)")
                .accessibilityHint("Asks all 31 clubs what they would pay for him")
            }

            // "If this player leaves" replacement preview (#37) — shows the next-best player
            // on the same team at the same position so the user understands the depth-chart
            // impact of cutting / trading.
            if let replacement = replacementPlayerInfo {
                Divider().overlay(Color.surfaceBorder)
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "person.fill.questionmark")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textTertiaryReadable)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("If \(player.lastName) leaves")
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text(replacement)
                            .font(.system(size: DSType.Size.caption).monospacedDigit())
                            .foregroundStyle(Color.textTertiaryReadable)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Comparable players in the league at the same position with similar OVR (±3).
            // Helps anchor the player's trade value against real peers and their salaries.
            if let comparables = comparablesText {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textTertiaryReadable)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Comparables")
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text("Similar: \(comparables)")
                            .font(.system(size: DSType.Size.caption).monospacedDigit())
                            .foregroundStyle(Color.textTertiaryReadable)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Next-best player on the same team at the same position, used for the
    /// "if cut/traded" depth-chart preview (#37).
    /// Returns text like "Smith starts at QB — 71 OVR (-13)".
    private var replacementPlayerInfo: String? {
        guard let teamID = player.teamID else { return nil }
        let teammates = allLeaguePlayers
            .filter { $0.teamID == teamID && $0.position == player.position && $0.id != player.id }
            .sorted { $0.overall > $1.overall }
        guard let next = teammates.first else {
            return "No backup on roster — would need free agent / draft pick"
        }
        let delta = next.overall - player.overall
        let deltaText: String
        if delta > 0 { deltaText = "+\(delta)" }
        else if delta < 0 { deltaText = "\(delta)" }
        else { deltaText = "±0" }
        return "\(next.lastName) starts at \(player.position.rawValue) — \(next.overall) OVR (\(deltaText))"
    }

    /// Which way a factor pushes the player's price.
    private enum FactorTone {
        case up, flat, down

        var icon: String {
            switch self {
            case .up:   return "plus.circle.fill"
            case .flat: return "equal.circle.fill"
            case .down: return "minus.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .up:   return .success
            case .flat: return .textTertiary
            case .down: return .danger
            }
        }
    }

    private static let flatMultiplierBand = 0.005

    private func tone(for multiplier: Double) -> FactorTone {
        if multiplier > 1.0 + Self.flatMultiplierBand { return .up }
        if multiplier < 1.0 - Self.flatMultiplierBand { return .down }
        return .flat
    }

    /// "×1.30 (+30 %)" — the multiplier AND the plain-language swing, because
    /// the second is what a GM reads and the first is what the engine applies.
    private func multiplierText(_ multiplier: Double) -> String {
        let percent = Int(((multiplier - 1.0) * 100).rounded())
        if percent == 0 { return String(format: "×%.2f", multiplier) }
        return String(format: "×%.2f (%@%d%%)", multiplier, percent > 0 ? "+" : "\u{2212}", abs(percent))
    }

    private func tradeValueFactorRow(
        label: String,
        detail: String,
        magnitude: String,
        tone: FactorTone
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tone.icon)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(tone.color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text(detail)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(magnitude)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    /// `"Franchise Tagged — 2027 at $32.8M"`, falling back to the bare label
    /// when the commitment cannot be read (a save whose tag predates the forward
    /// ledger). The year is `currentSeason + 1` for the same reason the tag
    /// screen labels itself that way: `currentSeason` does not move across the
    /// offseason, so the tag decided in it always binds the following year.
    private var franchiseTagBadgeText: String {
        guard let career = careers.first,
              let row = CommittedCapLedger.forwardCommitment(
                  playerID: player.id,
                  careerID: career.id
              ),
              row.annualCapHit > 0
        else { return "Franchise Tagged" }
        let millions = Double(row.annualCapHit) / 1_000.0
        return String(format: "Franchise Tagged \u{2014} %d at $%.1fM", row.seasonYear, millions)
    }

    // MARK: - Action Buttons (#35)

    /// Whether the shown player is on the user's own roster. The league
    /// browser makes EVERY player in the league navigable to this screen, and
    /// the management actions below mutate the player — "Extend Contract" on a
    /// rival would literally rewrite his contract. Own-roster players get the
    /// management set; everyone else gets only "Trade For".
    private var isUserRosterPlayer: Bool {
        guard let userTeamID = careers.first?.teamID else { return false }
        return player.teamID == userTeamID
    }

    /// **The one commit surface** (§2.5, P5).
    ///
    /// Was an "Actions" section: a five-button `LazyVGrid` in the middle of a
    /// scrolling `List`, so the most consequential controls on the screen —
    /// releasing a man, repricing his deal — scrolled away behind a career
    /// table. The set is unchanged apart from one deletion: **"Set as Starter"
    /// is gone**, because its closure was literally `{}` — a gold-tinted button
    /// that had never done anything. The depth chart is where a starter is set.
    ///
    /// Slot order is `DSActionBar`'s, not this screen's: destructive · ghost ·
    /// secondary · primary, with the destructive separated by a rule.
    @ViewBuilder
    private var playerActionBar: some View {
        if isUserRosterPlayer {
            DSActionBar(
                explainer: ownRosterBarExplainer,
                destructive: cutAction,
                ghost: .init(title: "Change Position", handler: { activeSheet = .positionChange }),
                secondary: secondaryContractAction,
                primary: primaryContractAction
            )
        } else if player.teamID == nil {
            // A free agent has no club to trade with, and `ProposeTradeButton`
            // renders NOTHING for him — so this branch is the difference
            // between "the bar says where he is signed" and the screen having
            // no commit surface at all, which is one of the two no-primary
            // screens §0 counts.
            DSActionBar(
                explainer: .init(
                    title: "Free agent",
                    message: "He is not under contract to anybody. Offers are made in the **Free Agency** workspace, where the cap room and the rival bids are on the same screen."
                )
            )
        } else {
            // A player on another club is a trade TARGET: this opens the Trade
            // Center with his team as the partner and him already ticked in
            // their column. `ProposeTradeButton` supplies the hint from our
            // actual depth at the position and the shared need model.
            ProposeTradeButton(player: player, leaguePlayers: allLeaguePlayers) { hint, openTradeCenter in
                DSActionBar(
                    explainer: .init(
                        title: "Not your player",
                        message: hint ?? "Opens the Trade Center with **\(playerTeam?.abbreviation ?? "his club")** as the partner and him already ticked in their column."
                    ),
                    primary: .init(title: "Trade For", handler: openTradeCenter)
                )
            }
        }
    }

    /// §2.12 — a blocked commit swaps the gold rule for orange and the
    /// explainer states the reason (#208 G1). The deal terms are still on the
    /// contract card directly above; what the BAR has to say while the room is
    /// one man deep is why the cut is shut, because the bar is where the cut is.
    private var ownRosterBarExplainer: DSActionBar.Explainer {
        if let reason = cutBlockReason {
            return DSActionBar.Explainer(
                title: "Cannot release",
                message: reason,
                isWarning: true
            )
        }
        return DSActionBar.Explainer(title: "Under contract", message: ownRosterExplainer)
    }

    /// What the bar says about the deal it is about to spend against. Both
    /// halves are quoted from the contract card directly above it, so the two
    /// numbers on one screen cannot disagree (§2.13, arithmetic gate).
    private var ownRosterExplainer: String {
        let years = player.contractYearsRemaining
        let yearsText = years == 1 ? "**1 year**" : "**\(years) years**"
        return "\(yearsText) left at **\(formattedSalary)** — \(capPercentageText) of the cap."
    }

    /// **Why the cut is closed, or nil** (#208 G1).
    ///
    /// QA released all three quarterbacks from THIS screen, one at a time, and
    /// walked into the preseason with an empty QB room: the cut sheet's guard
    /// never covered the per-player door. The rule is the engine's — this
    /// screen only asks it, and asks it against the same league query the rest
    /// of the page is drawn from.
    private var cutBlockReason: String? {
        guard let team = playerTeam else { return nil }
        return CapManagementEngine.releaseBlockReason(
            player: player,
            team: team,
            roster: allLeaguePlayers
        )
    }

    /// The destructive slot. Blocked, it is **disabled and says why** — the
    /// caption swaps the dead-cap preview for the reason, so the button and the
    /// explainer tell the same story rather than the reason hiding in a note
    /// beside a live control (§2.12).
    private var cutAction: DSActionBar.Action {
        let blocked = cutBlockReason
        return .init(
            title: "Cut / Release",
            caption: blocked ?? cutImpactPreviewText,
            isEnabled: blocked == nil,
            handler: { if blocked == nil { showCutConfirmation = true } }
        )
    }

    /// **The release, actually booked** (#188).
    ///
    /// The confirmation alert's Release button used to run an empty closure
    /// commented "Release action handled by parent" — no parent ever did. The
    /// button was priced correctly (`cutImpactPreviewText` quotes
    /// `releaseCapSplit`), showed a destructive confirmation, and then did
    /// nothing at all: the man stayed on the roster and the cap never moved.
    ///
    /// Same shape as `PlayerContractView.cutPlayer` — the ONE authority
    /// (`CapManagementEngine.applyRelease`), an explicit save, then out. The
    /// engine is what deletes the `Contract` rows, drops the franchise tag and
    /// stamps `cutByTeamID`, which is exactly why nothing here touches the
    /// player's fields by hand.
    private func releasePlayer() {
        guard let team = playerTeam, let career = careers.first else { return }
        // #208 G1: the roster this screen is already rendering IS the roster the
        // floors are measured against, so the engine does not re-fetch one. A
        // refused release writes nothing and leaves the man where he is; the
        // screen deliberately does NOT dismiss on a refusal, so the user is left
        // looking at the orange bar that says why.
        let split = CapManagementEngine.applyRelease(
            player: player,
            team: team,
            authority: .club(roster: allLeaguePlayers),
            contract: playerContract,
            capMode: career.capMode,
            leagueYearRemaining: CapManagementEngine.leagueYearRemaining(
                phase: career.currentPhase,
                week: career.currentWeek
            ),
            careerID: career.id,
            // #188: the engine files the receipt the Cap screen reads, so this
            // cut shows up by name under Dead Money like a camp cut does.
            reason: .rosterMove,
            seasonYear: career.currentSeason,
            modelContext: modelContext
        )
        guard !split.isRefused else { return }
        // Sweep him out of the saved depth chart and promote the man behind
        // him. A released starter's UUID left in his slot renders the slot
        // empty and stops the next offseason advance on "Lineup Incomplete",
        // a screen and sometimes a phase away from this release.
        DepthChart.reconcileSaved(
            career: career,
            roster: allLeaguePlayers.filter { $0.teamID == team.id }
        )
        try? modelContext.save()
        dismiss()
    }

    /// **The one gold fill on this screen** (P5): whichever contract
    /// conversation is actually live. With more than two years to run there is
    /// no extension to negotiate, so the repricing is promoted rather than the
    /// bar shipping a disabled gold button (§2.12).
    private var primaryContractAction: DSActionBar.Action? {
        if canExtend { return extensionAction }
        if canRenegotiate { return renegotiateAction }
        return nil
    }

    /// The repricing, but only when the extension already owns the primary —
    /// never both slots pointing at the same conversation.
    private var secondaryContractAction: DSActionBar.Action? {
        (canExtend && canRenegotiate) ? renegotiateAction : nil
    }

    /// TWO conversations, not one (#127). "Contact Agent" was a single door that
    /// only ever opened the extension, so the club's other contract lever —
    /// asking a man to take less on the deal he already has — was reachable only
    /// from the Cap Compliance workspace, i.e. only after the club was already
    /// over the cap.
    ///
    /// Neither caption carries a money estimate. It used to read
    /// "~$38.4M/yr · 3yr" off `estimateMarketValue`, which put the answer on the
    /// button: the whole point of the Contact Agent wave is that the agent's ask
    /// is something you find out by ringing him. What survives is
    /// `ContactAgentEntry.badge` — the state of a conversation already in
    /// progress — which reveals nothing the user has not been told to his face.
    private var renegotiateAction: DSActionBar.Action {
        .init(
            title: "Renegotiate",
            caption: ContactAgentEntry.badge(for: player, season: careers.first?.currentSeason ?? 0),
            handler: { contractTalk = .renegotiate }
        )
    }

    private var extensionAction: DSActionBar.Action {
        .init(
            title: "Negotiate Extension",
            caption: ContactAgentEntry.badge(for: player, season: careers.first?.currentSeason ?? 0),
            handler: { contractTalk = .extension_ }
        )
    }

    /// One-line dead cap preview for the Cut button. E.g. "$2.4M dead cap".
    ///
    /// Quoted from `CapManagementEngine.releaseCapSplit` — the same call the cut
    /// screens book against (#68). It used to be its own `salary × years ÷ 4`
    /// invention, which agreed with neither the roster-cut screen (20 %), the
    /// contract screen (50 %) nor the trade path (15 %/yr).
    private var cutImpactPreviewText: String? {
        guard player.annualSalary > 0 else { return nil }
        let split = CapManagementEngine.releaseCapSplit(
            player: player,
            contract: playerContract,
            capMode: careers.first?.capMode ?? .simple,
            leagueYearRemaining: careers.first.map {
                CapManagementEngine.leagueYearRemaining(phase: $0.currentPhase, week: $0.currentWeek)
            } ?? 1.0
        )
        let deadK = split.deadCap
        guard deadK > 0 else { return "No dead cap" }
        if deadK >= 1_000 {
            return String(format: "~$%.1fM dead cap", Double(deadK) / 1_000.0)
        }
        return "~$\(deadK)K dead cap"
    }

    // The "~$32M/yr × 4yr" extension preview that used to sit under the Contact
    // Agent button is gone (#127). It was `estimateMarketValue` rendered on the
    // door, which meant the user knew the shape of the deal before the agent had
    // said a word — and when the agent's opening ask came in above it (personas,
    // stances and the GM's standing all move the number), the button read as a
    // broken promise. The ask belongs in the conversation.

    /// **When an extension is a real question.**
    ///
    /// A deal with four years to run is not up for renewal — offering new years
    /// on top of it is a decision nobody in a front office makes, and
    /// `applyNegotiatedDeal(.extendExisting)` would happily stack them. Two years
    /// out is where a club starts talking, which is also where
    /// `FreeAgencyEngine`'s own retention logic starts looking.
    ///
    /// This gates on the CONTRACT, never on the man's willingness — the rule
    /// `ContactAgentEntry` exists to enforce. Whether his camp picks up is still
    /// something the agent says in the chat; how long he is signed for is printed
    /// on the contract row two sections up this very screen.
    private var canExtend: Bool {
        isUserRosterPlayer && player.contractYearsRemaining <= Self.extensionWindowYears
    }

    /// Contract years remaining at which an extension becomes a live question.
    private static let extensionWindowYears = 2

    /// **When a repricing is a real question.**
    ///
    /// There has to be a deal to reprice — an expired row still sitting on the
    /// sheet at $0 has nothing to give back — and it has to be a deal whose
    /// money is still ahead of the club.
    ///
    /// A **franchise-tagged** man fails that second test (#127). His
    /// `annualSalary` is the contract for the season already played; the tag
    /// number does not land on the row until the March rollover. Asking him to
    /// take a cut would reprice a year that is over, and `applyPayCut` would
    /// hand the club cap relief in the one phase nothing checks compliance in
    /// (`CapManagementEngine.isComplianceWindow` is false for `.reviewRoster`)
    /// — relief the rollover's true-up then silently takes back. There is no
    /// honest transaction there, so the button is not offered.
    ///
    /// Sandbox has no cap to relieve, so there is nothing to negotiate for.
    private var canRenegotiate: Bool {
        isUserRosterPlayer
            && player.contractYearsRemaining >= 1
            && player.annualSalary > 0
            && !player.isFranchiseTagged
            && (careers.first?.capMode ?? .simple) != .sandbox
    }

    // The old "~6 teams interested" teaser lived here. It was a hardcoded curve
    // over OVR and age that never consulted a roster, a need or a cap sheet, so
    // it invented a market that did not exist. `ProposeTradeButton` now supplies
    // the subtitle from our actual depth at the position and the shared need
    // model (`UI/Roster/LeagueRostersView.swift`).

    // The hand-rolled `actionButton` recipe that used to live here — tinted
    // 10 %-opacity fill, 30 % border, 8 r, ~34 pt tall — is deleted. Every
    // control on this screen is now a `DSActionBar` button in one of the four
    // shipped `ButtonStyle`s, which are the only ones that meet the 44 pt floor
    // and draw a real pressed/disabled state (§2.12).

    // MARK: - Injury History (#38)

    private var injuryHistoryCard: some View {
        DSDetailCard(
            "Injury History",
            icon: "cross.case",
            explainer: "What he has missed, whether the same thing keeps happening, and the **durability** rating that drives how often it will."
        ) {
            if player.isInjured, let injuryType = player.injuryType {
                HStack(spacing: 8) {
                    Image(systemName: "cross.circle.fill")
                        .foregroundStyle(Color.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current: \(injuryType.rawValue)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.danger)
                        Text("\(player.injuryWeeksRemaining) of \(player.injuryWeeksOriginal) weeks remaining")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                        // R28: rehab trajectory
                        if let rehab = player.rehabStatus {
                            HStack(spacing: 3) {
                                Image(systemName: rehab.icon)
                                    .font(.system(size: DSType.Size.micro))
                                Text(rehab.displayName)
                                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                            }
                            .foregroundStyle(rehabColor(rehab))
                        }
                    }
                    Spacer()
                    // Recovery progress
                    let progress = player.injuryWeeksOriginal > 0
                        ? Double(player.injuryWeeksOriginal - player.injuryWeeksRemaining) / Double(player.injuryWeeksOriginal)
                        : 0.0
                    CircularProgressView(progress: progress, color: .danger)
                        .frame(width: 32, height: 32)
                }
            } else if player.rushBackWeeksRemaining > 0 {
                // R28: recently rushed back — elevated re-injury risk window
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(Color.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Returned early — elevated re-injury risk")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.warning)
                        Text("\(player.rushBackWeeksRemaining) week\(player.rushBackWeeksRemaining == 1 ? "" : "s") until fully conditioned")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                }
            }

            // R28: permanent injury history (newest first), with recurrence flags
            let history = player.injuryHistory
            if !history.isEmpty {
                ForEach(history.suffix(6).reversed()) { record in
                    let repeatCount = history.filter { $0.injuryTypeRaw == record.injuryTypeRaw }.count
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.textTertiary)
                        Text(record.summary)
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                        if repeatCount >= 2 {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: DSType.Size.micro, weight: .bold))
                                Text("x\(repeatCount)")
                                    .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                            }
                            .foregroundStyle(Color.warning)
                            .accessibilityLabel("Recurring injury, \(repeatCount) times")
                        }
                        Spacer()
                    }
                }
            } else if !player.isInjured {
                // #180: Show "No injury history" with durability rating
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No injury history")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.success)
                        Text("Durability: \(player.physical.durability)")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    // Durability indicator
                    VStack(spacing: 2) {
                        Text("\(player.physical.durability)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(colorForAttribute(player.physical.durability))
                        Text("Durability")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
    }

    /// R28: theme color for a rehab trajectory.
    private func rehabColor(_ status: RehabStatus) -> Color {
        switch status {
        case .aheadOfSchedule: return .success
        case .onTrack:         return .textSecondary
        case .setback:         return .warning
        }
    }

    // MARK: - Position Change Sheet (#41)

    private var positionChangeSheet: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                List {
                    Section {
                        HStack(spacing: 8) {
                            positionLabel
                            Text("Current Position")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    } header: {
                        Text("Current")
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    // #176/#177: Filter by position compatibility matrix, label as Developing/Can Learn
                    Section {
                        let viablePositions = VersatilityEngine.viablePositions(for: player)
                            .filter { $0.0 != player.position && isRealisticConversion(from: player.position, to: $0.0) }

                        if viablePositions.isEmpty {
                            Text("No viable alternate positions for this player's position group.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        } else {
                            ForEach(viablePositions, id: \.0) { pos, rating in
                                let familiarity = player.familiarity(at: pos)
                                let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: pos)
                                let statusLabel = familiarity > 0 ? "Developing" : "Can Learn"
                                Button {
                                    player.trainingPosition = pos
                                    activeSheet = nil
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(pos.rawValue)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                            .frame(width: 30, alignment: .leading)
                                        Text(statusLabel)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(familiarity > 0 ? Color.accentGold : Color.accentBlue)
                                            .frame(width: 70, alignment: .leading)
                                        Spacer()
                                        Text("\(familiarity)%")
                                            .font(.caption2.weight(.bold).monospacedDigit())
                                            .foregroundStyle(rating.color)
                                        Text("(max \(ceiling)%)")
                                            .font(.system(size: DSType.Size.micro))
                                            .foregroundStyle(Color.textTertiary)
                                        Image(systemName: "arrow.right.circle")
                                            .font(.caption)
                                            .foregroundStyle(Color.accentBlue)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Convert To")
                    } footer: {
                        // §5.3: starting the programme is a commitment, not a
                        // reversible depth-chart experiment.
                        Text("Training here banks familiarity week by week. At \(VersatilityDevelopmentEngine.conversionCommitFamiliarity)% he converts PERMANENTLY — his listed position changes and his attributes are rebuilt around the new spot, with a dip for what does not carry over. He keeps what he knew at \(player.position.rawValue). Stop the programme before \(VersatilityDevelopmentEngine.conversionCommitFamiliarity)% if you only want him as cover.")
                            .font(.caption2)
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Change Position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
            }
        }
    }

    // MARK: - Pre-Camp Scouting Report (TRACK B)

    /// What stands in for the three attribute sections while a rookie is still
    /// fogged. Deliberately small: the band his scouts filed, the staff's first
    /// projection if a camp has already written one, and a plain statement of
    /// when the real evaluation arrives — so the empty space reads as a rule of
    /// the game rather than as missing data.
    private var preCampScoutingReportCard: some View {
        DSDetailCard(
            "Scouting Report",
            icon: "doc.text.magnifyingglass",
            explainer: "He has not reported to camp, so nobody in this building has measured him yet. This is what the file says until they do."
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    VStack(spacing: 2) {
                        Text(RookieFog.bandText(for: player))
                            .font(.title3.monospaced().weight(.heavy))
                            .foregroundStyle(RookieFog.source(for: player).tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(RookieFog.source(for: player).label.uppercased())
                            .font(.system(size: DSType.Size.micro, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .frame(width: 84)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full evaluation at training camp")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(RookieFog.source(for: player) == .scouts
                             ? "This is the grade band our scouts filed on him before the draft. Exact ratings come off the practice field, not the college tape."
                             : "Nobody in this building filed on him — this is the media's read on his draft slot. Exact ratings come off the practice field.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                // The SAME projection row the Development card prints — it was
                // hand-copied here, which is the "one thing, two renderings"
                // this wave exists to delete.
                coachProjectionRow
            }
        }
    }

    // The three `AttributeRowWith*` list forks that used to live here are gone.
    // They were a *second* rendering of Physical / Mental / Position Skills,
    // shown only in the compact branch, while the grid forms below were shown
    // on iPad — the "same screen built twice" §0 names, inside one file. The
    // grid forms survive as the single implementation and reflow by column
    // count instead of by branch.

    // MARK: - Personality

    private var personalityCard: some View {
        DSDetailCard(
            "Personality",
            icon: "person.crop.circle",
            explainer: "His archetype and his motivation state — the two dials the development pass and the locker room read."
        ) {
            // Archetype with explanation (#183)
            DSDetailRow("Archetype", archetypeDisplayName)
            DSDetailNote(text: archetypeEffectDescription)

            // Motivator with explanation (#183).
            // NOTE (#140): this row is the *trait* — what drives him (Money /
            // Winning / Stats / Loyalty / Fame). The Overview card's
            // "Motivation" pill is the transient `motivationState`
            // (Driven / Focused / …). Two different things, so they must not
            // share a label or the card reads as a contradiction
            // ("Motivation: Focused" vs "Motivation: Fame").
            DSDetailRow("Motivator", player.personality.motivation.rawValue)
            DSDetailNote(text: motivationEffectDescription)

            if player.personality.isMentor {
                Label("Mentor influence on team", systemImage: "person.2.fill")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)
            }
            if player.personality.isDramaticInMedia {
                Label("Can generate media drama", systemImage: "exclamationmark.bubble.fill")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.warning)
            }
        }
    }

    // MARK: - Versatility & Scheme Familiarity

    private var versatilityCard: some View {
        DSDetailCard(
            "Position Versatility",
            icon: "arrow.triangle.swap",
            explainer: "Where else he could line up, and how much of each scheme he has actually installed."
        ) {
            // Primary position at 100%
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(player.position.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 30, alignment: .leading)
                    Text("Primary")
                        .font(.system(size: DSType.Size.micro, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Spacer()
                    Text("100%")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }

                // Training status
                if let trainingPos = player.trainingPosition, trainingPos != player.position {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "figure.run")
                                .font(.caption)
                                .foregroundStyle(Color.accentGold)
                            Text("Training: \(trainingPos.rawValue)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentGold)
                            Spacer()
                            let familiarity = player.familiarity(at: trainingPos)
                            let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: trainingPos)
                            Text("\(familiarity)/\(ceiling)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.accentGold)
                        }
                        // §5.3: this is a conversion programme, not just
                        // cross-training — say so before it fires.
                        Text("At \(VersatilityDevelopmentEngine.conversionCommitFamiliarity)% familiarity he converts to \(trainingPos.rawValue) PERMANENTLY and his ratings are rebuilt around it. Stop the programme first if you only want cover there.")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .background(Color.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                }

                Divider().overlay(Color.surfaceBorder)

                // #176/#177: Filter by compatibility matrix, label Developing vs Can Learn
                let allViable = VersatilityEngine.viablePositions(for: player)
                    .filter { $0.0 != player.position && isRealisticConversion(from: player.position, to: $0.0) }

                if allViable.isEmpty {
                    Text("No viable alternate positions for this player's position group.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    ForEach(allViable, id: \.0) { pos, rating in
                        let familiarity = player.familiarity(at: pos)
                        let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: pos)
                        let statusLabel = familiarity > 0 ? "Developing" : "Can Learn"
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                Text(pos.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.textPrimary)
                                    .frame(width: 30, alignment: .leading)

                                Text(statusLabel)
                                    .font(.system(size: DSType.Size.micro, weight: .medium))
                                    .foregroundStyle(familiarity > 0 ? Color.accentGold : Color.accentBlue)

                                Spacer()

                                Text("\(familiarity)%")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(familiarity > 0 ? versatilityBarColor(familiarity) : Color.textTertiary)
                            }

                            // Familiarity bar with ceiling
                            GeometryReader { geo in
                                let barWidth = geo.size.width
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                        .fill(Color.backgroundTertiary)
                                        .frame(height: 6)
                                    if familiarity > 0 {
                                        RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                            .fill(versatilityBarColor(familiarity))
                                            .frame(width: barWidth * CGFloat(familiarity) / 100.0, height: 6)
                                    }
                                    // Ceiling marker
                                    Rectangle()
                                        .fill(Color.textTertiary)
                                        .frame(width: 1.5, height: 10)
                                        .offset(x: barWidth * CGFloat(ceiling) / 100.0 - 0.75)
                                }
                            }
                            .frame(height: 10)

                            // Explanation of why this alternate position exists (#32)
                            Text(versatilityExplanation(from: player.position, to: pos, rating: rating))
                                .font(.system(size: DSType.Size.footnote))
                                .foregroundStyle(Color.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            // #181: Show ALL relevant schemes, not just learned ones.
            //
            // Now that the card is a plain `VStack` rather than a `Section`, a
            // `Divider()` is an inline rule again — inside a List it was its own
            // ~44 pt row with a hairline floating in the middle of it, which is
            // why this heading had no rule above it before.
            Divider().overlay(Color.surfaceBorder)
            SectionHeaderText(title: "Scheme Familiarity")

            let allSchemes: [(String, Int)] = {
                let schemeNames: [String]
                switch player.position.side {
                case .offense:
                    schemeNames = OffensiveScheme.allCases.map(\.rawValue)
                case .defense:
                    schemeNames = DefensiveScheme.allCases.map(\.rawValue)
                case .specialTeams:
                    // Special teams players show both offensive and defensive schemes
                    schemeNames = OffensiveScheme.allCases.map(\.rawValue) + DefensiveScheme.allCases.map(\.rawValue)
                }
                return schemeNames.map { name in
                    (name, player.schemeFamiliarity[name] ?? 0)
                }.sorted { $0.1 > $1.1 }
            }()

            ForEach(allSchemes, id: \.0) { scheme, familiarity in
                HStack(spacing: 8) {
                    Text(scheme)
                        .font(.caption)
                        .foregroundStyle(familiarity > 0 ? Color.textSecondary : Color.textTertiary)
                        .frame(width: 80, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 6)
                            if familiarity > 0 {
                                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                    .fill(schemeFamColor(familiarity))
                                    .frame(width: geo.size.width * CGFloat(familiarity) / 100.0, height: 6)
                            }
                        }
                    }
                    .frame(height: 6)

                    Text("\(familiarity)%")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(familiarity > 0 ? schemeFamColor(familiarity) : Color.textTertiary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    /// Both meters are 0–99 reads like any other, so both go through the one
    /// ladder (§4 wave 4). The two bespoke ladders they replace disagreed with
    /// `Color.forRating` *and with each other* — same value, same card, gold in
    /// the versatility bar and green in the familiarity bar beneath it.
    private func versatilityBarColor(_ value: Int) -> Color {
        Color.forRating(value)
    }

    private func schemeFamColor(_ value: Int) -> Color {
        Color.forRating(value)
    }

    // MARK: - Scheme Fit

    private var schemeFitCard: some View {
        DSDetailCard(
            "Scheme Fit",
            icon: "square.grid.3x3",
            explainer: "Which system he already knows, and the two profile averages a coordinator reads before he installs anything."
        ) {
            // Best-fit scheme call-out (#42) — derived from the player's highest familiarity entry.
            if let best = bestSchemeFit {
                DSDetailRow(label: "Best Scheme") {
                    HStack(spacing: DSSpacing.xxs) {
                        Text(best.scheme)
                            .font(.system(size: DSType.Size.body, weight: .semibold))
                            .foregroundStyle(Color.accentGold)
                        Text("\(best.familiarity)%")
                            .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.textTertiaryReadable)
                    }
                }
            }
            DSDetailRow("Position Group", positionGroupName, tint: .textSecondary, weight: .regular)
            DSDetailRow(label: "Physical Profile") {
                let avg = Int(player.physical.average.rounded())
                HStack(spacing: DSSpacing.xxs) {
                    Text(physicalProfileLabel(for: avg))
                        .font(.system(size: DSType.Size.body))
                        .foregroundStyle(Color.textSecondary)
                    Text("(\(avg))")
                        .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                        .foregroundStyle(colorForAttribute(avg))
                }
            }
            DSDetailRow(label: "Mental Profile") {
                let avg = Int(player.mental.average.rounded())
                HStack(spacing: DSSpacing.xxs) {
                    Text(mentalProfileLabel(for: avg))
                        .font(.system(size: DSType.Size.body))
                        .foregroundStyle(Color.textSecondary)
                    Text("(\(avg))")
                        .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                        .foregroundStyle(colorForAttribute(avg))
                }
            }
        }
    }

    /// Highest-familiarity scheme for the player, used in Scheme Fit recommendation.
    /// Returns nil when the player has no scheme familiarity data.
    private var bestSchemeFit: (scheme: String, familiarity: Int)? {
        let entries = player.schemeFamiliarity.filter { $0.value > 0 }
        guard let top = entries.max(by: { $0.value < $1.value }) else { return nil }
        return (scheme: top.key, familiarity: top.value)
    }

    // MARK: - Attribute cards
    //
    // The one implementation. Column count comes from the page, so the same
    // card is a two-up grid in a wide column and a single list in a narrow one
    // — no second set of section builders for "compact".

    private var physicalAttributesCard: some View {
        DSDetailCard("Physical Attributes", icon: "figure.run") {
            attributeGrid([
                ("Speed",        player.physical.speed),
                ("Acceleration", player.physical.acceleration),
                ("Strength",     player.physical.strength),
                ("Agility",      player.physical.agility),
                ("Stamina",      player.physical.stamina),
                ("Durability",   player.physical.durability),
            ])
        }
    }

    private var mentalAttributesCard: some View {
        DSDetailCard("Mental Attributes", icon: "brain.head.profile") {
            attributeGrid([
                ("Awareness",       player.mental.awareness),
                ("Decision Making",  player.mental.decisionMaking),
                ("Clutch",           player.mental.clutch),
                ("Work Ethic",       player.mental.workEthic),
                ("Coachability",     player.mental.coachability),
                ("Leadership",       player.mental.leadership),
                // Learning drives how fast he installs a new scheme.
                ("Learning",         player.learning),
                // Competitiveness: the fighter mentality (plan §2.1).
                ("Competitiveness",  player.competitiveness),
            ])
        }
    }

    @ViewBuilder
    private var positionAttributesCards: some View {
        switch player.positionAttributes {
        case .quarterback(let a):
            // #182: QB grid with league averages
            let avg = qbLeagueAverages
            DSDetailCard("Quarterback Skills", icon: "football") {
                attributeGridWithAvg([
                    ("Arm Strength", a.armStrength, avg.armStrength),
                    ("Accuracy Short", a.accuracyShort, avg.accuracyShort),
                    ("Accuracy Mid", a.accuracyMid, avg.accuracyMid),
                    ("Accuracy Deep", a.accuracyDeep, avg.accuracyDeep),
                    ("Pocket Presence", a.pocketPresence, avg.pocketPresence),
                    ("Scrambling", a.scrambling, avg.scrambling),
                ])
            }
        case .wideReceiver(let a):
            DSDetailCard("Receiver Skills", icon: "hand.raised") {
                attributeGrid([
                    ("Route Running", a.routeRunning), ("Catching", a.catching),
                    ("Release", a.release), ("Spectacular Catch", a.spectacularCatch),
                ])
            }
        case .runningBack(let a):
            DSDetailCard("Running Back Skills", icon: "figure.run") {
                attributeGrid([
                    ("Vision", a.vision), ("Elusiveness", a.elusiveness),
                    ("Break Tackle", a.breakTackle), ("Receiving", a.receiving),
                ])
            }
        case .tightEnd(let a):
            DSDetailCard("Tight End Skills", icon: "shield.lefthalf.filled") {
                attributeGrid([
                    ("Blocking", a.blocking), ("Catching", a.catching),
                    ("Route Running", a.routeRunning), ("Speed", a.speed),
                ])
            }
        case .offensiveLine(let a):
            DSDetailCard("Offensive Line Skills", icon: "shield") {
                attributeGrid([
                    ("Run Block", a.runBlock), ("Pass Block", a.passBlock),
                    ("Pull", a.pull), ("Anchor", a.anchor),
                ])
            }
        case .defensiveLine(let a):
            DSDetailCard("Defensive Line Skills", icon: "bolt.shield") {
                attributeGrid([
                    ("Pass Rush", a.passRush), ("Block Shedding", a.blockShedding),
                    ("Power Moves", a.powerMoves), ("Finesse Moves", a.finesseMoves),
                ])
            }
        case .linebacker(let a):
            DSDetailCard("Linebacker Skills", icon: "shield.righthalf.filled") {
                attributeGrid([
                    ("Tackling", a.tackling), ("Zone Coverage", a.zoneCoverage),
                    ("Man Coverage", a.manCoverage), ("Blitzing", a.blitzing),
                ])
            }
        case .defensiveBack(let a):
            DSDetailCard("Defensive Back Skills", icon: "lock.shield") {
                attributeGrid([
                    ("Man Coverage", a.manCoverage), ("Zone Coverage", a.zoneCoverage),
                    ("Press", a.press), ("Ball Skills", a.ballSkills),
                ])
            }
        case .kicking(let a):
            DSDetailCard("Kicking Skills", icon: "figure.kickboxing") {
                attributeGrid([
                    ("Kick Power", a.kickPower), ("Kick Accuracy", a.kickAccuracy),
                ])
            }
        }
    }

    private func attributeGrid(_ attributes: [(String, Int)]) -> some View {
        let cols = attributeColumns
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: cols)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
            ForEach(attributes, id: \.0) { attr in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(colorForAttribute(attr.1))
                        .frame(width: 3, height: 16)
                    Text(attr.0)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(attr.1)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(colorForAttribute(attr.1))
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// #182: Grid variant that shows league average next to each attribute value.
    private func attributeGridWithAvg(_ attributes: [(String, Int, Int)]) -> some View {
        let cols = attributeColumns
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: cols)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
            ForEach(attributes, id: \.0) { attr in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(colorForAttribute(attr.1))
                        .frame(width: 3, height: 16)
                    Text(attr.0)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(attr.1)")
                        .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                        .foregroundStyle(colorForAttribute(attr.1))
                    // The gap to the league average at this position, signed —
                    // clearer than the bare "(68)" parenthetical, which never
                    // said what the number referenced (#182).
                    Text(leagueDeltaText(value: attr.1, avg: attr.2))
                        .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                        .foregroundStyle(leagueDeltaColor(value: attr.1, avg: attr.2))
                        .accessibilityLabel("\(leagueDeltaText(value: attr.1, avg: attr.2)) versus the league average for this position, \(attr.2)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// "+5" / "-12" / "±0" — the signed gap to the league average.
    private func leagueDeltaText(value: Int, avg: Int) -> String {
        let delta = value - avg
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "\(delta)" }
        return "\u{00B1}0"
    }

    /// Three states, not a rating ladder: clearly above, clearly below, or
    /// inside the ±5 band where the difference is noise.
    private func leagueDeltaColor(value: Int, avg: Int) -> Color {
        let delta = value - avg
        if delta >= 5 { return .success }
        if delta <= -5 { return .danger }
        return .textTertiaryReadable
    }

    // MARK: - Helpers

    private var positionLabel: some View {
        HStack(spacing: 6) {
            Text(player.position.rawValue)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(positionSideColor, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            Text(player.position.side.rawValue)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var developmentBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: developmentPhase.icon)
                .font(.system(size: DSType.Size.micro))
            Text(developmentPhase.shortLabel)
                .font(.system(size: DSType.Size.micro, weight: .medium))
        }
        .foregroundStyle(developmentPhase.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(developmentPhase.color.opacity(0.15), in: Capsule())
    }

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var moraleShortLabel: String {
        switch player.morale {
        case 85...: return "Great"
        case 70..<85: return "Good"
        case 55..<70: return "OK"
        default:    return "Low"
        }
    }

    /// The single morale encoding this screen uses: the number AND the tier word
    /// together. The hero strip used to print the raw figure ("68") while the
    /// Overview card printed the tier ("OK") 35pt below it, so one fact read as
    /// two — and neither told you which scale the other was on.
    private var moraleDisplayLabel: String {
        "\(player.morale) · \(moraleShortLabel)"
    }

    // `moraleLabel`, `moraleIcon` and `moraleSystemImage` were the compact
    // list fork's morale row and died with it. The one morale encoding on this
    // screen is `moraleDisplayLabel` in the Overview card.

    private var moraleColor: Color {
        Color.forRating(player.morale)
    }

    // MARK: - Motivation (plan §2.10)

    /// Badge color for the motivation state — the same green/gold/red language
    /// the rest of the detail screen uses for "good / neutral / bad".
    private var motivationColor: Color {
        switch player.motivationState {
        case .driven:      return .success
        case .focused:     return .textSecondary
        case .complacent:  return .warning
        case .discouraged: return .danger
        }
    }

    /// The Overview card's motivation badge — the ONE place this screen states
    /// it, since the hero strip's duplicate copy was removed.
    private var motivationPill: some View {
        HStack(spacing: 4) {
            Text("Motivation")
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Image(systemName: player.motivationState.icon)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(motivationColor)
            Text(player.motivationState.displayName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(motivationColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
    }

    /// Plain-language morale impact (#40). Helps the user understand *why* morale matters.
    private var moraleImpactDescription: String {
        switch player.morale {
        case 85...:
            return "Energized — small in-game performance bonus, more likely to extend long-term."
        case 70..<85:
            return "Content — performs to expectations, no extra friction in negotiations."
        case 55..<70:
            return "Neutral — no boost; expect harder-line contract demands."
        case 40..<55:
            return "Unhappy — minor performance penalty; risk of locker room drama."
        default:
            return "Disgruntled — clear performance penalty; may demand a trade or hold out."
        }
    }

    private var archetypeDisplayName: String {
        player.personality.archetype.displayName
    }

    // #183: Archetype effect descriptions
    private var archetypeEffectDescription: String {
        switch player.personality.archetype {
        case .teamLeader:        return "Boosts team morale; rallies teammates in tough games"
        case .loneWolf:          return "Self-motivated; less affected by team chemistry"
        case .feelPlayer:        return "Performance varies with mood; streaky in big moments"
        case .steadyPerformer:   return "Consistent in pressure situations; rarely has off days"
        case .dramaQueen:        return "Creates media drama; can disrupt locker room if unhappy"
        case .quietProfessional: return "Steady presence; does not seek spotlight but delivers"
        case .mentor:            return "Accelerates development of younger teammates"
        case .fieryCompetitor:   return "Elevated play in rivalries; risk of penalties when frustrated"
        case .classClown:        return "Keeps locker room loose; may lack focus in preparation"
        }
    }

    // #183: Motivation effect descriptions
    private var motivationEffectDescription: String {
        switch player.personality.motivation {
        case .money:   return "Motivated by contract value; morale drops if underpaid"
        case .winning: return "Thrives on winning; morale suffers during losing streaks"
        case .stats:   return "Wants volume and usage; unhappy if production drops"
        case .loyalty: return "Values long-term commitment; bonus morale for extensions"
        case .fame:    return "Motivated by media attention; prefers big-market teams"
        }
    }

    private var formattedSalary: String {
        let millions = Double(player.annualSalary) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.2fM", millions)
        } else {
            return "$\(player.annualSalary)K"
        }
    }

    // MARK: - Market Value Estimation

    private var estimatedMarketValue: String {
        let marketValue = estimateMarketValueAmount
        let millions = Double(marketValue) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.2fM", millions)
        } else {
            return "$\(marketValue)K"
        }
    }

    /// Market value in thousands — **`ContractEngine`, the one market authority**
    /// (task #87 / F3).
    ///
    /// This pill used to run `PlayerValueEngine`: its own `20_000 × (ovr/75)^4.5`
    /// curve, its own position table that contradicted `ContractEngine`'s
    /// outright, no salary cap at all, and no knowledge of the vet-minimum floor
    /// or the position-switch rule. Measured against the real engine it was
    /// +111 % at RB / +35 % at QB down at OVR 74 and −27 % at C / −21 % at DT up
    /// at 96 — so the number on the card the user looks at most matched neither
    /// the ask he met in `ContractNegotiationView` nor the peer band printed two
    /// pills to its right.
    private var estimateMarketValueAmount: Int {
        ContractEngine.estimateMarketValue(player: player, salaryCap: contextSalaryCap)
    }

    /// The bands the Value pill is testing. Named once, here, so the sentence
    /// under the card and the verdict on it can never drift apart.
    private static let bargainRatio = 1.3
    private static let fairValueRatio = 0.8

    /// Bargain / Fair / Overpaid, off the same engine and the same cap as the
    /// Market pill above it — and therefore agreeing with `RosterEvaluationView`,
    /// which has always graded the same player off `ContractEngine`.
    private var marketValueComparison: MarketValueAssessment {
        let market = estimateMarketValueAmount
        // No salary on file (e.g. an unsigned rookie) — surface the upside.
        guard player.annualSalary > 0 else { return .bargain }
        let ratio = Double(market) / Double(player.annualSalary)
        if ratio > Self.bargainRatio { return .bargain }
        if ratio > Self.fairValueRatio { return .fairValue }
        return .overpaid
    }

    /// **The gap the card printed two numbers around and never stated.**
    ///
    /// Market and Salary sat side by side as two absolute figures, and the
    /// arithmetic between them — the only thing a GM actually acts on — was
    /// left to the reader. The verdict beside them says which side of the line
    /// he is on; this says by how much, and what the line is.
    private var marketGapNote: String? {
        guard player.annualSalary > 0 else {
            return "No salary on file yet, so the market figure is what he would cost to sign rather than a comparison."
        }
        let gap = estimateMarketValueAmount - player.annualSalary
        let gapText = formatDollars(abs(gap))
        let verdict: String = {
            if gap > 0 { return "Underpaid by \(gapText) against his market value" }
            if gap < 0 { return "Overpaid by \(gapText) against his market value" }
            return "Paid exactly his market value"
        }()
        let band = "\"Fair Value\" is a market value between \(String(format: "%.1f", Self.fairValueRatio))× and \(String(format: "%.1f", Self.bargainRatio))× his salary — above that band he is a Bargain, below it Overpaid."
        return "\(verdict). \(band)"
    }

    /// Thousands, in the two-decimal millions this card already prints.
    private func formatDollars(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.2fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    // MARK: - Development Phase

    private var developmentPhase: DevelopmentPhaseInfo {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return .rising
        } else if peak.contains(player.age) {
            return .prime
        } else {
            return .declining
        }
    }

    private var trajectoryDescription: String {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            let yearsToGo = peak.lowerBound - player.age
            return "Entering prime in ~\(yearsToGo) year\(yearsToGo == 1 ? "" : "s"). Expect improvement."
        } else if peak.contains(player.age) {
            let yearsLeft = peak.upperBound - player.age
            return "In prime window. ~\(yearsLeft) year\(yearsLeft == 1 ? "" : "s") of peak performance remaining."
        } else {
            let yearsOver = player.age - peak.upperBound
            return "Past prime by \(yearsOver) year\(yearsOver == 1 ? "" : "s"). Expect gradual decline."
        }
    }

    // MARK: - Scheme Fit Helpers

    private var positionGroupName: String {
        switch player.position {
        case .QB: return "Quarterback"
        case .RB, .FB: return "Backfield"
        case .WR: return "Receiving Corps"
        case .TE: return "Tight End"
        case .LT, .LG, .C, .RG, .RT: return "Offensive Line"
        case .DE, .DT: return "Defensive Line"
        case .OLB, .MLB: return "Linebacker Corps"
        case .CB, .FS, .SS: return "Secondary"
        case .K: return "Kicking"
        case .P: return "Punting"
        }
    }

    private func physicalProfileLabel(for value: Int) -> String {
        switch value {
        case 85...:   return "Elite Athlete"
        case 75..<85: return "Above Average"
        case 65..<75: return "Average"
        case 55..<65: return "Below Average"
        default:      return "Limited"
        }
    }

    private func mentalProfileLabel(for value: Int) -> String {
        switch value {
        case 85...:   return "Football IQ Genius"
        case 75..<85: return "High IQ"
        case 65..<75: return "Average IQ"
        case 55..<65: return "Developing"
        default:      return "Raw"
        }
    }

    // MARK: - League Ranking (#33, #178)

    /// Returns a ranking string like "#3 QB" or "Top 12%" using @Query data.
    ///
    /// **#134a: the OVR comparison alone is not a total order.** A position group
    /// is thick with ties — twenty of the league's linebackers sit on the same
    /// two or three OVR values — and `sorted(by:)` gives no stability guarantee
    /// when the comparator answers `false` both ways, so tied players came back
    /// in whatever order the array happened to arrive in. That array is
    /// `allLeaguePlayersUnscoped`, a `@Query` with **no sort descriptor**: the
    /// fetch order is unspecified and re-orders across re-fetches. The badge is
    /// recomputed on every body pass, so the same 85-OVR receiver read "#3 WR"
    /// on one render and "#5 WR" on the next without a single attribute moving.
    ///
    /// Falling through to the stable, persisted player id makes the ordering
    /// total, which makes the rank a function of the *set* rather than of the
    /// order the set was handed over in. Deliberately a tiebreak and not a
    /// cache: the number still recomputes, it just cannot disagree with itself.
    private var leagueRanking: String? {
        let samePos = allLeaguePlayers.filter { $0.position == player.position }
        guard samePos.count > 1 else { return nil }
        let sorted = samePos.sorted {
            $0.overall != $1.overall
                ? $0.overall > $1.overall
                : $0.id.uuidString < $1.id.uuidString
        }
        guard let rank = sorted.firstIndex(where: { $0.id == player.id }) else { return nil }
        let position = rank + 1
        let total = sorted.count
        let pct = Int((Double(position) / Double(total)) * 100)
        if position <= 5 {
            return "#\(position) \(player.position.rawValue)"
        } else {
            return "Top \(pct)% \(player.position.rawValue)"
        }
    }

    // MARK: - Trade Value (#37)

    /// What the engine says this player is worth, on the Jimmy Johnson chart.
    ///
    /// This screen used to compute a private 0-100 "score" of its own — a
    /// different formula, a different scale, and a different answer from the one
    /// `TradeValueEngine` uses to accept or reject every offer the user makes.
    /// The card now quotes the engine, so the bucket it names is the bucket the
    /// AI will actually trade at.
    private var tradeValuePoints: Int {
        TradeValueEngine.playerTradeValue(player: player)
    }

    /// The raw OVR curve before position/age/contract, so the factor rows below
    /// add up to `tradeValuePoints` instead of being three unweighted ticks.
    private var tradeValueBasePoints: Int {
        max(1, Int(32.0 * pow(1.128, Double(player.overall - 60))))
    }

    private var tradeValueAgeMultiplier: Double {
        TradeValueEngine.ageMultiplier(age: player.age, position: player.position)
    }

    private var tradeValueContractMultiplier: Double {
        TradeValueEngine.contractMultiplier(player: player, salaryCap: contextSalaryCap)
    }

    /// The earliest pick those points buy on the same chart the war room reads.
    /// `nil` only when the player outprices pick #1 (99 OVR QBs do).
    private var tradeValuePickEquivalent: Int? {
        let points = tradeValuePoints
        guard points < PickValueChart.points(forPick: 1) else { return nil }
        return (1...224).first { PickValueChart.points(forPick: $0) <= points }
    }

    /// Round bucket, derived FROM the points rather than from a parallel scale.
    private var tradeValueRound: Int? {
        guard let pick = tradeValuePickEquivalent else { return 1 }
        guard pick <= 224 else { return nil }
        return (pick - 1) / 32 + 1
    }

    private var tradeValueLabel: String {
        guard let round = tradeValueRound else { return "Minimal Value" }
        let ordinal: String
        switch round {
        case 1: ordinal = "1st"
        case 2: ordinal = "2nd"
        case 3: ordinal = "3rd"
        default: ordinal = "\(round)th"
        }
        return "\(ordinal) Round Pick"
    }

    private var tradeValueColor: Color {
        switch tradeValueRound {
        case .some(1):      return .accentGold
        case .some(2), .some(3): return .success
        case .some(4), .some(5): return .textSecondary
        default:            return .textTertiary
        }
    }

    // MARK: - QB League Averages (#182)

    /// Compute average QB attributes across all QBs in the league for context display.
    private var qbLeagueAverages: QBAttributes {
        let qbs = allLeaguePlayers.filter { $0.position == .QB }
        guard !qbs.isEmpty else {
            return QBAttributes(armStrength: 70, accuracyShort: 70, accuracyMid: 70,
                                accuracyDeep: 70, pocketPresence: 70, scrambling: 70)
        }
        var totalArm = 0, totalShort = 0, totalMid = 0, totalDeep = 0, totalPocket = 0, totalScramble = 0
        for qb in qbs {
            if case .quarterback(let a) = qb.positionAttributes {
                totalArm += a.armStrength
                totalShort += a.accuracyShort
                totalMid += a.accuracyMid
                totalDeep += a.accuracyDeep
                totalPocket += a.pocketPresence
                totalScramble += a.scrambling
            }
        }
        let count = qbs.count
        return QBAttributes(
            armStrength: totalArm / count,
            accuracyShort: totalShort / count,
            accuracyMid: totalMid / count,
            accuracyDeep: totalDeep / count,
            pocketPresence: totalPocket / count,
            scrambling: totalScramble / count
        )
    }

    // MARK: - Versatility Explanation (#32)

    private func versatilityExplanation(from primary: Position, to alt: Position, rating: VersatilityRating) -> String {
        let ceilingPct = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: alt)

        switch (primary, alt) {
        case (.QB, .WR):
            return "Athletic QB can line up as WR in trick plays. Max ceiling: \(ceilingPct)%."
        case (.WR, .TE), (.TE, .WR):
            return "Size/speed combo allows flex between WR and TE. Max ceiling: \(ceilingPct)%."
        case (.RB, .FB), (.FB, .RB):
            return "Backfield versatility between RB and FB roles. Max ceiling: \(ceilingPct)%."
        case (.FS, .SS), (.SS, .FS):
            return "Safety interchangeability based on athleticism. Max ceiling: \(ceilingPct)%."
        case (.CB, .FS), (.CB, .SS), (.FS, .CB), (.SS, .CB):
            return "DB versatility across secondary positions. Max ceiling: \(ceilingPct)%."
        case (.OLB, .MLB), (.MLB, .OLB):
            return "Linebacker scheme flexibility (3-4/4-3). Max ceiling: \(ceilingPct)%."
        case (.DE, .OLB), (.OLB, .DE):
            return "Edge versatility for 3-4/4-3 scheme conversions. Max ceiling: \(ceilingPct)%."
        case (.DE, .DT), (.DT, .DE):
            return "D-line position shift based on size/speed profile. Max ceiling: \(ceilingPct)%."
        case _ where primary.side == .offense && alt.side == .offense
            && [Position.LT, .LG, .C, .RG, .RT].contains(primary)
            && [Position.LT, .LG, .C, .RG, .RT].contains(alt):
            return "O-line interoperability across positions. Max ceiling: \(ceilingPct)%."
        default:
            return "\(rating.label) fit based on physical attributes. Max ceiling: \(ceilingPct)%."
        }
    }

    // MARK: - Career Trend Arrow

    /// Arrow indicator (rising / prime / declining) shown next to the OVR circle.
    /// Derived directly from the existing `developmentPhase` enum so it stays in sync.
    private var careerTrendArrow: (icon: String, color: Color, label: String) {
        switch developmentPhase {
        case .rising:    return ("arrow.up", .success, "Rising")
        case .prime:     return ("arrow.right", .accentGold, "In Prime")
        case .declining: return ("arrow.down", .danger, "Declining")
        }
    }

    // MARK: - Scheme Mismatch CTA

    /// Head coach of the player's team, if any. Used for scheme-mismatch detection.
    private var teamHeadCoach: Coach? {
        guard let teamID = player.teamID else { return nil }
        return allCoaches.first { $0.teamID == teamID && $0.role == .headCoach }
    }

    /// Display name of the team's offensive or defensive scheme for the player's side.
    /// For offense players we read the HC's offensive scheme; for defense, the defensive scheme.
    /// Special teams players have no scheme assignment so this returns nil.
    private var teamSchemeForPlayer: (key: String, displayName: String)? {
        guard let hc = teamHeadCoach else { return nil }
        switch player.position.side {
        case .offense:
            if let s = hc.offensiveScheme { return (s.rawValue, s.displayName) }
        case .defense:
            if let s = hc.defensiveScheme { return (s.rawValue, s.displayName) }
        case .specialTeams:
            return nil
        }
        return nil
    }

    /// True when the player's best scheme fit is materially different from the team scheme,
    /// AND the player has low familiarity in the team scheme. Threshold mirrors the
    /// CareerDashboard mismatch warning logic (familiarity < 50 in current scheme).
    private var schemeMismatchInfo: (playerScheme: String, teamScheme: String, hcName: String)? {
        guard let best = bestSchemeFit,
              let team = teamSchemeForPlayer,
              let hc = teamHeadCoach else { return nil }
        // Skip if the player's best scheme already matches the team scheme.
        if best.scheme.caseInsensitiveCompare(team.key) == .orderedSame { return nil }
        if best.scheme.caseInsensitiveCompare(team.displayName) == .orderedSame { return nil }
        // Only warn when the player isn't already comfortable in the team scheme.
        let teamFamiliarity = player.schemeFamiliarity[team.key] ?? 0
        guard teamFamiliarity < 50 else { return nil }
        // Pretty-print the player's best scheme: try to match an enum displayName.
        let bestDisplay: String = {
            if let s = OffensiveScheme(rawValue: best.scheme) { return s.displayName }
            if let s = DefensiveScheme(rawValue: best.scheme) { return s.displayName }
            return best.scheme
        }()
        return (playerScheme: bestDisplay, teamScheme: team.displayName, hcName: "Coach \(hc.lastName)")
    }

    /// Yellow callout shown when the player's best scheme doesn't match the team's scheme.
    /// Surfaces the mismatch so the user can consider trading the player or changing scheme.
    @ViewBuilder
    private var schemeMismatchCard: some View {
        if let info = schemeMismatchInfo {
            DSDetailCard("Scheme Mismatch", icon: "exclamationmark.triangle.fill") {
                Text("\(player.lastName) knows **\(info.playerScheme)**. \(info.hcName) runs **\(info.teamScheme)**.")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                DSDetailNote(
                    text: "He installs the club's system from scratch, which costs him snaps and costs the coordinator a package. A trade or a scheme change are the two ways out.",
                    icon: "arrow.triangle.branch",
                    tint: .warning
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .strokeBorder(Color.warning.opacity(0.45), lineWidth: 1)
            )
        }
    }

    // MARK: - Comparable Players (Trade Value)

    /// Up to 3 players in the league at the same position with OVR within ±3 of this player.
    /// Used to anchor the player's trade value against real peers.
    ///
    /// #134a again, and a worse case than the rank badge: the filter is a ±3 OVR
    /// window, so nearly every candidate ties with several others and `prefix(3)`
    /// was picking three names out of the unsorted `@Query` order. The line named
    /// three different peers on three consecutive renders. Same fix, same reason
    /// — the id makes the ordering total.
    private var comparablePlayers: [Player] {
        allLeaguePlayers
            .filter { $0.id != player.id
                && $0.position == player.position
                && abs($0.overall - player.overall) <= 3 }
            .sorted {
                $0.overall != $1.overall
                    ? $0.overall > $1.overall
                    : $0.id.uuidString < $1.id.uuidString
            }
            .prefix(3)
            .map { $0 }
    }

    /// Formatted line: "Allen 86 ($45M) / Burrow 84 ($52M) / Hurts 82 ($48M)".
    private var comparablesText: String? {
        let peers = comparablePlayers
        guard !peers.isEmpty else { return nil }
        return peers.map { p -> String in
            let salaryStr: String
            if p.annualSalary >= 1_000 {
                salaryStr = String(format: "$%.0fM", Double(p.annualSalary) / 1_000.0)
            } else if p.annualSalary > 0 {
                salaryStr = "$\(p.annualSalary)K"
            } else {
                salaryStr = "—"
            }
            return "\(p.lastName) \(p.overall) (\(salaryStr))"
        }.joined(separator: " / ")
    }

    // MARK: - Year-by-Year Contract Breakdown

    /// Estimated cap hit per remaining contract year. Without a live Contract object on
    /// the player here, we approximate using a simple ramp: year 1 = base, then +6% per year
    /// to mirror typical NFL escalators. Returns at least 2 entries to be worth showing.
    private var yearByYearCapHits: [(year: Int, capHitK: Int)] {
        let years = max(0, player.contractYearsRemaining)
        guard years >= 2, player.annualSalary > 0 else { return [] }
        let base = Double(player.annualSalary)
        return (0..<years).map { offset in
            let multiplier = 1.0 + Double(offset) * 0.06
            return (year: offset + 1, capHitK: Int((base * multiplier).rounded()))
        }
    }

    private func formatCapHit(_ thousands: Int) -> String {
        if thousands >= 1_000 {
            return String(format: "$%.1fM", Double(thousands) / 1_000.0)
        }
        return "$\(thousands)K"
    }
}

// MARK: - Market Value Assessment

enum MarketValueAssessment {
    case bargain, fairValue, overpaid

    var label: String {
        switch self {
        case .bargain:   return "Bargain"
        case .fairValue: return "Fair Value"
        case .overpaid:  return "Overpaid"
        }
    }

    var icon: String {
        switch self {
        case .bargain:   return "arrow.down.circle.fill"
        case .fairValue: return "equal.circle.fill"
        case .overpaid:  return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .bargain:   return .success
        case .fairValue: return .accentGold
        case .overpaid:  return .danger
        }
    }
}

// MARK: - Development Phase Info

enum DevelopmentPhaseInfo {
    case rising, prime, declining

    var label: String {
        switch self {
        case .rising:    return "Rising"
        case .prime:     return "Prime"
        case .declining: return "Declining"
        }
    }

    var shortLabel: String {
        switch self {
        case .rising:    return "Rising"
        case .prime:     return "Prime"
        case .declining: return "Decline"
        }
    }

    var icon: String {
        switch self {
        case .rising:    return "arrow.up.right"
        case .prime:     return "star.fill"
        case .declining: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .rising:    return .success
        case .prime:     return .accentGold
        case .declining: return .danger
        }
    }
}

// MARK: - Color-Coded Attribute Row

/// Displays an attribute name and value with color coding:
/// green (80+), gold/yellow (60-79), orange (40-59), red (<40).
struct ColorCodedAttributeRow: View {
    let name: String
    let value: Int

    private var attributeColor: Color {
        colorForAttribute(value)
    }

    private var ratingLabel: String {
        switch value {
        case 80...:   return "elite"
        case 60..<80: return "good"
        case 40..<60: return "average"
        default:      return "below average"
        }
    }

    var body: some View {
        LabeledContent(name) {
            HStack(spacing: 6) {
                // Color bar indicator
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .fill(attributeColor)
                    .frame(width: 3, height: 16)

                Text("\(value)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(attributeColor)
            }
        }
        .accessibilityLabel("\(name), \(value), \(ratingLabel)")
    }
}

// MARK: - Circular Progress View (injury recovery)

/// Small circular progress indicator used for injury recovery progress.
private struct CircularProgressView: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

// The `AttributeRowWithTrend` (#184) and `AttributeRowWithContext` (#182) row
// types were deleted with the list forks that were their only call sites.
//
// #184's trend arrow was never wired to anything: every one of its 14 call
// sites passed `previousValue: nil`, so it printed a grey "---" on every row of
// every player card in the game. #182's league-average delta was real
// information and survives — `attributeGridWithAvg` prints it, in the same
// signed form and on the same ±5 threshold.

// MARK: - Legacy AttributeRow (kept for backward compatibility)

struct AttributeRow: View {
    let name: String
    let value: Int

    var body: some View {
        ColorCodedAttributeRow(name: name, value: value)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayerDetailView(player: Player(
            firstName: "Patrick",
            lastName: "Mahomes",
            position: .QB,
            age: 28,
            yearsPro: 7,
            physical: PhysicalAttributes(
                speed: 72, acceleration: 78, strength: 65,
                agility: 80, stamina: 85, durability: 88
            ),
            mental: MentalAttributes(
                awareness: 94, decisionMaking: 92, clutch: 96,
                workEthic: 88, coachability: 82, leadership: 90
            ),
            positionAttributes: .quarterback(QBAttributes(
                armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                accuracyDeep: 87, pocketPresence: 92, scrambling: 80
            )),
            personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
            morale: 90,
            contractYearsRemaining: 3,
            annualSalary: 45000
        ))
    }
    .modelContainer(for: Player.self, inMemory: true)
}
