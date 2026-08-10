import SwiftUI

// MARK: - The one negotiation chat (#105 Wave 3c)
//
// UI_REDESIGN_VISION §4 Wave 3: *"Merge the two negotiation chats first, then put
// the single result on the bar — rounds become steps, outcome becomes a result
// sheet, and the duplicate 'Close'/'Done' pair collapses to one."*
//
// The app shipped the chat-transcript metaphor twice. `ContractNegotiationView`
// (an agent, a contract) and `TradeNegotiationView` (a GM, a package) had the
// same five parts and shared none of them: two headers, two bubble pairs, two
// transcripts, two composers-with-a-footer and two ways to leave. ~3490 lines
// with no common ancestor, and the two drifted — one bubble clamped at 500 pt and
// the other at 520, one right-aligned its own name and the other did not, one
// carried a tone chip the other had no way to draw.
//
// This file is that ancestor. It owns the CHROME of a negotiation and nothing
// else:
//
//   NegotiationChatHeader     who is on the other end of the line
//   NegotiationRoundBand      the rounds, as `DSSlatBand` steps + a patience meter
//   NegotiationTranscript     the scrollback, and the one bubble grammar
//   NegotiationNotice         the banner shape both screens use for a blocker
//   NegotiationCloseStrip     what a finished thread reads like on re-entry
//
// **No negotiation logic lives here, in either direction.** The ratchet, the
// stance pinning, the pricing ladders, the verdicts and the persistence stay in
// `ContractNegotiationEngine` / `TradeValueEngine` and in the two screens that
// call them. This file cannot compute money, cannot decide a tone and cannot
// close a thread — it is handed values and it draws them.
//
// **Fog note:** nothing here reads a player at all. The two screens pass strings
// they have already composed, so no attribute disclosure gate can be bypassed by
// moving a view into the shared layer.

// MARK: - Sides

/// Who is speaking. `them` is the other side of the table — an agent in a
/// contract talk, a rival GM in a trade talk — because from the chat's point of
/// view those are the same role.
enum NegotiationChatSide {
    case them
    case you
    case system
}

// MARK: - One line of the transcript

/// A rendered line, already resolved by the screen that owns the conversation.
///
/// Deliberately NOT the persisted message model: `NegotiationThreadMessage` and
/// `TradeThreadMessage` are Codable save data with different senders, different
/// attachments and different lifetimes, and unifying *those* would be a
/// shared-model migration rather than a presentation merge. This is the view's
/// own value type, built fresh each body pass from whichever model the screen
/// persists.
struct NegotiationChatLine: Identifiable {

    /// The badge on a line that names the tone it was said in.
    struct Tone {
        var label: String
        var color: Color
    }

    /// The inline receipt — a signed contract, an agreed trade. Rendered centred
    /// and full-width instead of as a bubble, because the conversation IS the
    /// record and the signature belongs inside it.
    struct Receipt {
        var title: String
        var icon: String = "checkmark.seal.fill"
        var color: Color = .success
    }

    let id: UUID
    var side: NegotiationChatSide
    /// The name over the bubble. Ignored on `you` (always "You") and `system`.
    var speaker: String = ""
    var text: String
    var tone: Tone?
    /// Draws the bubble's border in `danger` — the "he took that badly" channel.
    var isAlarmed: Bool = false
    var receipt: Receipt?
    /// The offer / package card that rides under the words. `AnyView` because the
    /// two screens attach genuinely different widgets (a contract card, a
    /// two-column asset table) and a generic parameter here would infect every
    /// container up to the screen.
    var attachment: AnyView?
}

// MARK: - Header

/// One chip in the header's identity row.
struct NegotiationChatChip: Identifiable {

    enum Style {
        /// Bare text — the facts that need no emphasis (age, salary, years).
        case plain
        /// Tinted capsule — a persona, an archetype, a stance.
        case tinted
        /// Solid capsule — the one categorical marker (a position side).
        case solid
    }

    let id: String
    var text: String
    var icon: String?
    var color: Color = .textSecondary
    var style: Style = .plain
}

