import SwiftUI

// MARK: - Weekly Press Conference View

/// Compact post-game press conference presented after each regular-season
/// game. Reuses the same visual language as `PressConferenceView` (reporter
/// badge, question card, response options, media reaction banner) but
/// skips the intro phase and shows a shorter summary.
struct WeeklyPressConferenceView: View {

    let questions: [PressQuestion]
    let career: Career
    /// #161: the context `WeekAdvancer` assembled next to the questions —
    /// situation, standing, locker-room band, owner persona, tone ledger.
    /// Everything on this screen is resolved from it, so the weekly presser and
    /// the intro presser cannot drift apart mechanically.
    var context: PressConferenceEngine.PressContext = .neutral
    let onComplete: (PressConferenceResult) -> Void

    @State private var currentQuestionIndex = 0
    @State private var selectedIndices: [Int] = []
    @State private var phase: Phase = .questioning

    // Animation states
    @State private var showReporter = false
    @State private var showResponses = false
    /// P5 step 1: picked, not yet said.
    @State private var pendingResponseIndex: Int? = nil
    /// P5 step 2: on the record.
    @State private var selectedResponseIndex: Int? = nil
    @State private var showReaction = false
    @State private var reactionText = ""
    /// The real, context-resolved deltas of the committed answer.
    @State private var revealedEffects: PressEffects? = nil
    /// Index of the response whose headline preview is currently expanded.
    @State private var headlinePreviewIndex: Int? = nil

    private enum Phase {
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

    /// The context question N is answered in. Mirrors
    /// `PressConferenceEngine.buildResult` exactly.
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

            // Dimmed background image
            GeometryReader { geo in
                Image("BgPressConference")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.25)
            }
            .ignoresSafeArea()

            // Dark gradient overlay for readability
            LinearGradient(
                colors: [
                    Color.backgroundPrimary.opacity(0.6),
                    Color.backgroundPrimary.opacity(0.4),
                    Color.backgroundPrimary.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            switch phase {
            case .questioning:
                questioningContent
            case .summary:
                summaryContent
            }
        }
        .onAppear { animateQuestion() }
    }

    // MARK: - Questioning Phase

    /// Scroll anchors — same reason as the intro presser: the reveal is
    /// appended below the response cards and must not land under the action bar.
    private enum Anchor {
        static let question = "press.question"
        static let reveal = "press.reveal"
    }

