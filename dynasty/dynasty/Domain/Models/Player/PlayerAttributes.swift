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
}

struct WRAttributes: Codable, Equatable {
    var routeRunning: Int
    var catching: Int
    var release: Int
    var spectacularCatch: Int
}

struct RBAttributes: Codable, Equatable {
    var vision: Int
    var elusiveness: Int
    var breakTackle: Int
    var receiving: Int
}

struct TEAttributes: Codable, Equatable {
    var blocking: Int
    var catching: Int
    var routeRunning: Int
    var speed: Int
}

struct OLAttributes: Codable, Equatable {
    var runBlock: Int
    var passBlock: Int
    var pull: Int
    var anchor: Int
}

struct DLAttributes: Codable, Equatable {
    var passRush: Int
    var blockShedding: Int
    var powerMoves: Int
    var finesseMoves: Int
}

struct LBAttributes: Codable, Equatable {
    var tackling: Int
    var zoneCoverage: Int
    var manCoverage: Int
    var blitzing: Int
}

struct DBAttributes: Codable, Equatable {
    var manCoverage: Int
    var zoneCoverage: Int
    var press: Int
    var ballSkills: Int
}

struct KickingAttributes: Codable, Equatable {
    var kickPower: Int
    var kickAccuracy: Int
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
}
