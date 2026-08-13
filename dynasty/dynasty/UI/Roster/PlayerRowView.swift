import SwiftUI

struct PlayerRowView: View {

    /// Column widths shared with `RosterView`'s sortable header.
    ///
    /// The header and the cells used to carry their own literals, so a column
    /// could be 32pt wide in one file and 40 in the other — which is exactly
    /// how the Mental mode's "OVR" sort button ended up 32pt wide and wrapped
    /// to "OV / R" the moment the sort chevron joined it, and how "Discouraged"
    /// ended up hyphen-less-wrapped into "Disco / urage / d" in a 56pt box.
    /// One definition, read from both sides.
    ///
    /// Wave 1 re-bases these onto `DSListColumn` (`UI/Common/DSListRow.swift`),
    /// which is the same discipline one level up: the roster and the Big Board
    /// now read one ladder rather than two that happen to agree. Every value
    /// below is byte-for-byte the width that shipped — the point of the move is
    /// that the board's `OVR` and the roster's are provably the same 40, not
    /// that either of them changes.
    enum Column {
        /// Fits "Age" plus the sort chevron on one line.
        static let age = DSListColumn.age                 // 36
        /// Fits "OVR" plus the sort chevron on one line.
        static let ovr = DSListColumn.ovr                 // 40
        /// Fits "Discouraged", the longest motivation label.
        static let motivation = DSListColumn.state        // 76
        /// Contracts mode: dead cap if cut, e.g. "$12.3M" over a "dead" caption.
        static let deadCap = DSListColumn.label           // 48
        /// Contracts mode: net cap saved by cutting, same shape as `deadCap`.
        static let capSavings = DSListColumn.label        // 48
        /// The depth chip that rides in front of the face.
        static let depthChip: CGFloat = 14
        /// The whole leading slot the depth chip and the face share, including
        /// the 6pt gutters that used to come from the row `HStack`'s spacing:
        /// 6 + 14 + 6 + 30. `DSListRow` lays out at spacing 0, so the gutters
        /// have to live inside the slot that owns them.
        static let portraitSlot: CGFloat = 56
        /// Inter-column gap inside the trailing block. It is 6 and not 0
        /// because `RosterView.sortableHeader` is right-anchored against the
        /// same edge: at spacing 0 the data block was 42pt narrower than the
        /// header labelling it and every label sat right of its own numbers.
        static let gap: CGFloat = 6
    }

    let player: Player
    /// Depth chart index: 0 = starter, 1 = backup, 2+ = 3rd string. nil = unknown.
    var depthIndex: Int? = nil
    /// Optional detailed contract for cap hit display.
    var contract: Contract? = nil
    /// Analysis view mode that determines which columns to show.
    var analysisMode: RosterAnalysisMode = .overview
    /// Total number of players at this position (used for promote/demote bounds).
    var positionGroupCount: Int = 0
    /// Called when the user requests a depth change. Parameter is the new depth index.
    var onDepthChange: ((Int) -> Void)? = nil
    /// Called when the user taps the position badge to change position (#175).
    var onPositionBadgeTap: (() -> Void)? = nil
    /// Called when the user taps the starter badge to pick a new starter (#198).
    var onStarterBadgeTap: (() -> Void)? = nil
    /// Number of starters at this player's specific position (scheme-aware). Used for depth numbering (#279).
    var starterCountForPosition: Int = 1
    /// Team salary cap in thousands — used to calculate cap% per player.
    var teamSalaryCap: Int = ContractEngine.openingSalaryCap
    /// The scheme this player's unit actually runs, as the key
    /// `Player.schemeFamiliarity` stores it. Feeds the `FIT` slot; `nil` leaves
    /// the slot honestly empty rather than filling it with the deepest scheme
    /// he learned at a previous club.
    var installedScheme: String? = nil

    /// TRACK B — season + phase, injected once by `CareerShellView`. A rookie
    /// who has not yet reported to training camp shows his scouting BAND where
    /// his OVR would be; everyone else, and every context that never got the
    /// context (previews, stand-alone lists), reads exactly as before.
    @Environment(\.rookieFog) private var rookieFog

    /// True while this player's exact ratings are still fogged.
    private var isFogged: Bool { rookieFog.isFogged(player) }

    /// The OVR cell, in whichever of the six analysis modes asked for it.
    /// Display only — sorting, the depth chart and every engine keep reading
    /// `player.overall` itself.
    @ViewBuilder
    private func ovrCell(font: Font) -> some View {
        if isFogged {
            RookieBandChip(player: player, font: .caption2.monospaced().weight(.heavy))
                .dsColumn(Column.ovr)
        } else {
            Text("\(player.overall)")
                .font(font)
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .dsColumn(Column.ovr)
        }
    }

