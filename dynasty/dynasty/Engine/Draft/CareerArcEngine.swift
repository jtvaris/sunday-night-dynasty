import Foundation
import SwiftData

/// Evaluates the career arc of every drafted player at offseason boundaries
/// and updates `CareerArcState` + `DraftPickGrade.trueGrade` accordingly.
///
/// The engine answers two questions for the player:
/// 1. Did this pick deliver? (True Grade)
/// 2. Is this a hidden gem? (gem trigger when True Grade ≥ A but Public Grade ≤ B)
///
/// Vaihe 5 surface area uses heuristics over `Player.overall` /
/// `Player.yearsPro` / persisted `PlayerSeasonHistory` because the broader
/// simulation does not yet record per-season awards (Pro Bowl, All-Pro).
/// Once awards are wired in (future work), the heuristics can be replaced
/// with the underlying milestone counts.
@MainActor
enum CareerArcEngine {

    // MARK: - Public entry point

    /// Walks every drafted player and refreshes their `CareerArcState`
    /// and `DraftPickGrade.trueGrade`. Returns gem flashbacks the UI / Inbox
    /// can surface to the player.
    static func evaluateAllDraftedPlayers(
        currentSeason: Int,
        userTeamID: UUID?,
        modelContext: ModelContext
    ) -> [GemFlashback] {
        let playerFetch = FetchDescriptor<Player>(
            predicate: #Predicate { $0.draftPickNumber != nil && $0.yearsPro >= 1 }
        )
        let players = (try? modelContext.fetch(playerFetch)) ?? []

        var flashbacks: [GemFlashback] = []

        for player in players {
            let outcome = evaluate(player: player, currentSeason: currentSeason, modelContext: modelContext)
            if let flashback = outcome.gemFlashback,
               player.teamID == userTeamID {
                flashbacks.append(flashback)
            }
        }

        try? modelContext.save()
        return flashbacks
    }

    // MARK: - Per-player evaluation

    struct EvaluationOutcome {
        let trueGrade: PickGrade?
        let gemFlashback: GemFlashback?
    }

    private static func evaluate(
        player: Player,
        currentSeason: Int,
        modelContext: ModelContext
    ) -> EvaluationOutcome {
        // Locate or create the CareerArcState for this player.
        let pid = player.id
        let stateFetch = FetchDescriptor<CareerArcState>(
            predicate: #Predicate { $0.playerID == pid }
        )
        let state: CareerArcState
        if let existing = (try? modelContext.fetch(stateFetch))?.first {
            state = existing
        } else {
            state = CareerArcState(
                playerID: player.id,
                draftYear: currentSeason - player.yearsPro,
                draftPickNumber: player.draftPickNumber ?? 224
            )
            modelContext.insert(state)
        }

        // Skip if we already evaluated this season — keeps repeated calls idempotent.
        if state.lastEvaluatedSeason == currentSeason {
            return EvaluationOutcome(trueGrade: nil, gemFlashback: nil)
        }

        // Pull season history (oldest → newest)
        let historyFetch = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate { $0.playerID == pid },
            sortBy: [SortDescriptor(\.season)]
        )
        let history = (try? modelContext.fetch(historyFetch)) ?? []

        // Update milestone counters from history.
        // #33: `gamesPlayed` is now a real per-season appearance count, so a
        // healthy player accrues ~17 games whether he starts or rides the bench.
        // A "start season" therefore requires BOTH availability (8+ games, ~half
        // the season) AND starter-caliber play that year (season-end OVR ≥ 75) —
        // otherwise every healthy backup's roster season would count as a start
        // and inflate his True Grade. The OVR gate keeps the heuristic meaningful
        // now that the appearance signal exists.
        state.startSeasons = history.filter { $0.gamesPlayed >= 8 && $0.overallAtEndOfSeason >= 75 }.count

        // Bust event: cut by team before yearsPro 4 (rookie deal usually 4y)
        let isCut = (player.teamID == nil) && player.yearsPro <= 4
        state.cutBeforeContractEnd = isCut

        // Use peak OVR across history as a proxy for awards/Pro-Bowl-track.
        let peakOVR = max(player.overall, history.map(\.overallAtEndOfSeason).max() ?? 0)
        if peakOVR >= 90 {
            // Synthetic Pro Bowl approximation
            state.probowlCount = max(state.probowlCount, 1 + (peakOVR - 90))
        }

