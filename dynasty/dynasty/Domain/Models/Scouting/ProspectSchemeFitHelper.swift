import Foundation

/// Shared scheme fit evaluation logic for CollegeProspect.
/// Used by both ProspectDetailView (full section) and row views (compact badge).
enum ProspectSchemeFitHelper {

    /// Evaluate offensive scheme fit. Returns "Good", "Fair", or "Poor".
    static func offensiveFit(prospect: CollegeProspect, scheme: OffensiveScheme) -> String {
        var score = 0
        let physical = prospect.truePhysical

        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            switch scheme {
            case .airRaid, .spread:
                score = (qb.accuracyShort + qb.accuracyDeep + qb.armStrength) / 3
            case .westCoast, .proPassing:
                score = (qb.accuracyShort + qb.accuracyMid + qb.pocketPresence) / 3
            case .powerRun, .shanahan:
                score = (qb.pocketPresence + qb.scrambling + physical.strength) / 3
            case .rpo, .option:
                score = (qb.scrambling + physical.speed + qb.accuracyShort) / 3
            }
        case .wideReceiver(let wr):
            switch scheme {
            case .airRaid, .spread:
                score = (wr.routeRunning + wr.catching + physical.speed) / 3
            case .westCoast, .proPassing:
                score = (wr.routeRunning + wr.catching + wr.release) / 3
            case .powerRun, .shanahan:
                score = (physical.strength + wr.release + physical.speed) / 3
            default:
                score = (wr.routeRunning + wr.catching) / 2
            }
        case .runningBack(let rb):
            switch scheme {
            case .powerRun:
                score = (rb.breakTackle + rb.vision + physical.strength) / 3
            case .shanahan:
                score = (rb.vision + rb.elusiveness + physical.speed) / 3
            case .westCoast, .spread:
                score = (rb.receiving + rb.elusiveness + rb.vision) / 3
            default:
                score = (rb.vision + rb.elusiveness) / 2
            }
        case .offensiveLine(let ol):
            switch scheme {
            case .powerRun:
                score = (ol.runBlock + ol.anchor + physical.strength) / 3
            case .airRaid, .proPassing, .westCoast:
                score = (ol.passBlock + ol.anchor + physical.strength) / 3
            case .shanahan:
                score = (ol.pull + ol.runBlock + physical.agility) / 3
            default:
                score = (ol.runBlock + ol.passBlock) / 2
            }
        case .tightEnd(let te):
            switch scheme {
            case .airRaid, .spread, .westCoast:
                score = (te.catching + te.routeRunning + te.speed) / 3
            case .powerRun, .shanahan:
                score = (te.blocking + te.speed + physical.strength) / 3
            default:
                score = (te.catching + te.blocking) / 2
            }
        default:
            score = 65
        }
        return label(for: score)
    }

    /// Evaluate defensive scheme fit. Returns "Good", "Fair", or "Poor".
    static func defensiveFit(prospect: CollegeProspect, scheme: DefensiveScheme) -> String {
        var score = 0
        let physical = prospect.truePhysical

        switch prospect.truePositionAttributes {
        case .defensiveBack(let db):
            switch scheme {
            case .pressMan:
                score = (db.manCoverage + db.press + physical.speed) / 3
            case .cover3, .tampa2:
                score = (db.zoneCoverage + db.ballSkills + physical.speed) / 3
            case .multiple, .hybrid:
                score = (db.manCoverage + db.zoneCoverage + db.press) / 3
            default:
                score = (db.manCoverage + db.zoneCoverage) / 2
            }
        case .linebacker(let lb):
            switch scheme {
            case .base34:
                score = (lb.tackling + lb.blitzing + physical.strength) / 3
            case .base43:
                score = (lb.tackling + lb.zoneCoverage + physical.speed) / 3
            case .tampa2:
                score = (lb.zoneCoverage + physical.speed + lb.tackling) / 3
            case .cover3:
                score = (lb.zoneCoverage + lb.tackling + physical.speed) / 3
            default:
                score = (lb.tackling + lb.zoneCoverage) / 2
            }
        case .defensiveLine(let dl):
            switch scheme {
            case .base43:
                score = (dl.passRush + dl.powerMoves + physical.strength) / 3
            case .base34:
                score = (dl.blockShedding + dl.powerMoves + physical.strength) / 3
            case .multiple, .hybrid:
                score = (dl.passRush + dl.finesseMoves + physical.agility) / 3
            default:
                score = (dl.passRush + dl.blockShedding) / 2
            }
        default:
            score = 65
        }
        return label(for: score)
    }

    private static func label(for score: Int) -> String {
        switch score {
        case 75...:  return "Good"
        case 55..<75: return "Fair"
        default:      return "Poor"
        }
    }
}
