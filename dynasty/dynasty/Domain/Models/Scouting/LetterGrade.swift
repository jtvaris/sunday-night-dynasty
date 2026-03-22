import Foundation

// MARK: - Letter Grade

/// A letter grade used for scouting evaluations of mental, positional, and overall attributes.
/// Physical attributes use NFL-scale numbers (measurable at combine); everything else uses grades.
enum LetterGrade: String, Codable, CaseIterable, Identifiable {
    case aPlus  = "A+"
    case a      = "A"
    case aMinus = "A-"
    case bPlus  = "B+"
    case b      = "B"
    case bMinus = "B-"
    case cPlus  = "C+"
    case c      = "C"
    case cMinus = "C-"
    case dPlus  = "D+"
    case d      = "D"
    case f      = "F"

    var id: String { rawValue }

    /// Numeric rank for comparison (higher = better). A+ = 12, F = 1.
    var rank: Int {
        switch self {
        case .aPlus:  return 12
        case .a:      return 11
        case .aMinus: return 10
        case .bPlus:  return 9
        case .b:      return 8
        case .bMinus: return 7
        case .cPlus:  return 6
        case .c:      return 5
        case .cMinus: return 4
        case .dPlus:  return 3
        case .d:      return 2
        case .f:      return 1
        }
    }

    /// Converts a numeric attribute value (40-99 scale) to a letter grade.
    static func from(numericValue: Int) -> LetterGrade {
        switch numericValue {
        case 95...:   return .aPlus
        case 90..<95: return .a
        case 85..<90: return .aMinus
        case 80..<85: return .bPlus
        case 75..<80: return .b
        case 70..<75: return .bMinus
        case 65..<70: return .cPlus
        case 60..<65: return .c
        case 55..<60: return .cMinus
        case 50..<55: return .dPlus
        case 45..<50: return .d
        default:      return .f
        }
    }

    /// Returns a grade shifted by a number of steps (positive = better, negative = worse).
    func shifted(by steps: Int) -> LetterGrade {
        let all = LetterGrade.allCases
        guard let idx = all.firstIndex(of: self) else { return self }
        let newIdx = max(0, min(all.count - 1, idx - steps)) // allCases is A+ first, so subtract for better
        return all[newIdx]
    }
}

extension LetterGrade: Comparable {
    static func < (lhs: LetterGrade, rhs: LetterGrade) -> Bool {
        lhs.rank < rhs.rank
    }
}

// MARK: - Grade Range

/// Represents a scouting evaluation with progressive confidence.
/// With 1 report the range is wide (e.g. B- to B+); with 3+ it narrows to a single grade.
struct GradeRange: Codable, Equatable {
    var low: LetterGrade
    var high: LetterGrade
    var reportCount: Int

    /// Single-grade range (high confidence).
    init(grade: LetterGrade) {
        self.low = grade
        self.high = grade
        self.reportCount = 3
    }

    /// Range with specified confidence.
    init(low: LetterGrade, high: LetterGrade, reportCount: Int) {
        // Ensure low <= high
        if low.rank > high.rank {
            self.low = high
            self.high = low
        } else {
            self.low = low
            self.high = high
        }
        self.reportCount = reportCount
    }

    /// Display string: "B+" (single) or "B-/B+" (range).
    var displayText: String {
        if low == high { return low.rawValue }
        return "\(low.rawValue)/\(high.rawValue)"
    }

    /// True if the range is narrow enough to be a single grade.
    var isSingleGrade: Bool { low == high }

    /// The midpoint grade of the range.
    var midGrade: LetterGrade {
        let midRank = (low.rank + high.rank) / 2
        return LetterGrade.allCases.min(by: { abs($0.rank - midRank) < abs($1.rank - midRank) }) ?? .c
    }

    /// Narrows the range by incorporating a new grade observation.
    mutating func incorporate(newGrade: LetterGrade) {
        reportCount += 1
        if reportCount >= 3 {
            // High confidence — converge to midpoint of current range and new observation
            let avg = (low.rank + high.rank + newGrade.rank) / 3
            let best = LetterGrade.allCases.min(by: { abs($0.rank - avg) < abs($1.rank - avg) }) ?? .c
            low = best
            high = best
        } else {
            // Medium confidence — tighten range toward new observation
            if newGrade.rank > low.rank { low = low.shifted(by: -1) }  // raise floor
            if newGrade.rank < high.rank { high = high.shifted(by: 1) } // lower ceiling
            // Ensure new grade is within range
            if newGrade < low { low = newGrade }
            if newGrade > high { high = newGrade }
        }
    }
}

// MARK: - Potential Label

/// Verbal assessment of a player's development ceiling. Shown instead of a numeric potential value.
/// Accuracy depends on coaching staff quality and time with team.
enum PotentialLabel: String, Codable, CaseIterable {
    case eliteCeiling   = "Elite Ceiling"
    case highUpside     = "High Upside"
    case solidStarter   = "Solid Starter"
    case average        = "Average"
    case limitedUpside  = "Limited Upside"
    case unknown        = "Unknown"

    /// Converts a numeric potential (40-99) to a label with optional noise.
    /// - Parameters:
    ///   - potential: The true potential value.
    ///   - noise: Number of buckets to potentially shift (+/-). Higher = less accurate.
    static func from(potential: Int, noise: Int = 0) -> PotentialLabel {
        let shifted = potential + Int.random(in: -noise * 8...noise * 8)
        switch shifted {
        case 88...:   return .eliteCeiling
        case 78..<88: return .highUpside
        case 68..<78: return .solidStarter
        case 55..<68: return .average
        default:      return .limitedUpside
        }
    }
}
