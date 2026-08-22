import Foundation

// MARK: - SchemeInstallForecast
//
// F-65. What changing a scheme actually costs, priced BEFORE the user commits.
//
// The tax itself is real, correctly shaped, and on the DO NOT TOUCH list: a
// switch costs roughly a season of scheme fit, takes ~1.6 seasons to reach the
// fit pivot and ~3.7 to reach the completion pivot. Nothing here moves any of
// that. The defect F-65 names is narrower and entirely a UI one — the picker
// presented a switch as free and instant, with **no preview at all**, and then
// dismissed itself.
//
// ## Every number here is computed by the engine, not restated from it
//
// The one rule this file follows is that it may not re-derive a formula. So:
//
//   * the fit numbers come from `CoachingEngine.rosterSchemeFit` itself, called
//     twice per starter — once with the schemes the building installs today and
//     once with the candidate substituted on the relevant side. The delta is
//     therefore the engine's own arithmetic, in the engine's own units, and it
//     cannot drift from what the simulator reads;
//   * the learning rate comes from `VersatilityDevelopmentEngine.learnScheme`
//     itself, at the install-year intensity the engine will actually use;
//   * the pivots, the decay and the install bonus are read off the engine
//     constants rather than typed in.
//
// ## The one approximation, stated plainly
//
// `learnScheme` returns probabilistically-rounded Int points, so a single call
// is 0 or 1 and tells you nothing. `probabilisticPoints` is unbiased — its
// expectation IS the underlying rate — so the rate is recovered by sampling and
// averaging (`rateSamples` below). The season projection then multiplies that
// rate by the practice weeks in a season.
//
// That projection is deliberately an OVER-estimate of one season and is labelled
// "≈" everywhere it is shown, because `learnScheme` scales its gain by
// `headroom = (100 − F)/100` and the headroom shrinks as the room learns. It is
// not corrected here, because correcting it would mean re-implementing the
// headroom term in the UI — exactly the duplication this file exists to avoid.
// A forecast that is honestly labelled and slightly optimistic is the right
// error: it never talks a user out of a switch by overstating the bill.

/// A priced preview of one scheme change, for `SchemeSelectionView`.
struct SchemeInstallForecast {

    /// Practice weeks a season of installing gets.
    ///
    /// The in-season development pass runs `learnScheme` once per player per
    /// week advance (`WeekAdvancer`), across an 18-week regular season, and camp
    /// adds the preseason block on top. 18 is the conservative read: it counts
    /// the in-season reps only and leaves camp out, so the forecast under-counts
    /// cycles while the flat headroom over-counts the rate, and the two errors
    /// point in opposite directions.
    static let practiceWeeksPerSeason = 18

    /// How many times `learnScheme` is sampled per player to recover its
    /// underlying rate from the probabilistic rounding. 32 puts the standard
    /// error of the mean under a tenth of a point per player, which is well
    /// inside the rounding of the number that is eventually shown.
    static let rateSamples = 32

    // MARK: - Measured

    /// Average familiarity the starters already have with the CANDIDATE scheme.
    let familiarityAfter: Int
    /// Average familiarity they have with the scheme installed today.
    let familiarityNow: Int
    /// Average `rosterSchemeFit` across the starters as things stand, 0-100.
    let fitNow: Int
    /// The same average with the candidate scheme installed instead, 0-100.
    let fitAfter: Int
    /// Familiarity points a season of install-year practice buys, approximately.
    let pointsPerSeason: Int
    /// Starters the forecast was measured over. Zero means "no read".
    let starterCount: Int

    // MARK: - Derived

    /// Scheme-fit points the switch costs on day one. Negative means it helps.
    var fitCost: Int { fitNow - fitAfter }

    /// True when the candidate is what the building already runs.
    var isNoChange: Bool { familiarityAfter == familiarityNow && fitCost == 0 }

    /// Seasons of install-year practice before the room reaches
    /// `CoachingEngine.schemeFitFamiliarityPivot` — the point at which the
    /// playbook term stops docking scheme fit and starts adding to it.
    ///
    /// `nil` when the room is already there, or when the rate is too low for the
    /// projection to mean anything (a coordinator who cannot teach the system he
    /// was just handed).
    var seasonsToPivot: Double? {
        let pivot = Int(CoachingEngine.schemeFitFamiliarityPivot)
        guard familiarityAfter < pivot else { return nil }
        guard pointsPerSeason >= 1 else { return nil }
        return Double(pivot - familiarityAfter) / Double(pointsPerSeason)
    }

    /// The headline cost line. One sentence, in the units the simulator reads.
    var costHeadline: String {
        guard starterCount > 0 else { return "No starters on this side of the ball to measure." }
        if isNoChange { return "Already installed. Nothing changes." }
        if fitCost <= 0 {
            return "Scheme fit \(fitNow)% \u{2192} \(fitAfter)% \u{2014} this room is a better match for it than for what you run now."
        }
        return "Scheme fit \(fitNow)% \u{2192} \(fitAfter)%, a \(fitCost)-point drop your starters carry into every snap of next season."
    }

    /// The install curve, in one sentence.
    var curveLine: String {
        guard starterCount > 0, !isNoChange else { return "" }
        let pivot = Int(CoachingEngine.schemeFitFamiliarityPivot)
        guard let seasons = seasonsToPivot else {
            return "The room already knows it at \(familiarityAfter)% \u{2014} at or above the \(pivot)% pivot, so there is no install year to sit through."
        }
        let rounded = (seasons * 10).rounded() / 10
        return "The room starts at \(familiarityAfter)% and learns \u{2248}\(pointsPerSeason) points a season while installing \u{2014} \u{2248}\(Self.formatted(rounded)) season\(rounded == 1.0 ? "" : "s") to clear the \(pivot)% pivot where the playbook stops costing you."
    }