        // Compute True Grade.
        let trueGrade = computeTrueGrade(
            player: player,
            peakOVR: peakOVR,
            state: state
        )

        // Persist trueGrade onto the matching DraftPickGrade row.
        let pickGradeFetch = FetchDescriptor<DraftPickGrade>(
            predicate: #Predicate { $0.playerID == pid }
        )
        let pickGrade = (try? modelContext.fetch(pickGradeFetch))?.first

        var flashback: GemFlashback?
        if let pickGrade {
            let previousTrueGrade = pickGrade.trueGrade
            pickGrade.trueGrade = trueGrade

            // Gem trigger: True Grade improved to ≥ A while Public Grade was ≤ B.
            let publicSolidOrLess: Bool = {
                switch pickGrade.publicGrade {
                case .solid, .reach, .bigReach: return true
                default: return false
                }
            }()
            let trueAOrBetter: Bool = {
                switch trueGrade {
                case .smartA, .stealAPlus, .hofTrack: return true
                default: return false
                }
            }()
            let alreadyMarkedGem = pickGrade.isGem
            if publicSolidOrLess && trueAOrBetter && !alreadyMarkedGem {
                pickGrade.isGem = true
                state.currentArcTag = trueGrade == .hofTrack ? .homeRun : .sleeper
                flashback = GemFlashback(
                    playerID: player.id,
                    playerName: "\(player.firstName) \(player.lastName)",
                    publicGrade: pickGrade.publicGrade,
                    trueGrade: trueGrade,
                    draftYear: state.draftYear,
                    draftPickNumber: state.draftPickNumber,
                    season: currentSeason,
                    headline: gemHeadline(player: player, public: pickGrade.publicGrade, true: trueGrade)
                )
            } else if isCut && pickGrade.publicGrade == .stealAPlus && previousTrueGrade != .bigReach {
                // Bust storyline for high-public-grade picks that flopped
                pickGrade.trueGrade = .bigReach
                pickGrade.isBust = true
                state.currentArcTag = .bust
            }
        }

        state.lastEvaluatedSeason = currentSeason
        return EvaluationOutcome(trueGrade: trueGrade, gemFlashback: flashback)
    }

    // MARK: - Heuristics

    private static func computeTrueGrade(
        player: Player,
        peakOVR: Int,
        state: CareerArcState
    ) -> PickGrade {
        // Bust: cut before contract end
        if state.cutBeforeContractEnd { return .bigReach }

        // HOF track: peak OVR ≥ 92 + 3+ start seasons
        if peakOVR >= 92 && state.startSeasons >= 3 { return .hofTrack }

        // A: peak OVR ≥ 85 + 2+ start seasons
        if peakOVR >= 85 && state.startSeasons >= 2 { return .smartA }

        // A+ Steal track: peak OVR ≥ 88
        if peakOVR >= 88 { return .stealAPlus }

        // Solid starter: 3+ start seasons OR peak OVR ≥ 78
        if state.startSeasons >= 3 || peakOVR >= 78 { return .solid }

        // Role player / fringe
        if peakOVR >= 70 { return .reach }

        return .bigReach
    }

    private static func gemHeadline(player: Player, public: PickGrade, true trueGrade: PickGrade) -> String {
        let position = player.position.rawValue
        if trueGrade == .hofTrack {
            return "💎 \(player.firstName) \(player.lastName) (\(position)) is the steal of the decade — pre-draft scouts saw \(`public`.rawValue), now an HOF-track talent."
        }
        return "💎 Hidden Gem: \(player.firstName) \(player.lastName) (\(position)) was a Public \(`public`.rawValue) — now playing like an \(trueGrade.rawValue) pick. GM's bold call paid off."
    }
}

// MARK: - Gem Flashback

/// Surface-able news item for the Inbox / news feed when a drafted player
/// is confirmed as a hidden gem.
struct GemFlashback {
    let playerID: UUID
    let playerName: String
    let publicGrade: PickGrade
    let trueGrade: PickGrade
    let draftYear: Int
    let draftPickNumber: Int
    let season: Int
    let headline: String
}
