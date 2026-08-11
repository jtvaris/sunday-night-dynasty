import SwiftUI

// MARK: - The one press conference (#105 Wave 5a)
//
// UI_REDESIGN_VISION §4 Wave 5, and §3's row 12b by name:
//
// > Two ~1000-line press implementations already drifted (scrim 0.32 vs 0.25,
// > 4- vs 3-stop gradient) … Deduplicate into one component each *before*
// > styling anything, or every fix costs 2×.
//
// This file is that one component. `WeeklyPressConferenceView` still exists as a
// name — `CareerShellView` mounts it and this wave does not own that file — but
// it is a ~30-line adapter that builds this view in `.postGame` mode. There is
// one press conference in the app now, in one file.
//
// ## What the merge kept, exactly
//
// **#161's mechanics are untouched.** Every number on this screen still comes
// out of `PressConferenceEngine`, through the same four calls the two screens
// each made separately:
//
//   `preview(for:question:context:)`      the fogged hints — direction, never a
//                                         number, and "—" for an audience the
//                                         coach cannot read
//   `resolvedEffects(for:question:context:)`  the real deltas, revealed only
//                                         after the words have left his mouth
//   `sessionFeedback(for:)`               the running verdict (engine thresholds,
//                                         view picks only the colour)
//   `buildResult(questions:selectedIndices:context:)`  the promise ledger and
//                                         the tone ledger
//
// The tone matrix, the stance chip, the vanilla penalty, the promise ledger and
// the `liveContext` fold (each question resolved in the context it was ASKED in,
// mirroring `buildResult`) are copied across verbatim. Only the surface merged.
//
// **P5's confirmation corollary stays, and is now the screen's only commit.**
// An answer is picked (reversible, gold "Picked" tick) and then *said* (the
// `DSActionBar` primary). The two-step IS the confirmation; there is no dialog,
// and there is exactly one gold fill on the surface.
//
// ## What the merge changed
//
//  * **Two progress metaphors became one `DSSlatBand`** — the intro presser drew
//    a segmented `GeometryReader` bar, the weekly one drew a dot rail. §2.1's
//    band is the app's single process spine, and the questions are an ordered
//    run with an outcome per step (the tone he answered in), which is exactly
//    what a slat draws. It is pinned chrome above the scroll, so the process can
//    never scroll away from the answer.
//  * **The two backdrops became the audited one** (0.32 scrim, four-stop
//    directional vignette, top safe-area scrim).
//  * **The two reporter cards became the audited one** — identity strip with the
//    stance pill, prompt in its own card. The weekly card's duplicate outlet
//    badge is gone; it printed the outlet twice on one row.
//  * **Two hand-rolled gold capsules** ("Take the Podium", "Continue" /
//    "Return to Dashboard") are `DSActionBar` primaries.
//  * **The summary follows §2.6's order** — outcome headline → what changed →
//    what it cost → one Continue. Not a literal `DSResultSheet`: this is a phase
//    of a full-screen flow, and the sheet has no slot for the quote list or the
//    promise ledger, both of which are the point of a press summary.
//  * Everything informational is at or above the 11 pt display floor; the 9 pt
//    overlines and the 10 pt sub-labels the two screens shared are gone.
//
// ## #166 — the auto-scroll residue
//
// Both screens shipped the same fix and the same bug. The reveal was inserted
// with `.delay(0.35)` on a 0.5 s animation, i.e. it finished laying out at
// t ≈ 0.85 s, and the scroll was fired from a hard-coded `asyncAfter(0.5)`. The
// scroll therefore ran while the inserted card was still animating its scale
// transition, and `scrollTo` resolved against a frame that was still moving —
// so it landed short, and on a full card it did not appear to move at all.
//
// The second half of #166 is the *question* anchor: it sat on the screen header
// (ident + standing strip + running impact), so advancing a question scrolled to
// the top of a pile of chrome and left the prompt — the thing the player has to
// read — below the fold on a compact height.
//
// Both are fixed structurally rather than by a longer timer:
//
//   * the anchor moved onto the **prompt card**, which is what "the new question"
//     means to a reader;
//   * the scroll is requested from the insertion animation's own **completion**
//     (`completionCriteria: .logicallyComplete`), so it runs when the target has
//     a settled frame instead of at a guessed instant;
//   * requests go through a nonce, so the same anchor can be re-requested on
//     question 3 after it was already used on question 2.
//
// No timers remain on this screen.

struct PressConferenceView: View {

    // MARK: - Which conference

    /// The two pressers, as one screen with two openings. Everything below the
    /// opening — the band, the prompt, the cards, the reveal, the summary — is
    /// identical, which is the whole reason the merge is possible.
    enum Session: Equatable {
        /// The hiring presser. Owns a podium phase and generates its own
        /// questions and context from the roster it just inherited.
        case introductory
        /// The post-game presser. `WeekAdvancer` has already assembled the
        /// questions and the context; this screen only asks them.
        case postGame

        var ident: String {
            switch self {
            case .introductory: return "Press Conference"
            case .postGame:     return "Post-Game Press Conference"
            }
        }

        /// What the last button on the summary says.
        var finishTitle: String {
            switch self {
            case .introductory: return "Continue"
            case .postGame:     return "Return to dashboard"
            }
        }
    }

    // MARK: - Inputs

