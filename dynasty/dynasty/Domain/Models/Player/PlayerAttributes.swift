import Foundation

// MARK: - Physical Attributes

nonisolated struct PhysicalAttributes: Codable, Equatable {
    var speed: Int
    var acceleration: Int
    var strength: Int
    var agility: Int
    var stamina: Int
    var durability: Int

    static func random() -> PhysicalAttributes {
        PhysicalAttributes(
            speed: Int.random(in: 40...99),
            acceleration: Int.random(in: 40...99),
            strength: Int.random(in: 40...99),
            agility: Int.random(in: 40...99),
            stamina: Int.random(in: 40...99),
            durability: Int.random(in: 40...99)
        )
    }

    var average: Double {
        Double(speed + acceleration + strength + agility + stamina + durability) / 6.0
    }
}

// MARK: - Mental Attributes

nonisolated struct MentalAttributes: Codable, Equatable {
    var awareness: Int
    var decisionMaking: Int
    var clutch: Int
    var workEthic: Int
    var coachability: Int
    var leadership: Int

    static func random() -> MentalAttributes {
        MentalAttributes(
            awareness: Int.random(in: 40...99),
            decisionMaking: Int.random(in: 40...99),
            clutch: Int.random(in: 40...99),
            workEthic: Int.random(in: 40...99),
            coachability: Int.random(in: 40...99),
            leadership: Int.random(in: 40...99)
        )
    }

    var average: Double {
        Double(awareness + decisionMaking + clutch + workEthic + coachability + leadership) / 6.0
    }
}

// MARK: - Position-Specific Attributes

nonisolated struct QBAttributes: Codable, Equatable {
    var armStrength: Int
    var accuracyShort: Int
    var accuracyMid: Int
    var accuracyDeep: Int
    var pocketPresence: Int
    var scrambling: Int

    var overall: Double {
        Double(armStrength + accuracyShort + accuracyMid + accuracyDeep + pocketPresence + scrambling) / 6.0
    }
}

nonisolated struct WRAttributes: Codable, Equatable {
    var routeRunning: Int
    var catching: Int
    var release: Int
    var spectacularCatch: Int

    var overall: Double {
        Double(routeRunning + catching + release + spectacularCatch) / 4.0
    }
}

nonisolated struct RBAttributes: Codable, Equatable {
    var vision: Int
    var elusiveness: Int
    var breakTackle: Int
    var receiving: Int

    var overall: Double {
        Double(vision + elusiveness + breakTackle + receiving) / 4.0
    }
}

nonisolated struct TEAttributes: Codable, Equatable {
    var blocking: Int
    var catching: Int
    var routeRunning: Int
    var speed: Int

    var overall: Double {
        Double(blocking + catching + routeRunning + speed) / 4.0
    }
}

nonisolated struct OLAttributes: Codable, Equatable {
    var runBlock: Int
    var passBlock: Int
    var pull: Int
    var anchor: Int

    var overall: Double {
        Double(runBlock + passBlock + pull + anchor) / 4.0
    }
}

nonisolated struct DLAttributes: Codable, Equatable {
    var passRush: Int
    var blockShedding: Int
    var powerMoves: Int
    var finesseMoves: Int

    var overall: Double {
        Double(passRush + blockShedding + powerMoves + finesseMoves) / 4.0
    }
}

nonisolated struct LBAttributes: Codable, Equatable {
    var tackling: Int
    var zoneCoverage: Int
    var manCoverage: Int
    var blitzing: Int

    var overall: Double {
        Double(tackling + zoneCoverage + manCoverage + blitzing) / 4.0
    }
}

nonisolated struct DBAttributes: Codable, Equatable {
    var manCoverage: Int
    var zoneCoverage: Int
    var press: Int
    var ballSkills: Int

    var overall: Double {
        Double(manCoverage + zoneCoverage + press + ballSkills) / 4.0
    }
}

nonisolated struct KickingAttributes: Codable, Equatable {
    var kickPower: Int
    var kickAccuracy: Int

    var overall: Double {
        Double(kickPower + kickAccuracy) / 2.0
    }
}

/// What a long snapper is graded on.
///
/// Deliberately NOT `KickingAttributes`. A snapper reusing the kicker's payload
/// would print PWR / ACC — "Kick Power", "Kick Accuracy" — on the card of a man
/// who never kicks, which is the same mislabelling that would grade a kicker as
/// a guard. The two things a snapper is actually judged on are how fast the ball
/// gets there and where it arrives.
nonisolated struct SnapAttributes: Codable, Equatable {
    /// Ball speed over the fifteen yards to the punter.
    var snapVelocity: Int
    /// Placement — into the hold, or into the punter's hands.
    var snapAccuracy: Int

    var overall: Double {
        Double(snapVelocity + snapAccuracy) / 2.0
    }
}

/// What a holder is graded on: catching whatever the snapper sends him and
/// getting the ball down, upright and laces out, in about 1.3 seconds.
nonisolated struct HoldAttributes: Codable, Equatable {
    /// Fielding the snap clean — high, low or wide.
    var handling: Int
    /// Spot, tilt and laces once it is in his hands.
    var placement: Int

    var overall: Double {
        Double(handling + placement) / 2.0
    }
}

// MARK: - Position Attributes Enum

nonisolated enum PositionAttributes: Codable, Equatable {
    case quarterback(QBAttributes)
    case wideReceiver(WRAttributes)
    case runningBack(RBAttributes)
    case tightEnd(TEAttributes)
    case offensiveLine(OLAttributes)
    case defensiveLine(DLAttributes)
    case linebacker(LBAttributes)
    case defensiveBack(DBAttributes)
    case kicking(KickingAttributes)
    case snapping(SnapAttributes)
    case holding(HoldAttributes)

    /// Average of the position-specific attribute fields (0-99 scale).
    var overall: Double {
        switch self {
        case .quarterback(let a):    return a.overall
        case .wideReceiver(let a):   return a.overall
        case .runningBack(let a):    return a.overall
        case .tightEnd(let a):       return a.overall
        case .offensiveLine(let a):  return a.overall
        case .defensiveLine(let a):  return a.overall
        case .linebacker(let a):     return a.overall
        case .defensiveBack(let a):  return a.overall
        case .kicking(let a):        return a.overall
        case .snapping(let a):       return a.overall
        case .holding(let a):        return a.overall
        }
    }
}
