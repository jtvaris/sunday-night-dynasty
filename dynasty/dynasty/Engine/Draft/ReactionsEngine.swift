import Foundation

/// Computes reactions from the four actors (Owner, Media, Locker Room, Fans)
/// to draft events.
///
/// Selectivity rules (per design §6):
/// - **B Solid** → silent or single low-key fan reaction (50/50)
/// - **A Smart Pick / C Reach** → ~2 actors react
/// - **A+ Steal / D Big Reach** → all four actors react with strong sentiment
///
/// The caller is responsible for:
/// 1. Persisting each `Reaction` as a `DraftEvent` (one of `.ownerReaction`,
///    `.mediaReaction`, `.lockerRoomReaction`, `.fanReaction`).
/// 2. Calling `apply(_:to:)` to mutate `DraftReputation` *only when the pick
///    was the user's own*. AI picks generate flavor reactions but no stat
///    deltas on the user's reputation row.
enum ReactionsEngine {

    // MARK: - Types

    enum Actor: String, CaseIterable {
        case owner
        case media
        case lockerRoom
        case fans

        var draftEventType: DraftEventType {
            switch self {
            case .owner:      return .ownerReaction
            case .media:      return .mediaReaction
            case .lockerRoom: return .lockerRoomReaction
            case .fans:       return .fanReaction
            }
        }
    }

    enum Sentiment {
        case positive, mixed, negative, critical
    }

    struct Reaction {
        let actor: Actor
        let sentiment: Sentiment
        let message: String         // short flavor text
        let mechanicalDelta: Int    // signed; applied to that actor's stat
    }

    // MARK: - Public API

    /// Returns 0..4 reactions to a completed pick.
    ///
    /// - Parameters:
    ///   - result: the completed `PickResult` (grade + position + names).
    ///   - isUserTeam: whether the pick belongs to the user's team. AI picks
    ///       still generate flavor reactions for the league recap, but their
    ///       deltas are discarded by the caller.
    ///   - previousLockerRoomFamiliarPosition: true if the user just drafted
    ///       a player at the same position as an existing starter — locker
    ///       room reads it as competition pressure.
    ///   - rivalDivisionStarter: true if the player is on track to start
    ///       against a divisional rival next season — adds intensity to media
    ///       and fans.
    static func reactions(
        to result: PickResult,
        isUserTeam: Bool,
        previousLockerRoomFamiliarPosition: Bool = false,
        rivalDivisionStarter: Bool = false
    ) -> [Reaction] {
        var reactions: [Reaction] = []

        switch result.grade {
        case .stealAPlus, .hofTrack:
            reactions.append(makeReaction(.owner, .positive, +6, result, isUserTeam: isUserTeam))
            reactions.append(makeReaction(.media, .positive, +5, result, isUserTeam: isUserTeam))
            reactions.append(makeReaction(.lockerRoom, .positive, +2, result, isUserTeam: isUserTeam))
            reactions.append(makeReaction(.fans, .positive, +5, result, isUserTeam: isUserTeam))

        case .smartA:
            reactions.append(makeReaction(.owner, .positive, +3, result, isUserTeam: isUserTeam))
            reactions.append(makeReaction(.media, .positive, +2, result, isUserTeam: isUserTeam))

        case .solid:
            // 50/50 silent vs. single fan blip.
            if Bool.random() {
                reactions.append(makeReaction(.fans, .mixed, +1, result, isUserTeam: isUserTeam))
            }

        case .reach:
            reactions.append(makeReaction(.media, .critical, -3, result, isUserTeam: isUserTeam))
            reactions.append(makeReaction(.fans, .negative, -2, result, isUserTeam: isUserTeam))

        case .bigReach:
            reactions.append(makeReaction(.owner, .negative, -6, result, isUserTeam: isUserTeam))
            reactions.append(makeReaction(.media, .critical, -5, result, isUserTeam: isUserTeam))
            reactions.append(makeReaction(.lockerRoom, .negative, -2, result, isUserTeam: isUserTeam))
            reactions.append(makeReaction(.fans, .negative, -4, result, isUserTeam: isUserTeam))
        }

        // Bonus triggers — additive layered on top of the base matrix.
        reactions = applyBonusTriggers(
            base: reactions,
            result: result,
            isUserTeam: isUserTeam,
            previousLockerRoomFamiliarPosition: previousLockerRoomFamiliarPosition,
            rivalDivisionStarter: rivalDivisionStarter
        )

        return reactions
    }