    private var questioningContent: some View {
        VStack(spacing: 0) {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                questioningHeader
                    .padding(.top, 16)
                    .id(Anchor.question)

                // Running totals strip — shows accumulated impact after each question
                if !selectedIndices.isEmpty {
                    runningTotalsStrip
                        .padding(.top, 12)
                }

                if currentQuestionIndex < questions.count {
                    let question = questions[currentQuestionIndex]

                    if showReporter {
                        reporterCard(question: question)
                            .padding(.top, 24)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if showResponses {
                        VStack(spacing: 12) {
                            ForEach(Array(question.responses.enumerated()), id: \.element.id) { index, response in
                                responseCard(response: response, question: question, index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

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
            // Same delayed-insertion caveat as the intro presser.
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

        // P5: the ONE commit surface, identical to the intro presser's.
        commitBar
        }
    }

    // MARK: - P5 Commit Bar

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

    private var questioningHeader: some View {
        VStack(spacing: 12) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<questions.count, id: \.self) { i in
                    Circle()
                        .fill(i < currentQuestionIndex ? Color.accentGold :
                              i == currentQuestionIndex ? Color.accentGold.opacity(0.8) :
                              Color.textTertiary.opacity(0.3))
                        .frame(width: i == currentQuestionIndex ? 10 : 7,
                               height: i == currentQuestionIndex ? 10 : 7)
                        .animation(.easeInOut(duration: 0.3), value: currentQuestionIndex)
                }
            }

            // The player is the one answering, so the player's own face heads
            // the screen — the reporter's badge already carries a portrait slot
            // one card down, and only one side of the exchange had a face.
            HStack(spacing: 10) {
                UserPortraitView(career: career, size: .small)

                VStack(alignment: .leading, spacing: 1) {
                    Text(career.playerName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("At the podium")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Text("POST-GAME PRESS CONFERENCE")
                .font(.system(size: 11, weight: .black))
                .tracking(4)
                .foregroundStyle(Color.accentGold)

            Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Running Totals Strip

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

    // MARK: - Reporter Card

    private func reporterCard(question: PressQuestion) -> some View {
        let tone = reporterTone(for: question)
        return VStack(alignment: .leading, spacing: 14) {
            // Reporter badge
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(question.reporterName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text(question.outlet)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentGold)

                        // Reporter tone indicator: colored dot + small descriptor
                        Circle()
                            .fill(reporterToneColor(tone))
                            .frame(width: 6, height: 6)
                        Text(tone.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(reporterToneColor(tone))
                    }
                }

                Spacer()

                // Outlet badge
                Text(question.outlet)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.accentGold)
                    )
            }

            // Question text
            Text("\"\(question.question)\"")
                .font(.title3.weight(.semibold))
                .italic()
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentGold.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Response Card

    private func responseCard(
        response: PressResponse,
        question: PressQuestion,
        index: Int
    ) -> some View {
        let isPending = pendingResponseIndex == index && selectedResponseIndex == nil
        let isSaid = selectedResponseIndex == index
        let isDisabled = selectedResponseIndex != nil && !isSaid
        let isHighlighted = isPending || isSaid
        let isHeadlineExpanded = headlinePreviewIndex == index
        let preview = PressConferenceEngine.preview(
            for: response, question: question, context: liveContext
        )

        return Button(action: { pickResponse(index: index) }) {
            VStack(alignment: .leading, spacing: 10) {
                // Tone badge + the vanilla warning, if the press has a name for it
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: response.tone.icon)
                            .font(.caption2)
                        Text(response.tone.label)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(toneColor(response.tone))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
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
                    .font(.subheadline.weight(.medium))
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHighlighted ? toneColor(response.tone).opacity(0.12) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isHighlighted ? toneColor(response.tone).opacity(0.75) : Color.surfaceBorder,
                                lineWidth: isHighlighted ? 2 : 1
                            )
                    )
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
            Button(action: { toggleHeadlinePreview(index: index) }) {
                HStack(spacing: 6) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 10))
                    Text(isExpanded ? "Hide headline" : "Preview headline")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
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
                        .font(.caption2)
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

    /// AFTER the answer: the headline that ran, and the real numbers. Before
    /// the answer this screen showed +/- glyphs per audience on every card,
    /// which was the same spreadsheet problem in smaller type.
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

    private func effectPill(icon: String, label: String, value: Int) -> some View {
        let pillColor: Color = value > 0 ? Color.success : Color.dangerText
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
                .overlay(Capsule().strokeBorder(pillColor.opacity(0.3), lineWidth: 1))
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

                // Effect summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("IMPACT")
                        .font(.system(size: 12, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Color.accentGold)

                    HStack(spacing: 16) {
                        effectSummaryItem(icon: "building.2.fill", label: "Owner", value: result.totalEffects.ownerSatisfaction)
                        effectSummaryItem(icon: "person.3.fill", label: "Morale", value: result.totalEffects.playerMorale)
                        effectSummaryItem(icon: "hands.clap.fill", label: "Fans", value: result.totalEffects.fanExcitement)
                        effectSummaryItem(icon: "star.fill", label: "Legacy", value: result.totalEffects.legacyPoints)
                    }
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

                // Return to Dashboard button
                Button(action: { completeConference() }) {
                    HStack(spacing: 8) {
                        Text("Return to Dashboard")
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

    private func effectSummaryItem(icon: String, label: String, value: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(value > 0 ? Color.success : value < 0 ? Color.danger : Color.textTertiary)

            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(value > 0 ? Color.success : value < 0 ? Color.danger : Color.textTertiary)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func animateQuestion() {
        showReporter = false
        showResponses = false
        showReaction = false
        pendingResponseIndex = nil
        selectedResponseIndex = nil
        revealedEffects = nil
        headlinePreviewIndex = nil

        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showReporter = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) { showResponses = true }
    }

    /// P5 step 1 — reversible.
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

    private func completeConference() {
        let result = PressConferenceEngine.buildResult(
            questions: questions,
            selectedIndices: selectedIndices,
            context: context
        )
        onComplete(result)
    }

    // MARK: - Helpers

    /// #161: one mapping, in the engine, shared by both press screens — the
    /// stance chip is an input to `stanceAdjustment`, so it can never disagree
    /// with the math it is advertising.
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
}

// MARK: - Preview

#Preview {
    WeeklyPressConferenceView(
        questions: PressConferenceEngine.generateWeeklyPressConference(
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
            lastGameResult: true,
            week: 5
        ),
        career: Career(
            playerName: "Mike Johnson",
            avatarID: "avatar_00000",
            role: .gmAndHeadCoach,
            capMode: .simple
        ),
        onComplete: { _ in }
    )
}
