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
//
// ## Wave 6 — the three findings the surgical pass could not take
//
// Three things were raised against this screen and then deliberately skipped as
// "too big for a surgical fix". They were one thing.
//
//  1. **"BEFORE THIS SESSION" was frozen under all five questions.** It was
//     honest — nothing is written until `onComplete` fires — and it was dead. It
//     printed three career numbers that cannot move, while the card immediately
//     beneath it printed the session's deltas with no baseline to hang them on:
//     two cards, each holding one half of a sentence. They are `roomLedgerCard`
//     now, one card in two states, and the baseline is not lost — it moves into
//     the `72% → 76%`.
//  2. **A band of empty navy under the last answer card.** The screen resolves
//     every hint chip against a context the engine assembles before the first
//     question — the situation, where the roster actually is, the mood in the
//     building, the owner's known persona — and named none of it anywhere on
//     the surface. `roomReadCard` fills the band with exactly that: the only
//     answer this screen has ever had to "why does this card say they'll
//     pounce". It reads the axes off `PressContext`, so an axis the engine
//     grows later is a row added here, not a rewrite.
//  3. **The bottom of the summary was empty.** `DSLayout.wideMeasure`'s own doc
//     names "the press-conference transcript" as one of the three things the
//     900 pt column exists for, and the app did not have one. It had a quote
//     list with the question and the price both dropped, and between questions
//     it had nothing: the reveal printed an answer's real cost once and then
//     destroyed it when the coach moved on. `transcriptCard` is that
//     transcript, at two densities.
//
// Nothing in `PressConferenceEngine` moved. Every number is still read out of
// the same four calls, and the two new readings — the live projection and the
// tone ledger — are the engine's own `rosterMoraleDelta`, `fanSupportDelta`,
// `repetitionCount` and `repetitionScale`, printed rather than recomputed.

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

    /// One answer already on the record: who asked, what he said, and what that
    /// line actually cost in the context it was said in.
    private struct SessionEntry: Identifiable {
        let id: UUID
        /// 1-based, so the transcript and the slat band count the same way.
        let number: Int
        let question: PressQuestion
        let response: PressResponse
        let effects: PressEffects
    }

    /// Every answer already given, resolved ONCE.
    ///
    /// The running totals, the live projection and the transcript all read this
    /// one list, so none of them can book a different number than another — and
    /// the fold is the same one `PressConferenceEngine.buildResult` runs when
    /// the result is finally written, so the screen cannot disagree with the
    /// save either. Five entries at most, and it is the only place
    /// `resolvedEffects` is called for an answer that is already on the record.
    private var sessionLedger: [SessionEntry] {
        var entries: [SessionEntry] = []
        var live = context
        for (qIdx, respIdx) in selectedIndices.enumerated() {
            guard qIdx < questions.count,
                  respIdx < questions[qIdx].responses.count else { continue }
            let question = questions[qIdx]
            let response = question.responses[respIdx]
            entries.append(SessionEntry(
                id: response.id,
                number: qIdx + 1,
                question: question,
                response: response,
                effects: PressConferenceEngine.resolvedEffects(
                    for: response, question: question, context: live
                )
            ))
            live = live.appending(tone: response.tone)
        }
        return entries
    }

    /// Live deltas accumulated from the answers already on the record.
    private var runningTotals: PressEffects {
        sessionLedger.reduce(PressEffects()) { $0 + $1.effects }
    }

    /// The answers from questions the coach has already walked away from.
    ///
    /// Deliberately NOT the whole ledger: the moment an answer is committed its
    /// reveal is on screen with the same pills on it, so a receipt that included
    /// the live question would print the current answer's cost twice, a hand's
    /// width apart. The receipt is for the ones whose reveal has gone.
    private var priorAnswers: [SessionEntry] {
        sessionLedger.filter { $0.number <= currentQuestionIndex }
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
            // under it. `.hero` and not `.large`: this face IS the screen's
            // subject, and at detail-header size the plate floated in the middle
            // of a portrait iPad with nothing above or below it.
            UserPortraitView(career: career, size: .hero)
                .shadow(color: Color.black.opacity(0.5), radius: 10, y: 4)
                .overlay(alignment: .bottom) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: DSType.Size.title2))
                        .foregroundStyle(Color.accentGold)
                        .shadow(color: Color.accentGold.opacity(0.4), radius: 10)
                        .shadow(color: Color.black.opacity(0.55), radius: 4, y: 2)
                        .offset(y: 12)
                }

            Text(career.playerName)
                .font(DSType.text(DSType.Size.callout, .bold))
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
                .font(DSType.text(DSType.Size.callout, .regular, prose: true))
                .foregroundStyle(Color.textPrimary.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xl)
                .fixedSize(horizontal: false, vertical: true)

            // Where he stands before he says anything — the same card the
            // questioning phase carries, so the podium is a reading of the room
            // rather than a title card with a button under it.
            roomLedgerCard

            // And WHICH room it is. On the podium this is the whole brief: the
            // coach is about to pick a note for a building, a roster and an
            // owner he inherited ten minutes ago, and all three are already
            // inputs to the first answer he gives.
            roomReadCard

            // The same band the questioning phase runs on, drawn ahead of the
            // first question so the shape of the session is known before it
            // starts. Every slat is `.future`; nothing is current yet.
            if !questions.isEmpty {
                DSSlatBand(
                    slats: questionSlats(previewOnly: true),
                    headline: "\(questions.count) questions",
                    meter: DSResourceMeter(spent: 0, total: questions.count, unit: "questions")
                )
                .frame(maxWidth: DSLayout.wideMeasure)
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
                    // `DSResourceMeter` counts the unit *in progress* as spent —
                    // that is what makes the brightest pip the live one. Counting
                    // answers instead left the meter a question behind the
                    // headline beside it, with no pip on the question being asked.
                    spent: min(currentQuestionIndex + 1, max(questions.count, 1)),
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
                        roomLedgerCard

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

                        // The band under the answers, which used to be most of a
                        // portrait iPad's worth of empty navy. Reference material
                        // is what belongs there: the room read is what the hint
                        // chips above it are computed from, and the receipt is
                        // what every earlier answer actually cost — numbers the
                        // reveal printed once and then threw away the moment the
                        // coach tapped Next question.
                        //
                        // It also finishes #166. `scrollTo(prompt, anchor: .top)`
                        // can only pull the prompt to the top of the viewport if
                        // there is a viewport's worth of content BELOW it; with
                        // three short answer cards and nothing after them the
                        // scroll ran against a content height that had no room
                        // left to give, and the prompt stayed where it was.
                        roomReadCard

                        if !priorAnswers.isEmpty {
                            transcriptCard(entries: priorAnswers, detail: .receipt)
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

            // On the podium every slat carries its reporter and stance: the rail
            // is the only thing that says who is in the room, and the player is
            // about to decide how to talk to them. That has to hold for the
            // questions still to come, too — the stance is an engine input, so a
            // hostile writer waiting at question 3 is the whole reason to hold a
            // tone back at question 1. A future slat carries the stance alone
            // because it is a fraction of the current slat's width and the
            // caption is one 11 pt line: a full reporter name truncates there.
            let subcaption: String?
            switch state {
            case .done:
                subcaption = nil
            case .current:
                subcaption = "\(question.reporterName) \u{00B7} \(stance.label.lowercased())"
            default:
                subcaption = previewOnly
                    ? "\(question.reporterName) \u{00B7} \(stance.label.lowercased())"
                    : stance.label.lowercased()
            }

            return DSSlat(
                id: question.id.uuidString,
                index: "\(index + 1)",
                title: question.outlet,
                subcaption: subcaption,
                state: state,
                // Prefixed, because a done slat and a live one print their second
                // line in the same slot and the two vocabularies collide there:
                // bare "Humble" is the tone he answered in, "neutral" is the
                // reporter's stance.
                outcome: answeredTone.map { "Said \($0.label.lowercased())" },
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

    // MARK: The room ledger — one card, two states
    //
    // "BEFORE THIS SESSION" was a true label on a dead card. The three numbers
    // under it cannot move until `onComplete` fires, so it read identically
    // beneath all five questions, while the card directly below it printed the
    // session's deltas with no baseline to hang them on. Two cards, each holding
    // one half of a sentence, and the half that answered "so where does that
    // leave me" was in neither of them.
    //
    // One card now. Before a word is said it is the reading of the room it
    // always was, widened from three tiles to the five meters the legend under
    // it already promised to explain — the locker room and the city were being
    // described there and shown nowhere. From the first committed answer it
    // becomes the projection: the delta, and where the meter that delta feeds
    // actually lands. The baseline is not lost; it moves into the `72% → 76%`.
    //
    // What it deliberately does NOT project is the PENDING pick. This screen is
    // built on #161's fog rule — direction before the answer, arithmetic after —
    // and a card that showed the owner landing on 76% while the coach was still
    // choosing would hand back the spreadsheet the fog took away.

    private var roomLedgerCard: some View {
        let hasSpoken = !selectedIndices.isEmpty
        let totals = runningTotals

        return VStack(spacing: DSSpacing.xs) {
            Text(hasSpoken ? "WHERE YOU STAND NOW" : "BEFORE THIS SESSION")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasSpoken {
                meterLedgerGrid(cells: meterCells(for: totals))
                sessionVerdict(totals: totals)
            } else {
                baselineTiles
            }

            // #119: what each of those actually does, in the card's own column
            // order. It stays on BOTH states — these five words are defined
            // nowhere else on the screen, and the state that would drop them is
            // the one where the player has started spending them.
            Text("Owner affects job security \u{00B7} Morale is the locker room's read \u{00B7} Fans are the city's \u{00B7} Media shapes the narrative \u{00B7} Legacy affects career rating")
                .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    /// The five meters before a word is said. Five, not the three the strip
    /// printed: the legend under it already named the locker room and the city,
    /// the session moves both, and the summary reports both — so the only card
    /// that never showed them was the one the player reads first.
    ///
    /// Column order matches `meterLedgerGrid` exactly. The two states are one
    /// card; if Owner sat third here and first there, the card would reshuffle
    /// itself the moment the first answer landed.
    private var baselineTiles: some View {
        HStack(spacing: 0) {
            // #117: the owner's satisfaction, not his "Comp" — and labelled
            // OWNER, because the legend under it, the ledger grid and every hint
            // chip on this screen call that audience the owner.
            if let owner {
                standingItem(
                    icon: "building.2.fill",
                    label: "Owner",
                    value: "\(owner.satisfaction)%",
                    caption: nil,
                    color: Color.forRating(owner.satisfaction, scale: .percent)
                )
            }
            // The band, not an average. `Player.morale` is a per-man stat and
            // the engine reads the roster as one of three bands; printing a mean
            // here would invent a meter the sim does not keep.
            standingItem(
                icon: "person.3.fill",
                label: "Morale",
                value: context.lockerRoom.label,
                caption: nil,
                color: lockerRoomColor(context.lockerRoom)
            )
            standingItem(
                icon: "hands.clap.fill",
                label: "Fans",
                value: "\(career.fanSupport)%",
                caption: nil,
                color: Color.forRating(career.fanSupport, scale: .percent)
            )
            standingItem(
                icon: "newspaper.fill",
                label: "Media",
                value: "\(career.legacy.mediaReputation)",
                caption: career.legacy.reputationLabel,
                color: career.legacy.mediaReputation >= 0 ? Color.success : Color.dangerText
            )
            standingItem(
                icon: "star.fill",
                label: "Legacy",
                value: "\(career.legacy.totalPoints)",
                caption: nil,
                color: Color.accentGold
            )
        }
    }

    private func standingItem(
        icon: String,
        label: String,
        value: String,
        caption: String?,
        color: Color
    ) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.footnote))
                .foregroundStyle(color)
            Text(value)
                .font(DSType.display(DSType.Size.title3, .heavy))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(DSType.display(DSType.Size.caption, .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiaryReadable)
            // Reserved on every tile, exactly as the grid reserves its context
            // row: a caption on one tile of five would leave that tile a line
            // taller than its four neighbours and break the row's baseline.
            Text(caption ?? " ")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(color.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            caption.map { "\(label): \(value), \($0)" } ?? "\(label): \(value)"
        )
    }

    // MARK: The five-meter ledger
    //
    // ONE cell list and ONE grid, read by the card between questions and by the
    // summary. The running strip used to print five bare deltas and the summary
    // printed five projections of the same numbers: a player who wanted to know
    // where his owner would actually end up had to finish the session to find
    // out, and the two readings were free to drift apart in the meantime.

    /// One audience's line: what the session did to it, and where the meter that
    /// delta feeds ends up.
    private struct MeterCell: Identifiable {
        var id: String { label }
        let label: String
        let icon: String
        let value: Int
        /// `before \u{2192} after` for the meter this axis actually moves, or the
        /// sentence that stands in for it where that meter is not one number.
        let context: String?
    }

    private func meterCells(for effects: PressEffects) -> [MeterCell] {
        [
            MeterCell(
                label: "Owner",
                icon: "building.2.fill",
                value: effects.ownerSatisfaction,
                context: owner.map { base in
                    "\(base.satisfaction)% \u{2192} \(min(100, max(0, base.satisfaction + effects.ownerSatisfaction)))%"
                }
            ),
            // Both of these used to carry NO context line, for the honest reason
            // that neither number was written anywhere: the podium's two biggest
            // meters were painted and dropped. They land now, scaled by the
            // engine (a session sums four ±20 answers; `Player.morale` is a
            // 0…100 stat the sim reads), and the context line states the value
            // that actually lands rather than the headline the user cannot act
            // on.
            MeterCell(
                label: "Morale",
                icon: "person.3.fill",
                value: effects.playerMorale,
                context: { () -> String in
                    let delta = PressConferenceEngine.rosterMoraleDelta(for: effects)
                    if delta == 0 { return "room unmoved" }
                    return "every man \(delta > 0 ? "+" : "")\(delta)"
                }()
            ),
            MeterCell(
                label: "Fans",
                icon: "hands.clap.fill",
                value: effects.fanExcitement,
                context: { () -> String in
                    let delta = PressConferenceEngine.fanSupportDelta(for: effects)
                    if delta == 0 { return "city unmoved" }
                    return "\(career.fanSupport)% \u{2192} \(max(0, min(100, career.fanSupport + delta)))%"
                }()
            ),
            // Media was the one meter the running strip tracked and the summary
            // card dropped — usually the largest delta of the session, and the
            // one the summary headline is derived from.
            MeterCell(
                label: "Media",
                icon: "newspaper.fill",
                value: effects.mediaPerception,
                context: "\(career.legacy.mediaReputation) \u{2192} \(max(-100, min(100, career.legacy.mediaReputation + effects.mediaPerception)))"
            ),
            MeterCell(
                label: "Legacy",
                icon: "star.fill",
                value: effects.legacyPoints,
                context: "\(career.legacy.totalPoints) \u{2192} \(career.legacy.totalPoints + effects.legacyPoints)"
            )
        ]
    }

    /// Laid out as a `Grid` for the same reason `DSResultSheet` is — an `HStack`
    /// of stacks drops a numeral the moment one column grows a line.
    private func meterLedgerGrid(cells: [MeterCell]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: DSSpacing.lg, verticalSpacing: DSSpacing.xxs) {
            GridRow {
                ForEach(cells) { cell in
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: cell.icon)
                            .font(.system(size: DSType.Size.micro))
                        Text(cell.label.uppercased())
                            .font(DSType.display(DSType.Size.caption, .heavy))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color.textTertiaryReadable)
                    .lineLimit(1)
                }
            }
            GridRow {
                ForEach(cells) { cell in
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
                ForEach(cells) { cell in
                    // The row always reserves its context line so cells with and
                    // without a baseline sit at one height (§2.2).
                    Text(cell.context ?? " ")
                        .font(DSType.display(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    /// The engine's running verdict on the session so far. The thresholds that
    /// decide "Owner growing impatient" are its; the view paints the severity's
    /// colour and owns nothing else.
    private func sessionVerdict(totals: PressEffects) -> some View {
        let feedback = PressConferenceEngine.sessionFeedback(for: totals)
        let color = feedbackColor(feedback.severity)

        return HStack(spacing: DSSpacing.xxs) {
            Image(systemName: feedback.icon)
                .font(.system(size: DSType.Size.caption, weight: .bold))
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

    // MARK: The room read
    //
    // Every hint chip on this screen is resolved against a context the engine
    // assembles before the first question is asked — the situation, where the
    // roster actually is, the mood in the building, the owner's known persona —
    // and until this wave not one of those was named anywhere on the surface. A
    // capsule that reads "they'll pounce" with no stated reason is a dice roll;
    // the same capsule under "the year is coming apart, and this room wants a
    // position" is a read the player can act on.
    //
    // One row per axis, so an axis the engine grows later is a row added here.
    // All of them are fog-legal by #161's own rule, each for its own reason: the
    // coach knows his owner's persona from the hiring meeting, he is in the
    // building every day, he knows which of the three rosters he runs, and he
    // watched Sunday's game. Nothing here is a number the fog is protecting —
    // no per-audience delta, no per-tone table, no magnitudes. Every line is a
    // qualitative statement of a rule that is already running, taken from the
    // matrix's own doc comments, so it cannot advertise arithmetic the engine is
    // not doing.

    private var roomReadCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("READ THE ROOM")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            roomReadRow(
                icon: "mic.fill",
                axis: "The room",
                value: situationLabel(context.situation),
                read: situationRead(context.situation)
            )
            roomReadRow(
                icon: "sportscourt.fill",
                axis: "The roster",
                value: context.standing.label,
                read: standingRead(context.standing)
            )
            roomReadRow(
                icon: "person.3.fill",
                axis: "The building",
                value: context.lockerRoom.label,
                read: lockerRoomRead(context.lockerRoom)
            )
            roomReadRow(
                icon: "building.2.fill",
                axis: "The owner",
                value: ownerPersonaLabel,
                read: ownerRead
            )

            Divider().overlay(Color.surfaceBorder)

            toneLedgerStrip
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func roomReadRow(
        icon: String,
        axis: String,
        value: String,
        read: String
    ) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.callout))
                .foregroundStyle(Color.accentGold.opacity(0.8))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xs) {
                    Text(axis.uppercased())
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.textTertiaryReadable)
                    Text(value)
                        .font(DSType.display(DSType.Size.footnote, .heavy))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(read)
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(axis): \(value). \(read)")
    }

    // MARK: The room read — copy
    //
    // One sentence per band, and each one is a restatement of a cell that is
    // actually in `PressConferenceEngine`. Where a line names a tone it names
    // the tone that cell singles out, never a magnitude.

    private func situationLabel(_ situation: PressConferenceEngine.PressSituation) -> String {
        switch situation {
        case .introduction: return "Day one"
        case .afterWin:     return "After a win"
        case .afterBadLoss: return "After a beating"
        case .crisis:       return "The year is coming apart"
        case .highStakes:   return "The stakes are real"
        case .routine:      return "A quiet week"
        }
    }

    private func situationRead(_ situation: PressConferenceEngine.PressSituation) -> String {
        switch situation {
        case .introduction:
            return "Nobody has a read on you yet. The one thing this room will not forgive is being boring."
        case .afterWin:
            return "The room is generous. Souring the win is the only reliable way to lose it."
        case .afterBadLoss:
            return "Sunny reads delusional and funny reads tone-deaf. Owning it is the answer that gains on every axis."
        case .crisis:
            return "They want a position, not a posture — and dodging costs double in a room like this one."
        case .highStakes:
            return "Belief plays here. Modesty reads as a coach who does not fancy it."
        case .routine:
            return "Nothing is burning, so nothing moves far — and neither the crowd nor the press has a mood you can read."
        }
    }

    private func standingRead(_ standing: PressConferenceEngine.TeamStanding) -> String {
        switch standing {
        case .rebuilding:
            return "A title claim here costs you with the owner: he hears an expectation he did not set and cannot meet."
        case .middling:
            return "Nothing about this roster pushes an answer either way. The room is judging the words alone."
        case .contender:
            return "Humility on a roster this good reads as a coach who does not believe in it."
        }
    }

    private func lockerRoomRead(_ band: PressConferenceEngine.LockerRoomBand) -> String {
        switch band {
        case .fragile:
            return "They are listening for whether you protect them. A public whipping lands twice as hard in here."
        case .steady:
            return "The room can take whatever you say about it, either way."
        case .buoyant:
            return "They can absorb a whipping, and confidence is cheap to hand them."
        }
    }

    private var ownerPersonaLabel: String {
        let stance = context.ownerPrefersWinNow ? "Wants to win now" : "Backing a build"
        return "\(stance) \u{00B7} patience \(context.ownerPatience)/10"
    }

    private var ownerRead: String {
        // The persona adjustment is deliberately SKIPPED on the intro presser:
        // those four questions branch their authored effects on `prefersWinNow`
        // themselves, and the engine refuses to count him twice. The read has to
        // follow that split, or it would describe a rule that is not running.
        if context.situation == .introduction {
            return context.ownerPrefersWinNow
                ? "He wants it now. Ambition buys him; talk of tearing it down does not."
                : "He is backing a build. A title promise is a bill he never agreed to."
        }
        if context.ownerPrefersWinNow {
            return "He rewards certainty, and hears humility as the lack of it."
        }
        return context.ownerPatience <= 3
            ? "He is backing the plan, but thin-skinned — a promise you have not earned stings him hardest."
            : "He is backing the plan. Humility buys credit with him; heat costs it."
    }

    // MARK: The tone ledger
    //
    // The repetition ratchet is the one piece of engine state that quietly eats
    // the player's payoff, and the only trace of it on the surface was a chip
    // that appeared on a card AFTER the decay had already started. Counted here
    // the way the ratchet counts — `repetitionCount` over its own window, off
    // `liveContext`, so an answer given a minute ago is in the total on the very
    // next question rather than at the end of the session.

    /// `ResponseTone` is not `CaseIterable` — it is a Codable content enum in
    /// the engine, and adding a case list there is an engine change this wave is
    /// not allowed to make — so the ledger fixes its own reading order.
    private static let toneOrder: [ResponseTone] = [
        .confident, .humble, .aggressive, .diplomatic, .funny
    ]

    private var toneLedgerStrip: some View {
        let recent = liveContext.recentTones
        let counted = Self.toneOrder
            .map { tone in
                (tone: tone, count: PressConferenceEngine.repetitionCount(tone: tone, recentTones: recent))
            }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("WHAT THEY HAVE HEARD FROM YOU")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textTertiaryReadable)

            if counted.isEmpty {
                Text("Nothing yet. Whatever note you open on is the one the room starts counting.")
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(counted, id: \.tone) { item in
                        toneCountChip(tone: item.tone, count: item.count)
                    }
                    Spacer(minLength: 0)
                }

                Text(ratchetLine(counted: counted))
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toneCountChip(tone: ResponseTone, count: Int) -> some View {
        let isTaxed = PressConferenceEngine.repetitionScale(
            tone: tone, recentTones: liveContext.recentTones
        ) < 1.0
        // `alertOrange` is the vanilla chip's colour on the answer cards, and a
        // taxed note here is the same fact one question earlier.
        let tint = isTaxed ? Color.alertOrange : toneColor(tone)

        return HStack(spacing: DSSpacing.xxs) {
            Image(systemName: tone.icon)
                .font(.system(size: DSType.Size.caption))
            Text(tone.label.uppercased())
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.5)
            Text("\(count)")
                .font(DSType.display(DSType.Size.footnote, .heavy))
            if isTaxed {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: DSType.Size.micro, weight: .bold))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
                .overlay(Capsule().strokeBorder(tint.opacity(isTaxed ? 0.45 : 0.28), lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(tone.label), \(count) of the last \(PressConferenceEngine.toneRepetitionWindow) answers"
                + (isTaxed ? ", already losing value" : "")
        )
    }

    /// What the ratchet is doing right now, in the order it happens: the press
    /// coins a name for the note first (`isVanilla`), and only the decay that is
    /// already running (`repetitionScale`) if it has not.
    private func ratchetLine(counted: [(tone: ResponseTone, count: Int)]) -> String {
        let recent = liveContext.recentTones
        let window = PressConferenceEngine.toneRepetitionWindow

        if let named = counted.first(where: {
            PressConferenceEngine.isVanilla(tone: $0.tone, recentTones: recent)
        }) {
            return "\u{201C}\(PressConferenceEngine.vanillaLabel(for: named.tone))\u{201D} \u{2014} the press has a name for it now, and a \(named.tone.label.lowercased()) answer is worth a fraction of what it was."
        }
        if let taxed = counted.first(where: {
            PressConferenceEngine.repetitionScale(tone: $0.tone, recentTones: recent) < 1.0
        }) {
            return "\(taxed.tone.label) has come up \(taxed.count) times in the last \(window). The room is already discounting it; one more and most of the payoff goes."
        }
        return "No note repeated often enough to go stale. The room starts discounting one it has heard three times in \(window)."
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
                        .font(DSType.text(DSType.Size.body, .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(question.outlet.uppercased())
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.accentGold)
                }

                Spacer(minLength: DSSpacing.xs)

                HStack(spacing: DSSpacing.xxs) {
                    Circle()
                        .fill(stanceColor)
                        .frame(width: 6, height: 6)
                    Text(stance.label.uppercased())
                        .font(DSType.display(DSType.Size.caption, .heavy))
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
                .font(DSType.text(DSType.Size.title3, .semibold, prose: true))
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
                            .font(.system(size: DSType.Size.caption, weight: .bold))
                        Text(response.tone.label.uppercased())
                            .font(DSType.display(DSType.Size.caption, .heavy))
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
                    .font(DSType.text(DSType.Size.callout, .medium, prose: true))
                    .foregroundStyle(isDisabled ? Color.textSecondary : Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // #161 B: fogged reaction hints — direction, never numbers.
                hintRow(preview)

                // Only while the answer is still a choice. After the commit the
                // reveal below prints the same `mediaReaction` verbatim, so the
                // card he picked was offering to "preview" a headline that had
                // already run and was quoted an inch beneath it — and the two
                // cards he did not pick kept a full capsule control that could
                // not be opened.
                if selectedResponseIndex == nil {
                    headlinePreviewSection(
                        response: response,
                        index: index,
                        isExpanded: isHeadlineExpanded
                    )
                }
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
            // One dim, not two multiplied. The quote's own colour is already a
            // step down; a 0.4 card opacity on top of it composited the label to
            // ~1.8 : 1 on the backdrop, and the answers he did NOT give are the
            // record he reads back. Measured at 0.8 with `textSecondary`: 4.6 : 1,
            // clear of the AA floor the palette commits to.
            .opacity(isDisabled ? 0.8 : 1.0)
        }
        .buttonStyle(.plain)
        // No `.disabled` on the card: SwiftUI propagates it to every descendant
        // and a child cannot re-enable itself. `pickResponse` already refuses
        // once an answer is committed, so the guard is the lock.
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
        // Five audiences do not always clear one line at this measure, and each
        // capsule is `lineLimit(1)` — so an overflow truncates a phrase rather
        // than wrapping it. Two rows are better than "they'll poun…".
        ViewThatFits(in: .horizontal) {
            hintLine(Array(preview.hints))
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                hintLine(Array(preview.hints.prefix(3)))
                hintLine(Array(preview.hints.dropFirst(3)))
            }
        }
    }

    private func hintLine(_ hints: [PressConferenceEngine.ReactionHint]) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(hints) { hint in
                let color = hintColor(hint.direction)
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: hint.audience.icon)
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textSecondary)
                    Text(hint.audience.label)
                        .font(DSType.text(DSType.Size.footnote, .medium))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: hint.direction.glyph)
                        .font(.system(size: DSType.Size.micro, weight: .bold))
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
                .font(.system(size: DSType.Size.micro, weight: .bold))
            Text(label.uppercased())
                .font(DSType.display(DSType.Size.caption, .heavy))
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
        isExpanded: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // A separate gesture so it does not trigger the card's selection.
            Button(action: { toggleHeadlinePreview(index: index) }) {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "newspaper")
                        .font(.system(size: DSType.Size.caption))
                    Text(isExpanded ? "Hide headline preview" : "Preview headline")
                        .font(DSType.display(DSType.Size.caption, .semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                }
                .foregroundStyle(Color.textTertiaryReadable)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    Capsule().strokeBorder(Color.textTertiary.opacity(0.35), lineWidth: 1)
                )
                // §2.12: 11 pt text on 4 pt padding is a 21 pt target, and this
                // is the only per-option control on the screen — it sits in a row
                // of hint chips the same height that cannot be tapped at all. The
                // capsule keeps its size; the hit area is padded out around it.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: DSType.Size.caption))
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
                    .font(.system(size: DSType.Size.callout))
                    .foregroundStyle(Color.accentGold)

                Text(reactionText)
                    .font(DSType.text(DSType.Size.body, .medium, prose: true))
                    .italic()
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let effects = revealedEffects {
                Divider().overlay(Color.accentGold.opacity(0.2))

                // "Cost" over a row of five green gains reads as five losses, or
                // as a broken label. The heading follows the signs the pills
                // paint from the same data.
                Text(hasCost(effects) ? "WHAT IT ACTUALLY COST" : "WHAT IT ACTUALLY MOVED")
                    .font(DSType.display(DSType.Size.caption, .heavy))
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

    /// Whether the answer actually charged anybody. The reveal heading and the
    /// commit bar both name the transaction, and neither may call a row of gains
    /// a cost.
    private func hasCost(_ effects: PressEffects) -> Bool {
        effects.ownerSatisfaction < 0
            || effects.playerMorale < 0
            || effects.fanExcitement < 0
            || effects.mediaPerception < 0
            || effects.legacyPoints < 0
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
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textSecondary)
            Text(label.uppercased())
                .font(DSType.display(DSType.Size.caption, .semibold))
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

    // MARK: - The transcript
    //
    // `DSLayout.wideMeasure`'s own doc names "the press-conference transcript"
    // as one of the three things the 900 pt column exists for, and until this
    // wave the app did not have one. What it had was a quote list on the summary
    // — the line he gave and the headline that ran, with the question that
    // provoked it and the price he paid for it both dropped — and, between
    // questions, nothing at all: `resultReveal` printed an answer's real cost
    // once and destroyed it the moment the coach tapped "Next question". The
    // learning loop the reveal exists to run was handing the player the receipt
    // and then taking it back.
    //
    // One component, two densities. Between questions it is a receipt: who
    // asked, what he said, what it cost. On the summary it is the record: the
    // question, the line, the headline that ran, and the price.

    private enum TranscriptDetail {
        /// Under the answer cards — a receipt, one line of question and two of
        /// quote, because the live question is what the player is here to read.
        case receipt
        /// On the summary — the whole record, nothing truncated.
        case record
    }

    private func transcriptCard(entries: [SessionEntry], detail: TranscriptDetail) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(detail == .receipt ? "ON THE RECORD SO FAR" : "THE TRANSCRIPT")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            ForEach(entries) { entry in
                transcriptEntry(entry, detail: detail)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func transcriptEntry(_ entry: SessionEntry, detail: TranscriptDetail) -> some View {
        let tint = toneColor(entry.response.tone)
        let isRecord = detail == .record

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Text("\(entry.number)")
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .foregroundStyle(Color.textTertiaryReadable)
                Text(entry.question.outlet.uppercased())
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.accentGold)
                    .lineLimit(1)

                Spacer(minLength: DSSpacing.xs)

                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: entry.response.tone.icon)
                        .font(.system(size: DSType.Size.caption, weight: .bold))
                    Text(entry.response.tone.label.uppercased())
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .tracking(0.5)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(Capsule().fill(tint.opacity(0.15)))
            }

            Text(entry.question.question)
                .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                .foregroundStyle(Color.textTertiaryReadable)
                .lineLimit(isRecord ? nil : 1)
                .fixedSize(horizontal: false, vertical: isRecord)

            Text("\u{201C}\(entry.response.text)\u{201D}")
                .font(DSType.text(isRecord ? DSType.Size.body : DSType.Size.footnote, .medium, prose: true))
                .italic()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(isRecord ? nil : 2)
                .fixedSize(horizontal: false, vertical: isRecord)

            if isRecord {
                Text(entry.response.mediaReaction)
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // A row of no pills is indistinguishable from a row the layout
            // failed to draw, and "nothing moved" is a real outcome on a fully
            // ratcheted answer — so it gets words rather than an empty line.
            if didMoveAnything(entry.effects) {
                effectPillRow(effects: entry.effects)
            } else {
                Text("Nothing in the room moved.")
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiaryReadable)
            }
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary.opacity(0.5))
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: DSCornerRadius.inline,
                        bottomLeadingRadius: DSCornerRadius.inline
                    )
                    .fill(tint.opacity(0.7))
                    .frame(width: 3)
                }
        )
        .accessibilityElement(children: .combine)
    }

    /// Whether an answer moved anything at all — the mirror of `hasCost`, which
    /// only ever asks about the negative half.
    private func didMoveAnything(_ effects: PressEffects) -> Bool {
        effects.ownerSatisfaction != 0
            || effects.playerMorale != 0
            || effects.fanExcitement != 0
            || effects.mediaPerception != 0
            || effects.legacyPoints != 0
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
            let didCost = revealedEffects.map(hasCost) ?? true
            return .init(
                title: "On the record",
                message: "That is what ran, and what it \(didCost ? "cost" : "moved"). It cannot be taken back."
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

        // The same ledger the questioning phase keeps its receipt from. The
        // transcript at the end of the session and the receipt under the answer
        // cards are one list, resolved once — and it is the list `buildResult`
        // folds, so the record and the save agree by construction.
        let ledger = sessionLedger

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    summaryHeadline(result: result)
                    summaryChanged(result: result)
                    if session == .introductory {
                        summaryFrontOffice(result: result)
                    }
                    summaryApproach(result: result)
                    if !ledger.isEmpty {
                        transcriptCard(entries: ledger, detail: .record)
                    }
                    if !result.promises.isEmpty {
                        summaryPromises(result: result)
                    }
                    Spacer(minLength: DSSpacing.sm)
                }
                .padding(DSSpacing.lg)
                .frame(maxWidth: DSLayout.wideMeasure, alignment: .leading)
                // Centred, like the podium and the questioning phase. The inner
                // frame keeps the cards left-aligned *within* the measure; the
                // outer one used to pin the measure itself to the left edge, so
                // the summary jumped sideways from the screen before it.
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            DSActionBar(
                explainer: .init(
                    title: hasCost(result.totalEffects) ? "What it cost" : "What it moved",
                    message: summaryCostLine(result: result)
                ),
                primary: .init(
                    title: "\(session.finishTitle) \u{2192}",
                    handler: finishConference
                )
            )
        }
    }

    /// The outcome headline, and where the media read actually lands.
    ///
    /// The reputation is projected here rather than read back, for the same
    /// reason `summaryFrontOffice` computes its identity: nothing is written
    /// until `onComplete` fires, which is after this screen is done. The clamp
    /// mirrors `LegacyTracker.applyPressConferenceResult` so the band this
    /// screen names is the band the save will hold a moment later.
    private func summaryHeadline(result: PressConferenceResult) -> some View {
        let media = result.totalEffects.mediaPerception
        var projected = career.legacy
        projected.mediaReputation = max(-100, min(100, projected.mediaReputation + media))

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text(session.ident.uppercased())
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.accentGold)
                    .lineLimit(1)
            }

            Text(mediaOutcomeHeadline(tone: result.dominantTone, media: media))
                .font(DSType.display(DSType.Size.title2, .heavy))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // #121: say what media perception actually affects.
            Text("That is how the room writes you up. It shapes free-agent interest, fan engagement and the tone of your coverage.")
                .font(DSType.text(DSType.Size.body, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Media reputation \(career.legacy.mediaReputation) \u{2192} \(projected.mediaReputation) \u{00B7} \(projected.reputationLabel)")
                .font(DSType.display(DSType.Size.footnote, .heavy))
                .foregroundStyle(
                    media > 0 ? Color.success : media < 0 ? Color.dangerText : Color.textTertiaryReadable
                )
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// F-56 — the other read the room takes away, and the only one the TRADE
    /// market cares about.
    ///
    /// The line above this card has said since #121 that the media read "shapes
    /// free-agent interest". This card is the half of that sentence the user
    /// could never see: the identity the other 31 front offices will price him
    /// against, which his coaching style seeded at team selection and which an
    /// emphatic answer at this podium has just overruled or left standing.
    ///
    /// It computes the read rather than reading the registry back, because
    /// `IntroSequenceView.applyPressConferenceResult` does not write it until
    /// `onComplete` fires — which is after this screen is done. Both sides call
    /// the same two functions, so they cannot disagree.
    ///
    /// The caveat underneath is not decoration. A declared identity that the
    /// user believes is permanent would be a free disguise, and it is not one:
    /// `TradeReputationRegistry` moves the league's read off this seed from the
    /// first executed deal onward.
    private func summaryFrontOffice(result: PressConferenceResult) -> some View {
        let identity = FranchiseIdentityDeclaration.podiumRead(for: result.dominantTone)
            ?? FranchiseIdentityDeclaration.seed(for: career.coachingStyle)
        let heldTheLine = FranchiseIdentityDeclaration.podiumRead(for: result.dominantTone) == nil

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("HOW THE LEAGUE WILL DEAL WITH YOU")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(FranchiseIdentityDeclaration.leagueReadHeadline(identity))
                    .font(DSType.display(DSType.Size.title3, .heavy))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(identity.declaration)
                    .font(DSType.text(DSType.Size.body, .regular, prose: true).italic())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                summaryFrontOfficeLedger(
                    icon: "plus.circle.fill",
                    tint: Color.success,
                    text: FranchiseIdentityDeclaration.buysLine(identity)
                )
                summaryFrontOfficeLedger(
                    icon: "minus.circle.fill",
                    tint: Color.dangerText,
                    text: FranchiseIdentityDeclaration.costsLine(identity)
                )

                // Not "that answer": `podiumRead` switches on the dominant tone
                // of the whole session, so the line that pointed at a single
                // answer sent the reader looking for a quote that is not marked
                // anywhere — and on a five-diplomatic session there were five.
                Text(heldTheLine
                     ? "Nothing you said at this podium changed that — it is the front office you described when you took the job."
                     : "The room heard one note more than any other — \(result.dominantTone.label.lowercased()) — and priced you on it. It is not what your staff file said when you were hired.")
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)

                Text(FranchiseIdentityDeclaration.priorCaveat)
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryFrontOfficeLedger(
        icon: String, tint: Color, text: String
    ) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.footnote, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(DSType.text(DSType.Size.footnote, .medium, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// #120 / #122: the deltas, with `baseline \u{2192} final` where a baseline
    /// exists.
    ///
    /// The cells and the grid are `meterCells` / `meterLedgerGrid` — the same
    /// two the live card between questions draws, which is the whole point: the
    /// reading the coach took after question three and the reading he takes at
    /// the end are one card with more answers folded into it.
    private func summaryChanged(result: PressConferenceResult) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("WHAT CHANGED")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            meterLedgerGrid(cells: meterCells(for: result.totalEffects))
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
        }
    }

    /// #123: the tone distribution — what kind of coach he sounded like, and
    /// what the room has now heard often enough to stop paying for.
    ///
    /// The chips count THIS session; the ratchet counts the career. "2
    /// DIPLOMATIC" can be the fourth diplomatic answer the room has heard, which
    /// is the point where the engine starts taking the payoff away — so the
    /// window it actually scores sits under them, in the same strip the room
    /// read carries between questions.
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
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(counts, id: \.tone) { item in
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: item.tone.icon)
                                .font(.system(size: DSType.Size.caption))
                            Text("\(item.count) \(item.tone.label.uppercased())")
                                .font(DSType.display(DSType.Size.caption, .heavy))
                                .tracking(0.5)
                        }
                        .foregroundStyle(toneColor(item.tone))
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, DSSpacing.xxs)
                        .background(Capsule().fill(toneColor(item.tone).opacity(0.12)))
                    }
                    Spacer(minLength: 0)
                }

                Divider().overlay(Color.surfaceBorder)

                toneLedgerStrip
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    /// #161 D: the bar, in the coach's own words, next to the line that set it.
    /// Nothing vague — the season either clears it or the quote comes back.
    private func summaryPromises(result: PressConferenceResult) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("PROMISES TRACKED")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.warning)

            HStack(alignment: .top, spacing: DSSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: DSType.Size.footnote))
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
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.accentGold)
                        Text("\u{201C}\(promise.statement)\u{201D}")
                            .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                            .italic()
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(promise.kind.shortLabel.uppercased()) \u{00B7} \(promise.kind.thresholdCopy)")
                        .font(DSType.display(DSType.Size.caption, .semibold))
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
        let media = effects.mediaPerception
        let legacy = effects.legacyPoints
        let ownerPart = owner == 0
            ? "left the owner where he was"
            : "moved the owner **\(owner > 0 ? "+" : "")\(owner)**"
        let mediaPart = media == 0
            ? "no movement in the press"
            : "**\(media > 0 ? "+" : "")\(media)** media"
        let legacyPart = legacy == 0
            ? "no legacy points"
            : "**\(legacy > 0 ? "+" : "")\(legacy)** legacy"
        let promisePart = result.promises.isEmpty
            ? "no promises on the ledger"
            : "**\(result.promises.count)** promise\(result.promises.count == 1 ? "" : "s") on the ledger"
        // The locker room and the city are named only when they moved — but they
        // ARE named. WHAT CHANGED shows all five meters, so a bar that lists
        // three of them can head "what it cost" over a session whose only cost
        // was the fans, and the two summaries on one screen then disagree.
        var parts = ["\(result.selectedResponses.count) answers", ownerPart, mediaPart]
        if effects.playerMorale != 0 {
            parts.append("**\(effects.playerMorale > 0 ? "+" : "")\(effects.playerMorale)** locker room")
        }
        if effects.fanExcitement != 0 {
            parts.append("**\(effects.fanExcitement > 0 ? "+" : "")\(effects.fanExcitement)** fans")
        }
        parts.append(legacyPart)
        parts.append(promisePart)
        return parts.joined(separator: " \u{00B7} ") + "."
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

    /// The locker-room band on the baseline tile. Buoyant/steady/fragile is a
    /// mood, not a rating ladder, so this is three categorical hues and not
    /// `Color.forRating` — but `warning` is the honest colour for fragile: it is
    /// the band where an aggressive answer costs the most.
    private func lockerRoomColor(_ band: PressConferenceEngine.LockerRoomBand) -> Color {
        switch band {
        case .buoyant: return Color.success
        case .steady:  return Color.textSecondary
        case .fragile: return Color.warning
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
        // NOT `warning`. #C9A94E and #EAB308 are one degree of hue apart, so the
        // CONFIDENT and FUNNY rails were the same yellow and two of the three
        // cards on a question could not be told apart by tint — which is the
        // only job the tint has. `alertOrange` is the palette's remaining
        // separable hue, and the two are 20° apart at very different saturation.
        case .funny:      return Color.alertOrange
        }
    }

    /// How he sounded — the tone he used, not the verdict it earned.
    ///
    /// This switch used to BE the outcome headline, which is how a session that
    /// booked Media -21 could open with "The media sees a steady, professional
    /// operator": the screen that reports the arithmetic was contradicting it.
    /// Tone is now the subject of the sentence and the media delta is the
    /// predicate, so the headline can never disagree with the ledger under it.
    private func toneReadLabel(for tone: ResponseTone) -> String {
        switch tone {
        case .confident:  return "You sounded bold and certain"
        case .humble:     return "You sounded measured and self-effacing"
        case .aggressive: return "You came out swinging"
        case .diplomatic: return "You kept every answer safe"
        case .funny:      return "You played the room for laughs"
        }
    }

    private func mediaOutcomeHeadline(tone: ResponseTone, media: Int) -> String {
        let verdict: String
        switch media {
        case 12...:      verdict = "and the room loved it"
        case 4..<12:     verdict = "and the room came away sold"
        case -3..<4:     verdict = "and the room found nothing to write"
        case -12 ..< -3: verdict = "and the room is not buying it"
        default:         verdict = "and the room has turned on you"
        }
        return "\(toneReadLabel(for: tone)) \u{2014} \(verdict)."
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
