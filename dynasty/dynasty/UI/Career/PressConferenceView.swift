import SwiftUI

// MARK: - Press Conference View

/// Full-screen immersive press conference where the player chooses responses
/// to reporter questions, with real consequences for legacy, morale, and media perception.
struct PressConferenceView: View {

    let career: Career
    let team: Team
    let owner: Owner?
    /// #161: the roster the new coach just inherited. Feeds the engine's
    /// `standing` and `lockerRoom` bands — the two context axes the fogged
    /// hints are read off. Empty is safe (both fall back to neutral bands).
    var roster: [Player] = []
    let onComplete: (PressConferenceResult) -> Void

    @State private var questions: [PressQuestion] = []
    @State private var currentQuestionIndex = 0
    @State private var selectedIndices: [Int] = []
    @State private var phase: Phase = .intro

    /// #161: the engine context, advanced one tone at a time as the coach
    /// answers. Everything on screen — hints, resolved deltas, the vanilla
    /// label — is computed from this and nothing else.
    @State private var context: PressConferenceEngine.PressContext = .neutral

    // Animation states
    @State private var showHeader = false
    @State private var showReporter = false
    @State private var showQuestion = false
    @State private var showResponses = false
    /// P5 step 1: the card the coach has picked but not yet said out loud.
    @State private var pendingResponseIndex: Int? = nil
    /// P5 step 2: the answer he committed to. `nil` until "Say it".
    @State private var selectedResponseIndex: Int? = nil
    @State private var showReaction = false
    @State private var reactionText = ""
    /// The real, context-resolved deltas of the committed answer — revealed
    /// only after the words have left his mouth.
    @State private var revealedEffects: PressEffects? = nil
    /// Index of the response whose headline preview is currently expanded.
    /// Tapping a response card's "preview headline" chevron toggles this.
    @State private var headlinePreviewIndex: Int? = nil

    private enum Phase {
        case intro
        case questioning
        case summary
    }

