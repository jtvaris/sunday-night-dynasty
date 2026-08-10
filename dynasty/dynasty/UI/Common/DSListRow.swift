import SwiftUI

// MARK: - DSListRow — the one list standard
//
// UI_REDESIGN_VISION §2.2, over P2 ("one row component") and P3 ("three
// densities, chosen explicitly"). One anatomy, in this order and no other:
//
//     [rank] [position badge] [portrait] [identity + fixed state-chip slots]
//            [lens columns] [OVR] [trailing] [affordance]
//
// **The anatomy is derived from the Big Board, not invented for it.** The board
// is the screen the user says he likes and the one this wave is forbidden to
// redesign: shared column constants, lens tabs, an OVR that is a dual grade
// rather than an integer, TAPE and MEET as two separate always-visible columns.
// Everything here is that row, generalised — which is why the board's conversion
// is a re-hosting rather than a rewrite, and why the roster can adopt it without
// negotiating a second grammar.
//
// What a screen chooses: its **columns**, its **lens set**, its **density**, and
// which **state slots** it reserves. What a screen never chooses: row structure,
// chip shape, or density arithmetic.
//
// Three structural guarantees this file exists to make, all three of which the
// vision's own iteration 2 got wrong and named by hand:
//
//  1. **Every cell clips itself.** A `nowrap` marker in a fixed-width column
//     with no clipping paints over its neighbour — "CHARACTER" (87 pt) in a
//     66 pt `RISK` column landed on top of the `TAPE` grade. `dsColumn(_:)` is
//     the only sanctioned way to give a cell a width, and it shrinks before it
//     clips.
//  2. **The rank slot reserves its movement row on every line.** A rank with a
//     `↑6` badge is two lines tall and a rank without one is a single line, so
//     the first column of a 350-row list visibly jitters down the page.
//     `DSRankSlot` is a fixed two-row box whose second row is empty when there
//     is no mover.
//  3. **Every informational glyph clears the 11 pt display floor.** The board's
//     own micro chips ran 6–8 pt. `DSType.display` clamps, so a call site
//     cannot reintroduce the tail by asking for 7.
//
// One thing this component deliberately does NOT own: the contents of the
// identity block. The board puts a mark chip, a compare tick and a user-grade
// badge on the name line and a declaration chip beside its slots; the roster
// puts contract and personality badges there. Modelling that as parameters
// would be a fourth grammar. The row owns the identity SLOT — its minimum
// width, its alignment, its clipping — and the screen fills it.

// MARK: - Density (P3)

/// A named decision on every surface, never an accident of who wrote it.
///
/// Today the same conceptual density lands anywhere between
/// `padding(.vertical, 4)` and 16. These are the only three values a list is
/// allowed to be, and the tier is a visible control on list screens so the user
/// can trade breadth for depth without leaving the screen.
enum DSListDensity: String, CaseIterable, Identifiable {
    /// ~32 pt, ≤ 4 info elements — rails, hub cards, mini-standings.
    case glance
    /// ~44 pt, 8–14 info elements — the default list: roster, board, FA market,
    /// standings.
    case scan
    /// Card stacks, unbounded — detail screens, game log, comparison.
    case study

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glance: return "Glance"
        case .scan:   return "Scan"
        case .study:  return "Study"
        }
    }

    /// The row's minimum height.
    ///
    /// `scan` is 44 because §2.12 has no exceptions: "every button, link,
    /// capsule, segment, stepper AND ROW is ≥ 44 pt in both axes — measured
    /// rects, not declared styles". The board's rows measured 34 before this
    /// wave, which is the same finding the audit recorded against every other
    /// small control in the app. A list row is the largest touch target on a
    /// list screen and it was under the floor.
    var minHeight: CGFloat {
        switch self {
        case .glance: return 32
        case .scan:   return 44
        case .study:  return 56
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .glance: return 1
        case .scan:   return 2
        case .study:  return DSSpacing.xs
        }
    }

    /// Width reserved for the portrait slot — the face plus its leading gap.
    /// A screen that puts something else in the slot (the roster's depth chip
    /// travels with the face) overrides it with `portraitWidth:`.
    var portraitColumn: CGFloat {
        switch self {
        case .glance: return 0
        case .scan:   return DSListColumn.scanPortrait
        case .study:  return 48
        }
    }

    /// The name's point size in the text voice. Never above 18 (§2.10).
    var nameSize: CGFloat {
        switch self {
        case .glance: return 12
        case .scan:   return 14
        case .study:  return 16
        }
    }
}