    let session: Session
    let career: Career
    /// The club, for the podium plate. Only the introductory presser has one.
    var team: Team?
    /// Drives the "before this session" satisfaction reading and the intro
    /// generator's fallback persona. Optional on both paths.
    var owner: Owner?
    /// #161: the inherited roster. Feeds the engine's `standing` and
    /// `lockerRoom` bands — the two context axes the fogged hints are read off.
    /// Empty is safe (both fall back to neutral bands).
    var roster: [Player] = []
    let onComplete: (PressConferenceResult) -> Void

    // MARK: - Session state

    @State private var questions: [PressQuestion]
    /// #161: the engine context, advanced one tone at a time as the coach
    /// answers. Everything on screen — hints, resolved deltas, the vanilla
    /// label — is computed from this and nothing else.
    @State private var context: PressConferenceEngine.PressContext
    @State private var phase: Phase

    @State private var currentQuestionIndex = 0
    @State private var selectedIndices: [Int] = []
    @State private var didPrepare = false

    // Reveal choreography
    @State private var showPodium = false
    @State private var showReporter = false
    @State private var showResponses = false
    /// P5 step 1: the card the coach has picked but not yet said out loud.
    @State private var pendingResponseIndex: Int?
    /// P5 step 2: the answer he committed to. `nil` until "Say it".
    @State private var selectedResponseIndex: Int?
    @State private var showReaction = false
    @State private var reactionText = ""
    /// The real, context-resolved deltas of the committed answer — revealed
    /// only after the words have left his mouth.
    @State private var revealedEffects: PressEffects?
    /// Index of the response whose headline preview is currently expanded.
    @State private var headlinePreviewIndex: Int?

    // #166 — see the file header.
    @State private var scrollTarget: Anchor?
    @State private var scrollNonce = 0

    private enum Phase {
        case podium
        case questioning
        case summary
    }

    /// The two places the screen ever scrolls to. Both live on content, never
    /// on chrome — that was half of #166.
    private enum Anchor: String {
        /// The prompt card: reporter, outlet, stance, question.
        case prompt = "press.prompt"
        /// The reveal: what ran, and what it actually cost.
        case reveal = "press.reveal"

        var alignment: UnitPoint {
            switch self {
            case .prompt: return .top
            case .reveal: return .bottom
            }
        }
    }

    // MARK: - Inits

    /// The hiring presser.
    init(
        career: Career,
        team: Team,
        owner: Owner?,
        roster: [Player] = [],
        onComplete: @escaping (PressConferenceResult) -> Void
    ) {
        self.session = .introductory
        self.career = career
        self.team = team
        self.owner = owner
        self.roster = roster
        self.onComplete = onComplete
        _questions = State(initialValue: [])
        _context = State(initialValue: .neutral)
        _phase = State(initialValue: .podium)
    }

    /// The post-game presser — questions and context assembled by the caller.
    init(
        questions: [PressQuestion],
        career: Career,
        context: PressConferenceEngine.PressContext = .neutral,
        owner: Owner? = nil,
        onComplete: @escaping (PressConferenceResult) -> Void
    ) {
        self.session = .postGame
        self.career = career
        self.team = nil
        self.owner = owner
        self.roster = []
        self.onComplete = onComplete
        _questions = State(initialValue: questions)
        _context = State(initialValue: context)
        _phase = State(initialValue: .questioning)
    }

    // MARK: - Derived (#161, unchanged)

    /// Live deltas accumulated from the answers already on the record.
    private var runningTotals: PressEffects {
        var totals = PressEffects()
        var live = context
        for (qIdx, respIdx) in selectedIndices.enumerated() {
            guard qIdx < questions.count,
                  respIdx < questions[qIdx].responses.count else { continue }
            let response = questions[qIdx].responses[respIdx]
            totals = totals + PressConferenceEngine.resolvedEffects(
                for: response, question: questions[qIdx], context: live
            )
            live = live.appending(tone: response.tone)
        }
        return totals
    }

    /// The context question N is answered in — the opening context plus every
    /// tone already used. Mirrors `PressConferenceEngine.buildResult` exactly.
    private var liveContext: PressConferenceEngine.PressContext {
        var live = context
        for (qIdx, respIdx) in selectedIndices.enumerated() {
            guard qIdx < questions.count,
                  respIdx < questions[qIdx].responses.count else { continue }
            live = live.appending(tone: questions[qIdx].responses[respIdx].tone)
        }
        return live
    }

