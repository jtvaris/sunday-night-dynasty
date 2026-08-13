import SwiftUI

// MARK: - DSSlatBand — the spine of every ordered thing
//
// UI_REDESIGN_VISION §2.1. **The geometry is the identity.** A contiguous ribbon
// of parallelogram slats skewed −11°, butted with a 2 pt gap, on the darkest
// surface in the app (`plate #060B16`). Nothing else in the app is skewed, so
// the band is recognisable in peripheral vision, and the skew reads as forward
// motion — which is literally what it encodes.
//
// It replaces the seven progress metaphors the audit counted: four
// `GeometryReader` bars in two accent colours, a capsule, two dot-rails and a
// family of bare "N/M" counters. It is deliberately **domain-agnostic** — draft
// prep is only its first consumer; season weeks, free-agency waves, draft picks,
// the current drive and negotiation rounds are the same component at other
// scales.
//
// ## Three channels, not one
//
// State is carried by surface value, top rule AND a glyph/caption at the same
// time, so it survives distance and colour-blindness. A row of identical shapes
// differing only in fill hue — the Bootstrap/Material wizard — is the thing this
// component exists to not be.
//
//   done     surface one step up from the track · 2 pt textSecondary rule · check + outcome
//   current  lifted gradient + DSElevation.bar  · 3 pt GOLD rule · expands · sub-caption
//   future   the track value                     · no rule       · label only
//   locked   below the track + diagonal hatch    · no rule       · the unlock condition
//
// ## The place slat (#165) — ADDITIVE, opt-in, off by default
//
// A band is sometimes the WHOLE navigation of a screen rather than only its
// process: the scouting hub used to carry two permanent nav rows — a tab strip
// of destinations over a band of stages — and two rows of navigation for one
// screen is one row too many. Unifying them means the band has to be able to
// hold one thing that is **a place, not a step**.
//
// So `DSSlat` gained a ``DSSlat/Role``. `.step` is everything above and is the
// default; `.place` is a slat that:
//
//   * has NO state channels — no numeral, no check, no rule, no lift, no hatch,
//     no sub-caption. It cannot be `done`, it is never `current`, and it never
//     counts in the head's "STAGE N OF M" or in the meter, because the band's
//     arithmetic is computed by the caller and a place is not part of the run.
//   * draws an SF Symbol where a step draws its position numeral, on a flat
//     `backgroundTertiary` — a surface value none of the four states uses, so
//     the place reads as "not on this ladder" at peripheral distance.
//   * takes a FIXED width (`DSSlatGeometry.placeWidth`) instead of a share of
//     the flex, and is followed by a wider seam with a skewed hairline in it
//     (`DSSlatGeometry.placeSeam`), so the ordered pipeline still reads as its
//     own contiguous run.
//   * may carry `hasObligation`, a 7 pt dot for "something is owed in here" —
//     the only mark it has, because a place has no progress to report.
//
// Selection is the band's existing 2 pt `accentBlue` ring, unchanged. A place
// slat is deliberately NOT given the gold current rule: gold marks where the
// process is standing, and a destination is not a position in a process.
//
// **Backward compatibility.** The three new `DSSlat` properties are declared
// LAST and all carry defaults, so the synthesized memberwise initializer keeps
// its existing parameter list and order; every existing call site compiles and
// yields `role == .step`. Every new branch in the layout and the renderer is
// guarded on `role == .place`, and each guard's `.step` path is the previous
// expression verbatim: with no place slat in the array `placeCount` and
// `seamCount` are both 0, so `slatWidths` reduces to the arithmetic it had
// before, and `DSSlatButton` takes none of the new branches. A band that does
// not use the capability renders byte-identically.

// MARK: - Geometry