    /// Convenience: applies all deltas from a reaction list to a
    /// `DraftReputation` in place. Clamps values to 0...100.
    static func apply(_ reactions: [Reaction], to reputation: DraftReputation) {
        for reaction in reactions {
            switch reaction.actor {
            case .owner:
                reputation.ownerTrust = clamp(reputation.ownerTrust + reaction.mechanicalDelta)
            case .media:
                // Media has no numeric stat — the narrative captures its
                // mood. The delta still flows into the cumulative tracker
                // through `updateNarrative`, so we no-op here.
                continue
            case .lockerRoom:
                reputation.lockerRoomMood = clamp(reputation.lockerRoomMood + reaction.mechanicalDelta)
            case .fans:
                reputation.fanMood = clamp(reputation.fanMood + reaction.mechanicalDelta)
            }
        }
    }

    /// Updates `mediaNarrative` based on cumulative pick patterns.
    /// Call after each user pick (or at round boundaries) with the recent
    /// PickResults that belong to the user.
    static func updateNarrative(_ reputation: DraftReputation, recentPicks: [PickResult]) {
        guard !recentPicks.isEmpty else { return }

        var safeCount = 0
        var bigSwingCount = 0
        var reachCount = 0
        var earlyDevPositionCount = 0  // O-line, D-line, S — typically "rebuilder" signals

        let earlyDevPositions: Set<Position> = [.LT, .LG, .C, .RG, .RT, .DE, .DT, .FS, .SS]

        for pick in recentPicks {
            switch pick.grade {
            case .solid:
                safeCount += 1
            case .stealAPlus, .hofTrack, .smartA where pick.isGem:
                bigSwingCount += 1
            case .reach, .bigReach:
                reachCount += 1
            default:
                break
            }
            if earlyDevPositions.contains(pick.position) {
                earlyDevPositionCount += 1
            }
        }

        let total = recentPicks.count
        let safeRatio = Double(safeCount) / Double(total)
        let bigSwingRatio = Double(bigSwingCount) / Double(total)
        let reachRatio = Double(reachCount) / Double(total)
        let foundationRatio = Double(earlyDevPositionCount) / Double(total)

        let narrative: MediaNarrative
        if reachRatio >= 0.4 {
            narrative = .gambler
        } else if bigSwingRatio >= 0.4 {
            narrative = .starHunter
        } else if foundationRatio >= 0.5 {
            narrative = .rebuilder
        } else if safeRatio >= 0.6 {
            narrative = .conservative
        } else {
            narrative = .neutral
        }

        reputation.mediaNarrative = narrative
    }

    // MARK: - Internals