    // MARK: - Running totals (revealed answers only)

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

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Dimmed background image — slightly brighter than before so the
            // podium/microphone context still reads through the scrim (audit).
            GeometryReader { geo in
                Image("BgPressConference")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.32)
            }
            .ignoresSafeArea()

            // Directional vignette: darker top/bottom for text protection, a
            // lighter mid band where the podium sits so the venue keeps its
            // atmosphere without swallowing the focal area (audit).
            LinearGradient(
                stops: [
                    .init(color: Color.backgroundPrimary.opacity(0.80), location: 0.0),
                    .init(color: Color.backgroundPrimary.opacity(0.32), location: 0.38),
                    .init(color: Color.backgroundPrimary.opacity(0.36), location: 0.62),
                    .init(color: Color.backgroundPrimary.opacity(0.85), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Top safe-area scrim — keeps status bar text protected even if the
            // background asset ever brightens (audit).
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

            switch phase {
            case .intro:
                introContent
            case .questioning:
                questioningContent
            case .summary:
                summaryContent
            }
        }
        .onAppear { generateQuestions() }
    }

    // MARK: - Intro Phase

    private var introContent: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                if showHeader {
                    VStack(spacing: 20) {
                        // The person about to take the podium is the player, so
                        // the podium screen opens on the player's own face with
                        // the microphone tucked under it. The mic alone was
                        // scene-setting for nobody in particular.
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
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.top, 6)

                        // Eyebrow shrunk + tracking widened: clear 3-step ladder of
                        // eyebrow < subtitle < title (audit).
                        Text("PRESS CONFERENCE")
                            .font(.system(size: 13, weight: .black))
                            .tracking(8)
                            .foregroundStyle(Color.accentGold.opacity(0.9))

                        Text("\(team.city) \(team.name)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Color.textPrimary)

                        Text("Introductory Press Conference")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textPrimary.opacity(0.78))

                        // Divider line
                        Rectangle()
                            .fill(Color.accentGold.opacity(0.3))
                            .frame(width: 80, height: 2)
                            .padding(.top, 8)

                        Text("The media is waiting. Choose your words carefully — they will be remembered.")
                            .font(.body)
                            .foregroundStyle(Color.textPrimary.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 4)

                        // Question N of 4 progress bar visualization (intro preview)
                        introProgressPreview
                            .padding(.top, 8)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Two spacers below the header vs one above: shifts the title
                // block up ~15% so the coach photo reads as backdrop (audit).
                Spacer(minLength: 24)
                Spacer(minLength: 0)

                if showHeader {
                    // Primary CTA scaled up — the only action on an iPad screen
                    // should dominate, not whisper (audit).
                    Button(action: { beginQuestioning() }) {
                        HStack(spacing: 10) {
                            Text("Take the Podium")
                                .font(.title3.weight(.bold))
                                .tracking(0.5)
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(minWidth: 320)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 18)
                        .background(
                            Capsule()
                                .fill(Color.accentGold)
                                .shadow(color: Color.accentGold.opacity(0.35), radius: 10, y: 4)
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 50)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: DSLayout.wideMeasure)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geometry.size.height)
        }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.3)) { showHeader = true }
        }
    }

    /// Visualization on the intro screen previewing the 4-question structure.
    private var introProgressPreview: some View {
        let count = max(questions.count, 1)
        return VStack(spacing: 8) {
            Text("Question 0 of \(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentGold.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1)
                        )
                        .frame(height: 6)
                        .overlay(
                            Text("\(i + 1)")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.accentGold.opacity(0.8))
                                .padding(.top, 16)
                        )
                }
            }
            .frame(maxWidth: 240)
        }
    }

    // MARK: - Questioning Phase

    /// Scroll anchors. The reveal is the payoff of the whole screen and it is
    /// appended BELOW four response cards — on a first commit it landed under
    /// the action bar, off-screen, so the numbers the player just paid for were
    /// only visible if he thought to scroll. Both transitions are driven here.
    private enum Anchor {
        static let question = "press.question"
        static let reveal = "press.reveal"
    }

    private var questioningContent: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                // Top bar with current stats (#61)
                questioningHeader
                    .padding(.top, 16)
                    .id(Anchor.question)

                currentStatsBar
                    .padding(.top, 12)

                // Running totals strip — shows accumulated impact after each question
                if !selectedIndices.isEmpty {
                    runningTotalsStrip
                        .padding(.top, 10)
                }

                if currentQuestionIndex < questions.count {
                    let question = questions[currentQuestionIndex]

                    // Reporter + question
                    if showReporter {
                        reporterCard(question: question)
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Response cards — wider and taller for iPad
                    if showResponses {
                        VStack(spacing: 14) {
                            ForEach(Array(question.responses.enumerated()), id: \.element.id) { index, response in
                                responseCard(response: response, question: question, index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // What actually happened — headline + the real numbers.
                    if showReaction {
                        resultReveal
                            .padding(.top, 20)
                            .id(Anchor.reveal)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }

                Spacer().frame(height: 24)
            }
            .frame(maxWidth: DSLayout.wideMeasure)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onChange(of: showReaction) { _, isShowing in
            guard isShowing else { return }
            // The reveal is inserted with a delayed transition, so its anchor
            // is not in the scroll view's layout on the same run loop turn —
            // scrolling immediately is a no-op (observed on device). Wait out
            // the insertion, then bring it up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(Anchor.reveal, anchor: .bottom)
                }
            }
        }
        .onChange(of: currentQuestionIndex) { _, _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(Anchor.question, anchor: .top)
            }
        }
        }

        // P5: the ONE commit surface. Tapping a card selects; this says it.
        commitBar
        }
        .frame(minHeight: geometry.size.height)
        }
    }

    // MARK: - P5 Commit Bar

    /// Select-then-commit. An answer used to fire on first tap — irreversible,
    /// no confirmation, on a screen whose whole point is that words are
    /// remembered. The two-step IS the confirmation; there is no dialog.
    private var commitBar: some View {
        let question = currentQuestionIndex < questions.count
            ? questions[currentQuestionIndex] : nil
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

    // MARK: - Running Totals Strip

    /// Live deltas accumulated from the responses chosen so far. Updates after each question.
    private var runningTotalsStrip: some View {
        let totals = runningTotals
        let feedback = sessionFeedback(for: totals)
        return VStack(spacing: 6) {
            Text("RUNNING IMPACT")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.textTertiary)

            HStack(spacing: 6) {
                runningTotalChip(icon: "building.2.fill", label: "Owner", value: totals.ownerSatisfaction)
                runningTotalChip(icon: "person.3.fill", label: "Morale", value: totals.playerMorale)
                runningTotalChip(icon: "hands.clap.fill", label: "Fans", value: totals.fanExcitement)
                runningTotalChip(icon: "newspaper.fill", label: "Media", value: totals.mediaPerception)
            }

            // Session feedback — interprets how the answers are landing in real-time.
            HStack(spacing: 6) {
                Image(systemName: feedback.icon)
                    .font(.system(size: 10, weight: .bold))
                Text(feedback.text)
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(feedback.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(feedback.color.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(feedback.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 20)
    }

    private func runningTotalChip(icon: String, label: String, value: Int) -> some View {
        let color: Color = value > 0 ? Color.success : value < 0 ? Color.danger : Color.textTertiary
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.caption2.weight(.semibold))
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.caption2.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - #61 Current Stats Bar

    /// Shows the player's current baseline stats so they know where they stand before choosing.
    private var currentStatsBar: some View {
        VStack(spacing: 0) {
        // Audit: label the strip so 0-value baselines read as starting values,
        // not as errors ("0 Legacy / 0 Media" looked broken without context).
        Text("CURRENT STANDING \u{00B7} BEFORE THIS SESSION")
            .font(.system(size: 9, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Color.textTertiary)
            .padding(.bottom, 6)
        HStack(spacing: 0) {
            statBarItem(
                icon: "star.fill",
                label: "Legacy",
                value: "\(career.legacy.totalPoints)",
                color: Color.accentGold
            )
            statBarItem(
                icon: "newspaper.fill",
                label: "Media",
                value: "\(career.legacy.mediaReputation)",
                color: career.legacy.mediaReputation >= 0 ? Color.success : Color.danger
            )
            // #117: Renamed from "Comp" to "Satisfaction" for clarity
            if let ownerObj = owner {
                statBarItem(
                    icon: "building.2.fill",
                    label: "Satisfaction",
                    value: "\(ownerObj.satisfaction)%",
                    color: ownerObj.satisfaction >= 50 ? Color.success : Color.danger
                )
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)

        // #119: Guidance text explaining what stats matter
        // (audit: bumped from caption2/tertiary — was unreadably small at iPad distance)
        Text("Owner affects job security  \u{00B7}  Media shapes public narrative  \u{00B7}  Legacy affects career rating")
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }

    private func statBarItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var questioningHeader: some View {
        VStack(spacing: 12) {
            Text("PRESS CONFERENCE")
                .font(.system(size: 11, weight: .black))
                .tracking(4)
                .foregroundStyle(Color.accentGold)

            Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)

            // Segmented progress bar
            HStack(spacing: 4) {
                ForEach(0..<questions.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i <= currentQuestionIndex ? Color.accentGold : Color.textTertiary.opacity(0.2))
                        .frame(height: 6)
                        .animation(.easeInOut(duration: 0.3), value: currentQuestionIndex)
                }
            }
            .padding(.horizontal, 40)
        }
    }

    private func reporterCard(question: PressQuestion) -> some View {
        let tone = reporterTone(for: question)
        return VStack(spacing: 10) {
            // Reporter identity strip — visually separated from the question so
            // the prompt reads as the prompt, not metadata (audit).
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(question.reporterName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    Text(question.outlet)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }

                Spacer()

                // Right pill now carries the reporter tone instead of duplicating
                // the outlet a second time (audit).
                HStack(spacing: 5) {
                    Circle()
                        .fill(reporterToneColor(tone))
                        .frame(width: 6, height: 6)
                    Text(tone.label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(reporterToneColor(tone))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(reporterToneColor(tone).opacity(0.12))
                        .overlay(
                            Capsule().strokeBorder(reporterToneColor(tone).opacity(0.35), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
            )

            // Question card — the prompt stands alone below the reporter strip.
            Text("\"\(question.question)\"")
                .font(.title3.weight(.semibold))
                .italic()
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.accentGold.opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 20)
    }

    private func responseCard(
        response: PressResponse,
        question: PressQuestion,
        index: Int
    ) -> some View {
        // Two distinct states now: PICKED (step 1, reversible) and SAID
        // (step 2, on the record).
        let isPending = pendingResponseIndex == index && selectedResponseIndex == nil
        let isSaid = selectedResponseIndex == index
        let isDisabled = selectedResponseIndex != nil && !isSaid
        let isHighlighted = isPending || isSaid
        let isHeadlineExpanded = headlinePreviewIndex == index
        let preview = PressConferenceEngine.preview(
            for: response, question: question, context: liveContext
        )

        return Button(action: { pickResponse(index: index) }) {
            VStack(alignment: .leading, spacing: 12) {
                // Tone badge
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: response.tone.icon)
                            .font(.caption)
                        Text(response.tone.label)
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(toneColor(response.tone))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(toneColor(response.tone).opacity(0.15))
                    )

                    if preview.isVanilla, let label = preview.vanillaLabel {
                        vanillaChip(label)
                    }

                    Spacer()

                    if isPending {
                        Label("Picked", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentGold)
                    }
                }

                // Response text
                Text("\"\(response.text)\"")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isDisabled ? Color.textTertiaryReadable : Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // #161 B: fogged reaction hints — direction, never numbers.
                hintRow(preview)

                // Headline preview toggle — the strongest read available before
                // answering: the fiction of the consequence, not its arithmetic.
                headlinePreviewSection(
                    response: response,
                    index: index,
                    isExpanded: isHeadlineExpanded,
                    isDisabled: isDisabled
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isHighlighted ? toneColor(response.tone).opacity(0.12) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                // Audit: default stroke tinted by the archetype color so the
                                // four cards can be pre-scanned by personality, not just read.
                                isHighlighted ? toneColor(response.tone).opacity(0.75) : toneColor(response.tone).opacity(0.28),
                                lineWidth: isHighlighted ? 2 : 1
                            )
                    )
                    .overlay(alignment: .leading) {
                        // Personality accent bar (audit): Confident=gold, Humble=blue,
                        // Aggressive=red, Diplomatic=green, Funny=amber.
                        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                            .fill(toneColor(response.tone).opacity(isDisabled ? 0.35 : 0.85))
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

    // MARK: - #161 B: Fogged Hints

    /// Direction markers only. What a coach can plausibly read in the room —
    /// his owner's known persona, the mood in his own building, the stance on
    /// the reporter's chip — and a dash for the audiences he cannot.
    private func hintRow(_ preview: PressConferenceEngine.ReactionPreview) -> some View {
        HStack(spacing: 6) {
            ForEach(preview.hints) { hint in
                HStack(spacing: 4) {
                    Image(systemName: hint.audience.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                    Text(hint.audience.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: hint.direction.glyph)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hintColor(hint.direction))
                    Text(hint.phrase)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hintColor(hint.direction))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(hintColor(hint.direction).opacity(0.10))
                        .overlay(
                            Capsule()
                                .strokeBorder(hintColor(hint.direction).opacity(0.28), lineWidth: 1)
                        )
                )
            }
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
        HStack(spacing: 4) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(Color.alertOrange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.alertOrange.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.alertOrange.opacity(0.35), lineWidth: 1))
        )
    }

    /// Headline preview section under each response. Tapping the chevron toggles
    /// a small box showing what the media headline COULD be if this answer is chosen.
    private func headlinePreviewSection(
        response: PressResponse,
        index: Int,
        isExpanded: Bool,
        isDisabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toggle row — separate gesture so it doesn't trigger the card's selection action.
            Button(action: { toggleHeadlinePreview(index: index) }) {
                HStack(spacing: 6) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 11))
                    Text(isExpanded ? "Hide headline preview" : "Preview headline")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .strokeBorder(Color.textTertiary.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            if isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundStyle(Color.accentGold.opacity(0.7))
                    Text(response.mediaReaction)
                        .font(.caption.weight(.medium))
                        .italic()
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentGold.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentGold.opacity(0.2), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleHeadlinePreview(index: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if headlinePreviewIndex == index {
                headlinePreviewIndex = nil
            } else {
                headlinePreviewIndex = index
            }
        }
    }

    // MARK: - #161 C: The Reveal

    /// AFTER the answer. The headline that ran, and — for the first time on
    /// this screen — the real numbers. This is the learning loop: the player
    /// finds out what "Diplomatic, on a crisis question, in front of a hostile
    /// writer" actually costs by paying it once.
    private var resultReveal: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "newspaper.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentGold)

                Text(reactionText)
                    .font(.subheadline.weight(.medium))
                    .italic()
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let effects = revealedEffects {
                Divider().overlay(Color.accentGold.opacity(0.2))

                Text("WHAT IT ACTUALLY COST")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.textTertiaryReadable)

                effectPillRow(effects: effects)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentGold.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentGold.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    private func effectPillRow(effects: PressEffects) -> some View {
        HStack(spacing: 6) {
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
        }
    }

    // #116: Larger pill fonts; #118: Intensity scaling for negative effects
    // Audit follow-ups: 12-13pt type at iPad distance, lighter error red on dark
    // navy (Color.danger sat at the WCAG borderline at these sizes), and neutral
    // icon/label hue so the colored delta value is the single scannable signal.
    private func effectPill(icon: String, label: String, value: Int) -> some View {
        let pillColor: Color = value > 0 ? Color.success : Color.dangerText
        let isStrongNegative = value <= -6

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(pillColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(pillColor.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(pillColor.opacity(isStrongNegative ? 0.55 : 0.3), lineWidth: isStrongNegative ? 1.5 : 1)
                )
        )
    }

    // MARK: - Summary Phase

    private var summaryContent: some View {
        let result = PressConferenceEngine.buildResult(
            questions: questions,
            selectedIndices: selectedIndices,
            context: context
        )

        return ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                // Header
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentGold)

                    Text("PRESS CONFERENCE SUMMARY")
                        .font(.system(size: 14, weight: .black))
                        .tracking(4)
                        .foregroundStyle(Color.accentGold)
                }

                // Key quotes
                VStack(alignment: .leading, spacing: 16) {
                    Text("YOUR KEY QUOTES")
                        .font(.system(size: 12, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Color.accentGold)

                    ForEach(result.selectedResponses) { response in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\"\(response.responseText)\"")
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(Color.textPrimary)

                            Text(response.mediaReaction)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.backgroundTertiary.opacity(0.5))
                        )
                    }
                }
                .padding(20)
                .cardBackground()
                .padding(.horizontal, 20)

                // #121: Media perception with subtitle explaining what it affects
                VStack(alignment: .leading, spacing: 12) {
                    Text("MEDIA PERCEPTION")
                        .font(.system(size: 12, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Color.accentGold)

                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title3)
                            .foregroundStyle(toneColor(result.dominantTone))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("The media sees you as:")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text(mediaPerceptionLabel(for: result.dominantTone))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            // #121: Explain what media perception affects
                            Text("Shapes free agent interest, fan engagement, and media coverage tone")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }

                    // #123: Show answer pattern (tone distribution)
                    answerPatternView(result: result)

                    // #120 & #122: Effect summary with larger numbers and final values
                    HStack(spacing: 12) {
                        effectSummaryItem(
                            icon: "building.2.fill", label: "Owner",
                            value: result.totalEffects.ownerSatisfaction,
                            baseline: owner?.satisfaction ?? 50, suffix: "%"
                        )
                        effectSummaryItem(
                            icon: "person.3.fill", label: "Morale",
                            value: result.totalEffects.playerMorale,
                            baseline: nil, suffix: ""
                        )
                        effectSummaryItem(
                            icon: "hands.clap.fill", label: "Fans",
                            value: result.totalEffects.fanExcitement,
                            baseline: nil, suffix: ""
                        )
                        effectSummaryItem(
                            icon: "star.fill", label: "Legacy",
                            value: result.totalEffects.legacyPoints,
                            baseline: career.legacy.totalPoints, suffix: ""
                        )
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .cardBackground()
                .padding(.horizontal, 20)

                // Promises tracked
                if !result.promises.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PROMISES TRACKED")
                            .font(.system(size: 12, weight: .black))
                            .tracking(2)
                            .foregroundStyle(Color.warning)

                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.warning)
                            Text("These are settled in the season review. Deliver and the quote holds up; fall short and it runs next to the final standings.")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }

                        // #161 D: the bar, in the coach's own words, next to
                        // the line that set it. Nothing vague — the season
                        // either clears it or the quote comes back.
                        ForEach(result.promises) { promise in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 10) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentGold)
                                    Text("\"\(promise.statement)\"")
                                        .font(.caption)
                                        .italic()
                                        .foregroundStyle(Color.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("\(promise.kind.shortLabel) \u{00B7} \(promise.kind.thresholdCopy)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.warning)
                                    .padding(.leading, 24)
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.backgroundSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.warning.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                }

                Spacer().frame(height: 12)

                // Continue button
                Button(action: { finishConference() }) {
                    HStack(spacing: 8) {
                        Text("Continue")
                            .font(.headline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.accentGold)
                    )
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: DSLayout.wideMeasure)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    // #120: Larger stat numbers; #122: Show final values not just deltas
    private func effectSummaryItem(
        icon: String, label: String, value: Int,
        baseline: Int? = nil, suffix: String = ""
    ) -> some View {
        let color: Color = value > 0 ? Color.success : value < 0 ? Color.danger : Color.textTertiary

        return VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)

            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)

            // #122: Show "baseline -> final" when baseline is available
            if let base = baseline {
                Text("\(base)\(suffix) \u{2192} \(base + value)\(suffix)")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // #123: Show answer pattern — tone distribution from chosen responses
    private func answerPatternView(result: PressConferenceResult) -> some View {
        let toneCounts: [(tone: ResponseTone, count: Int)] = {
            var counts: [ResponseTone: Int] = [:]
            for response in result.selectedResponses {
                counts[response.tone, default: 0] += 1
            }
            return counts
                .sorted { $0.value > $1.value }
                .map { (tone: $0.key, count: $0.value) }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Text("YOUR APPROACH")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.textTertiary)

            HStack(spacing: 8) {
                ForEach(toneCounts, id: \.tone) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.tone.icon)
                            .font(.caption2)
                        Text("\(item.count) \(item.tone.label)")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(toneColor(item.tone))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(toneColor(item.tone).opacity(0.12))
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func generateQuestions() {
        // Use the real owner if available; otherwise fall back to a neutral placeholder
        // so the press conference is never empty even if the owner relationship hasn't
        // been loaded from SwiftData yet.
        let effectiveOwner = owner ?? Owner(name: "The Owner")
        questions = PressConferenceEngine.generateIntroConference(
            team: team,
            owner: effectiveOwner,
            career: career
        )
        // #161: the intro presser has no season history — no last game, no
        // record, no streak — so its context is the simplified one. It is the
        // SAME engine path as the weekly presser, which is the whole point:
        // whatever the matrix says here, it says in week 9 too.
        context = PressConferenceEngine.introContext(
            career: career,
            team: team,
            owner: owner,
            roster: roster
        )
    }

    private func beginQuestioning() {
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .questioning
        }
        animateQuestion()
    }

    private func animateQuestion() {
        showReporter = false
        showQuestion = false
        showResponses = false
        showReaction = false
        pendingResponseIndex = nil
        selectedResponseIndex = nil
        revealedEffects = nil
        headlinePreviewIndex = nil

        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showReporter = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) { showQuestion = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) { showResponses = true }
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

        withAnimation(.easeInOut(duration: 0.3)) {
            selectedResponseIndex = index
        }
        selectedIndices.append(index)

        withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
            showReaction = true
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

    // MARK: - Helpers

    /// #161: the stance chip is an ENGINE input now, not a view decoration —
    /// hostile reporters punish evasion and reward candor in
    /// `PressConferenceEngine.stanceAdjustment`. Both press screens read the
    /// same mapping, so the chip can never disagree with the math.
    private func reporterTone(for question: PressQuestion) -> PressConferenceEngine.ReporterStance {
        PressConferenceEngine.stance(for: question)
    }

    private func reporterToneColor(_ tone: PressConferenceEngine.ReporterStance) -> Color {
        switch tone {
        case .friendly: return Color.success
        case .neutral:  return Color.textSecondary
        case .hostile:  return Color.danger
        }
    }

    /// Real-time session feedback derived from accumulated running totals.
    /// #161: the thresholds live in `PressConferenceEngine.sessionFeedback` —
    /// this screen only paints the severity the engine returned.
    private func sessionFeedback(
        for totals: PressEffects
    ) -> (text: String, icon: String, color: Color) {
        let feedback = PressConferenceEngine.sessionFeedback(for: totals)
        return (feedback.text, feedback.icon, feedbackColor(feedback.severity))
    }

    private func feedbackColor(
        _ severity: PressConferenceEngine.SessionFeedback.Severity
    ) -> Color {
        switch severity {
        case .good:    return Color.success
        case .warning: return Color.warning
        case .bad:     return Color.danger
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
        case .confident:  return "A Bold, Confident Leader"
        case .humble:     return "A Measured, Thoughtful Builder"
        case .aggressive: return "A Controversial Firebrand"
        case .diplomatic: return "A Steady, Professional Operator"
        case .funny:      return "A Charismatic Fan Favorite"
        }
    }
}

// MARK: - Preview

#Preview {
    PressConferenceView(
        career: Career(
            playerName: "Mike Johnson",
            avatarID: "avatar_00000",
            role: .gmAndHeadCoach,
            capMode: .simple
        ),
        team: Team(
            name: "Chiefs",
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