/// The band's measurements, in one place, because every consumer has to agree
/// about them (the shape, the clip, the top rule and the layout all read the
/// same slant).
enum DSSlatGeometry {
    /// The skew, in degrees. Negative in CSS terms: the top edge leans right.
    static let skewDegrees: Double = 11
    /// Band height on a surface the band is the subject of.
    static let fullHeight: CGFloat = 56
    /// Band height where the band is context — still ≥ 44 pt, so a compact slat
    /// is a legal touch target (§2.12 has no exceptions).
    static let compactHeight: CGFloat = 44
    /// The seam between two slats.
    static let gap: CGFloat = 2
    /// How much wider the current slat is than a future one. §2.1 asks for 2–4×.
    ///
    /// 2.5 rather than 3, measured on the 9-stage draft-prep band at a 1032 pt
    /// portrait iPad: at 3× the eight remaining slats get 81 pt, which is 54 pt
    /// of text, and INTERVIEWS is 57 pt at the 11 pt floor — the band broke the
    /// word across two lines. The floor cannot move, so the flex did.
    static let currentFlex: CGFloat = 2.5
    /// The width below which the ribbon scrolls instead of breaking words.
    ///
    /// **Measured on device, not guessed.** SF Pro condensed heavy at the 11 pt
    /// floor with +0.6 tracking runs ~7.7 pt per uppercase character, so
    /// INTERVIEWS is 77 pt, the leading index numeral and its gap are another
    /// 12, and the parallelogram plus its optical margin take 22. A slat narrower
    /// than this breaks a stage name across two lines mid-word — which the band
    /// did at 1032 pt portrait — and the type floor means the text cannot shrink
    /// to meet it. So the band scrolls, and every stage stays reachable.
    ///
    /// At the 1376 pt landscape iPad the app is built for, nine stages fit at
    /// 125 pt each and nothing scrolls.
    static let minSlatWidth: CGFloat = 112
    static let minCompactSlatWidth: CGFloat = 112

    /// A `place` slat's fixed width — it takes no share of the flex (#165).
    ///
    /// Below `minSlatWidth`, and legitimately so: that floor exists because a
    /// two-word stage name has to wrap to two lines at the 11 pt type floor. A
    /// place slat carries ONE short word and a glyph and never wraps, so it is
    /// measured against its own content instead. "WAR ROOM" at the 11 pt
    /// condensed heavy voice with +0.6 tracking is ~62 pt, the leading glyph and
    /// its gap another 18, and the parallelogram plus its optical margin 22 —
    /// 102. 104 is that with a point of slack, and taking it out of the flex is
    /// what keeps the ordered slats wide.
    static let placeWidth: CGFloat = 104

    /// The seam after a `place` slat: wider than the 2 pt slat gap, with a
    /// skewed hairline in it (#165).
    ///
    /// The whole point of the place slat is that the numbered run beside it is a
    /// separate thing. At the standard 2 pt gap the eye reads seven slats in one
    /// ribbon and starts counting from the wrong end; at 10 pt with a rule in
    /// the middle it reads one destination, then a pipeline.
    static let placeSeam: CGFloat = 10

    /// Horizontal displacement of each corner from the vertical centre line.
    ///
    /// The skew is anchored on the slat's middle, so a corner moves by
    /// `(height / 2) · tan(11°)` — 5.4 pt at the 56 pt band height, which is the
    /// number §2.1 quotes and the reason a slat must clip its own content: 5.4 pt
    /// of unclipped counter-skewed text paints across the 2 pt seam onto the
    /// neighbouring slat.
    static func slant(height: CGFloat) -> CGFloat {
        (height / 2) * CGFloat(tan(skewDegrees * .pi / 180))
    }
}