    /// The roster row is the second mount of the list standard
    /// (`UI_REDESIGN_VISION` §2.2), and Wave 1 converts it right after the Big
    /// Board precisely because it already mirrored it — same shared column
    /// enum, same lens-swapped trailing block, same anatomy. If the abstraction
    /// were wrong, it would be wrong here cheaply.
    ///
    /// What the conversion changed, and nothing else:
    ///
    ///  1. The hand-rolled `HStack` became `DSListRow`, so the row measures
    ///     44pt (§2.12: rows are controls and had no exception) and the leading
    ///     slots come from one place rather than from four inline frames.
    ///  2. The five conditional badges under the name became three FIXED slots
    ///     — `FIT` / `EXT` / `HLTH` (`DSStateSlotRow`). This is §2.2's
    ///     load-bearing idea: the badges only ever appeared when the fact was
    ///     TRUE, so a row with nothing wrong with it and a row nobody has
    ///     looked at were the same empty line. Now the slot is always in its
    ///     position and an unfilled one is a dimmed, dashed word.
    ///  3. Every cell width goes through `dsColumn`, which shrinks then clips.
    ///     The header already documented one paint-over bug in this file
    ///     ("Discouraged" wrapping to "Disco / urage / d"); a fixed frame with
    ///     no clipping is how that class of bug happens.
    ///
    /// The trailing block keeps its 6pt inter-column gap (`Column.gap`) because
    /// `RosterView.sortableHeader` is right-anchored against the same edge and
    /// documents the 42pt drift that appears at spacing 0.
    var body: some View {
        DSListRow(
            density: .scan,
            // No rank slot: a roster is grouped by position, not ordered
            // 1…53, and reserving a rank column on an unranked list would be
            // 24pt of gutter carrying nothing.
            badge: DSRowBadge(
                text: player.position.rawValue,
                tint: positionColor,
                accessibilityLabel: "\(player.position.rawValue), \(player.position.side.rawValue)",
                action: onPositionBadgeTap
            ),
            portraitWidth: Column.portraitSlot
        ) {
            // The depth chip travels with the face — it is a fact about where
            // this man stands, not a column of its own — which is the case
            // `portraitWidth` exists for.
            HStack(spacing: Column.gap) {
                depthIndicator
                    .frame(width: Column.depthChip, alignment: .center)
                PersonFaceView(player: player, size: .small)
            }
            .padding(.leading, Column.gap)
        } identity: {
            identityBlock
        } columns: {
            Spacer(minLength: 2)

            // Mode-specific columns — the lens. Only the trailing block swaps.
            HStack(spacing: Column.gap) {
                switch analysisMode {
                case .overview:
                    overviewColumns
                case .contracts:
                    contractColumns
                case .development:
                    developmentColumns
                case .physical:
                    physicalColumns
                case .attributes:
                    attributeColumns
                case .mental:
                    mentalColumns
                case .depth:
                    depthColumns
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Identity block

    /// Name line, then the three reserved state slots.
    ///
    /// `DSListRow` owns the identity SLOT — its minimum width, its alignment
    /// and its clipping — and the screen owns what goes in it.
    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            // 14, from the density, not 15 from `.subheadline`. The board's
            // name line was already 14 and the two lists disagreeing by a
            // point is exactly the drift one standard exists to stop.
            Text(player.fullName)
                .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            HStack(spacing: 4) {
                DSStateSlotRow(slots: rosterSlots)

                // The two states that are neither a slot nor a routine fact.
                // They are rare, they are trailing, and they sit at the end of
                // the ONE flexible column, so they cannot shift a fixed cell.
                if player.isFranchiseTagged {
                    DSStatusPill(label: "Tag", tone: .warn, showsDot: false,
                                 spokenLabel: "Franchise tagged")
                }
                if player.isHoldingOut {
                    DSStatusPill(label: "Out", tone: .bad, showsDot: false,
                                 spokenLabel: "Holding out")
                }

                // R25: personality archetype — a scouting fact, not a state,
                // so it stays a word rather than becoming a fourth pill.
                Text(player.personality.archetype.shortLabel)
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(personalityTierColor)
            }
            .lineLimit(1)
        }
    }

    /// The roster's three fixed slots — `FIT` · `EXT` · `HLTH` (§2.2).
    ///
    /// Each is always drawn, in this order, whether or not the fact behind it
    /// exists. What the user scans for is the gap.
    ///
    /// `FIT` is honest about not knowing: the row is handed the scheme its unit
    /// runs (`installedScheme`) and reads `Player.schemeFamiliarity` for it. No
    /// scheme wired to this list means the slot is `empty` — the word
    /// "unknown", printed — rather than a number invented from the deepest
    /// scheme he happens to have learned somewhere else.
    private var rosterSlots: [DSStateSlot] {
        [fitSlot, extensionSlot, healthSlot]
    }

    private var fitSlot: DSStateSlot {
        guard let installedScheme,
              let familiarity = player.schemeFamiliarity[installedScheme] else {
            return DSStateSlot(
                label: "FIT",
                tone: .empty,
                spokenLabel: "Scheme fit unknown — he has not taken a rep in this scheme"
            )
        }
        // Thresholds mirror the development engine's own scheme-fit bands
        // (`PlayerDevelopmentEngine.updatePotentialRealization`: 0.8 / 0.6 /
        // 0.4 on a 0–1 scale), so the chip and the engine cannot disagree about
        // who is comfortable.
        let tone: DSStatusPill.Tone
        switch familiarity {
        case 80...:   tone = .ok
        case 60..<80: tone = .neutral
        default:      tone = .warn
        }
        return DSStateSlot(
            label: "FIT",
            tone: tone,
            value: "\(familiarity)",
            spokenLabel: "Scheme familiarity \(familiarity) of 100"
        )
    }

    private var extensionSlot: DSStateSlot {
        let years = player.contractYearsRemaining
        guard years > 0 else {
            return DSStateSlot(
                label: "EXT",
                tone: .bad,
                value: "0",
                spokenLabel: "Contract expires this offseason"
            )
        }
        return DSStateSlot(
            label: "EXT",
            tone: years <= 1 ? .warn : .ok,
            value: "\(years)y",
            spokenLabel: years == 1
                ? "One year left on his deal"
                : "\(years) years left on his deal"
        )
    }

    private var healthSlot: DSStateSlot {
        guard player.isInjured else {
            return DSStateSlot(label: "HLTH", tone: .ok,
                               spokenLabel: "Available")
        }
        let weeks = player.injuryWeeksRemaining
        return DSStateSlot(
            label: "HLTH",
            tone: weeks >= 4 ? .bad : .warn,
            value: "\(weeks)w",
            spokenLabel: "Injured, \(weeks) week\(weeks == 1 ? "" : "s") remaining"
        )
    }

    // MARK: - Mental Columns (LRN/CMP analysis — TODO §6)

    /// The scouting-report trio the draft surfaces already speak (LRN/CMP/WE)
    /// plus the live motivation state, so the roster can be read the way the
    /// development engine reads it.
    private var mentalColumns: some View {
        Group {
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .dsColumn(Column.age)

            ovrCell(font: .caption.monospacedDigit())

            colorCodedMiniAttribute(value: player.learning, label: "LRN")
                .dsColumn(DSListColumn.attribute)

            colorCodedMiniAttribute(value: player.competitiveness, label: "CMP")
                .dsColumn(DSListColumn.attribute)

            colorCodedMiniAttribute(value: player.mental.workEthic, label: "WE")
                .dsColumn(DSListColumn.attribute)

            // `lineLimit` + `minimumScaleFactor` rather than a wider box alone:
            // the state names differ by five characters, so the widest one has
            // to shrink a hair instead of breaking mid-word.
            Text(player.motivationState.displayName)
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .dsColumn(Column.motivation)
                .accessibilityLabel("Motivation \(player.motivationState.displayName)")
        }
    }

    // MARK: - Overview Columns (default)

    private var overviewColumns: some View {
        Group {
            // Age
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .dsColumn(Column.age)

            // Form indicator (#97)
            formColumn

            // OVR (large, color-coded)
            ovrCell(font: .callout.monospacedDigit())

            // Development potential indicator
            Text(shortPotentialLabel)
                .font(.system(size: DSType.Size.body, weight: .bold))
                .foregroundStyle(shortPotentialColor)
                .dsColumn(20)

            // Cap Hit + cap%
            VStack(alignment: .trailing, spacing: 0) {
                Text(formattedCapHit)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                Text(capPercentLabel)
                    .font(DSType.display(11, .medium))
                    .foregroundStyle(capPercentColor)
            }
            .dsColumn(DSListColumn.money, alignment: .trailing)

            // Contract years remaining
            contractYearsLabel
                .dsColumn(DSListColumn.tight)

            // Morale icon
            moraleIndicator
                .dsColumn(DSListColumn.glyph)

            // Health status
            healthIndicator
                .dsColumn(DSListColumn.health)
        }
    }

    // MARK: - Contract Columns

    private var contractColumns: some View {
        Group {
            // DEAD and SAVE lead the group on purpose. `RosterView`'s header row
            // is right-aligned against the same trailing edge as these cells, so
            // appending a column would have slid every existing header label one
            // column off its own numbers. Added at the head, the five headed
            // columns (Salary / Cap / Yrs / FA / OVR) keep their alignment and
            // the two new ones carry their own captions until the header learns
            // to label them.

            // Dead cap if cut — the number that decides whether a bad contract
            // is escapable at all.
            capColumn(
                value: deadCapIfCut,
                caption: "dead",
                color: deadCapIfCut > 0 ? Color.danger : Color.textTertiary,
                width: Column.deadCap
            )

            // Net cap saved by the release. Cutting is only ever worth what is
            // left after the dead money, which is why the two travel together.
            capColumn(
                value: capSavingsIfCut,
                caption: "save",
                color: capSavingsIfCut > 0 ? Color.success : Color.textTertiary,
                width: Column.capSavings
            )

            // Base Salary
            Text(formattedSalary)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .dsColumn(DSListColumn.money, alignment: .trailing)

            // Cap Hit
            VStack(alignment: .trailing, spacing: 0) {
                Text(formattedCapHit)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentGold)
                Text("cap")
                    .font(DSType.display(11, .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .dsColumn(DSListColumn.money, alignment: .trailing)

            // Years remaining
            contractYearsLabel
                .dsColumn(DSListColumn.attribute)

            // Free agent year estimate. "FA 31" read as a season — it is the
            // player's AGE when the deal runs out, so it is written like one.
            Text("FA @\(player.age + player.contractYearsRemaining)")
                .font(DSType.display(11, .medium))
                .foregroundStyle(player.contractYearsRemaining <= 1 ? Color.warning : Color.textTertiary)
                .dsColumn(DSListColumn.projection - 12)

            // OVR for context
            ovrCell(font: .caption.monospacedDigit())
        }
    }

    /// A money cell with its own caption — the shape the cap-hit column already
    /// uses, factored out so DEAD and SAVE read as the same component.
    private func capColumn(value: Int, caption: String, color: Color, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(formatSalary(value))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(caption)
                .font(DSType.display(11, .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .dsColumn(width, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption == "dead" ? "Dead cap if cut" : "Cap saved by cutting") \(formatSalary(value))")
    }

    // MARK: - Development Columns

    private var developmentColumns: some View {
        Group {
            // Age
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .dsColumn(Column.age)

            // OVR
            ovrCell(font: .caption.monospacedDigit())

            // Potential (hidden value shown as fuzzy label)
            Text(potentialLabel)
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.accentGold)
                .dsColumn(DSListColumn.projection - 12)

            // Development arrow
            developmentArrow
                .dsColumn(20)

            // Phase label
            Text(developmentPhaseLabel)
                .font(DSType.display(11, .medium))
                .foregroundStyle(developmentTrend.color)
                .dsColumn(DSListColumn.label)

            // Form
            formColumn

            // Work ethic indicator
            colorCodedMiniAttribute(value: player.mental.workEthic, label: "WE")
                .dsColumn(32)
        }
    }

    // MARK: - Physical Columns

    private var physicalColumns: some View {
        Group {
            colorCodedMiniAttribute(value: player.physical.speed, label: "SPD")
                .dsColumn(DSListColumn.attribute)
            colorCodedMiniAttribute(value: player.physical.strength, label: "STR")
                .dsColumn(DSListColumn.attribute)
            colorCodedMiniAttribute(value: player.physical.stamina, label: "STA")
                .dsColumn(DSListColumn.attribute)
            colorCodedMiniAttribute(value: player.physical.durability, label: "DUR")
                .dsColumn(DSListColumn.attribute)

            // Health
            healthIndicator
                .dsColumn(DSListColumn.health)

            // OVR
            ovrCell(font: .caption.monospacedDigit())
        }
    }

    // MARK: - Position Skills Columns (#280)

    /// Returns position-specific attribute tuples: (value, label).
    private var positionSkillAttributes: [(value: Int, label: String)] {
        switch player.positionAttributes {
        case .quarterback(let a):
            return [(a.armStrength, "ARM"), (a.accuracyShort, "SHT"), (a.accuracyDeep, "DEP"), (a.pocketPresence, "POC")]
        case .wideReceiver(let a):
            return [(a.routeRunning, "RTE"), (a.catching, "CTH"), (a.release, "REL")]
        case .runningBack(let a):
            return [(a.vision, "VIS"), (a.elusiveness, "ELU"), (a.breakTackle, "TRK")]
        case .tightEnd(let a):
            return [(a.blocking, "BLK"), (a.catching, "CTH"), (a.routeRunning, "RTE")]
        case .offensiveLine(let a):
            return [(a.passBlock, "PBK"), (a.runBlock, "RBK"), (a.anchor, "ANC")]
        case .defensiveLine(let a):
            return [(a.passRush, "PRU"), (a.blockShedding, "RST"), (a.powerMoves, "PWR")]
        case .linebacker(let a):
            return [(a.tackling, "TKL"), (a.zoneCoverage, "ZCV"), (a.manCoverage, "MCV")]
        case .defensiveBack(let a):
            if player.position == .CB {
                return [(a.manCoverage, "MAN"), (a.zoneCoverage, "ZON"), (a.press, "PRS")]
            } else {
                // Safeties: range (zone), tackle-oriented, ball skills
                return [(a.zoneCoverage, "RNG"), (a.ballSkills, "BAL"), (a.manCoverage, "MCV")]
            }
        case .kicking(let a):
            return [(a.kickPower, "PWR"), (a.kickAccuracy, "ACC")]
        }
    }

    private var attributeColumns: some View {
        Group {
            let skills = positionSkillAttributes
            ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in
                colorCodedMiniAttribute(value: skill.value, label: skill.label)
                    .dsColumn(32)
            }
            // Pad to 4 columns if fewer attributes
            if skills.count < 4 {
                ForEach(0..<(4 - skills.count), id: \.self) { _ in
                    Spacer().frame(width: 32)
                }
            }

            // OVR
            ovrCell(font: .caption.monospacedDigit())
        }
    }

    // MARK: - Depth Columns

    private var depthColumns: some View {
        Group {
            // Starter/Backup badge (larger) — tappable to pick starter (#198)
            Group {
                if isStarterRole, let onStarterBadgeTap {
                    Button {
                        onStarterBadgeTap()
                    } label: {
                        starterBadgeContent
                    }
                    .buttonStyle(.plain)
                } else {
                    starterBadgeContent
                }
            }

            // Depth label
            Text(depthLabel)
                .font(DSType.display(11, .medium))
                .foregroundStyle(depthColor)
                .dsColumn(DSListColumn.money, alignment: .leading)

            // OVR
            ovrCell(font: .caption.monospacedDigit())

            // Age
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .dsColumn(Column.age)

            // Health
            healthIndicator
                .dsColumn(DSListColumn.health)

            // Form
            formColumn
        }
    }

    // MARK: - Starter Badge Content (#198)

    private var starterBadgeContent: some View {
        Text(depthBadgeText)
            .font(DSType.display(11, .heavy))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .depthChipStyle(isStarter: isStarterRole, tint: depthColor)
    }

    // MARK: - Form Column (#97)

    private var formColumn: some View {
        let form = playerFormIndicator(for: player)
        let label: String = {
            switch form.symbol {
            case "\u{2191}": return "↑"
            case "\u{2192}": return "→"
            default:         return "↓"
            }
        }()
        return VStack(spacing: 0) {
            Text(label)
                .font(.system(size: DSType.Size.callout, weight: .bold))
                .foregroundStyle(form.color)
        }
        .dsColumn(DSListColumn.glyph)
        .accessibilityLabel("Form \(formAccessibilityLabel)")
    }

    private var formAccessibilityLabel: String {
        let form = playerFormIndicator(for: player)
        switch form.symbol {
        case "\u{2191}": return "hot"
        case "\u{2192}": return "steady"
        default:         return "cold"
        }
    }

    // MARK: - Mini Attribute Helper

    private func colorCodedMiniAttribute(value: Int, label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(DSType.display(11, .bold))
                .foregroundStyle(analysisAttributeColor(for: value))
            Text(label)
                .font(DSType.display(11, .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    /// Color coding for attribute columns: 90+ gold, 80+ green, 70+ blue, below 70 orange/red.
    /// Unified onto `Color.forRating`. The bespoke ladder here had no poor
    /// tier — every attribute under 70 painted the same yellow, so a 42 SPD and
    /// a 68 SPD were indistinguishable in the analysis columns. It also used
    /// gold for 90+, which is the app's *accent*, not its elite-rating colour.
    private func analysisAttributeColor(for value: Int) -> Color {
        Color.forRating(value)
    }

    // MARK: - Subviews

    // The position badge is `DSPositionBadge` now (`UI/Common/DSListRow.swift`)
    // — same 36 × 24 box, same `DSCornerRadius.tight`, same hairline when it is
    // tappable, and the "tap to change" hint moved into the component's
    // `accessibilityHint` where the board's copy of it also lives.

    /// Whether this player is a starter based on depth index and scheme-aware starter count.
    /// (No `@ViewBuilder` — it is a `Bool`; the attribute only silenced itself into a warning.)
    private var isStarterRole: Bool {
        guard let idx = depthIndex else { return false }
        return idx < starterCountForPosition
    }

    @ViewBuilder
    private var depthIndicator: some View {
        if let onDepthChange, let currentIndex = depthIndex, positionGroupCount > 1 {
            Menu {
                if currentIndex > 0 {
                    Button {
                        onDepthChange(currentIndex - 1)
                    } label: {
                        Label("Promote to \(depthRoleLabel(for: currentIndex - 1))", systemImage: "arrow.up")
                    }
                }
                if currentIndex < positionGroupCount - 1 {
                    Button {
                        onDepthChange(currentIndex + 1)
                    } label: {
                        Label("Demote to \(depthRoleLabel(for: currentIndex + 1))", systemImage: "arrow.down")
                    }
                }
            } label: {
                depthChip
            }
            .accessibilityLabel("\(depthLabel), tap to change")
        } else {
            depthChip
                .accessibilityLabel(depthLabel)
        }
    }

    /// The small S / B / rank marker in front of a player's face.
    ///
    /// Rank 3 and deeper used to fall out of the chip language: same box, but
    /// `textTertiary` on a 20 %-tertiary fill is barely a shape, so a "5" read
    /// as a stray digit next to the solid green "S" and tinted blue "B" above
    /// it. Now all three are one control in three colours — same font, box,
    /// radius, fill weight and border — and the reserve tint is legible.
    private var depthChip: some View {
        Text(depthBadgeShortText)
            .font(DSType.display(11, .heavy))
            .frame(width: 14, height: 14)
            .depthChipStyle(isStarter: isStarterRole, tint: depthColor)
    }

    /// Returns a position-specific numbered depth badge, e.g. "DT1", "DE2", "QB1" (#279).
    private var depthBadgeText: String {
        guard let idx = depthIndex else { return "-" }
        let pos = player.position.rawValue
        return "\(pos)\(idx + 1)"
    }

    /// Short badge text for the small depth indicator (non-depth mode).
    private var depthBadgeShortText: String {
        guard let idx = depthIndex else { return "-" }
        if idx < starterCountForPosition { return "S" }
        if idx < starterCountForPosition + 1 { return "B" }
        return "\(min(idx + 1, 9))"
    }

    private var isExpiringContract: Bool {
        player.contractYearsRemaining <= 1
    }

    /// R25: badge color for the personality trait (positive/risky/neutral tier).
    private var personalityTierColor: Color {
        switch player.personality.archetype.tier {
        case .positive: return Color.success
        case .risky:    return Color.warning
        case .neutral:  return Color.textTertiary
        }
    }

    // The "Invested" badge ($15M+ annual) left the name line with the rest of
    // the conditional badges. It was a word standing in for a number the
    // overview lens already prints two columns to the right — cap hit over cap
    // percent — which is §2.2's "one encoding per quantity, never both".

    private var contractYearsLabel: some View {
        Text("\(player.contractYearsRemaining)yr")
            .font(DSType.display(11, .bold))
            .foregroundStyle(isExpiringContract ? Color.backgroundPrimary : Color.textTertiary)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(
                isExpiringContract
                    ? Color.warning
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 3)
            )
            .overlay(
                isExpiringContract
                    ? RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.warning.opacity(0.6), lineWidth: 1)
                    : nil
            )
    }

    private var moraleIndicator: some View {
        Image(systemName: moraleSystemImage)
            .font(.system(size: DSType.Size.callout))
            .foregroundStyle(moraleColor)
            .accessibilityLabel("Morale \(moraleLabel)")
    }

    private var healthIndicator: some View {
        Group {
            if player.isInjured {
                HStack(spacing: 2) {
                    Image(systemName: "cross.circle.fill")
                        .font(.system(size: DSType.Size.body))
                        .foregroundStyle(Color.danger)
                    Text("\(player.injuryWeeksRemaining)")
                        .font(DSType.display(11, .bold))
                        .foregroundStyle(Color.danger)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(Color.success)
            }
        }
        .accessibilityLabel(player.isInjured ? "Injured, \(player.injuryWeeksRemaining) weeks" : "Healthy")
    }

    private var developmentArrow: some View {
        Group {
            let trend = developmentTrend
            Image(systemName: trend.icon)
                .font(.system(size: DSType.Size.body, weight: .bold))
                .foregroundStyle(trend.color)
        }
        .accessibilityLabel("Development \(developmentTrend.label)")
    }

    /// Short potential label for overview columns (1-2 chars)
    private var shortPotentialLabel: String {
        let pot = player.truePotential
        switch pot {
        case 90...:   return "★"
        case 80..<90: return "↑↑"
        case 70..<80: return "↑"
        case 60..<70: return "→"
        default:      return "↓"
        }
    }

    private var shortPotentialColor: Color {
        let pot = player.truePotential
        switch pot {
        case 90...:   return .accentGold
        case 80..<90: return .success
        case 70..<80: return .accentBlue
        case 60..<70: return .textTertiary
        default:      return .danger
        }
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var depthColor: Color {
        guard let idx = depthIndex else { return .textSecondary }
        if idx < starterCountForPosition { return .success }       // starter = green
        if idx < starterCountForPosition + 1 { return .accentBlue } // backup = blue
        // 3rd string or deeper = gray. `textSecondary`, not `textTertiary`:
        // tertiary on a tertiary-tinted chip is below the contrast the green
        // and blue chips read at, which is what made the rank badge look like
        // a different component instead of the same one in gray.
        return .textSecondary
    }

    private var depthLabel: String {
        guard let idx = depthIndex else { return "Reserve" }
        if idx < starterCountForPosition { return "Starter" }
        if idx < starterCountForPosition + 1 { return "Backup" }
        if idx < starterCountForPosition + 2 { return "Third string" }
        return "Reserve"
    }

    private func depthRoleLabel(for index: Int) -> String {
        if index < starterCountForPosition { return "Starter" }
        if index < starterCountForPosition + 1 { return "Backup" }
        if index < starterCountForPosition + 2 { return "3rd String" }
        return "#\(index + 1)"
    }

    /// Cap hit from the detailed Contract model (if available), otherwise falls back to annualSalary.
    private var capHitValue: Int {
        contract?.capHit ?? player.annualSalary
    }

    private var formattedCapHit: String {
        formatSalary(capHitValue)
    }

    private var formattedSalary: String {
        formatSalary(player.annualSalary)
    }

    /// Dead cap the club still owes if this player is released, in thousands.
    ///
    /// Not recomputed here: the precedence is `CapManagementEngine.tradeCapSplit`'s
    /// — a detailed `Contract` row's own `deadCap` when one exists, and
    /// `RosterCutEvaluator.deadCap` (the 15 %-per-remaining-year proxy the cut
    /// screens already quote) for everyone else, which is most of the league.
    @MainActor
    private var deadCapIfCut: Int {
        if let contract, contract.totalYears > 0 {
            return contract.deadCap
        }
        return RosterCutEvaluator.deadCap(player: player)
    }

    /// Cap actually freed by the release: salary minus the dead money.
    @MainActor
    private var capSavingsIfCut: Int {
        if let contract, contract.totalYears > 0 {
            return max(0, player.annualSalary - contract.deadCap)
        }
        return RosterCutEvaluator.capSavings(player: player)
    }

    private var capPercent: Double {
        guard teamSalaryCap > 0 else { return 0 }
        return Double(capHitValue) / Double(teamSalaryCap) * 100.0
    }

    private var capPercentLabel: String {
        String(format: "%.1f%%", capPercent)
    }

    private var capPercentColor: Color {
        switch capPercent {
        case 8...:  return .warning   // Heavy cap hit
        case 4..<8: return .textSecondary
        default:    return .textTertiary
        }
    }

    /// Returns true when the contract provides a distinct cap hit that differs from base salary.
    private var showsSeparateCapHit: Bool {
        guard let contract else { return false }
        return contract.capHit != player.annualSalary
    }

    private func formatSalary(_ value: Int) -> String {
        let millions = Double(value) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(value)K"
        }
    }

    private var moraleColor: Color {
        switch player.morale {
        case 85...:   return .success
        case 70..<85: return .accentGold
        case 55..<70: return .warning
        default:      return .danger
        }
    }

    private var moraleLabel: String {
        switch player.morale {
        case 85...:   return "excellent"
        case 70..<85: return "good"
        case 55..<70: return "neutral"
        default:      return "low"
        }
    }

    private var moraleSystemImage: String {
        switch player.morale {
        case 85...:   return "face.smiling.fill"
        case 70..<85: return "face.smiling"
        case 55..<70: return "face.dashed"
        default:      return "face.dashed.fill"
        }
    }

    private var developmentTrend: DevelopmentTrend {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return .improving
        } else if peak.contains(player.age) {
            return .stable
        } else {
            return .declining
        }
    }

    private var potentialLabel: String {
        let pot = player.truePotential
        switch pot {
        case 90...:   return "Elite"
        case 80..<90: return "Star"
        case 70..<80: return "Good"
        case 60..<70: return "Avg"
        default:      return "Low"
        }
    }

    private var developmentPhaseLabel: String {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return "Rising"
        } else if peak.contains(player.age) {
            return "Prime"
        } else {
            return "Decline"
        }
    }

    private var accessibilityText: String {
        var parts = [
            player.fullName,
            player.position.rawValue,
            depthLabel,
            isFogged
                ? RookieFog.accessibilityText(for: player)
                : "overall \(player.overall)",
            "age \(player.age)",
            formattedSalary,
            "\(player.contractYearsRemaining) year\(player.contractYearsRemaining == 1 ? "" : "s") remaining",
        ]
        if player.isInjured {
            parts.append("injured \(player.injuryWeeksRemaining) weeks")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Depth Chip Style

/// The one visual definition of a depth marker, applied to both the compact
/// S / B / rank chip in front of the player's face and the wider "WR1"-style
/// badge in Depth mode: filled for a starter, tinted-with-border for everyone
/// behind him, always the same corner radius and fill weight.
private struct DepthChipStyle: ViewModifier {
    let isStarter: Bool
    let tint: Color

    private static let radius: CGFloat = 3
    private static let fill: Double = 0.22
    private static let border: Double = 0.45

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isStarter ? Color.backgroundPrimary : tint)
            .background(
                isStarter
                    ? AnyShapeStyle(tint)
                    : AnyShapeStyle(tint.opacity(Self.fill)),
                in: RoundedRectangle(cornerRadius: Self.radius)
            )
            .overlay(
                isStarter
                    ? nil
                    : RoundedRectangle(cornerRadius: Self.radius)
                        .strokeBorder(tint.opacity(Self.border), lineWidth: 1)
            )
    }
}

private extension View {
    func depthChipStyle(isStarter: Bool, tint: Color) -> some View {
        modifier(DepthChipStyle(isStarter: isStarter, tint: tint))
    }
}

// MARK: - Roster Analysis Mode (#96, #98)

/// Analysis view modes for the roster list. Each mode adjusts which columns
/// PlayerRowView displays, enabling different analytical perspectives.
enum RosterAnalysisMode: String, CaseIterable, Identifiable {
    case overview
    case contracts
    case development
    case physical
    case attributes
    case mental
    case depth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview:    return "Overview"
        case .contracts:   return "Contracts"
        case .development: return "Development"
        case .physical:    return "Physical"
        case .attributes:  return "Position Skills"
        case .mental:      return "Mental"
        case .depth:       return "Depth"
        }
    }

    var icon: String {
        switch self {
        case .overview:    return "list.bullet"
        case .contracts:   return "dollarsign.circle"
        case .development: return "chart.line.uptrend.xyaxis"
        case .physical:    return "figure.run"
        case .attributes:  return "figure.american.football"
        case .mental:      return "brain.head.profile"
        case .depth:       return "person.3.sequence"
        }
    }
}

// MARK: - Development Trend

enum DevelopmentTrend {
    case improving, stable, declining

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable:    return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .success
        case .stable:    return .accentGold
        case .declining: return .danger
        }
    }

    var label: String {
        switch self {
        case .improving: return "improving"
        case .stable:    return "stable"
        case .declining: return "declining"
        }
    }
}

// MARK: - Overall Color Helper (package-level for reuse)

func overallColor(for value: Int) -> Color {
    Color.forRating(value)
}

// MARK: - Preview

#Preview {
    List {
        PlayerRowView(player: Player(
            firstName: "Patrick",
            lastName: "Mahomes",
            position: .QB,
            age: 28,
            yearsPro: 7,
            positionAttributes: .quarterback(QBAttributes(
                armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                accuracyDeep: 87, pocketPresence: 92, scrambling: 80
            )),
            personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
            morale: 85, contractYearsRemaining: 3, annualSalary: 45000
        ), depthIndex: 0)
        PlayerRowView(player: Player(
            firstName: "Tyreek",
            lastName: "Hill",
            position: .WR,
            age: 29,
            yearsPro: 8,
            positionAttributes: .wideReceiver(WRAttributes(
                routeRunning: 88, catching: 90, release: 92, spectacularCatch: 85
            )),
            personality: PlayerPersonality(archetype: .loneWolf, motivation: .stats),
            isInjured: true, injuryWeeksRemaining: 4, contractYearsRemaining: 2, annualSalary: 30000
        ), depthIndex: 1, analysisMode: .contracts)
        PlayerRowView(player: Player(
            firstName: "Myles",
            lastName: "Garrett",
            position: .DE,
            age: 28,
            yearsPro: 7,
            positionAttributes: .defensiveLine(DLAttributes(
                passRush: 96, blockShedding: 90, powerMoves: 88, finesseMoves: 91
            )),
            personality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
            contractYearsRemaining: 4, annualSalary: 25000
        ), depthIndex: 2, analysisMode: .attributes)
        PlayerRowView(player: Player(
            firstName: "Justin",
            lastName: "Tucker",
            position: .K,
            age: 34,
            yearsPro: 12,
            positionAttributes: .kicking(KickingAttributes(kickPower: 95, kickAccuracy: 98)),
            personality: PlayerPersonality(archetype: .steadyPerformer, motivation: .loyalty),
            contractYearsRemaining: 1, annualSalary: 6000
        ), depthIndex: 0, analysisMode: .physical)
    }
}