// MARK: - Shared column widths
//
// §2.2: "Header and row share a `Column` width enum, as Big Board and
// `PlayerRowView` already do — that discipline generalises."
//
// These are the BOARD'S SHIPPED WIDTHS, named. They are not a fresh ladder: the
// point of the enum is that a header and its cells read the same constant from
// the same place, which is how `PlayerRowView.Column` already stops "OVR" from
// being 32 pt on one side and 40 on the other. Re-basing the numbers onto a
// tidy scale would be a visual change to the one screen this wave is forbidden
// to redesign, so it is not done here.

enum DSListColumn {
    /// A leading row action that lives OUTSIDE the row's own anatomy — the
    /// board's mark button. 44 pt because it is a real control.
    static let leadingAction: CGFloat = 44
    /// Rank plus its reserved movement row.
    static let rank: CGFloat = 24
    /// The position badge.
    static let position: CGFloat = 36
    /// The portrait slot at `scan` density, for headers and other call sites
    /// that must reserve the gutter without owning a `DSListDensity`. Same
    /// number as `DSListDensity.scan.portraitColumn`, which reads it.
    static let scanPortrait: CGFloat = 36
    /// One glyph: a form arrow, a morale face, a dev arrow.
    static let glyph: CGFloat = 24
    /// Two to three characters: "3yr", "GRD", a letter grade.
    static let tight: CGFloat = 30
    /// A number over a 3-letter caption: LRN / SPD / a skill.
    static let attribute: CGFloat = 34
    /// The value read (`+18` / `−12`).
    static let value: CGFloat = 34
    /// Age plus a sort chevron.
    static let age: CGFloat = 36
    /// The meeting read — an exact interview number.
    static let meet: CGFloat = 38
    /// A bare OVR integer plus a sort chevron.
    static let ovr: CGFloat = 40
    /// The tape read — a scouted band, "C+/A-".
    static let tape: CGFloat = 42
    /// A health / injury marker.
    static let health: CGFloat = 28
    /// A short word: "Prime", "Rising".
    static let label: CGFloat = 48
    /// The dual grade (`DualGradeDisplay`: your number over the scouts' range).
    static let grade: CGFloat = 50
    /// Money, e.g. "$12.3M" over a caption.
    static let money: CGFloat = 52
    /// A projection, e.g. "Rd 2" over two movement arrows.
    static let projection: CGFloat = 52
    /// The longest state label the app prints in a cell ("Discouraged").
    static let state: CGFloat = 76
    /// The trailing affordance: a drag handle, a chevron.
    static let affordance: CGFloat = 22
    /// The identity block's floor. It is the one flexible column.
    static let identityMin: CGFloat = 80
    /// Gap between the portrait slot and the identity block.
    static let identityGap: CGFloat = 6
}

extension View {
    /// Gives a cell its column, and makes the cell responsible for staying
    /// inside it.
    ///
    /// Shrink, then clip: `lineLimit(1)` + `minimumScaleFactor` are what keep a
    /// label from wrapping mid-word inside a fixed box ("OVR" became "OV / R"
    /// the moment a sort chevron joined it), and `clipped()` is the backstop for
    /// anything that still will not fit. A fixed width WITHOUT clipping is the
    /// bug §2.2 names: the marker simply paints over the next column.
    func dsColumn(_ width: CGFloat, alignment: Alignment = .center) -> some View {
        self
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: alignment)
            .clipped()
    }
}

// MARK: - Column header

/// One label over one column, in the display voice at the 11 pt floor.
///
/// Big Board's header shipped at 8 pt bold, which is three steps under the floor
/// on the row of words that tells the user what every number below it means.
struct DSColumnHeader: View {
    let title: String
    var width: CGFloat?
    var alignment: Alignment = .center

    init(_ title: String, width: CGFloat? = nil, alignment: Alignment = .center) {
        self.title = title
        self.width = width
        self.alignment = alignment
    }