/// **Who is on the other end of the line.**
///
/// The two screens' headers had the same three bands — a name, an identity row,
/// a one-line character note — plus a trailing block that differed (an OVR
/// numeral / the round counter). The bands are shared; the trailing block and an
/// optional footer are the two slots a caller fills.
///
/// The round counter is deliberately NOT one of them any more: rounds are the
/// process, and a process states its count on the band (§2.1's "the one place a
/// process prints its count").
struct NegotiationChatHeader<Trailing: View, Footer: View>: View {

    let title: String
    /// The facts about the subject — a position, an age, a payroll number.
    var chips: [NegotiationChatChip] = []
    /// Who you are talking TO — the agent and how he bargains, the GM and how he
    /// is described around the league. A second row rather than a longer first
    /// one: at portrait width eight chips on one line truncate the last three,
    /// and the identity is the half a user actually reads.
    var identityChips: [NegotiationChatChip] = []
    var note: String?
    var noteColor: Color = .textTertiaryReadable
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(title)
                        .font(DSType.display(DSType.Size.title3, .heavy))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !chips.isEmpty {
                        HStack(spacing: DSSpacing.xxs) {
                            ForEach(chips) { chip in
                                chipView(chip)
                            }
                        }
                    }

                    if !identityChips.isEmpty {
                        HStack(spacing: DSSpacing.xxs) {
                            ForEach(identityChips) { chip in
                                chipView(chip)
                            }
                        }
                    }

                    if let note {
                        Text(note)
                            .font(DSType.text(12, .regular, prose: true))
                            .foregroundStyle(noteColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: DSSpacing.xs)

                trailing()
            }

            footer()
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.surfaceBorder).frame(height: 1)
        }
    }

    @ViewBuilder
    private func chipView(_ chip: NegotiationChatChip) -> some View {
        let label = HStack(spacing: DSSpacing.xxs) {
            if let icon = chip.icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(chip.text)
                .font(DSType.display(11, .heavy))
                .tracking(0.4)
                .lineLimit(1)
        }

        switch chip.style {
        case .plain:
            label.foregroundStyle(chip.color)
        case .tinted:
            label
                .foregroundStyle(chip.color)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, 2)  // ds-lint:allow(spacing) chip inset: 4 makes an 11 pt capsule 23 pt tall next to a 16 pt line
                .background(chip.color.opacity(0.14), in: Capsule())
        case .solid:
            label
                .foregroundStyle(Color.backgroundPlate)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, 2)  // ds-lint:allow(spacing) see above
                .background(chip.color, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
        }
    }
}

extension NegotiationChatHeader where Footer == EmptyView {
    init(
        title: String,
        chips: [NegotiationChatChip] = [],
        identityChips: [NegotiationChatChip] = [],
        note: String? = nil,
        noteColor: Color = .textTertiaryReadable,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            title: title,
            chips: chips,
            identityChips: identityChips,
            note: note,
            noteColor: noteColor,
            trailing: trailing,
            footer: { EmptyView() }
        )
    }
}

// MARK: - Rounds, as a band

/// **The rounds of a negotiation, drawn as the app's one process spine.**
///
/// Both screens carried a bare "Round 3" counter — one of the seven progress
/// metaphors §2.1 exists to delete — and one of them drew its own dot-rail for
/// patience beside it. Here a round is a `DSSlat` and patience is the band's
/// `DSResourceMeter`, so a negotiation reads like every other ordered thing in
/// the game and a filled pip means the same thing it means on the draft-prep
/// band: spent.
///
/// **Two channels, two quantities.** The ribbon is the ordered run — the rounds
/// this conversation has actually had — and the meter is the RESOURCE being
/// spent, which is not always the same number. A contract talk spends a round
/// every time the club speaks, so its two agree; a trade talk only spends the
/// GM's patience on a lowball, so a fair counter advances the ribbon and leaves
/// the meter alone. Passing them separately is what lets the band be honest
/// about both.
///
/// The band computes neither. Both come from the engine's own patience model
/// (`ContractDemand.maxRounds`, `GMIdentity.patience`/`strikes`) via the screen.
struct NegotiationRoundBand: View {