    private var currentQuestion: PressQuestion? {
        currentQuestionIndex < questions.count ? questions[currentQuestionIndex] : nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backdrop
            switch phase {
            case .podium:      podiumContent
            case .questioning: questioningContent
            case .summary:     summaryContent
            }
        }
        .onAppear(perform: prepare)
    }

    // MARK: - Backdrop
    //
    // The audited one, singular. The weekly presser's 0.25 scrim and three-stop
    // gradient were a copy that drifted, not a decision.

    private var backdrop: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Token-only backdrop (#167). The press-room photograph carried a
            // shield-form crest on the backdrop wall, so the asset is deleted.
            // The vignette that used to sit *over* the photo now carries the
            // whole job: darker top and bottom for text protection, a lifted
            // mid band where the podium sits, so the eye still lands there.
            LinearGradient(
                stops: [
                    .init(color: Color.backgroundPlate,     location: 0.0),
                    .init(color: Color.backgroundSecondary, location: 0.38),
                    .init(color: Color.backgroundSecondary, location: 0.62),
                    .init(color: Color.backgroundPlate,     location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Podium key light — a soft pool centred on the mid band, the one
            // piece of shaping the photograph used to provide for free.
            RadialGradient(
                colors: [
                    Color.backgroundTertiary.opacity(0.50),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.48),
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Top safe-area scrim — keeps status-bar text protected.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.5), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)
                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Podium phase (introductory only)

    private var podiumContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: DSSpacing.lg) {
                        Spacer(minLength: DSSpacing.xl)

                        if showPodium {
                            podiumPlate
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }

                        Spacer(minLength: DSSpacing.lg)
                    }
                    .padding(.horizontal, DSSpacing.lg)
                    .frame(maxWidth: DSLayout.wideMeasure)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }

            // §2.5: the one commit surface, even when the only thing to commit
            // to is walking up to the microphone.
            DSActionBar(
                explainer: .init(
                    title: "Introductory press conference",
                    message: "**\(max(questions.count, 1)) questions.** Everything you say is on the record."
                ),
                primary: .init(title: "Take the podium", handler: beginQuestioning)
            )
        }
    }

    private var podiumPlate: some View {
        VStack(spacing: DSSpacing.md) {
            // The person about to take the podium is the player, so the podium
            // screen opens on the player's own face with the microphone tucked
            // under it.
            UserPortraitView(career: career, size: .large)
                .shadow(color: Color.black.opacity(0.5), radius: 10, y: 4)
                .overlay(alignment: .bottom) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentGold)
                        .shadow(color: Color.accentGold.opacity(0.4), radius: 10)
                        .shadow(color: Color.black.opacity(0.55), radius: 4, y: 2)
                        .offset(y: 12)
                }

            Text(career.playerName)
                .font(DSType.text(16, .bold))
                .foregroundStyle(Color.textPrimary)

            Text(session.ident.uppercased())
                .font(DSType.display(DSType.Size.footnote, .black))
                .tracking(8)
                .foregroundStyle(Color.accentGold.opacity(0.9))

            if let team {
                Text("\(team.city) \(team.name)")
                    .font(DSType.display(DSType.Size.title1, .heavy))
                    .foregroundStyle(Color.textPrimary)
            }

            Rectangle()
                .fill(Color.accentGold.opacity(0.3))
                .frame(width: 80, height: 2)
                .padding(.top, DSSpacing.xs)

            Text("The media is waiting. Choose your words carefully \u{2014} they will be remembered.")
                .font(DSType.text(15, .regular, prose: true))
                .foregroundStyle(Color.textPrimary.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xl)
                .fixedSize(horizontal: false, vertical: true)

            // The same band the questioning phase runs on, drawn ahead of the
            // first question so the shape of the session is known before it
            // starts. Every slat is `.future`; nothing is current yet.
            if !questions.isEmpty {
                DSSlatBand(
                    slats: questionSlats(previewOnly: true),
                    headline: "\(questions.count) questions",
                    meter: DSResourceMeter(spent: 0, total: questions.count, unit: "questions")
                )
                .frame(maxWidth: DSLayout.contentMeasure)
                .padding(.top, DSSpacing.xs)
            }
        }
    }

    // MARK: - Questioning phase

    private var questioningContent: some View {
        VStack(spacing: 0) {
            // §2.1: the process is pinned chrome. It used to be the first thing
            // in the scroll view, which meant the player lost sight of where he
            // was the moment he read a long answer.
            DSSlatBand(
                slats: questionSlats(previewOnly: false),
                headline: "Question \(min(currentQuestionIndex + 1, max(questions.count, 1))) of \(max(questions.count, 1))",
                meter: DSResourceMeter(
                    spent: selectedIndices.count,
                    total: max(questions.count, 1),
                    unit: "questions"
                )
            )
            .frame(maxWidth: DSLayout.wideMeasure)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.xs)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DSSpacing.md) {
                        standingStrip

                        if !selectedIndices.isEmpty {
                            runningImpactStrip
                        }

                        if let question = currentQuestion {
                            if showReporter {
                                promptCard(question: question)
                                    .id(Anchor.prompt.rawValue)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if showResponses {
                                VStack(spacing: DSSpacing.sm) {
                                    ForEach(Array(question.responses.enumerated()), id: \.element.id) { index, response in
                                        responseCard(response: response, question: question, index: index)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            if showReaction {
                                resultReveal
                                    .id(Anchor.reveal.rawValue)
                                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            }
                        }

                        Spacer(minLength: DSSpacing.lg)
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.top, DSSpacing.sm)
                    .frame(maxWidth: DSLayout.wideMeasure)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                // #166: one scroll driver, fired from an animation completion
                // rather than from a timer. The nonce is what lets the same
                // anchor be requested again on the next question.
                .onChange(of: scrollNonce) { _, _ in
                    guard let target = scrollTarget else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(target.rawValue, anchor: target.alignment)
                    }
                }
            }

            // P5: the ONE commit surface. Tapping a card selects; this says it.
            commitBar
        }
    }

    // MARK: The question band (§2.1)

    /// The session as slats. A `done` slat carries the tone he answered in —
    /// which is what §2.1 means by "what a done step produced".
    private func questionSlats(previewOnly: Bool) -> [DSSlat] {
        questions.enumerated().map { index, question in
            let answeredTone: ResponseTone? = {
                guard index < selectedIndices.count else { return nil }
                let choice = selectedIndices[index]
                guard choice < question.responses.count else { return nil }
                return question.responses[choice].tone
            }()

            let state: DSSlat.State
            if previewOnly {
                state = .future
            } else if answeredTone != nil {
                state = .done
            } else if index == currentQuestionIndex {
                state = .current
            } else {
                state = .future
            }

            let stance = PressConferenceEngine.stance(for: question)

            return DSSlat(
                id: question.id.uuidString,
                index: "\(index + 1)",
                title: question.outlet,
                subcaption: state == .current
                    ? "\(question.reporterName) \u{00B7} \(stance.label.lowercased())"
                    : nil,
                state: state,
                outcome: answeredTone?.label,
                isLive: state == .current,
                accessibilityText: slatSpeech(
                    index: index,
                    question: question,
                    state: state,
                    tone: answeredTone
                )
            )
        }
    }

    private func slatSpeech(
        index: Int,
        question: PressQuestion,
        state: DSSlat.State,
        tone: ResponseTone?
    ) -> String {
        let position = "Question \(index + 1) of \(questions.count), \(question.outlet)"
        switch state {
        case .done:    return "\(position), answered \(tone?.label ?? "")"
        case .current: return "\(position), on the microphone now"
        default:       return "\(position), still to come"
        }
    }

    // MARK: Standing strip

    /// Where the coach stands *before* this session. Labelled, because a fresh
    /// career reads "0 Legacy / 0 Media" and a bare zero looks like a fault.
    private var standingStrip: some View {
        VStack(spacing: DSSpacing.xs) {
            Text("BEFORE THIS SESSION")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                standingItem(
                    icon: "star.fill",
                    label: "Legacy",
                    value: "\(career.legacy.totalPoints)",
                    color: Color.accentGold
                )
                standingItem(
                    icon: "newspaper.fill",
                    label: "Media",
                    value: "\(career.legacy.mediaReputation)",
                    color: career.legacy.mediaReputation >= 0 ? Color.success : Color.dangerText
                )
                // #117: "Satisfaction", not "Comp".
                if let owner {
                    standingItem(
                        icon: "building.2.fill",
                        label: "Satisfaction",
                        value: "\(owner.satisfaction)%",
                        color: Color.forRating(owner.satisfaction, scale: .percent)
                    )
                }
            }

            // #119: what each of those actually does.
            Text("Owner affects job security \u{00B7} Media shapes the narrative \u{00B7} Legacy affects career rating")
                .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private func standingItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(value)
                .font(DSType.display(DSType.Size.title3, .heavy))
                .foregroundStyle(Color.textPrimary)
            Text(label.uppercased())
                .font(DSType.display(11, .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Running impact

    private var runningImpactStrip: some View {
        let totals = runningTotals
        let feedback = PressConferenceEngine.sessionFeedback(for: totals)
        let color = feedbackColor(feedback.severity)

        return VStack(spacing: DSSpacing.xs) {
            Text("RUNNING IMPACT")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DSSpacing.xs) {
                deltaChip(icon: "building.2.fill", label: "Owner", value: totals.ownerSatisfaction)
                deltaChip(icon: "person.3.fill", label: "Morale", value: totals.playerMorale)
                deltaChip(icon: "hands.clap.fill", label: "Fans", value: totals.fanExcitement)
                deltaChip(icon: "newspaper.fill", label: "Media", value: totals.mediaPerception)
                Spacer(minLength: 0)
            }

            // The engine decides the words and the severity; the view only
            // paints the severity's colour.
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: feedback.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(feedback.text)
                    .font(DSType.text(DSType.Size.footnote, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(color)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(color.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private func deltaChip(icon: String, label: String, value: Int) -> some View {
        let color: Color = value > 0 ? Color.success : value < 0 ? Color.dangerText : Color.textTertiaryReadable
        return HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(label.uppercased())
                .font(DSType.display(11, .semibold))
                .tracking(0.4)
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(DSType.display(11, .heavy))
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value > 0 ? "up" : value < 0 ? "down" : "unchanged") \(abs(value))")
    }

    // MARK: Prompt card

    /// Reporter identity strip over the prompt. The stance pill is an **engine
    /// input** (`PressConferenceEngine.stanceAdjustment`), not a decoration —
    /// hostile writers punish evasion and reward candour — so the chip can never
    /// disagree with the arithmetic it advertises.
    private func promptCard(question: PressQuestion) -> some View {
        let stance = PressConferenceEngine.stance(for: question)
        let stanceColor = stanceColor(stance)

        return VStack(spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(question.reporterName)
                        .font(DSType.text(14, .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(question.outlet.uppercased())
                        .font(DSType.display(11, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.accentGold)
                }

                Spacer(minLength: DSSpacing.xs)

                HStack(spacing: DSSpacing.xxs) {
                    Circle()
                        .fill(stanceColor)
                        .frame(width: 6, height: 6)
                    Text(stance.label.uppercased())
                        .font(DSType.display(11, .heavy))
                        .tracking(0.6)
                }
                .foregroundStyle(stanceColor)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    Capsule()
                        .fill(stanceColor.opacity(0.12))
                        .overlay(Capsule().strokeBorder(stanceColor.opacity(0.35), lineWidth: 1))
                )
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
            )

            // The prompt stands alone. It is the subject of the screen, so it
            // is the one bordered, elevated insert on it (§2.11).
            Text("\u{201C}\(question.question)\u{201D}")
                .font(DSType.text(18, .semibold, prose: true))
                .italic()
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .fill(Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                                .strokeBorder(Color.accentGold.opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(question.reporterName), \(question.outlet), \(stance.label). \(question.question)"
        )
    }

    // MARK: Response cards

    private func responseCard(
        response: PressResponse,
        question: PressQuestion,
        index: Int
    ) -> some View {
        // Two distinct states: PICKED (step 1, reversible) and SAID (step 2, on
        // the record).
        let isPending = pendingResponseIndex == index && selectedResponseIndex == nil
        let isSaid = selectedResponseIndex == index
        let isDisabled = selectedResponseIndex != nil && !isSaid
        let isHighlighted = isPending || isSaid
        let isHeadlineExpanded = headlinePreviewIndex == index
        let tint = toneColor(response.tone)
        let preview = PressConferenceEngine.preview(
            for: response, question: question, context: liveContext
        )

        return Button(action: { pickResponse(index: index) }) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: response.tone.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(response.tone.label.uppercased())
                            .font(DSType.display(11, .heavy))
                            .tracking(0.6)
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Capsule().fill(tint.opacity(0.15)))

                    if preview.isVanilla, let label = preview.vanillaLabel {
                        vanillaChip(label)
                    }

                    Spacer(minLength: 0)

                    if isPending {
                        Label("Picked", systemImage: "checkmark.circle.fill")
                            .font(DSType.text(DSType.Size.footnote, .bold))
                            .foregroundStyle(Color.accentGold)
                    }
                }

                Text("\u{201C}\(response.text)\u{201D}")
                    .font(DSType.text(15, .medium, prose: true))
                    .foregroundStyle(isDisabled ? Color.textTertiaryReadable : Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // #161 B: fogged reaction hints — direction, never numbers.
                hintRow(preview)

                headlinePreviewSection(
                    response: response,
                    index: index,
                    isExpanded: isHeadlineExpanded,
                    isDisabled: isDisabled
                )
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(isHighlighted ? tint.opacity(0.12) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(
                                // The default stroke is tinted by the archetype so
                                // the cards can be pre-scanned by personality.
                                isHighlighted ? tint.opacity(0.75) : tint.opacity(0.28),
                                lineWidth: isHighlighted ? 2 : 1
                            )
                    )
                    .overlay(alignment: .leading) {
                        UnevenRoundedRectangle(
                            topLeadingRadius: DSCornerRadius.card,
                            bottomLeadingRadius: DSCornerRadius.card
                        )
                        .fill(tint.opacity(isDisabled ? 0.35 : 0.85))
                        .frame(width: 4)
                    }
            )
            .opacity(isDisabled ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(selectedResponseIndex != nil)
        .accessibilityLabel("\(response.tone.label) answer. \(response.text)")
        .accessibilityHint(hintSpeech(preview))
        .animation(.easeInOut(duration: 0.25), value: pendingResponseIndex)
        .animation(.easeInOut(duration: 0.25), value: selectedResponseIndex)
        .animation(.easeInOut(duration: 0.2), value: headlinePreviewIndex)
    }

    // MARK: - #161 B: fogged hints

    /// Direction markers only. What a coach can plausibly read in the room —
    /// his owner's known persona, the mood in his own building, the stance on
    /// the reporter's chip — and a dash for the audiences he cannot.
    private func hintRow(_ preview: PressConferenceEngine.ReactionPreview) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(preview.hints) { hint in
                let color = hintColor(hint.direction)
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: hint.audience.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                    Text(hint.audience.label)
                        .font(DSType.text(DSType.Size.footnote, .medium))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: hint.direction.glyph)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                    Text(hint.phrase)
                        .font(DSType.text(DSType.Size.footnote, .semibold))
                        .foregroundStyle(color)
                }
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    Capsule()
                        .fill(color.opacity(0.10))
                        .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func hintColor(_ direction: PressConferenceEngine.ReactionHint.Direction) -> Color {
        switch direction {
        case .up:      return Color.success
        case .down:    return Color.dangerText
        case .neutral: return Color.textSecondary
        case .unknown: return Color.textTertiaryReadable
        }
    }

    private func hintSpeech(_ preview: PressConferenceEngine.ReactionPreview) -> String {
        preview.hints
            .map { "\($0.audience.label): \($0.phrase)" }
            .joined(separator: ". ")
    }

    private func vanillaChip(_ label: String) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 10, weight: .bold))
            Text(label.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.5)
        }
        .foregroundStyle(Color.alertOrange)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(Color.alertOrange.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.alertOrange.opacity(0.35), lineWidth: 1))
        )
    }

    /// The strongest read available *before* answering: the fiction of the
    /// consequence, not its arithmetic.
    private func headlinePreviewSection(
        response: PressResponse,
        index: Int,
        isExpanded: Bool,
        isDisabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // A separate gesture so it does not trigger the card's selection.
            Button(action: { toggleHeadlinePreview(index: index) }) {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 11))
                    Text(isExpanded ? "Hide headline preview" : "Preview headline")
                        .font(DSType.display(11, .semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color.textTertiaryReadable)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    Capsule().strokeBorder(Color.textTertiary.opacity(0.35), lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            if isExpanded {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentGold.opacity(0.7))
                    Text(response.mediaReaction)
                        .font(DSType.text(DSType.Size.footnote, .medium, prose: true))
                        .italic()
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DSSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .fill(Color.accentGold.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .strokeBorder(Color.accentGold.opacity(0.2), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleHeadlinePreview(index: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            headlinePreviewIndex = headlinePreviewIndex == index ? nil : index
        }
    }

    // MARK: - #161 C: the reveal

    /// AFTER the answer. The headline that ran, and — for the first time on this
    /// screen — the real numbers. This is the learning loop: the player finds out
    /// what "Diplomatic, on a crisis question, in front of a hostile writer"
    /// actually costs by paying it once.
    private var resultReveal: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentGold)

                Text(reactionText)
                    .font(DSType.text(14, .medium, prose: true))
                    .italic()
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let effects = revealedEffects {
                Divider().overlay(Color.accentGold.opacity(0.2))

                Text("WHAT IT ACTUALLY COST")
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.textSecondary)

                effectPillRow(effects: effects)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.accentGold.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.accentGold.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func effectPillRow(effects: PressEffects) -> some View {
        HStack(spacing: DSSpacing.xs) {
            if effects.ownerSatisfaction != 0 {
                effectPill(icon: "building.2.fill", label: "Owner", value: effects.ownerSatisfaction)
            }
            if effects.playerMorale != 0 {
                effectPill(icon: "person.3.fill", label: "Morale", value: effects.playerMorale)
            }
            if effects.fanExcitement != 0 {
                effectPill(icon: "hands.clap.fill", label: "Fans", value: effects.fanExcitement)
            }
            if effects.mediaPerception != 0 {
                effectPill(icon: "newspaper.fill", label: "Media", value: effects.mediaPerception)
            }
            if effects.legacyPoints != 0 {
                effectPill(icon: "star.fill", label: "Legacy", value: effects.legacyPoints)
            }
            Spacer(minLength: 0)
        }
    }

    /// Neutral icon and label so the coloured delta is the single scannable
    /// signal; `dangerText` rather than `danger` because these are words on a
    /// dark navy card (#116 / #118 and the WCAG follow-up).
    private func effectPill(icon: String, label: String, value: Int) -> some View {
        let pillColor: Color = value > 0 ? Color.success : Color.dangerText
        let isStrongNegative = value <= -6

        return HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
            Text(label.uppercased())
                .font(DSType.display(11, .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.textSecondary)
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(DSType.display(DSType.Size.footnote, .heavy))
                .foregroundStyle(pillColor)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(pillColor.opacity(0.12))
                .overlay(
                    Capsule().strokeBorder(
                        pillColor.opacity(isStrongNegative ? 0.55 : 0.3),
                        lineWidth: isStrongNegative ? 1.5 : 1
                    )
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value > 0 ? "+" : "")\(value)")
    }

    // MARK: - P5 commit bar

    /// Select-then-commit. An answer used to fire on first tap — irreversible,
    /// no confirmation, on a screen whose whole point is that words are
    /// remembered. The two-step IS the confirmation; there is no dialog.
    private var commitBar: some View {
        let question = currentQuestion
        let isCommitted = selectedResponseIndex != nil
        let isLast = currentQuestionIndex + 1 >= questions.count

        return DSActionBar(
            explainer: commitExplainer(question: question, isCommitted: isCommitted),
            primary: .init(
                title: isCommitted ? (isLast ? "Wrap it up" : "Next question") : "Say it",
                isEnabled: isCommitted || pendingResponseIndex != nil,
                handler: { isCommitted ? advanceAfterAnswer() : commitPendingResponse() }
            )
        )
    }

    private func commitExplainer(
        question: PressQuestion?,
        isCommitted: Bool
    ) -> DSActionBar.Explainer {
        if isCommitted {
            return .init(
                title: "On the record",
                message: "That is what ran, and what it cost. It cannot be taken back."
            )
        }
        guard let question,
              let index = pendingResponseIndex,
              index < question.responses.count else {
            return .init(
                title: "Your answer",
                message: "Pick a line. Nothing is said until you **say it**."
            )
        }
        let tone = question.responses[index].tone
        return .init(
            title: "\(tone.label) answer",
            message: "You will say it in front of **\(question.outlet)**. The room reacts after."
        )
    }

    // MARK: - Summary phase
    //
    // §2.6's order: outcome headline → what changed → what it cost → one
    // Continue. `DSResultSheet` is that order as a sheet; this is the same order
    // as a phase, because the quote list and the promise ledger have no slot in
    // the sheet and they are the reason a press summary exists.

    private var summaryContent: some View {
        let result = PressConferenceEngine.buildResult(
            questions: questions,
            selectedIndices: selectedIndices,
            context: context
        )

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    summaryHeadline(result: result)
                    summaryChanged(result: result)
                    summaryApproach(result: result)
                    summaryQuotes(result: result)
                    if !result.promises.isEmpty {
                        summaryPromises(result: result)
                    }
                    Spacer(minLength: DSSpacing.sm)
                }
                .padding(DSSpacing.lg)
                .frame(maxWidth: DSLayout.wideMeasure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            DSActionBar(
                explainer: .init(
                    title: "What it cost",
                    message: summaryCostLine(result: result)
                ),
                primary: .init(
                    title: "\(session.finishTitle) \u{2192}",
                    handler: finishConference
                )
            )
        }
    }

    private func summaryHeadline(result: PressConferenceResult) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text(session.ident.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.accentGold)
                    .lineLimit(1)
            }

            Text(mediaPerceptionLabel(for: result.dominantTone))
                .font(DSType.display(DSType.Size.title2, .heavy))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // #121: say what media perception actually affects.
            Text("That is how the room writes you up. It shapes free-agent interest, fan engagement and the tone of your coverage.")
                .font(DSType.text(14, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// #120 / #122: the deltas, with `baseline \u{2192} final` where a baseline
    /// exists. Laid out as a `Grid` for the same reason `DSResultSheet` is — an
    /// `HStack` of stacks drops a numeral the moment one column grows a line.
    private func summaryChanged(result: PressConferenceResult) -> some View {
        let effects = result.totalEffects
        let cells: [(label: String, value: Int, context: String?)] = [
            ("Owner", effects.ownerSatisfaction, owner.map { base in
                "\(base.satisfaction)% \u{2192} \(min(100, max(0, base.satisfaction + effects.ownerSatisfaction)))%"
            }),
            ("Morale", effects.playerMorale, nil),
            ("Fans", effects.fanExcitement, nil),
            ("Legacy", effects.legacyPoints,
             "\(career.legacy.totalPoints) \u{2192} \(career.legacy.totalPoints + effects.legacyPoints)")
        ]

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("WHAT CHANGED")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            Grid(alignment: .leading, horizontalSpacing: DSSpacing.lg, verticalSpacing: DSSpacing.xxs) {
                GridRow {
                    ForEach(cells, id: \.label) { cell in
                        Text(cell.label.uppercased())
                            .font(DSType.display(11, .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Color.textTertiaryReadable)
                            .lineLimit(1)
                    }
                }
                GridRow {
                    ForEach(cells, id: \.label) { cell in
                        Text(cell.value > 0 ? "+\(cell.value)" : "\(cell.value)")
                            .font(DSType.display(DSType.Size.title2, .heavy))
                            .foregroundStyle(
                                cell.value > 0 ? Color.success
                                    : cell.value < 0 ? Color.dangerText : Color.textTertiaryReadable
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                GridRow {
                    ForEach(cells, id: \.label) { cell in
                        // The row always reserves its context line so cells with
                        // and without a baseline sit at one height (§2.2).
                        Text(cell.context ?? " ")
                            .font(DSType.display(11, .semibold))
                            .foregroundStyle(Color.textTertiaryReadable)
                            .lineLimit(1)
                    }
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    /// #123: the tone distribution — what kind of coach he sounded like.
    private func summaryApproach(result: PressConferenceResult) -> some View {
        let counts: [(tone: ResponseTone, count: Int)] = {
            var table: [ResponseTone: Int] = [:]
            for response in result.selectedResponses {
                table[response.tone, default: 0] += 1
            }
            return table.sorted { $0.value > $1.value }.map { (tone: $0.key, count: $0.value) }
        }()

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("YOUR APPROACH")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: DSSpacing.xs) {
                ForEach(counts, id: \.tone) { item in
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: item.tone.icon)
                            .font(.system(size: 11))
                        Text("\(item.count) \(item.tone.label.uppercased())")
                            .font(DSType.display(11, .heavy))
                            .tracking(0.5)
                    }
                    .foregroundStyle(toneColor(item.tone))
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Capsule().fill(toneColor(item.tone).opacity(0.12)))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func summaryQuotes(result: PressConferenceResult) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("YOUR KEY QUOTES")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            ForEach(result.selectedResponses) { response in
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("\u{201C}\(response.responseText)\u{201D}")
                        .font(DSType.text(14, .regular, prose: true))
                        .italic()
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(response.mediaReaction)
                        .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .fill(Color.backgroundTertiary.opacity(0.5))
                )
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// #161 D: the bar, in the coach's own words, next to the line that set it.
    /// Nothing vague — the season either clears it or the quote comes back.
    private func summaryPromises(result: PressConferenceResult) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("PROMISES TRACKED")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.warning)

            HStack(alignment: .top, spacing: DSSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.warning)
                Text("These are settled in the season review. Deliver and the quote holds up; fall short and it runs next to the final standings.")
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(result.promises) { promise in
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(alignment: .top, spacing: DSSpacing.xs) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentGold)
                        Text("\u{201C}\(promise.statement)\u{201D}")
                            .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                            .italic()
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(promise.kind.shortLabel.uppercased()) \u{00B7} \(promise.kind.thresholdCopy)")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.warning)
                        .padding(.leading, DSSpacing.lg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.warning.opacity(0.3), lineWidth: 1)
                )
        )
    }

    /// The action bar's explainer on the summary — the cost line §2.5 asks every
    /// commit to carry, in the caller's own words.
    private func summaryCostLine(result: PressConferenceResult) -> String {
        let effects = result.totalEffects
        let owner = effects.ownerSatisfaction
        let legacy = effects.legacyPoints
        let ownerPart = owner == 0
            ? "left the owner where he was"
            : "moved the owner **\(owner > 0 ? "+" : "")\(owner)**"
        let legacyPart = legacy == 0
            ? "no legacy points"
            : "**\(legacy > 0 ? "+" : "")\(legacy)** legacy"
        let promisePart = result.promises.isEmpty
            ? "no promises on the ledger"
            : "**\(result.promises.count)** promise\(result.promises.count == 1 ? "" : "s") on the ledger"
        return "\(result.selectedResponses.count) answers \u{00B7} \(ownerPart) \u{00B7} \(legacyPart) \u{00B7} \(promisePart)."
    }

    // MARK: - Actions

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        switch session {
        case .introductory:
            // Use the real owner if available; otherwise a neutral placeholder,
            // so the presser is never empty if the relationship has not loaded.
            let effectiveOwner = owner ?? Owner(name: "The Owner")
            if let team {
                questions = PressConferenceEngine.generateIntroConference(
                    team: team,
                    owner: effectiveOwner,
                    career: career
                )
                // #161: the intro presser has no season history — no last game,
                // no record, no streak — so its context is the simplified one.
                // It is the SAME engine path as the weekly presser, which is the
                // whole point: whatever the matrix says here, it says in week 9.
                context = PressConferenceEngine.introContext(
                    career: career,
                    team: team,
                    owner: owner,
                    roster: roster
                )
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.3)) { showPodium = true }

        case .postGame:
            animateQuestion()
        }
    }

    private func beginQuestioning() {
        withAnimation(.easeInOut(duration: 0.4)) { phase = .questioning }
        animateQuestion()
    }

    /// Reveals the prompt, then the cards — and asks for the scroll from the
    /// *card* animation's completion, so the new question is on screen with a
    /// settled frame rather than at a guessed instant (#166).
    private func animateQuestion() {
        showReporter = false
        showResponses = false
        showReaction = false
        pendingResponseIndex = nil
        selectedResponseIndex = nil
        revealedEffects = nil
        headlinePreviewIndex = nil

        withAnimation(.easeOut(duration: 0.4).delay(0.15)) { showReporter = true }
        withAnimation(
            .easeOut(duration: 0.4).delay(0.35),
            completionCriteria: .logicallyComplete
        ) {
            showResponses = true
        } completion: {
            // Only on a *new* question. On the first one the standing strip
            // above the prompt is the context the player is meant to read
            // before he answers anything, and scrolling it away on entry would
            // be a different bug of the same family as #166.
            if currentQuestionIndex > 0 { requestScroll(to: .prompt) }
        }
    }

    /// P5 step 1 — reversible. Tapping a different card just moves the pick.
    private func pickResponse(index: Int) {
        guard selectedResponseIndex == nil,
              currentQuestionIndex < questions.count,
              index < questions[currentQuestionIndex].responses.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingResponseIndex = index
        }
    }

    /// P5 step 2 — irreversible, and the only place this screen commits.
    private func commitPendingResponse() {
        guard selectedResponseIndex == nil,
              let index = pendingResponseIndex,
              currentQuestionIndex < questions.count else { return }

        let question = questions[currentQuestionIndex]
        guard index < question.responses.count else { return }

        let response = question.responses[index]
        // Resolved in the context this question was ASKED in — before this
        // answer's own tone joins the ledger.
        revealedEffects = PressConferenceEngine.resolvedEffects(
            for: response, question: question, context: liveContext
        )
        reactionText = response.mediaReaction

        withAnimation(.easeInOut(duration: 0.25)) {
            selectedResponseIndex = index
        }
        selectedIndices.append(index)

        // #166: the reveal's own insertion tells us when it has landed.
        withAnimation(
            .easeOut(duration: 0.4).delay(0.25),
            completionCriteria: .logicallyComplete
        ) {
            showReaction = true
        } completion: {
            requestScroll(to: .reveal)
        }
    }

    private func advanceAfterAnswer() {
        guard selectedResponseIndex != nil else { return }
        if currentQuestionIndex + 1 < questions.count {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentQuestionIndex += 1
            }
            animateQuestion()
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                phase = .summary
            }
        }
    }

    private func finishConference() {
        let result = PressConferenceEngine.buildResult(
            questions: questions,
            selectedIndices: selectedIndices,
            context: context
        )
        onComplete(result)
    }

    /// #166: one request funnel. The nonce is why the same anchor can be asked
    /// for again on the next question — `onChange` on the anchor alone would
    /// fire once and then never again.
    private func requestScroll(to anchor: Anchor) {
        scrollTarget = anchor
        scrollNonce &+= 1
    }

    // MARK: - Palettes
    //
    // Categorical hues, not a rating ladder: nothing here maps a 0–100 number to
    // a colour, so `Color.forGrade` is not the right instrument. One copy now,
    // where there used to be two.

    private func stanceColor(_ stance: PressConferenceEngine.ReporterStance) -> Color {
        switch stance {
        case .friendly: return Color.success
        case .neutral:  return Color.textSecondary
        case .hostile:  return Color.dangerText
        }
    }

    private func feedbackColor(_ severity: PressConferenceEngine.SessionFeedback.Severity) -> Color {
        switch severity {
        case .good:    return Color.success
        case .warning: return Color.warning
        case .bad:     return Color.dangerText
        case .neutral: return Color.textSecondary
        }
    }

    private func toneColor(_ tone: ResponseTone) -> Color {
        switch tone {
        case .confident:  return Color.accentGold
        case .humble:     return Color.accentBlue
        case .aggressive: return Color.danger
        case .diplomatic: return Color.success
        case .funny:      return Color.warning
        }
    }

    private func mediaPerceptionLabel(for tone: ResponseTone) -> String {
        switch tone {
        case .confident:  return "The media sees a bold, confident leader"
        case .humble:     return "The media sees a measured, thoughtful builder"
        case .aggressive: return "The media sees a controversial firebrand"
        case .diplomatic: return "The media sees a steady, professional operator"
        case .funny:      return "The media sees a charismatic fan favorite"
        }
    }
}

// MARK: - Preview

#Preview("Introductory") {
    PressConferenceView(
        career: Career(
            playerName: "Mike Johnson",
            avatarID: "avatar_00000",
            role: .gmAndHeadCoach,
            capMode: .simple
        ),
        team: Team(
            name: "Stockyards",
            city: "Kansas City",
            abbreviation: "KC",
            conference: .AFC,
            division: .west,
            mediaMarket: .large,
            owner: Owner(name: "Merrill Ashford")
        ),
        owner: Owner(name: "Merrill Ashford"),
        onComplete: { _ in }
    )
}
