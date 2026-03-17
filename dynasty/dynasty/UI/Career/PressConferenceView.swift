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
        VStack(spacing: 32) {
            Spacer()

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

                    Text("The media is waiting. Choose your words carefully -- they will be remembered.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Spacer()

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
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.3)) { showHeader = true }
        }
    }

    // MARK: - Questioning Phase

    private var questioningContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Top bar
                questioningHeader
                    .padding(.top, 16)

                if currentQuestionIndex < questions.count {
                    let question = questions[currentQuestionIndex]

                    // Reporter + question
                    if showReporter {
                        reporterCard(question: question)
                            .padding(.top, 24)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Response cards
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

                    // Media reaction
                    if showReaction {
                        mediaReactionBanner
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }

                Spacer().frame(height: 40)
            }
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

            Text("PRESS CONFERENCE")
                .font(.system(size: 11, weight: .black))
                .tracking(4)
                .foregroundStyle(Color.accentGold)

            Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
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
            VStack(alignment: .leading, spacing: 10) {
                // Tone badge + effect hints
                HStack(spacing: 8) {
                    // Tone badge
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

                    // Small effect preview icons
                    effectPreview(effects: response.effects)
                }

                // Response text
                Text("\"\(response.text)\"")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isDisabled ? Color.textTertiary : Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
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
        .disabled(selectedResponseIndex != nil)
        .animation(.easeInOut(duration: 0.25), value: selectedResponseIndex)
    }

    private func effectPreview(effects: PressEffects) -> some View {
        HStack(spacing: 6) {
            if effects.ownerSatisfaction != 0 {
                effectDot(icon: "building.2.fill", value: effects.ownerSatisfaction)
            }
            if effects.playerMorale != 0 {
                effectDot(icon: "person.3.fill", value: effects.playerMorale)
            }
            if effects.fanExcitement != 0 {
                effectDot(icon: "hands.clap.fill", value: effects.fanExcitement)
            }
            if effects.mediaPerception != 0 {
                effectDot(icon: "newspaper.fill", value: effects.mediaPerception)
            }
        }
    }

    private func effectDot(icon: String, value: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(value > 0 ? "+" : "-")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(value > 0 ? Color.success : value < 0 ? Color.danger : Color.textTertiary)
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

                // Media perception
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
                        }
                    }

                    // Effect summary
                    HStack(spacing: 16) {
                        effectSummaryItem(icon: "building.2.fill", label: "Owner", value: result.totalEffects.ownerSatisfaction)
                        effectSummaryItem(icon: "person.3.fill", label: "Morale", value: result.totalEffects.playerMorale)
                        effectSummaryItem(icon: "hands.clap.fill", label: "Fans", value: result.totalEffects.fanExcitement)
                        effectSummaryItem(icon: "star.fill", label: "Legacy", value: result.totalEffects.legacyPoints)
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

    private func generateQuestions() {
        guard let realOwner = owner else { return }
        questions = PressConferenceEngine.generateIntroConference(
            team: team,
            owner: realOwner,
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
