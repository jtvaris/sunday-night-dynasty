import SwiftUI

// MARK: - Weekly Press Conference View

/// Compact post-game press conference presented after each regular-season
/// game. Reuses the same visual language as `PressConferenceView` (reporter
/// badge, question card, response options, media reaction banner) but
/// skips the intro phase and shows a shorter summary.
struct WeeklyPressConferenceView: View {

    let questions: [PressQuestion]
    let career: Career
    let onComplete: (PressConferenceResult) -> Void

    @State private var currentQuestionIndex = 0
    @State private var selectedIndices: [Int] = []
    @State private var phase: Phase = .questioning

    // Animation states
    @State private var showReporter = false
    @State private var showResponses = false
    @State private var selectedResponseIndex: Int? = nil
    @State private var showReaction = false
    @State private var reactionText = ""
    /// Index of the response whose headline preview is currently expanded.
    @State private var headlinePreviewIndex: Int? = nil

    private enum Phase {
        case questioning
        case summary
    }

    // MARK: - Running totals (computed from selectedIndices so far)

    private var runningTotals: PressEffects {
        var totals = PressEffects()
        for (qIdx, respIdx) in selectedIndices.enumerated() {
            guard qIdx < questions.count,
                  respIdx < questions[qIdx].responses.count else { continue }
            totals = totals + questions[qIdx].responses[respIdx].effects
        }
        return totals
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

    private var questioningContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                questioningHeader
                    .padding(.top, 16)

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
                                responseCard(response: response, index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if showReaction {
                        mediaReactionBanner
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }

                Spacer().frame(height: 40)
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
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

    private func responseCard(response: PressResponse, index: Int) -> some View {
        let isSelected = selectedResponseIndex == index
        let isDisabled = selectedResponseIndex != nil && !isSelected
        let isHeadlineExpanded = headlinePreviewIndex == index

        return Button(action: { selectResponse(index: index) }) {
            VStack(alignment: .leading, spacing: 10) {
                // Tone badge + effect hints
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

                    Spacer()

                    effectPreview(effects: response.effects)
                }

                // Response text
                Text("\"\(response.text)\"")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isDisabled ? Color.textTertiary : Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // Headline preview toggle — shows what the media headline COULD be
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
                    .fill(isSelected ? toneColor(response.tone).opacity(0.12) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? toneColor(response.tone).opacity(0.6) : Color.surfaceBorder,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
            .opacity(isDisabled ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(selectedResponseIndex != nil)
        .animation(.easeInOut(duration: 0.25), value: selectedResponseIndex)
        .animation(.easeInOut(duration: 0.2), value: headlinePreviewIndex)
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
                        .font(.system(size: 8, weight: .bold))
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

    // MARK: - Effect Preview

    private func effectPreview(effects: PressEffects) -> some View {
        let weakestKey = weakestMetricKey(for: effects)
        return HStack(spacing: 6) {
            if effects.ownerSatisfaction != 0 {
                effectDot(icon: "building.2.fill", value: effects.ownerSatisfaction,
                          isWeakest: weakestKey == "owner")
            }
            if effects.playerMorale != 0 {
                effectDot(icon: "person.3.fill", value: effects.playerMorale,
                          isWeakest: weakestKey == "morale")
            }
            if effects.fanExcitement != 0 {
                effectDot(icon: "hands.clap.fill", value: effects.fanExcitement,
                          isWeakest: weakestKey == "fans")
            }
            if effects.mediaPerception != 0 {
                effectDot(icon: "newspaper.fill", value: effects.mediaPerception,
                          isWeakest: weakestKey == "media")
            }
        }
    }

    /// Returns the metric key for the most-negative effect on a response, if any.
    private func weakestMetricKey(for effects: PressEffects) -> String? {
        let candidates: [(key: String, value: Int)] = [
            ("owner",  effects.ownerSatisfaction),
            ("morale", effects.playerMorale),
            ("fans",   effects.fanExcitement),
            ("media",  effects.mediaPerception)
        ]
        let negatives = candidates.filter { $0.value < 0 }
        guard let worst = negatives.min(by: { $0.value < $1.value }) else { return nil }
        return worst.key
    }

    private func effectDot(icon: String, value: Int, isWeakest: Bool = false) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(value > 0 ? "+" : "-")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(value > 0 ? Color.success : value < 0 ? Color.danger : Color.textTertiary)
        .overlay(alignment: .topTrailing) {
            if isWeakest {
                Circle()
                    .fill(Color.danger)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().strokeBorder(Color.backgroundSecondary, lineWidth: 1.5)
                    )
                    .offset(x: 4, y: -4)
                    .accessibilityLabel("Weakest impact")
            }
        }
    }

    // MARK: - Media Reaction Banner

    private var mediaReactionBanner: some View {
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

    // MARK: - Summary Phase

    private var summaryContent: some View {
        let result = PressConferenceEngine.buildResult(
            questions: questions,
            selectedIndices: selectedIndices
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
                            Text("These will be remembered. Deliver on them to boost your legacy -- or suffer the consequences.")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }

                        ForEach(result.promises) { promise in
                            HStack(spacing: 10) {
                                Image(systemName: "bookmark.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentGold)
                                Text("\"\(promise.statement)\"")
                                    .font(.caption)
                                    .italic()
                                    .foregroundStyle(Color.textPrimary)
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
            .frame(maxWidth: 900)
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
        selectedResponseIndex = nil
        headlinePreviewIndex = nil

        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showReporter = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) { showResponses = true }
    }

    private func selectResponse(index: Int) {
        guard selectedResponseIndex == nil,
              currentQuestionIndex < questions.count else { return }

        let question = questions[currentQuestionIndex]
        guard index < question.responses.count else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            selectedResponseIndex = index
        }

        selectedIndices.append(index)

        let response = question.responses[index]
        reactionText = response.mediaReaction

        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            showReaction = true
        }

        // Advance to next question or summary after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
    }

    private func completeConference() {
        let result = PressConferenceEngine.buildResult(
            questions: questions,
            selectedIndices: selectedIndices
        )
        onComplete(result)
    }

    // MARK: - Helpers

    /// Reporter "tone" hint — derived from the outlet (and reporter style).
    /// Engine doesn't expose this directly, so we use a stable mapping based on outlet.
    private enum ReporterTone {
        case friendly
        case neutral
        case hostile

        var label: String {
            switch self {
            case .friendly: return "Friendly"
            case .neutral:  return "Neutral"
            case .hostile:  return "Tough"
            }
        }
    }

    /// Maps a reporter/outlet to a tone. Local outlets lean friendly,
    /// FOX/CBS lean tough/hostile, the rest stay neutral.
    private func reporterTone(for question: PressQuestion) -> ReporterTone {
        let outlet = question.outlet.lowercased()
        let local = ["local press", "city tribune", "local news 9"]
        if local.contains(where: { outlet.contains($0) }) {
            return .friendly
        }
        let toughOutlets = ["fox sports", "cbs sports"]
        if toughOutlets.contains(where: { outlet.contains($0) }) {
            return .hostile
        }
        return .neutral
    }

    private func reporterToneColor(_ tone: ReporterTone) -> Color {
        switch tone {
        case .friendly: return Color.success
        case .neutral:  return Color.textSecondary
        case .hostile:  return Color.danger
        }
    }

    /// Real-time session feedback derived from accumulated running totals.
    /// Returns a short verdict on how the player's answers are landing.
    private func sessionFeedback(
        for totals: PressEffects
    ) -> (text: String, icon: String, color: Color) {
        let owner = totals.ownerSatisfaction
        let morale = totals.playerMorale
        let fans = totals.fanExcitement
        let media = totals.mediaPerception
        let net = owner + morale + fans + media

        if owner <= -8 {
            return ("Owner growing impatient", "exclamationmark.triangle.fill", Color.danger)
        }
        if morale <= -10 {
            return ("Locker room is restless", "person.3.fill", Color.danger)
        }
        if media >= 15 {
            return ("Media buzzing — you're driving headlines", "newspaper.fill", Color.warning)
        }
        if fans >= 15 {
            return ("Fans are fired up", "hands.clap.fill", Color.success)
        }
        if owner >= 10 && morale >= 5 {
            return ("Front office and locker room aligned", "checkmark.seal.fill", Color.success)
        }
        if net >= 10 {
            return ("Landing well across the board", "hand.thumbsup.fill", Color.success)
        }
        if net <= -10 {
            return ("Tough room — losing them", "hand.thumbsdown.fill", Color.danger)
        }
        if net == 0 {
            return ("Reporters waiting for a real take", "ellipsis.circle.fill", Color.textSecondary)
        }
        return ("Steady so far", "equal.circle.fill", Color.textSecondary)
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
                avatarID: "coach_m1",
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
                owner: Owner(name: "Clark Hunt")
            ),
            lastGameResult: true,
            week: 5
        ),
        career: Career(
            playerName: "Mike Johnson",
            avatarID: "coach_m1",
            role: .gmAndHeadCoach,
            capMode: .simple
        ),
        onComplete: { _ in }
    )
}