/// One slat of the ribbon: a parallelogram whose corners are displaced by
/// `slant` about the vertical centre.
///
/// Insettable so the focus ring strokes *inside* the slat rather than half a
/// line-width into the 2 pt seam.
struct DSSlatShape: InsettableShape {
    var slant: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.move(to: CGPoint(x: box.minX + slant, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX + slant, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - slant, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX - slant, y: box.maxY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> DSSlatShape {
        DSSlatShape(slant: slant, inset: inset + amount)
    }
}

/// The locked state's second channel: diagonal hatch, drawn on the same lean as
/// the slat so it reads as texture rather than as a rendering fault.
private struct DSSlatHatch: Shape {
    var spacing: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

// MARK: - Slat model

/// One step of an ordered thing, as the band draws it.
///
/// The band is a dumb renderer: everything here is computed once by the screen
/// that owns the process and handed down as a value, so the band cannot disagree
/// with the surface underneath it.
struct DSSlat: Identifiable, Equatable {

    enum State: Equatable {
        /// Behind the club.
        case done
        /// Where the club is standing **and may work**.
        case current
        /// Ahead of the club, and reachable in principle.
        case future
        /// Shut — by the pipeline or by the calendar.
        case locked
    }

    /// What KIND of thing this slat is (#165). See the file header.
    ///
    /// Additive and defaulted: everything written before #165 is a `.step`.
    enum Role: Equatable {
        /// A position in the ordered run. All four ``State`` channels apply.
        case step
        /// A destination that happens to live on the same ribbon. No state
        /// channels at all — see ``DSSlat/place(id:title:icon:hasObligation:accessibilityText:)``.
        case place
    }

    let id: String
    /// Position in the band — "4". Drawn as the slat's leading numeral so every
    /// slat states where it sits without a second component.
    var index: String?
    /// Display voice: condensed, uppercased by the band, tracked, tabular.
    let title: String
    /// The cost / unlock line. Drawn on the current slat (what this step spends)
    /// and on a locked one (what opens it). Never in the compact variant.
    var subcaption: String?
    var state: State
    /// A `future` slat the club may already act in. Raises the label one text
    /// tier; it is never a fourth state and never a colour of its own.
    var isAvailable: Bool = false
    /// What a `done` slat produced — "W 27–13", "$16.0M × 3", "12 interviews".
    var outcome: String?
    /// Optional tint for a `done` slat's top rule (W green / L red at season
    /// scale). `nil` keeps the neutral `textSecondary` rule.
    var tint: Color?
    /// Draws the "NOW" pill on the current slat.
    var isLive: Bool = false
    /// The whole screen-reader sentence: state, title, and the sub-caption or
    /// the unlock condition.
    var accessibilityText: String = ""

    // MARK: - #165 additions
    //
    // DECLARED LAST, ON PURPOSE. `DSSlat` is built through its synthesized
    // memberwise initializer, whose parameter order is declaration order, so
    // appending defaulted properties leaves every existing call site — and the
    // order it passes its labels in — compiling unchanged.

    /// Step or place. See ``Role`` and the file header.
    var role: Role = .step
    /// SF Symbol drawn where a step draws its position numeral. `place` only.
    var icon: String?
    /// "Something is owed in here" — a 7 pt dot, the place slat's only mark.
    var hasObligation: Bool = false

    // MARK: - #194 v2 addition

    /// **Who this slat belongs to**, as a colour — the club on the card, the
    /// franchise holding the wave. `nil` on every band that has no owner, which
    /// is all of them but the draft's.
    ///
    /// Distinct from ``tint``, and deliberately so: `tint` re-colours the `done`
    /// slat's TOP RULE and check, i.e. it re-states an outcome the state channel
    /// is already drawing (W green / L red). `accent` says nothing about state —
    /// it is an identity, and it is therefore drawn on channels no state uses:
    /// a bottom rule, and (on `current` only) a wash that fades in from the
    /// trailing edge across the empty half of the widened slat.
    ///
    /// **The gold rule is untouched.** `current` keeps its 3 pt `accentGold` top
    /// rule and its gold NOW pill, because those mark where the *process* is
    /// standing and an owner colour must never be able to impersonate them.
    ///
    /// **Contrast.** The wash is capped at 0.08 anywhere the slat prints words
    /// and only ramps past that after 50 % of the width, which no title, numeral
    /// or sub-caption reaches on a `currentFlex`-widened slat. Measured against
    /// the brightest owner colour in the league: `textTertiaryReadable` on the
    /// sub-caption line stays at 4.85 : 1 (the un-washed value is 4.86 : 1).
    /// A caller handing this a raw brand colour is the caller's bug — the draft
    /// room passes `DraftTeamTint.accentIfKnown`, which is lifted to ≥ 3 : 1
    /// against the plate first.
    var accent: Color? = nil

    /// A destination slat: an icon, a word, and no state channels (#165).
    ///
    /// A factory rather than a memberwise call because `state` has no default
    /// and a place has no state: this is the only way to build one without a
    /// caller having to pick a `State` value that the renderer then ignores.
    /// `.future` is what it stores, and nothing reads it — `slatWidths` looks
    /// for a `current` **step**, and every channel in `DSSlatButton` is
    /// short-circuited by the role.
    static func place(
        id: String,
        title: String,
        icon: String,
        hasObligation: Bool = false,
        accessibilityText: String = ""
    ) -> DSSlat {
        DSSlat(
            id: id,
            index: nil,
            title: title,
            subcaption: nil,
            state: .future,
            accessibilityText: accessibilityText,
            role: .place,
            icon: icon,
            hasObligation: hasObligation
        )
    }
}

// MARK: - Resource meter

/// The band head's meter. **One meaning on every scale: a filled pip is a spent
/// pip.**
///
/// §2.13: across three screens the same pips meant "spent" twice and "remaining"
/// once, and one of the fills was gold — a fourth job for a colour that has
/// three. Here the brightest filled pip is the one being spent now, a tick marks
/// half-way, and the value line always reads `<spent> spent · <left> left`, so
/// the pips and the words can never disagree.
struct DSResourceMeter: Equatable {
    /// Units already committed, **including the one in progress** — the brightest
    /// pip is spent, not pending, which is what makes `spent + left == total`.
    let spent: Int
    let total: Int
    /// Plural noun: "scouting weeks", "cap room", "patience".
    let unit: String

    var left: Int { max(0, total - spent) }

    var valueLine: String { "\(spent) spent \u{00B7} \(left) left" }

    var accessibilityText: String { "\(unit): \(spent) spent, \(left) left" }
}

// MARK: - The band

struct DSSlatBand: View {

    let slats: [DSSlat]
    /// The band head's left-hand line — "STAGE 4 OF 9". **The one place a
    /// process prints its count.**
    var headline: String?
    var meter: DSResourceMeter?
    /// Demoted rendering for the surfaces the process is not the subject of:
    /// shorter slats, no sub-captions, same geometry, same targets.
    var isCompact: Bool = false
    var selectedID: String?
    var onSelect: ((String) -> Void)?

    private var height: CGFloat {
        isCompact ? DSSlatGeometry.compactHeight : DSSlatGeometry.fullHeight
    }

    private var slant: CGFloat { DSSlatGeometry.slant(height: height) }

    private var minWidth: CGFloat {
        isCompact ? DSSlatGeometry.minCompactSlatWidth : DSSlatGeometry.minSlatWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            if headline != nil || meter != nil { head }
            ribbon
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundPlate, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
    }

    // MARK: Head

    private var head: some View {
        HStack(alignment: .center, spacing: 12) {
            if let headline {
                Text(headline.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let meter { meterView(meter) }
        }
        .frame(height: 14)
    }

    /// Pips, a half-way tick, and the value line — right-aligned, in the same
    /// slot on every scale.
    private func meterView(_ meter: DSResourceMeter) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {  // ds-lint:allow(spacing) pip gap: the meter is a 5 pt-wide rail, 4 pt reads as a dashed line
                ForEach(0..<max(meter.total, 1), id: \.self) { i in
                    if meter.total > 3 && i == meter.total / 2 {
                        Rectangle()
                            .fill(Color.textTertiary)
                            .frame(width: 1, height: 12)
                            .padding(.horizontal, 1)  // ds-lint:allow(spacing) half-way tick sits inside the pip gap
                    }
                    pip(index: i, meter: meter)
                }
            }
            Text(meter.valueLine)
                .font(DSType.display(11, .heavy))
                .foregroundStyle(Color.textTertiaryReadable)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meter.accessibilityText)
    }

    private func pip(index: Int, meter: DSResourceMeter) -> some View {
        // The brightest filled pip is the one being spent NOW. Never gold — gold
        // has three jobs and a pip fill is not one of them (§2.13).
        let isFilled = index < meter.spent
        let isCurrent = index == meter.spent - 1
        let fill: Color = isCurrent ? .textPrimary : (isFilled ? .textSecondary : .clear)
        return DSSlatShape(slant: DSSlatGeometry.slant(height: 11))
            .fill(fill)
            .overlay(
                DSSlatShape(slant: DSSlatGeometry.slant(height: 11))
                    .strokeBorder(isFilled ? Color.clear : Color.surfaceBorder, lineWidth: 1)
            )
            .frame(width: 5, height: 11)
    }

    // MARK: Ribbon

    private var ribbon: some View {
        GeometryReader { geo in
            let widths = slatWidths(available: geo.size.width)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSlatGeometry.gap) {
                        ForEach(Array(slats.enumerated()), id: \.element.id) { index, slat in
                            // #165: the wider seam after a place slat. Nothing
                            // is inserted when the band has no place slat, so
                            // the ribbon is the one it was.
                            if isSeamBreak(before: index) { seamRule }
                            slatView(slat, width: widths[index])
                                .id(slat.id)
                        }
                    }
                    // The first slat's bottom-left corner and the last slat's
                    // top-right corner overhang their frames by `slant`; the
                    // inset keeps the ribbon inside the plate.
                    .padding(.horizontal, slant)
                }
                .onAppear { scroll(proxy, animated: false) }
                .onChange(of: selectedID) { _, _ in scroll(proxy, animated: true) }
                // The trailing fade is the only affordance saying the ribbon
                // runs on. A hard edge at the band's right-hand rule reads as
                // "that is all of them".
                .mask(
                    HStack(spacing: 0) {
                        Color.white
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 16)
                    }
                )
            }
        }
        .frame(height: height)
    }

    /// Whether the slat at `index` opens a new run — i.e. the one before it is a
    /// place (#165). Always false on a band of pure steps.
    private func isSeamBreak(before index: Int) -> Bool {
        index > 0 && slats[index - 1].role == .place
    }

    /// The skewed hairline that sits in the wider seam after a place slat.
    ///
    /// A `DSSlatShape` rather than a plain `Rectangle` so the rule leans with
    /// the ribbon; a vertical line inside a −11° band reads as a rendering
    /// fault, which is the same reason the locked hatch is drawn on the slant.
    private var seamRule: some View {
        DSSlatShape(slant: slant)
            .fill(Color.surfaceBorder)
            .frame(width: 1, height: height)
            // ds-lint:allow(spacing) half the place seam either side of a 1 pt rule
            .padding(.horizontal, (DSSlatGeometry.placeSeam - 1) / 2)
    }

    /// Widths that fill the band when they can, and fall back to a scrollable
    /// minimum when nine slats will not fit.
    ///
    /// #165 adds two terms, both zero on a band of pure steps: place slats take
    /// a fixed width off the top instead of a share of the flex, and each seam
    /// break costs `placeSeam` plus the extra `HStack` gap the inserted rule
    /// brings with it.
    private func slatWidths(available: CGFloat) -> [CGFloat] {
        let count = slats.count
        guard count > 0 else { return [] }
        // The current marker belongs to the ORDERED run. A place slat stores
        // `.future` and can never match, but stating the role makes the rule
        // explicit rather than incidental.
        let currentIndex = slats.firstIndex { $0.role == .step && $0.state == .current }
        let placeCount = slats.filter { $0.role == .place }.count
        let seamCount = slats.indices.filter { isSeamBreak(before: $0) }.count
        let gaps = CGFloat(count - 1) * DSSlatGeometry.gap + slant * 2
            + CGFloat(seamCount) * (DSSlatGeometry.gap + DSSlatGeometry.placeSeam)
        let fixed = CGFloat(placeCount) * DSSlatGeometry.placeWidth
        let units = CGFloat(count - placeCount - (currentIndex == nil ? 0 : 1))
            + (currentIndex == nil ? 0 : DSSlatGeometry.currentFlex)
        let unit = max((available - gaps - fixed) / max(units, 1), minWidth)
        return slats.indices.map { index in
            if slats[index].role == .place { return DSSlatGeometry.placeWidth }
            return index == currentIndex ? unit * DSSlatGeometry.currentFlex : unit
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        // Follow the selection, falling back to the current step. Without this a
        // band six steps in opens parked on step 1 and the user has to hunt for
        // himself.
        let target = selectedID
            ?? slats.first(where: { $0.role == .step && $0.state == .current })?.id
            ?? slats.first?.id
        guard let target else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.22)) { proxy.scrollTo(target, anchor: .center) }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    // MARK: Slat

    private func slatView(_ slat: DSSlat, width: CGFloat) -> some View {
        DSSlatButton(
            slat: slat,
            width: width,
            height: height,
            slant: slant,
            isCompact: isCompact,
            isSelected: selectedID == slat.id,
            action: onSelect.map { handler in { handler(slat.id) } }
        )
    }
}

