import SwiftUI

// MARK: - DSResultSheet — how a process ends
//
// UI_REDESIGN_VISION §2.6. **One modal result pattern**, in this order and no
// other:
//
//   outcome headline  →  what changed  →  what it cost  →  a single "Continue"
//
// It replaces the five termination patterns the audit counted, and it exists
// because of the rule §2.6 states outright: **in-place body swaps are banned**.
// A user must never have to scroll *up* to find out that the thing he clicked
// worked, and he must never be handed two ways to leave one screen — the
// "Close"/"Done" pair `ContractNegotiationView` shipped is the case the vision
// names by file.
//
// So the sheet carries the ONLY commit on the surface it covers: one primary,
// bottom-trailing, and no dismissal of its own. A caller that wants the sheet to
// be unskippable pairs it with `.interactiveDismissDisabled(true)`; a caller that
// wants the transcript readable behind it does not. Both are presentation
// decisions, not component ones.
//
// The chips are §2.3's stat grammar — LABEL / value / context — laid out as a
// `Grid` rather than as three independent stacks, because `alignment: .bottom`
// on an `HStack` drops a numeral the moment one column carries an extra element.
// One baseline for the row, always.

struct DSResultSheet: View {

    /// What KIND of ending this is. Three, because a process ends well, ends
    /// plainly, or ends badly — and colour is the only thing this changes.
    enum Tone {
        case good
        case neutral
        case bad

        var accent: Color {
            switch self {
            case .good:    return .success
            case .neutral: return .accentGold
            case .bad:     return .dangerText
            }
        }

        var icon: String {
            switch self {
            case .good:    return "checkmark.seal.fill"
            case .neutral: return "flag.checkered"
            case .bad:     return "xmark.seal.fill"
            }
        }
    }

    /// One "what changed" cell: §2.3's three parts, always in that order.
    ///
    /// `context` is coloured ONLY when it is a movement — a rank, a denominator
    /// or a plain note stays grey. The caller decides, because only the caller
    /// knows whether its number moved.
    struct Chip: Identifiable {
        let id: String
        var label: String
        var value: String
        var context: String?
        /// Ladder colour is for 0–100 ratings and percentages of a whole (P7).
        /// Money and counts stay `textPrimary`, which is this default.
        var valueColor: Color = .textPrimary
        var contextColor: Color = .textTertiaryReadable

        init(
            id: String,
            label: String,
            value: String,
            context: String? = nil,
            valueColor: Color = .textPrimary,
            contextColor: Color = .textTertiaryReadable
        ) {
            self.id = id
            self.label = label
            self.value = value
            self.context = context
            self.valueColor = valueColor
            self.contextColor = contextColor
        }
    }

    var tone: Tone = .neutral
    /// The screen ident — "CONTRACT TALKS", "TRADE TALKS". Display voice.
    var eyebrow: String
    /// The outcome, in one line: "Deal signed", "He wants his release".
    var headline: String
    /// One or two sentences of prose. Markdown emphasis is honoured.
    var message: String?
    /// What changed. Empty is legitimate — a walk-out changes nothing.
    var chips: [Chip] = []
    /// What it cost, in the caller's own words. Rendered as the explainer line
    /// the vision asks every commit to carry.
    var cost: String?
    var continueTitle: String = "Continue"
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    headlineBlock
                    if !chips.isEmpty { changedBlock }
                }
                .padding(DSSpacing.lg)
                .frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // "What it cost" is the bar's explainer, not a fourth block above it:
            // §2.5 puts the cost line beside the commit it explains, and doing it
            // twice would put two gold rules on one sheet (P5 allows one gold).
            DSActionBar(
                explainer: cost.map { DSActionBar.Explainer(title: "What it cost", message: $0) },
                primary: .init(title: "\(continueTitle) \u{2192}", handler: onContinue)
            )
        }
        .background(Color.backgroundPrimary)
    }

    // MARK: Headline

    private var headlineBlock: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: tone.icon)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(tone.accent)
                Text(eyebrow.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(tone.accent)
                    .lineLimit(1)
            }

            // §2.10: the single most important line on the sheet is the outcome,
            // so it takes the display voice at the second tier. Text voice is
            // capped at 18 and this is a headline, not prose.
            Text(headline)
                .font(DSType.display(DSType.Size.title2, .heavy))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(LocalizedStringKey(message))
                    .font(DSType.text(14, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: What changed

    /// A three-band grid: label row, value row, context row. One baseline each,
    /// which is the whole reason this is a `Grid` and not a row of `VStack`s.
    private var changedBlock: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // §2.9: section heads are `textSecondary`, tracked, 11 pt — not gold.
            // `SectionHeaderText` is still gold until Wave 2 re-bases it, so this
            // header is written to the rule rather than borrowed from the type
            // that breaks it.
            Text("WHAT CHANGED")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            Grid(alignment: .leading, horizontalSpacing: DSSpacing.lg, verticalSpacing: DSSpacing.xxs) {
                GridRow {
                    ForEach(chips) { chip in
                        Text(chip.label.uppercased())
                            .font(DSType.display(11, .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Color.textTertiaryReadable)
                            .lineLimit(1)
                    }
                }
                GridRow {
                    ForEach(chips) { chip in
                        Text(chip.value)
                            .font(DSType.display(DSType.Size.title2, .heavy))
                            .foregroundStyle(chip.valueColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                GridRow {
                    ForEach(chips) { chip in
                        // The row always reserves its context line, so a chip
                        // with a delta and one without do not sit at two
                        // different heights (§2.2's slot rule).
                        Text(chip.context ?? " ")
                            .font(DSType.display(11, .semibold))
                            .foregroundStyle(chip.contextColor)
                            .lineLimit(1)
                    }
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

}

// MARK: - Preview

#Preview {
    Color.backgroundPrimary
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            DSResultSheet(
                tone: .good,
                eyebrow: "Contract talks",
                headline: "Marcus Webb signs for 3 years",
                message: "His agent took the deal at **$18.4M a year** after four rounds.",
                chips: [
                    .init(id: "years", label: "Years", value: "3"),
                    .init(id: "aav", label: "Per year", value: "$18.4M"),
                    .init(id: "gtd", label: "Guaranteed", value: "55%")
                ],
                cost: "Charges **$18.4M** against this year's cap and leaves **$4.2M** in room.",
                onContinue: {}
            )
        }
}
