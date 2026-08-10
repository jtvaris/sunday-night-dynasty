import SwiftUI

// MARK: - DSStatusPill — the small state marker
//
// UI_REDESIGN_VISION §2.3 (last paragraph) and §2.2's fixed-slot rule.
//
// A status pill says WHAT STATE a thing is in. It is never a button, and §2.12
// is explicit about why that matters: iteration 1 of the vision shipped a static
// chip and a tappable one that were visually identical (both "rounded rect, 1 pt
// border, tertiary fill"), so the user could not tell which half of a row he was
// allowed to press. So this component is deliberately FLAT — no gradient, no
// `DSElevation` shadow, tinted fill only. Anything raised is interactive; this
// never is.
//
// Six tones, and `empty` is the load-bearing one. The board's prep chips used to
// draw an icon only when the work HAD been done, which made the holes in the
// board invisible — and the holes are the entire question the user scans a
// 350-row list to answer. An unset slot is therefore a legible dimmed WORD in a
// dashed outline that still occupies its position, so the user reads the column
// of gaps rather than the column of achievements.
//
// **Keep the vocabulary short.** §2.2 records a real defect: "CHARACTER" (87 pt)
// in a 66 pt `RISK` column painted straight over the neighbouring `TAPE` grade.
// A pill label is one short word or a 3–4 letter ident — `Clean` · `Med` ·
// `Char` · `Unknown`, `Par` rather than `Even`, `RPT` / `CMB` / `MEET`. The pill
// clips itself as a backstop, but clipping is the seatbelt, not the plan.

struct DSStatusPill: View {

    /// State, not decoration. Every tone means one thing app-wide.
    enum Tone {
        /// A stated fact with no verdict attached.
        case neutral
        /// The work is done / the condition is met.
        case ok
        /// Caution, at a stated threshold. Orange, never gold — §P7's semantic
        /// hue separation (`warning #EAB308` and `accentGold #C9A94E` are the
        /// same hue and collapse into one another at 11 pt on a dark chip).
        case warn
        /// Failing, at a stated threshold.
        case bad
        /// Informational / selected.
        case info
        /// The slot exists and nothing has filled it. Dashed, dimmed, no dot.
        case empty

        var tint: Color {
            switch self {
            case .neutral: return .textSecondary
            case .ok:      return .success
            case .warn:    return .alertOrange
            case .bad:     return .danger
            case .info:    return .accentBlue
            case .empty:   return .textTertiary
            }
        }

        var isEmpty: Bool {
            if case .empty = self { return true }
            return false
        }
    }

    /// The ident. Uppercased by the pill.
    let label: String
    var tone: Tone = .neutral
    /// An optional trailing figure — a report count, a week count. Tabular.
    var value: String? = nil
    /// The 4 pt state dot. Dropped for `empty`, and worth dropping on rows that
    /// mount three or more pills side by side, where three dots read as noise.
    var showsDot: Bool = true
    /// What VoiceOver says instead of "RPT 2".
    var spokenLabel: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if showsDot && !tone.isEmpty {
                Circle()
                    .fill(tone.tint)
                    .frame(width: 4, height: 4)
            }
            Text(label.uppercased())
                // 11 pt is the display voice's floor (P7 corollary), and
                // `DSType.display` clamps it there whatever a call site asks
                // for. The board's own prep glyphs were 7 pt before this.
                .font(DSType.display(11, .heavy))
                .tracking(0.4)
            if let value {
                Text(value)
                    .font(DSType.display(11, .heavy))
            }
        }
        .foregroundStyle(tone.isEmpty ? Color.textTertiary.opacity(0.75) : tone.tint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                .fill(tone.isEmpty ? Color.clear : tone.tint.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                .strokeBorder(
                    tone.isEmpty ? Color.textTertiary.opacity(0.45) : tone.tint.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, dash: tone.isEmpty ? [2, 2] : [])
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel ?? defaultSpoken)
    }

    private var defaultSpoken: String {
        let head = value.map { "\(label) \($0)" } ?? label
        return tone.isEmpty ? "\(head), not done" : head
    }
}

// MARK: - Fixed state-chip slots

/// One reserved slot on a row: it is always drawn, in the same position, whether
/// or not the fact behind it exists.
///
/// UI_REDESIGN_VISION §2.2 calls this "the load-bearing idea" of the list
/// standard. A roster row reserves `FIT` / `EXT` / `HLTH`; a board row reserves
/// `RPT` / `CMB` / `MEET`. What the user is scanning for is the gap.
struct DSStateSlot: Identifiable {
    /// The 3–4 letter ident. Doubles as the identity, so a row may not mount the
    /// same slot twice.
    let label: String
    var tone: DSStatusPill.Tone
    var value: String? = nil
    var spokenLabel: String? = nil

    var id: String { label }

    /// The common case: a slot that is either filled (with a tone) or not.
    static func slot(
        _ label: String,
        isSet: Bool,
        tone: DSStatusPill.Tone,
        value: String? = nil,
        spoken: String? = nil
    ) -> DSStateSlot {
        DSStateSlot(
            label: label,
            tone: isSet ? tone : .empty,
            value: isSet ? value : nil,
            spokenLabel: spoken
        )
    }
}

/// The reserved row of slots that sits under a row's name.
///
/// Fixed order, fixed membership, one spacing. A screen chooses which slots it
/// reserves once, for the whole list — never per row, because a slot that
/// appears on some rows and not others is the missing-glyph problem again.
struct DSStateSlotRow: View {
    let slots: [DSStateSlot]
    /// Three pills with three dots reads as noise at this size; rows that mount
    /// the full set turn the dots off and let the tint carry the state.
    var showsDots: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(slots) { slot in
                DSStatusPill(
                    label: slot.label,
                    tone: slot.tone,
                    value: slot.value,
                    showsDot: showsDots,
                    spokenLabel: slot.spokenLabel
                )
            }
        }
    }
}

#Preview("Tones") {
    ZStack {
        Color.backgroundSecondary.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                DSStatusPill(label: "Clean", tone: .ok)
                DSStatusPill(label: "Med", tone: .warn)
                DSStatusPill(label: "Char", tone: .bad)
                DSStatusPill(label: "Par", tone: .neutral)
                DSStatusPill(label: "Info", tone: .info)
                DSStatusPill(label: "Unknown", tone: .empty)
            }
            DSStateSlotRow(slots: [
                .slot("RPT", isSet: true, tone: .ok, value: "3"),
                .slot("CMB", isSet: false, tone: .info),
                .slot("MEET", isSet: true, tone: .info),
            ])
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