    /// Rounds already spoken for.
    let used: Int
    /// How many slats the run draws.
    let limit: Int
    /// The resource actually being spent. `nil` means the rounds ARE the
    /// resource, which is the contract talk's case.
    var meter: DSResourceMeter?
    /// What a finished round produced, keyed by round number — the money tabled,
    /// or the answer that came back. Missing keys draw no outcome.
    var outcomes: [Int: String] = [:]
    /// A closed thread has no current step: everything behind the last round is
    /// done and everything ahead of it is locked, because it will never be used.
    var isClosed: Bool = false
    var unit: String = "patience"

    /// Never below `used`: a caller passing a cap that shrinks while the run
    /// grows would otherwise draw a ribbon with no current step, a full meter and
    /// a headline lower than the round the transcript is already showing.
    private var total: Int { max(1, limit, used) }

    private var slats: [DSSlat] {
        (1...total).map { round in
            let state: DSSlat.State = {
                if round <= used { return .done }
                if isClosed { return .locked }
                return round == used + 1 ? .current : .future
            }()
            let outcome = outcomes[round]
            return DSSlat(
                id: "round-\(round)",
                index: String(round),
                title: "Round \(round)",
                subcaption: state == .current ? "One of \(total) the table will hear" : nil,
                state: state,
                outcome: outcome,
                accessibilityText: accessibilityText(round: round, state: state, outcome: outcome)
            )
        }
    }

    private func accessibilityText(round: Int, state: DSSlat.State, outcome: String?) -> String {
        switch state {
        case .done:    return "Round \(round), done\(outcome.map { ", \($0)" } ?? "")"
        case .current: return "Round \(round), the round you are in"
        case .future:  return "Round \(round), still to come"
        case .locked:  return "Round \(round), never used — talks are over"
        }
    }

    /// The rounds themselves, when the screen has no separate resource to show.
    private var resolvedMeter: DSResourceMeter {
        meter ?? DSResourceMeter(spent: min(used, total), total: total, unit: unit)
    }

    var body: some View {
        DSSlatBand(
            slats: slats,
            headline: isClosed
                ? "\(used) round\(used == 1 ? "" : "s") spoken"
                : "Round \(min(used + 1, total)) of \(total)",
            meter: resolvedMeter,
            isCompact: true
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.xs)
        .frame(maxWidth: DSLayout.contentMeasure)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Transcript

/// The scrollback and the one bubble grammar.
///
/// `measure` is `DSLayout.contentMeasure` by default rather than the two
/// hardcoded widths that shipped (500 in one file, 520 and a bare `720` in the
/// other).
struct NegotiationTranscript: View {

    let lines: [NegotiationChatLine]
    /// The line to keep in view. The owner sets it to the newest message id.
    var scrollTarget: UUID?
    var measure: CGFloat = DSLayout.contentMeasure

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DSSpacing.sm) {
                    ForEach(lines) { line in
                        NegotiationBubble(line: line)
                            .id(line.id)
                    }
                }
                .padding(DSSpacing.md)
                .frame(maxWidth: measure)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
    }
}

/// One line. Three shapes — them, you, system — plus the receipt, and nothing
/// else. Both screens' six bubble functions collapse into this.
private struct NegotiationBubble: View {

    let line: NegotiationChatLine

    var body: some View {
        if let receipt = line.receipt {
            receiptCard(receipt)
        } else {
            switch line.side {
            case .them:   themBubble
            case .you:    youBubble
            case .system: systemLine
            }
        }
    }

    // MARK: Them

