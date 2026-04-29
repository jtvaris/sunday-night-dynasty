import Foundation

// MARK: - Physical Attributes

struct PhysicalAttributes: Codable, Equatable {
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

struct MentalAttributes: Codable, Equatable {
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

struct QBAttributes: Codable, Equatable {
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

struct WRAttributes: Codable, Equatable {
    var routeRunning: Int
    var catching: Int
    var release: Int
    var spectacularCatch: Int

    var overall: Double {
        Double(routeRunning + catching + release + spectacularCatch) / 4.0
    }
}

struct RBAttributes: Codable, Equatable {
    var vision: Int
    var elusiveness: Int
    var breakTackle: Int
    var receiving: Int

    var overall: Double {
        Double(vision + elusiveness + breakTackle + receiving) / 4.0
    }
}

struct TEAttributes: Codable, Equatable {
    var blocking: Int
    var catching: Int
    var routeRunning: Int
    var speed: Int

    var overall: Double {
        Double(blocking + catching + routeRunning + speed) / 4.0
    }
}

struct OLAttributes: Codable, Equatable {
    var runBlock: Int
    var passBlock: Int
    var pull: Int
    var anchor: Int

    var overall: Double {
        Double(runBlock + passBlock + pull + anchor) / 4.0
    }
}

struct DLAttributes: Codable, Equatable {
    var passRush: Int
    var blockShedding: Int
    var powerMoves: Int
    var finesseMoves: Int

    var overall: Double {
        Double(passRush + blockShedding + powerMoves + finesseMoves) / 4.0
    }
}

struct LBAttributes: Codable, Equatable {
    var tackling: Int
    var zoneCoverage: Int
    var manCoverage: Int
    var blitzing: Int

    var overall: Double {
        Double(tackling + zoneCoverage + manCoverage + blitzing) / 4.0
    }
}

struct DBAttributes: Codable, Equatable {
    var manCoverage: Int
    var zoneCoverage: Int
    var press: Int
    var ballSkills: Int

    var overall: Double {
        Double(manCoverage + zoneCoverage + press + ballSkills) / 4.0
    }
}

struct KickingAttributes: Codable, Equatable {
    var kickPower: Int
    var kickAccuracy: Int

    var overall: Double {
        Double(kickPower + kickAccuracy) / 2.0
    }
}

// MARK: - Position Attributes Enum

enum PositionAttributes: Codable, Equatable {
    case quarterback(QBAttributes)
    case wideReceiver(WRAttributes)
    case runningBack(RBAttributes)
    case tightEnd(TEAttributes)
    case offensiveLine(OLAttributes)
    case defensiveLine(DLAttributes)
    case linebacker(LBAttributes)
    case defensiveBack(DBAttributes)
    case kicking(KickingAttributes)

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
        }
    }
}