// MARK: - One slat

/// A slat is a **Button**, and it looks like one: pressed and focus states, and
/// a 44 pt minimum target that both band heights already satisfy.
///
/// §2.12 named this exactly: the signature element must be the most obviously
/// interactive thing on the screen, and the pressed state moves the
/// *counter-skewed content*, not the parallelogram.
private struct DSSlatButton: View {
    let slat: DSSlat
    let width: CGFloat
    let height: CGFloat
    let slant: CGFloat
    let isCompact: Bool
    let isSelected: Bool
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            content
        }
        .buttonStyle(DSSlatPressStyle())
        .disabled(action == nil)
        .frame(width: width, height: height)
        .accessibilityLabel(slat.accessibilityText.isEmpty ? slat.title : slat.accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A place, not a step (#165). Short-circuits every state channel.
    private var isPlace: Bool { slat.role == .place }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            DSSlatShape(slant: slant).fill(surface)

            if !isPlace, slat.state == .locked {
                DSSlatHatch()
                    .stroke(Color.textTertiary.opacity(0.30), lineWidth: 1)
            }

            // The owner's colour (#194 v2). Two layers, both no-ops when the
            // caller sets no `accent`, and neither of them touching a channel a
            // state already owns — see `DSSlat.accent`.
            if let accent = ownerAccent {
                if slat.state == .current {
                    DSSlatShape(slant: slant).fill(ownerWash(accent))
                }
                Rectangle()
                    .fill(accent)
                    .frame(height: ownerRuleHeight)
                    // Mirrors the top rule's `offset(x: slant)`: the bottom edge
                    // of the parallelogram runs `slant` to the LEFT of the top
                    // one, so the rule has to lean the other way to land on it.
                    .offset(x: -slant, y: height - ownerRuleHeight)
            }

            if ruleHeight > 0 {
                Rectangle()
                    .fill(ruleColor)
                    .frame(height: ruleHeight)
                    .offset(x: slant)
            }

            slatContent
                // `slant` is what the parallelogram takes off each side; the
                // rest is the optical margin. Both are as tight as the geometry
                // allows, because every point here comes off the stage name.
                .padding(.leading, slant + 6)
                .padding(.trailing, slant + 5)
                .padding(.vertical, isCompact ? 4 : 7)
                .frame(width: width, height: height, alignment: .leading)
        }
        .frame(width: width, height: height)
        // THE PARALLELOGRAM CLIPS ITS OWN CONTENT. At 56 pt a −11° skew displaces
        // each corner 5.4 pt, so unclipped text paints across the 2 pt seam.
        .clipShape(DSSlatShape(slant: slant))
        .overlay(
            DSSlatShape(slant: slant)
                .strokeBorder(isSelected ? Color.accentBlue : Color.clear, lineWidth: 2)
        )
        .modifier(DSSlatLift(isCurrent: !isPlace && slat.state == .current))
        .contentShape(DSSlatShape(slant: slant))
    }

    /// The counter-skewed content: upright, LEFT-aligned, never centred.
    @ViewBuilder
    private var slatContent: some View {
        if isPlace { placeContent } else { stepContent }
    }

    /// A destination: glyph, word, and at most an obligation dot (#165).
    ///
    /// **The dot is `alertOrange` in both states, and that is the finding, not a
    /// miss.** The rule the tab strip carries is that an obligation dot is a
    /// FOREGROUND mark, so on a control whose active state is a loud gold fill
    /// it has to take the foreground's plate ink — `alertOrange` on `accentGold`
    /// is ~1.4:1 and vanishes exactly where the control is loudest. A place slat
    /// never takes a gold fill: gold marks where the PROCESS is standing, and
    /// selection here is the band's `accentBlue` ring over the same dark
    /// `backgroundTertiary` surface. So the dark-surface value is the correct
    /// one in both states, and the plate-ink variant stays where a gold fill
    /// actually exists.
    private var placeContent: some View {
        HStack(spacing: DSSpacing.xxs) {
            if let icon = slat.icon {
                Image(systemName: icon)
                    .font(DSType.display(11, .black))
                    .foregroundStyle(titleColor)
                    .fixedSize()
            }
            Text(slat.title.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.6)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            if slat.hasObligation {
                Circle()
                    .fill(Color.alertOrange)
                    .frame(width: 7, height: 7)  // ds-lint:allow(spacing) obligation dot: a place slat has no second text tier to put this in
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: DSSpacing.xxs) {
                // ONE leading glyph slot. The check REPLACES the position
                // numeral on a done slat rather than sitting after the title:
                // a third element in the row costs 16 pt, and at nine stages
                // across a portrait iPad that is the 16 pt that broke
                // INTERVIEWS across two lines. §2.1's `done` row is "check glyph
                // + the outcome" — the position of finished work is carried by
                // where the slat sits and by the accessibility sentence.
                if slat.state == .done {
                    Image(systemName: "checkmark")
                        .font(DSType.display(11, .black))
                        .foregroundStyle(slat.tint ?? Color.textSecondary)
                } else if let index = slat.index {
                    Text(index)
                        .font(DSType.display(11, .heavy))
                        .foregroundStyle(indexColor)
                        // The title has the layout priority, so without this the
                        // numeral is the thing that gets squeezed — and a clipped
                        // "4" beside a full stage name reads as a rendering bug.
                        .fixedSize()
                }
                Text(slat.title.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(titleColor)
                    .lineLimit(titleLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                if slat.isLive && !isCompact {
                    Text("NOW")
                        .font(DSType.display(11, .black))
                        .foregroundStyle(Color.backgroundPlate)
                        .padding(.horizontal, DSSpacing.xxs)
                        .padding(.vertical, 1)  // ds-lint:allow(spacing) the live pill must not grow the 56 pt slat
                        .background(Capsule().fill(Color.accentGold))
                }
                Spacer(minLength: 0)
            }
            if !isCompact, let line = secondLine {
                Text(line)
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// The done slat says what it produced; every other state says what it costs
    /// or what opens it.
    private var secondLine: String? {
        if slat.state == .done, let outcome = slat.outcome, !outcome.isEmpty { return outcome }
        return slat.subcaption
    }

    /// Two lines, always.
    ///
    /// Measured, not guessed: at nine slats across a 1032 pt iPad the text box is
    /// ~82 pt wide, which is 12 uppercase condensed characters at the 11 pt
    /// floor — and PRIVATE WORKOUTS is sixteen. One line means the band
    /// truncates the stage names it exists to show, and the floor is a floor, so
    /// the type cannot shrink to meet it. Two 11 pt lines plus an 11 pt
    /// sub-caption is 39 pt inside a 42 pt content box.
    private var titleLines: Int { 2 }

    // MARK: Channel 1 — surface value

    private var surface: AnyShapeStyle {
        // #165. A value none of the four states uses, so a place reads as "not
        // on this ladder" before a single word is legible: one step above `done`
        // (`backgroundSecondary`) and flat, where `current` is a gradient.
        if isPlace { return AnyShapeStyle(Color.backgroundTertiary) }
        switch slat.state {
        case .current:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.backgroundTertiary, Color.backgroundSecondary],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .done:   return AnyShapeStyle(Color.backgroundSecondary)
        case .future: return AnyShapeStyle(Color.backgroundPrimary)
        case .locked: return AnyShapeStyle(Color.backgroundPlate)
        }
    }

    // MARK: Channel 1b — the owner (#194 v2)

    /// The owner colour, but only on the two states where identity is news.
    ///
    /// `done` is excluded on purpose: a finished slat already spends its two
    /// colour slots on `tint` (the top rule and the check), and a third mark
    /// under the same cell turns the ribbon's history into stripes. `locked` and
    /// `place` have no owner by definition.
    private var ownerAccent: Color? {
        guard !isPlace, slat.state == .current || slat.state == .future else { return nil }
        return slat.accent
    }

    /// The live cell states its owner twice as loudly as an upcoming one.
    private var ownerRuleHeight: CGFloat { slat.state == .current ? 3 : 2 }

    /// Flat and faint under the words; a real block of club colour in the empty
    /// trailing half of the widened `current` slat. See `DSSlat.accent` for the
    /// measurement that fixes 0.08 as the ceiling under text and 0.50 as the
    /// earliest the ramp may start.
    private func ownerWash(_ accent: Color) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: accent.opacity(0.08), location: 0.00),
                .init(color: accent.opacity(0.08), location: 0.50),
                .init(color: accent.opacity(0.20), location: 0.72),
                .init(color: accent.opacity(0.55), location: 1.00)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: Channel 2 — top rule

    private var ruleHeight: CGFloat {
        // A place has no position in the run, so it never carries the run's
        // marker — least of all the gold one (#165).
        if isPlace { return 0 }
        switch slat.state {
        case .current: return 3
        case .done:    return 2
        default:       return 0
        }
    }

    private var ruleColor: Color {
        switch slat.state {
        case .current: return .accentGold
        case .done:    return slat.tint ?? .textSecondary
        default:       return .clear
        }
    }

    // MARK: Channel 3 — the words

    private var titleColor: Color {
        // The place slat's only two readings are "you are standing here" and
        // "you are not", and the ring already says which. The ink follows it so
        // the answer survives at a distance where a 2 pt stroke does not.
        if isPlace { return isSelected ? .textPrimary : .textSecondary }
        switch slat.state {
        case .current: return .textPrimary
        case .done:    return .textSecondary
        case .future:  return slat.isAvailable ? .textPrimary : .textTertiaryReadable
        case .locked:  return .textTertiaryReadable
        }
    }

    private var indexColor: Color {
        slat.state == .current ? .accentGold : .textTertiaryReadable
    }
}

/// The current slat lifts; nothing else does. Kept as a modifier so the shadow
/// is applied to the clipped parallelogram rather than to its content.
private struct DSSlatLift: ViewModifier {
    let isCurrent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCurrent {
            content.dsElevation(.bar)
        } else {
            content
        }
    }
}

/// Pressed moves the CONTENT by 1 pt. The parallelogram stays put — the ribbon
/// is a fixed rail and a slat that jumps out of it reads as a layout bug.
private struct DSSlatPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Full") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        DSSlatBand(
            slats: [
                DSSlat(id: "a", index: "1", title: "Combine Review", state: .done,
                       outcome: "Read", accessibilityText: "Stage 1, Combine Review, complete"),
                DSSlat(id: "b", index: "2", title: "Interviews", state: .done,
                       outcome: "12 interviews", accessibilityText: "Stage 2, Interviews, complete"),
                DSSlat(id: "c", index: "3", title: "Film Study",
                       subcaption: "4 of 25 reports \u{00B7} spends 1 scouting week",
                       state: .current, isLive: true,
                       accessibilityText: "Stage 3, Film Study, current stage"),
                DSSlat(id: "d", index: "4", title: "Pro Day Focus",
                       subcaption: "Opens after free agency", state: .locked,
                       accessibilityText: "Stage 4, Pro Day Focus, locked"),
                DSSlat(id: "e", index: "5", title: "Private Workouts",
                       subcaption: "Opens after free agency", state: .locked,
                       accessibilityText: "Stage 5, Private Workouts, locked")
            ],
            headline: "Stage 3 of 5",
            meter: DSResourceMeter(spent: 3, total: 5, unit: "scouting weeks"),
            selectedID: "c",
            onSelect: { _ in }
        )
        .padding()
    }
}

