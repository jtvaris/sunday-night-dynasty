import SwiftUI

// MARK: - DraftBroadcastRail — the room's one ambient overlay (#105 Wave 3b)
//
// UI_REDESIGN_VISION §3 family 8: the war room's verdict is RESTYLE, and the
// named defect is "its five simultaneous overlay mechanisms (forced sheet, top
// banner, bottom toast, full-screen drama overlay, parallel round-recap sheet)
// reduced to the standard set".
//
// ## The five, and where each one went
//
//   1. forced sheet ............ `PickSheetView`, already the single
//                                `.sheet(item:)` point (#153a). UNCHANGED.
//   2. parallel round recap .... same sheet, second case. UNCHANGED.
//   3. top banner (trade offer)  a DECISION, and decisions commit on the bottom
//                                bar (P5). Moved to `DraftControlBar`.
//   4. bottom toast (reactions)  ambient. Folded in here.
//   5. full-screen drama ....... ambient. This file.
//   + trade beats .............. a sixth the audit did not count, in a third
//                                file with its own animation contract. Here.
//
// **Three mechanisms remain, and each answers a different question:** the sheet
// is "the room needs an answer and it owns the screen", the action bar is "you
// are being asked to commit", and this rail is "the broadcast is telling you
// something and will get out of the way". Nothing else may raise a view over
// the board.
//
// ## One queue, one at a time
//
// The old arrangement had three independent view-local lifecycles running over
// three coordinator queues, so a gem flash, a "WE HAVE A TRADE" cut-in and an
// owner reaction could all be on screen simultaneously, each with its own dwell
// and its own easing. The rail drains all three in one pump — drama, then trade
// beats, then reactions — and never shows two beats at once.
//
// ## The round curtain is gone (the roundTransition / pendingRoundRecap dedup)
//
// A round boundary used to fire TWO presentations off one event:
// `DraftDramaEngine` emitted `.roundTransition` and the rail's ancestor drew a
// full-screen gold "ROUND 2 BEGINS" curtain, while the coordinator
// independently set `pendingRoundRecap` and the sheet opened the recap card.
// Two interruptions, same instant, one of them carrying no information at all.
//
// The recap is the one that survives, because it is the one with content — your
// cards this round, the reputation deltas, the steal of the round. The curtain
// is consumed here without being drawn, and the round change is now *structural*
// rather than theatrical: `DraftPickBand`'s ribbon rolls over and its head reads
// "ROUND 3 · PICK 1 OF 32". The engine case is untouched — this is the view
// layer declining to draw it, which is the only half of the pair this wave owns.
//
// ## Iconography
//
// SF Symbols, never emoji (§2.12). The three files this replaces shipped
// 👔 📰 🏈 📣 💎 🎉 ⚡ as type.