    var body: some View {
        Text(title.uppercased())
            .font(DSType.display(11, .heavy))
            .tracking(0.6)
            .foregroundStyle(Color.textTertiary)
            .modifier(DSOptionalColumnWidth(width: width, alignment: alignment))
    }
}

/// `dsColumn` when a width is given, plain otherwise — the NAME column is the
/// one that flexes.
private struct DSOptionalColumnWidth: ViewModifier {
    let width: CGFloat?
    let alignment: Alignment

    @ViewBuilder
    func body(content: Content) -> some View {
        if let width {
            content.dsColumn(width, alignment: alignment)
        } else {
            content.lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Rank slot

/// A rank, and the hand-move it came from.
struct DSRank {
    let value: Int
    /// Where the consensus had him. `nil`, or equal to `value`, means he has not
    /// been moved — the movement row is still reserved.
    var origin: Int? = nil
    /// Overrides the default tint (gold for #1, primary for the top five).
    var tint: Color? = nil

    var movedUp: Bool? {
        guard let origin, origin != value else { return nil }
        return value < origin
    }
}

/// The rank column: a fixed two-row box.
///
/// §2.2, verbatim: "The rank slot reserves its movement row on every line … the
/// slot is a fixed two-row box whose second row is empty when there is no
/// mover." Before this the board's first column jittered down the page as
/// hand-moved rows grew a second line.
struct DSRankSlot: View {
    let rank: DSRank
    var width: CGFloat = DSListColumn.rank

    /// The reserved movement row. 13 pt is one 11 pt display line, so the two
    /// rows together (26 pt) still sit inside the 30 pt portrait that sets a
    /// scan row's content height — reserving the row costs the list nothing.
    private static let movementRowHeight: CGFloat = 13

    var body: some View {
        VStack(spacing: 0) {
            Text("\(rank.value)")
                .font(DSType.display(11, .heavy))
                .foregroundStyle(tint)
            movementRow
                .frame(height: Self.movementRowHeight)
        }
        .dsColumn(width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var movementRow: some View {
        if let movedUp = rank.movedUp, let origin = rank.origin {
            Text("\(movedUp ? "\u{2191}" : "\u{2193}")\(origin)")
                .font(DSType.display(11, .semibold))
                .foregroundStyle(movedUp ? Color.success : Color.dangerText)
        } else {
            // Reserved, not absent. `hidden()` keeps the box exactly one line
            // tall without painting anything in it.
            Text("0")
                .font(DSType.display(11, .semibold))
                .hidden()
        }
    }

    private var tint: Color {
        if let explicit = rank.tint { return explicit }
        if let movedUp = rank.movedUp { return movedUp ? .success : .danger }
        switch rank.value {
        case 1:     return .accentGold
        case 2...5: return .textPrimary
        default:    return .textSecondary
        }
    }

    private var spoken: String {
        guard let movedUp = rank.movedUp, let origin = rank.origin else {
            return "Rank \(rank.value)"
        }
        return "Rank \(rank.value), moved \(movedUp ? "up" : "down") from \(origin)"
    }
}

// MARK: - Position badge

/// The position badge, and whether it is a control.
struct DSRowBadge {
    let text: String
    var tint: Color
    var accessibilityLabel: String? = nil
    /// Non-nil makes the badge a button — and makes it look like one, with the
    /// hairline the flat badge does not carry.
    var action: (() -> Void)? = nil
}

struct DSPositionBadge: View {
    let badge: DSRowBadge
    var width: CGFloat = DSListColumn.position
    var height: CGFloat = 24

    var body: some View {
        if let action = badge.action {
            Button(action: action) {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(badge.accessibilityLabel ?? badge.text)
            .accessibilityHint("Tap to change")
        } else {
            content
                .accessibilityLabel(badge.accessibilityLabel ?? badge.text)
        }
    }

    private var content: some View {
        Text(badge.text)
            .font(DSType.display(11, .heavy))
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, height: height)
            .background(badge.tint, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            .overlay(
                badge.action != nil
                    ? RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .strokeBorder(Color.textTertiary.opacity(0.5), lineWidth: 1)
                    : nil
            )
    }
}

// MARK: - Trailing affordance

/// What sits at the trailing edge of a row and says what the row does.
enum DSRowAffordance {
    /// Nothing — the row is hosted in a `NavigationLink` that draws its own
    /// chevron, so drawing a second one would be two affordances for one tap.
    case none
    /// A reorderable list.
    case dragHandle
    /// A pushed destination the row owns itself.
    case disclosure
    /// Anything else, by SF Symbol name. Never a dingbat, never an emoji
    /// (§2.12).
    case icon(String)

    var systemImage: String? {
        switch self {
        case .none:              return nil
        case .dragHandle:        return "line.3.horizontal"
        case .disclosure:        return "chevron.right"
        case let .icon(name):    return name
        }
    }
}

// MARK: - DSListRow

/// One row of a list of entities-with-stats.
///
/// Three builders, in anatomy order:
///
///   * `portrait` — the face (and anything that travels with it, like the
///     roster's depth chip). Framed to `portraitWidth` and clipped.
///   * `identity` — the name line and whatever the screen hangs under it,
///     usually a `DSStateSlotRow`. The one flexible column.
///   * `columns` — everything from the OVR cell to the last always-visible
///     column, flattened into the row's `HStack`, so a `Spacer(minLength:)` in
///     the middle of the block works exactly as it does when written inline.
///     Give every cell in it a `dsColumn(_:)`.
struct DSListRow<Portrait: View, Identity: View, Columns: View>: View {

    var density: DSListDensity = .scan
    var rank: DSRank? = nil
    var badge: DSRowBadge? = nil
    /// Overrides `density.portraitColumn` for a slot that carries more than a
    /// face.
    var portraitWidth: CGFloat? = nil
    var affordance: DSRowAffordance = .none

    @ViewBuilder var portrait: () -> Portrait
    @ViewBuilder var identity: () -> Identity
    @ViewBuilder var columns: () -> Columns

    init(
        density: DSListDensity = .scan,
        rank: DSRank? = nil,
        badge: DSRowBadge? = nil,
        portraitWidth: CGFloat? = nil,
        affordance: DSRowAffordance = .none,
        @ViewBuilder portrait: @escaping () -> Portrait,
        @ViewBuilder identity: @escaping () -> Identity,
        @ViewBuilder columns: @escaping () -> Columns
    ) {
        self.density = density
        self.rank = rank
        self.badge = badge
        self.portraitWidth = portraitWidth
        self.affordance = affordance
        self.portrait = portrait
        self.identity = identity
        self.columns = columns
    }

    var body: some View {
        HStack(spacing: 0) {
            if let rank {
                DSRankSlot(rank: rank)
            }

            if let badge {
                DSPositionBadge(badge: badge)
            }

            portrait()
                .dsColumn(portraitWidth ?? density.portraitColumn, alignment: .leading)

            identity()
                .frame(minWidth: DSListColumn.identityMin, alignment: .leading)
                .padding(.leading, DSListColumn.identityGap)
                // The identity block is the flexible column, so it is also the
                // one that has to give way — without this it pushes the fixed
                // columns off the trailing edge instead of truncating a name.
                .clipped()

            columns()

            if let symbol = affordance.systemImage {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .dsColumn(DSListColumn.affordance)
            }
        }
        .frame(minHeight: density.minHeight)
        .padding(.vertical, density.verticalPadding)
    }
}

// MARK: - DSListHeaderRow

/// The header that labels a `DSListRow`, built from the same slots so the two
/// cannot drift.
///
/// It reserves the leading slots rather than labelling them — a rank column
/// headed "#" and an unlabelled portrait gutter — because a header whose gutters
/// are missing puts every label one column left of the numbers it describes.
/// That exact bug is documented twice in this codebase, once on the board and
/// once on the roster.
struct DSListHeaderRow<Columns: View>: View {

    var density: DSListDensity = .scan
    /// A leading control column that lives outside the anatomy (the board's
    /// mark button). 0 when the list has none.
    var leadingGutter: CGFloat = 0
    var reservesRank: Bool = false
    var rankLabel: String = "#"
    var reservesBadge: Bool = false
    var badgeLabel: String = "POS"
    var portraitWidth: CGFloat? = nil
    var identityLabel: String = "NAME"
    var affordance: DSRowAffordance = .none

    @ViewBuilder var columns: () -> Columns

    init(
        density: DSListDensity = .scan,
        leadingGutter: CGFloat = 0,
        reservesRank: Bool = false,
        rankLabel: String = "#",
        reservesBadge: Bool = false,
        badgeLabel: String = "POS",
        portraitWidth: CGFloat? = nil,
        identityLabel: String = "NAME",
        affordance: DSRowAffordance = .none,
        @ViewBuilder columns: @escaping () -> Columns
    ) {
        self.density = density
        self.leadingGutter = leadingGutter
        self.reservesRank = reservesRank
        self.rankLabel = rankLabel
        self.reservesBadge = reservesBadge
        self.badgeLabel = badgeLabel
        self.portraitWidth = portraitWidth
        self.identityLabel = identityLabel
        self.affordance = affordance
        self.columns = columns
    }

    var body: some View {
        HStack(spacing: 0) {
            if leadingGutter > 0 {
                Color.clear.frame(width: leadingGutter, height: 1)
            }
            if reservesRank {
                DSColumnHeader(rankLabel, width: DSListColumn.rank)
            }
            if reservesBadge {
                DSColumnHeader(badgeLabel, width: DSListColumn.position)
            }
            Color.clear
                .frame(width: portraitWidth ?? density.portraitColumn, height: 1)

            DSColumnHeader(identityLabel, alignment: .leading)
                .frame(minWidth: DSListColumn.identityMin, alignment: .leading)
                .padding(.leading, DSListColumn.identityGap)

            columns()

            if affordance.systemImage != nil {
                Color.clear.frame(width: DSListColumn.affordance, height: 1)
            }
        }
    }
}

// MARK: - Lens tabs

/// The control that swaps a list's trailing columns — and nothing else.
///
/// §2.2: "Lens tabs swap only the trailing columns. One control style, capsule,
/// one selected fill." The app shipped at least three: the board's mode chips,
/// the roster's analysis pills (with a blue glow the board's do not have) and a
/// `.pickerStyle(.segmented)`. Blue is the selected fill because blue means
/// "informational / selected" (P7) — gold has exactly three jobs and this is
/// none of them.
struct DSLensTabs<Lens: Hashable>: View {

    @Binding var selection: Lens
    let lenses: [Lens]
    let label: (Lens) -> String
    var icon: ((Lens) -> String?)? = nil
    /// The uppercase ident that says what the strip controls ("ANALYSIS").
    var title: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            if let title {
                HStack(spacing: DSSpacing.xxs + 2) {
                    Text(title.uppercased())
                        .font(DSType.display(11, .heavy))
                        .tracking(0.5)
                        .foregroundStyle(Color.textSecondary)
                    Text("\u{00B7}")
                        .font(DSType.display(11, .heavy))
                        .foregroundStyle(Color.textTertiary)
                    Text(label(selection).uppercased())
                        .font(DSType.display(11, .heavy))
                        .tracking(0.5)
                        .foregroundStyle(Color.accentBlue)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DSSpacing.xxs)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xxs + 2) {
                    ForEach(lenses, id: \.self) { lens in
                        capsule(for: lens)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    private func capsule(for lens: Lens) -> some View {
        let isSelected = lens == selection
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = lens }
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                if let symbol = icon?(lens) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                }
                Text(label(lens))
                    .font(DSType.text(13, isSelected ? .bold : .medium))
            }
            .lineLimit(1)
            .padding(.horizontal, DSSpacing.sm)
            // 44 pt, measured — a lens capsule is a control and §2.12 has no
            // exceptions. It shipped at 30 pt.
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? Color.backgroundPlate : Color.textSecondary)
            .background(isSelected ? Color.accentBlue : Color.backgroundTertiary, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.accentBlue : Color.surfaceBorder,
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(lens))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Group header rollup

/// The rollup a group header carries — Big Board's tier header, generalised.
///
/// §2.2: `QUARTERBACKS · Group grade A− · 3 players · $41.2M cap`. One shape, so
/// a position group on the roster and a tier on the board read as the same
/// object at the same weight.
struct DSGroupRollup: View {
    let title: String
    /// Short facts, in the order the screen wants them read. Already formatted —
    /// the header does not do arithmetic.
    var facts: [String] = []
    var tint: Color = .textSecondary

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Text(title.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.8)
                .foregroundStyle(tint)
            if !facts.isEmpty {
                Text(facts.joined(separator: " \u{00B7} "))
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }
}