#Preview("Place slat + run") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        DSSlatBand(
            slats: [
                DSSlat.place(id: "warRoom", title: "War Room", icon: "square.grid.2x2.fill",
                             hasObligation: true,
                             accessibilityText: "War Room. Mock 1.0 has not been filed"),
                DSSlat(id: "a", index: "1", title: "Combine Review", state: .done, outcome: "Read"),
                DSSlat(id: "b", index: "2", title: "Interviews", state: .done, outcome: "12 interviews"),
                DSSlat(id: "c", index: "3", title: "Film Study",
                       subcaption: "4 of 25 reports \u{00B7} spends 1 scouting week",
                       state: .current),
                DSSlat(id: "d", index: "4", title: "Pro Day Focus",
                       subcaption: "After FA", state: .locked),
                DSSlat(id: "e", index: "5", title: "Private Workouts",
                       subcaption: "After FA", state: .locked),
                DSSlat(id: "f", index: "6", title: "Top-30 Visits",
                       subcaption: "After FA", state: .locked)
            ],
            headline: "Stage 3 of 6",
            meter: DSResourceMeter(spent: 3, total: 6, unit: "scouting weeks"),
            selectedID: "warRoom",
            onSelect: { _ in }
        )
        .padding()
    }
}

#Preview("Compact") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        DSSlatBand(
            slats: [
                DSSlat(id: "a", index: "1", title: "Combine Review", state: .done),
                DSSlat(id: "b", index: "2", title: "Interviews", state: .current),
                DSSlat(id: "c", index: "3", title: "Film Study", state: .future, isAvailable: true),
                DSSlat(id: "d", index: "4", title: "Pro Day Focus", state: .locked)
            ],
            headline: "Stage 2 of 4",
            meter: DSResourceMeter(spent: 2, total: 4, unit: "scouting weeks"),
            isCompact: true,
            onSelect: { _ in }
        )
        .padding()
    }
}