struct DraftBroadcastRail: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    @State private var shown: Beat?
    @State private var visible = false
    @State private var isPumping = false

    var body: some View {
        ZStack {
            if let beat = shown {
                Group {
                    switch beat.style {
                    case .banner: bannerView(beat)
                    case .moment: momentView(beat)
                    }
                }
                // Fresh identity per beat, so the in-animation starts from the
                // out-state instead of cross-fading two headlines in one frame.
                .id(beat.key)
            }
        }
        .allowsHitTesting(false)
        .onAppear { pump() }
        .onChange(of: queueSignature) { _, _ in pump() }
    }

    /// Cheap change token over the three source queues. `clockSeconds`
    /// republishes once a second and must not restart the pump; the counts only
    /// move when a beat is produced or consumed.
    private var queueSignature: String {
        "\(coordinator.pendingDrama.count)-\(coordinator.pendingTradeBeats.count)-\(coordinator.pendingReactions.count)"
    }

    // MARK: - The pump

    private func pump() {
        guard !isPumping, shown == nil else { return }
        guard let next = nextBeat() else { return }
        isPumping = true
        shown = next
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            withAnimation(.easeOut(duration: DraftAnimation.bannerIn)) { visible = true }
            try? await Task.sleep(nanoseconds: UInt64(next.dwell * 1_000_000_000))
            withAnimation(.easeIn(duration: DraftAnimation.bannerOut)) { visible = false }
            try? await Task.sleep(
                nanoseconds: UInt64(DraftAnimation.bannerOut * 1_000_000_000) + 60_000_000
            )
            shown = nil
            switch next.source {
            case .drama:    coordinator.consumeOldestDrama()
            case .trade:    coordinator.consumeOldestTradeBeat()
            case .reaction: coordinator.consumeOldestReaction()
            }
            isPumping = false
            pump()
        }
    }

    /// Drama first (the broadcast's own moments), then league trades, then the
    /// four actors' reactions — which are the most numerous and the least
    /// time-critical, so they queue behind everything.
    ///
    /// Called only from `pump()`, never from `body`, because it mutates the
    /// coordinator: the round curtain is dropped here rather than drawn.
    private func nextBeat() -> Beat? {
        while let head = coordinator.pendingDrama.first, case .roundTransition = head {
            coordinator.consumeOldestDrama()
        }
        if let drama = coordinator.pendingDrama.first { return Beat(drama: drama) }
        if let trade = coordinator.pendingTradeBeats.first { return Beat(trade: trade) }
        if let reaction = coordinator.pendingReactions.first { return Beat(reaction: reaction) }
        return nil
    }

    // MARK: - Banner (the default treatment)

    private func bannerView(_ beat: Beat) -> some View {
        VStack {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Capsule()
                    .fill(beat.accent)
                    .frame(width: 3)
                if let icon = beat.icon {
                    Image(systemName: icon)
                        .font(DSType.display(16, .black))
                        .foregroundStyle(beat.accent)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(beat.eyebrow.uppercased())
                        .font(DSType.display(11, .heavy))
                        .tracking(0.7)
                        .foregroundStyle(beat.accent)
                        .lineLimit(1)
                    Text(beat.headline)
                        .font(DSType.text(16, .semibold, prose: true))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = beat.detail, !detail.isEmpty {
                        Text(detail)
                            .font(DSType.text(12, .regular, prose: true))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let delta = beat.delta, delta != 0 {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(DSType.display(16, .heavy))
                        .foregroundStyle(delta > 0 ? Color.success : Color.dangerText)
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, DSSpacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill((delta > 0 ? Color.success : Color.danger).opacity(0.16))
                        )
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .strokeBorder(beat.accent.opacity(0.45), lineWidth: 1)
            )
            .dsElevation(.card)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -32)
            .padding(.top, DSSpacing.sm)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Moment (full bleed — the end of the night, and nothing else)

    /// The only beat that still takes the whole screen.
    ///
    /// The round curtain used to share this treatment and fired ~7 times a
    /// draft; Mr. Irrelevant fires once, is terminal, and is the moment the room
    /// hands over to the UDFA stage. A full-bleed treatment that happens once is
    /// a punctuation mark; one that happens every round is a load screen.
    private func momentView(_ beat: Beat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.backgroundPlate,
                    beat.accent.opacity(0.40),
                    Color.backgroundPlate
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(visible ? 0.95 : 0)

            VStack(spacing: DSSpacing.sm) {
                if let icon = beat.icon {
                    Image(systemName: icon)
                        .font(.system(size: DSType.Size.display, weight: .black))
                        .foregroundStyle(beat.accent)
                }
                Text(beat.headline.uppercased())
                    .font(DSType.display(DSType.Size.hero, .black))
                    .tracking(2)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                if let detail = beat.detail {
                    Text(detail.uppercased())
                        .font(DSType.display(DSType.Size.title2, .heavy))
                        .tracking(4)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1.0 : 0.88)
        }
    }
}

// MARK: - One beat

/// Every ambient thing the room can say, flattened to one shape so the rail has
/// one lifecycle instead of three.
private struct Beat {
    enum Style { case banner, moment }
    /// Which of the coordinator's three queues this beat came off, so the pump
    /// clears the right one when it is done with it.
    enum Source { case drama, trade, reaction }

    let key: String
    let style: Style
    let dwell: Double
    let eyebrow: String
    let headline: String
    var detail: String? = nil
    var icon: String? = nil
    let accent: Color
    var delta: Int? = nil
    /// Declared LAST so the synthesized memberwise initializer keeps the
    /// optional slots (`detail` / `icon` / `delta`) defaultable ahead of it —
    /// a beat that carries no delta simply omits the label.
    let source: Source
}

extension Beat {

    // MARK: Drama

    /// Colour discipline (P7 / P5): gold has three jobs in this room and all
    /// three are already taken — the band's current rule, the pick clock, and
    /// the action bar's primary fill. The three files this replaces painted
    /// `draftStealGold` on the steal banner, the gem card, the trade cut-in and
    /// the positive-reaction toast, which is four more. So a beat's accent is
    /// semantic instead: green for a good outcome, blue for information, orange
    /// for urgency, red for a loss.
    init(drama: DraftDramaEngine.DramaEvent) {
        switch drama {
        case .stealOfTheDraft(let playerName, let teamAbbrev, let valueDelta):
            self.init(
                key: "steal:\(teamAbbrev):\(playerName):\(valueDelta)",
                style: .banner,
                dwell: 2.5,
                eyebrow: "Steal of the draft",
                headline: "\(teamAbbrev) take \(playerName)",
                detail: "\(valueDelta) slots past where the board had him.",
                icon: "bolt.fill",
                accent: .success,
                source: .drama
            )
        case .gemMoment(let playerName, let teamAbbrev):
            self.init(
                key: "gem:\(teamAbbrev):\(playerName)",
                style: .banner,
                dwell: 1.6,
                eyebrow: "\(teamAbbrev) land their guy",
                headline: playerName,
                detail: nil,
                icon: "sparkles",
                accent: .success,
                source: .drama
            )
        case .userPickIncoming(let picksAway):
            self.init(
                key: "incoming:\(picksAway)",
                style: .banner,
                dwell: 1.6,
                eyebrow: "You are up",
                headline: picksAway == 1
                    ? "Your pick is next"
                    : "Your pick is \(picksAway) cards away",
                detail: nil,
                icon: "exclamationmark.triangle.fill",
                accent: .alertOrange,
                source: .drama
            )
        case .targetOnTheBoard(let playerName, let position, let picksAway):
            self.init(
                key: "target:\(position):\(playerName):\(picksAway)",
                style: .banner,
                dwell: 2.4,
                eyebrow: "Your target is still on the board",
                headline: "\(position) \(playerName)",
                detail: picksAway == 1
                    ? "One card until yours."
                    : "\(picksAway) cards until yours.",
                icon: "star.fill",
                accent: .accentBlue,
                source: .drama
            )
        case .targetSniped(let playerName, let position, let teamAbbrev):
            self.init(
                key: "sniped:\(teamAbbrev):\(position):\(playerName)",
                style: .banner,
                dwell: 2.2,
                eyebrow: "Target gone",
                headline: "\(teamAbbrev) take \(position) \(playerName)",
                detail: "Off your board.",
                icon: "xmark.seal.fill",
                accent: .dangerText,
                source: .drama
            )
        case .finalPick:
            self.init(
                key: "final",
                style: .moment,
                dwell: 2.2,
                eyebrow: "Draft complete",
                headline: "Mr. Irrelevant",
                detail: "Draft complete",
                icon: "flag.checkered",
                accent: .success,
                source: .drama
            )
        case .roundTransition(let roundNumber):
            // Never reached: `nextBeat()` drains these before it builds a beat.
            // The case exists so the switch stays exhaustive against an engine
            // enum this wave does not own — see the file header for why the
            // curtain is dropped rather than drawn.
            self.init(
                key: "round:\(roundNumber)",
                style: .banner,
                dwell: 0,
                eyebrow: "Round \(roundNumber)",
                headline: "Round \(roundNumber) is under way",
                detail: nil,
                icon: nil,
                accent: .textSecondary,
                source: .drama
            )
        }
    }

    // MARK: League trades

    init(trade: DraftDayCoordinator.TradeBeat) {
        self.init(
            key: "trade:\(trade.id)",
            style: .banner,
            dwell: 2.6,
            eyebrow: "We have a trade",
            headline: trade.title,
            detail: trade.subtitle,
            icon: "arrow.left.arrow.right",
            accent: .accentBlue,
            source: .trade
        )
    }

    // MARK: The four actors

    init(reaction: ReactionsEngine.Reaction) {
        let accent: Color
        switch reaction.sentiment {
        case .positive: accent = .success
        case .mixed:    accent = .textSecondary
        case .negative: accent = .alertOrange
        case .critical: accent = .dangerText
        }
        self.init(
            key: "reaction:\(reaction.actor.rawValue):\(reaction.message)",
            style: .banner,
            // Reactions arrive four at a time after a user pick and the room is
            // still running underneath them, so they get the shortest dwell of
            // anything on the rail.
            dwell: DraftAnimation.toastDwell,
            eyebrow: Beat.actorName(reaction.actor),
            headline: reaction.message,
            detail: nil,
            icon: Beat.actorIcon(reaction.actor),
            accent: accent,
            delta: reaction.mechanicalDelta,
            source: .reaction
        )
    }

    private static func actorName(_ actor: ReactionsEngine.Actor) -> String {
        switch actor {
        case .owner:      return "Owner"
        case .media:      return "Media"
        case .lockerRoom: return "Locker room"
        case .fans:       return "Fans"
        }
    }

    private static func actorIcon(_ actor: ReactionsEngine.Actor) -> String {
        switch actor {
        case .owner:      return "briefcase.fill"
        case .media:      return "newspaper.fill"
        case .lockerRoom: return "figure.american.football"
        case .fans:       return "megaphone.fill"
        }
    }
}