    private static func clamp(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    private static func applyBonusTriggers(
        base: [Reaction],
        result: PickResult,
        isUserTeam: Bool,
        previousLockerRoomFamiliarPosition: Bool,
        rivalDivisionStarter: Bool
    ) -> [Reaction] {
        var out = base

        // QB pick: media reaction always (even on B), +1 to media intensity.
        if result.position == .QB {
            if let mediaIdx = out.firstIndex(where: { $0.actor == .media }) {
                let r = out[mediaIdx]
                let bumped = Reaction(
                    actor: r.actor,
                    sentiment: r.sentiment,
                    message: r.message,
                    mechanicalDelta: r.mechanicalDelta + (r.mechanicalDelta >= 0 ? 1 : -1)
                )
                out[mediaIdx] = bumped
            } else {
                // Add a media reaction even if the base matrix didn't include
                // one (e.g. a B Solid QB pick still gets media talk).
                out.append(makeReaction(.media, .mixed, +1, result, isUserTeam: isUserTeam, qbBonus: true))
            }
        }

        // Position match for existing starter: locker room −1 (competition).
        if previousLockerRoomFamiliarPosition {
            if let lrIdx = out.firstIndex(where: { $0.actor == .lockerRoom }) {
                let r = out[lrIdx]
                let bumped = Reaction(
                    actor: r.actor,
                    sentiment: r.sentiment,
                    message: r.message,
                    mechanicalDelta: r.mechanicalDelta - 1
                )
                out[lrIdx] = bumped
            } else {
                out.append(Reaction(
                    actor: .lockerRoom,
                    sentiment: .mixed,
                    message: "Veterans eye the rookie at \(result.position.rawValue) — competition is on.",
                    mechanicalDelta: -1
                ))
            }
        }

        // Rival division starter: media +1, fans +1.
        if rivalDivisionStarter {
            if let mIdx = out.firstIndex(where: { $0.actor == .media }) {
                let r = out[mIdx]
                out[mIdx] = Reaction(
                    actor: r.actor,
                    sentiment: r.sentiment,
                    message: r.message,
                    mechanicalDelta: r.mechanicalDelta + (r.mechanicalDelta >= 0 ? 1 : -1)
                )
            }
            if let fIdx = out.firstIndex(where: { $0.actor == .fans }) {
                let r = out[fIdx]
                out[fIdx] = Reaction(
                    actor: r.actor,
                    sentiment: r.sentiment,
                    message: r.message,
                    mechanicalDelta: r.mechanicalDelta + (r.mechanicalDelta >= 0 ? 1 : -1)
                )
            }
        }

        return out
    }

    // MARK: - Message templates

    private static func makeReaction(
        _ actor: Actor,
        _ sentiment: Sentiment,
        _ delta: Int,
        _ result: PickResult,
        isUserTeam: Bool,
        qbBonus: Bool = false
    ) -> Reaction {
        let template = pickMessage(actor: actor, sentiment: sentiment, result: result, qbBonus: qbBonus)
        return Reaction(actor: actor, sentiment: sentiment, message: template, mechanicalDelta: delta)
    }

    private static func pickMessage(
        actor: Actor,
        sentiment: Sentiment,
        result: PickResult,
        qbBonus: Bool
    ) -> String {
        let player = result.playerName
        let team = result.teamAbbrev
        let pos = result.position.rawValue

        switch (actor, sentiment) {
        case (.owner, .positive):
            return pickRandom([
                "Owner is fired up about \(player). Beautiful pick.",
                "Front office is grinning ear to ear over \(player).",
                "Ownership: 'That's how you build a roster.'"
            ])
        case (.owner, .mixed):
            return "Ownership cautiously optimistic about \(player)."
        case (.owner, .negative):
            return pickRandom([
                "Owner is not pleased with the \(pos) selection.",
                "Front office wanted a different name on the card.",
                "Ownership: 'We needed more here.'"
            ])
        case (.owner, .critical):
            return "Owner is openly questioning the \(pos) board."

        case (.media, .positive):
            if result.isGem || result.grade == .stealAPlus || result.grade == .hofTrack {
                return pickRandom([
                    "STEAL OF THE DRAFT — \(player) at #\(result.pickNumber)?!",
                    "How did \(player) fall to \(team)? This is grand larceny.",
                    "\(team) just stole \(player). Steal of the draft."
                ])
            }
            return pickRandom([
                "Sharp pick by \(team) — \(player) is a plug-and-play \(pos).",
                "Solid value for \(team) with \(player).",
                "\(team) gets a high-floor \(pos) in \(player)."
            ])
        case (.media, .mixed):
            if qbBonus {
                return "Media: 'Interesting QB swing — book-of-the-month right there.'"
            }
            return "Media split on the \(player) selection."
        case (.media, .negative):
            return "Media skeptical of the \(pos) value at this slot."
        case (.media, .critical):
            return pickRandom([
                "Eyebrows raised across the war room — \(player)?",
                "Talking heads are tearing the \(player) pick apart.",
                "Analysts: 'This was at least a round early.'"
            ])

        case (.lockerRoom, .positive):
            return pickRandom([
                "Locker room buzzing about \(player).",
                "Vets at \(pos) approve — \(player) fits the room.",
                "Players walked away impressed by the \(player) pick."
            ])
        case (.lockerRoom, .mixed):
            return "Locker room reading the \(pos) tea leaves on \(player)."
        case (.lockerRoom, .negative):
            return pickRandom([
                "Veterans question whether \(player) was the right call.",
                "Locker room confused by the \(pos) pick.",
                "Vets at \(pos) bristled at the \(player) selection."
            ])
        case (.lockerRoom, .critical):
            return "Locker room rumblings about the \(player) pick."

        case (.fans, .positive):
            return pickRandom([
                "Fans erupting — \(player) is the steal of the draft!",
                "Stadium would be on its feet for \(player).",
                "Fan reaction: ELITE pick. \(player) jersey sales spiking."
            ])
        case (.fans, .mixed):
            return "Fans cautiously optimistic about \(player)."
        case (.fans, .negative):
            return pickRandom([
                "Fans booing the \(player) selection.",
                "Fan reaction: 'WHO?!'",
                "Fanbase frustrated by the \(pos) pick."
            ])
        case (.fans, .critical):
            return "Fans are roasting the front office over \(player)."
        }
    }

    private static func pickRandom(_ options: [String]) -> String {
        options.randomElement() ?? options.first ?? ""
    }
}