    private var themBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xxs) {
                    Text(line.speaker)
                        .font(DSType.display(11, .heavy))
                        .tracking(0.5)
                        .foregroundStyle(Color.textTertiaryReadable)
                    if let tone = line.tone {
                        Text(tone.label.uppercased())
                            .font(DSType.display(11, .heavy))
                            .tracking(0.4)
                            .foregroundStyle(tone.color)
                            .padding(.horizontal, DSSpacing.xs)
                            .padding(.vertical, 2)  // ds-lint:allow(spacing) chip inset
                            .background(tone.color.opacity(0.14), in: Capsule())
                    }
                }

                Text(line.text)
                    .font(DSType.text(14, .regular, prose: true))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                line.attachment
            }
            .padding(DSSpacing.sm)
            .background(bubbleSurface(
                fill: Color.backgroundSecondary,
                border: line.isAlarmed ? Color.dangerText.opacity(0.45) : Color.surfaceBorder
            ))
            .frame(maxWidth: 520, alignment: .leading)

            Spacer(minLength: 40)
        }
    }

    // MARK: You

    private var youBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 40)

            VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                Text("YOU")
                    .font(DSType.display(11, .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.accentGold.opacity(0.75))

                Text(line.text)
                    .font(DSType.text(14, .regular, prose: true))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)

                line.attachment
            }
            .padding(DSSpacing.sm)
            .background(bubbleSurface(
                fill: Color.accentGold.opacity(0.12),
                border: Color.accentGold.opacity(0.25)
            ))
            .frame(maxWidth: 520, alignment: .trailing)
        }
    }

    // MARK: System

    private var systemLine: some View {
        Text(line.text)
            .font(DSType.text(12, .medium, prose: true))
            .foregroundStyle(Color.textTertiaryReadable)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    // MARK: Receipt

    private func receiptCard(_ receipt: NegotiationChatLine.Receipt) -> some View {
        VStack(spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: receipt.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(receipt.color)
                Text(receipt.title)
                    .font(DSType.display(14, .heavy))
                    .tracking(0.5)
                    .foregroundStyle(receipt.color)
            }

            Text(line.text)
                .font(DSType.text(12, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            line.attachment
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: 520)
        .background(bubbleSurface(
            fill: receipt.color.opacity(0.10),
            border: receipt.color.opacity(0.35)
        ))
        .frame(maxWidth: .infinity)
    }

    private func bubbleSurface(fill: Color, border: Color) -> some View {
        RoundedRectangle(cornerRadius: DSCornerRadius.card, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.card, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

// MARK: - Notice

/// The banner both screens grew independently: a refusal and its exit condition,
/// a pay-cut answer, the league office's blockers. Icon, title, body, optional
/// footnote, tinted card.
struct NegotiationNotice: View {

    let icon: String
    let color: Color
    let title: String
    var message: String?
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }
            if let message {
                Text(message)
                    .font(DSType.text(12, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote {
                Text(footnote)
                    .font(DSType.text(11, .regular, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(color.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(color.opacity(0.30), lineWidth: 1)
                )
        )
    }
}

// MARK: - Close strip

/// What a FINISHED conversation reads like when the user opens it again.
///
/// Deliberately not a button. §2.6 gives the outcome to `DSResultSheet` and P5's
/// corollary gives the screen exactly one dismissal — the toolbar's X. The
/// primary-styled "Done" that used to sit here, duplicating that X, is the
/// specific defect the vision names by file name; what survives is the *reading*
/// half of the old closing bar.
struct NegotiationCloseStrip: View {

    let status: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(status)
                .font(DSType.text(13, .semibold, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                HStack(alignment: .top, spacing: DSSpacing.xxs) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.warning)
                    Text(note)
                        .font(DSType.text(12, .regular, prose: true))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.surfaceBorder).frame(height: 1)
        }
    }
}

// MARK: - The ending

/// The values a `DSResultSheet` needs, in an `Identifiable` box.
///
/// Both chats drive their result through `.sheet(item:)` — one enum-shaped sheet
/// point per screen — and `.sheet(item:)` needs an identity, which a plain
/// `DSResultSheet` (a `View`) does not have. This is that identity, and it is
/// also the seam where a screen decides what "what changed" means: only the
/// screen knows whether its numbers are money, points or years.
struct NegotiationOutcome: Identifiable {
    let id = UUID()
    var tone: DSResultSheet.Tone
    var headline: String
    var message: String?
    var chips: [DSResultSheet.Chip] = []
    var cost: String?
}

// MARK: - The one dismissal

extension View {

    /// P5's corollary, as one modifier: **a modal closes with a 44 pt circular X
    /// in the top-trailing corner, and with nothing else.**
    ///
    /// Both chats shipped a toolbar "Close" AND a gold inline "Done"; every host
    /// that presents them carries a comment warning the wrapper not to add a
    /// third. One place, one glyph, one verb.
    func negotiationDismissButton(label: String, action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: action) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.backgroundTertiary, in: Circle())
                        .contentShape(Circle())
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel(label)
            }
        }
    }
}
