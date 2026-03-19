import SwiftUI

// MARK: - Press Conference View

/// Full-screen immersive press conference where the player chooses responses
/// to reporter questions, with real consequences for legacy, morale, and media perception.
struct PressConferenceView: View {

    let career: Career
    let team: Team
    let owner: Owner?
    let onComplete: (PressConferenceResult) -> Void

    @State private var questions: [PressQuestion] = []
    @State private var currentQuestionIndex = 0
    @State private var selectedIndices: [Int] = []
    @State private var phase: Phase = .intro

    // Animation states
    @State private var showHeader = false
    @State private var showReporter = false
    @State private var showQuestion = false
    @State private var showResponses = false
    @State private var selectedResponseIndex: Int? = nil
    @State private var showReaction = false
    @State private var reactionText = ""

    private enum Phase {
        case intro
        case questioning
        case summary
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
                        // Microphone icon
                        Image(systemName: "mic.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.accentGold)
                            .shadow(color: Color.accentGold.opacity(0.4), radius: 16, y: 0)

                        Text("PRESS CONFERENCE")
                            .font(.system(size: 16, weight: .black))
                            .tracking(6)
                            .foregroundStyle(Color.accentGold)

                        Text("\(team.city) \(team.name)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Color.textPrimary)

                        Text("Introductory Press Conference")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)

                        // Divider line
                        Rectangle()
                            .fill(Color.accentGold.opacity(0.3))
                            .frame(width: 80, height: 2)
                            .padding(.top, 8)

                        Text("The media is waiting. Choose your words carefully — they will be remembered.")
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 4)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer(minLength: 40)

                if showHeader {
                    Button(action: { beginQuestioning() }) {
                        HStack(spacing: 8) {
                            Text("Take the Podium")
                                .font(.headline.weight(.bold))
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.accentGold)
                                .shadow(color: Color.accentGold.opacity(0.3), radius: 8, y: 4)
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 50)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geometry.size.height)
        }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.3)) { showHeader = true }
        }
    }

    // MARK: - Questioning Phase

    private var questioningContent: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 0) {
                // Top bar with current stats (#61)
                questioningHeader
                    .padding(.top, 16)

                currentStatsBar
                    .padding(.top, 12)

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
                                responseCard(response: response, index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Media reaction
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
            .frame(minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
        }
    }

    // MARK: - #61 Current Stats Bar

    /// Shows the player's current baseline stats so they know where they stand before choosing.
    private var currentStatsBar: some View {
        VStack(spacing: 0) {
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
        Text("Owner affects job security  \u{00B7}  Media shapes public narrative  \u{00B7}  Legacy affects career rating")
            .font(.caption2)
            .foregroundStyle(Color.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.top, 4)
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
        VStack(alignment: .leading, spacing: 14) {
            // Reporter badge
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

    private func responseCard(response: PressResponse, index: Int) -> some View {
        let isSelected = selectedResponseIndex == index
        let isDisabled = selectedResponseIndex != nil && !isSelected

        return Button(action: { selectResponse(index: index) }) {
            VStack(alignment: .leading, spacing: 12) {
                // Tone badge
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

                // Response text
                Text("\"\(response.text)\"")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isDisabled ? Color.textTertiary : Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // Effect preview pills
                effectPreview(effects: response.effects)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? toneColor(response.tone).opacity(0.12) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
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
    }

    private func effectPreview(effects: PressEffects) -> some View {
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
        }
    }

    // #116: Larger pill fonts; #118: Intensity scaling for negative effects
    private func effectPill(icon: String, label: String, value: Int) -> some View {
        let pillColor: Color = {
            if value > 0 { return Color.success }
            // Intensity scaling: light red for small negatives, dark red for large
            let absVal = abs(value)
            if absVal >= 6 {
                return Color.danger
            } else {
                return Color.danger.opacity(0.65)
            }
        }()
        let pillScale: CGFloat = value < 0 ? (abs(value) >= 6 ? 1.1 : 1.0) : 1.0

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption.weight(.medium))
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(pillColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .scaleEffect(pillScale)
        .background(
            Capsule()
                .fill(pillColor.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(pillColor.opacity(0.3), lineWidth: value < 0 && abs(value) >= 6 ? 1.5 : 1)
                )
        )
    }

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
            .frame(maxWidth: 900)
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
        selectedResponseIndex = nil

        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showReporter = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) { showQuestion = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) { showResponses = true }
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

    private func finishConference() {
        let result = PressConferenceEngine.buildResult(
            questions: questions,
            selectedIndices: selectedIndices
        )
        onComplete(result)
    }

    // MARK: - Helpers

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
        owner: Owner(name: "Clark Hunt"),
        onComplete: { _ in }
    )
}
