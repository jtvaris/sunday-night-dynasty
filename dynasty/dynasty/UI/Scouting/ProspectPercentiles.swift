import Foundation

// MARK: - Population-Based Percentile Pools
//
// "What did he run, relative to his position" — computed once per screen off
// the class the screen is showing, then asked per cell.
//
// This lived at the bottom of `CombineResultsView.swift`, next to the table
// that grew it, which meant every other surface that wanted a percentile
// (`ProspectColumns`' Physical block, and through it the Big Board and the two
// batch-selection lists) depended on a 1600-line view file for a value type.
// Pure move — the arithmetic is unchanged.

/// Identifies a combine drill for percentile lookup.
enum DrillKind: Hashable {
    case forty, bench, vertical, broad, threeCone, shuttle

    /// True if a lower value is better (timed drills).
    var lowerIsBetter: Bool {
        switch self {
        case .forty, .threeCone, .shuttle: return true
        case .bench, .vertical, .broad:    return false
        }
    }
}

/// Percentile pools per (position, drill) computed from the combine invitee population.
/// Same value within the same pool always produces the same percentile.
/// Best in pool ~= 99th percentile, median ~= 50th, worst ~= 1st.
struct PercentilePools {
    /// Sorted (ascending) values per position+drill.
    private var pools: [PoolKey: [Double]]

    private struct PoolKey: Hashable {
        let position: Position
        let drill: DrillKind
    }

    var isEmpty: Bool { pools.isEmpty }

    init() {
        self.pools = [:]
    }

    init(prospects: [CollegeProspect]) {
        var collected: [PoolKey: [Double]] = [:]
        for prospect in prospects {
            let pos = prospect.position
            if let v = prospect.fortyTime {
                collected[PoolKey(position: pos, drill: .forty), default: []].append(v)
            }
            if let v = prospect.benchPress {
                collected[PoolKey(position: pos, drill: .bench), default: []].append(Double(v))
            }
            if let v = prospect.verticalJump {
                collected[PoolKey(position: pos, drill: .vertical), default: []].append(v)
            }
            if let v = prospect.broadJump {
                collected[PoolKey(position: pos, drill: .broad), default: []].append(Double(v))
            }
            if let v = prospect.coneDrill {
                collected[PoolKey(position: pos, drill: .threeCone), default: []].append(v)
            }
            if let v = prospect.shuttleTime {
                collected[PoolKey(position: pos, drill: .shuttle), default: []].append(v)
            }
        }
        // Sort each pool ascending for binary-search percentile.
        for key in collected.keys {
            collected[key]?.sort()
        }
        self.pools = collected
    }

    /// Population-based percentile for `value` within position+drill pool.
    /// Returns 1-99 with ties producing the same percentile.
    /// - Best value in pool ~= 99
    /// - Median ~= 50
    /// - Worst value ~= 1
    func percentile(value: Double, drill: DrillKind, position: Position) -> Int {
        let key = PoolKey(position: position, drill: drill)
        guard let pool = pools[key], !pool.isEmpty else { return 50 }
        let n = pool.count
        if n == 1 { return 99 }

        // Count strictly worse (so all ties get the same percentile).
        let countWorse: Int
        if drill.lowerIsBetter {
            // Worse = larger value
            countWorse = pool.filter { $0 > value }.count
        } else {
            countWorse = pool.filter { $0 < value }.count
        }

        // Map [0, n-1] → [1, 99]; best (countWorse == n-1) → 99, worst → 1.
        // Use rank-fraction so two prospects with the same value get the same percentile.
        let pct = Int(round(Double(countWorse) / Double(n - 1) * 98.0)) + 1
        return max(1, min(99, pct))
    }
}