    /// What happens to the system you are walking away from.
    var abandonedLine: String {
        "The playbook you leave behind decays \(VersatilityDevelopmentEngine.unusedSchemeDecayPerOffseason) points an offseason down to a floor of \(VersatilityDevelopmentEngine.unusedSchemeFloor)% \u{2014} rusty, not forgotten, if you ever hire that coordinator back."
    }

    /// The one thing working in the user's favour, so the panel is a price and
    /// not a scolding.
    var installYearLine: String {
        let bonus = Int(((VersatilityDevelopmentEngine.schemeInstallIntensityBonus - 1.0) * 100).rounded())
        return "An install year is not wasted: camp and every in-season practice teach \(bonus)% harder until the system is in."
    }

    // MARK: - Build

    /// Prices one candidate scheme against the roster and staff on hand.
    ///
    /// - Parameters:
    ///   - candidateOffense / candidateDefense: exactly one is non-nil — the
    ///     side being changed. The other side is held at what the building runs.
    ///   - currentOffense / currentDefense: what is installed today.
    ///   - players: the club's roster.
    ///   - coordinator: the man who would teach it. His expertise in the
    ///     candidate system is the single biggest term in the learning rate,
    ///     which is why the forecast is per-coordinator and not per-scheme.
    static func price(
        candidateOffense: OffensiveScheme?,
        candidateDefense: DefensiveScheme?,
        currentOffense: OffensiveScheme?,
        currentDefense: DefensiveScheme?,
        players: [Player],
        coordinator: Coach?
    ) -> SchemeInstallForecast {
        let side: PositionSide = candidateOffense != nil ? .offense : .defense
        let candidateKey = candidateOffense?.rawValue ?? candidateDefense?.rawValue ?? ""
        let currentKey = side == .offense
            ? (currentOffense?.rawValue ?? "")
            : (currentDefense?.rawValue ?? "")

        // The same top-11-by-OVR starter set `rosterFamiliarity` already uses,
        // so the two readings on one row cannot disagree (§2.13's arithmetic
        // gate). A scheme is installed for the people who play, not the 87 men
        // on an offseason roster.
        let starters = Array(
            players
                .filter { $0.position.side == side && !$0.isRetired }
                .sorted { $0.overall > $1.overall }
                .prefix(11)
        )
        guard !starters.isEmpty else {
            return SchemeInstallForecast(
                familiarityAfter: 0, familiarityNow: 0,
                fitNow: 0, fitAfter: 0, pointsPerSeason: 0, starterCount: 0
            )
        }

        let famAfter = mean(starters.map { $0.schemeFam(for: candidateKey) })
        let famNow = currentKey.isEmpty ? 0 : mean(starters.map { $0.schemeFam(for: currentKey) })

        // Both fit readings come out of `CoachingEngine`, which is the only
        // place that knows how a trait edge and a playbook term combine.
        let fitNowRaw = starters.map {
            CoachingEngine.rosterSchemeFit(
                player: $0,
                offensiveScheme: currentOffense,
                defensiveScheme: currentDefense
            )
        }
        let fitAfterRaw = starters.map {
            CoachingEngine.rosterSchemeFit(
                player: $0,
                offensiveScheme: side == .offense ? candidateOffense : currentOffense,
                defensiveScheme: side == .defense ? candidateDefense : currentDefense
            )
        }

        return SchemeInstallForecast(
            familiarityAfter: famAfter,
            familiarityNow: famNow,
            fitNow: percentPoints(fitNowRaw),
            fitAfter: percentPoints(fitAfterRaw),
            pointsPerSeason: seasonGain(
                starters: starters, scheme: candidateKey, coordinator: coordinator
            ),
            starterCount: starters.count
        )
    }

    // MARK: - Private

    /// Familiarity points a season of install-year practice buys the average
    /// starter, recovered from `learnScheme` by sampling (see the file note).
    private static func seasonGain(
        starters: [Player], scheme: String, coordinator: Coach?
    ) -> Int {
        guard !starters.isEmpty, !scheme.isEmpty else { return 0 }
        // The intensity the engine will actually use next season: the in-season
        // practice value (0.5), lifted by the install-year bonus, exactly as
        // `WeekAdvancer` composes it for a club whose `schemeInstallSeason`
        // matches.
        let intensity = 0.5 * VersatilityDevelopmentEngine.schemeInstallIntensityBonus
        var total = 0.0
        for player in starters {
            var points = 0
            for _ in 0..<rateSamples {
                points += VersatilityDevelopmentEngine.learnScheme(
                    player: player,
                    scheme: scheme,
                    coordinator: coordinator,
                    practiceIntensity: intensity
                )
            }
            total += Double(points) / Double(rateSamples)
        }
        let perWeek = total / Double(starters.count)
        return max(0, Int((perWeek * Double(practiceWeeksPerSeason)).rounded()))
    }

    private static func mean(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }

    /// `rosterSchemeFit` reports a 0.05…0.95 fraction; the screen speaks in
    /// whole percentage points like every other 0-100 reading on it.
    private static func percentPoints(_ values: [Double]) -> Int {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return Int((mean * 100).rounded())
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
