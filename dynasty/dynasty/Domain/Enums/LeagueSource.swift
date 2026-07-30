import Foundation

/// Where a new career's league comes from — the choice the new-career flow
/// makes before the team picker (`docs/REALISTIC_LEAGUE_PLAN.md` §6).
///
/// Two of the three sources are **fixed templates**: a career started from one
/// replays the exact same pre-calibrated 2026 league every time, because the
/// template file carries final, pre-solved ratings and every random decision in
/// `LeagueTemplateImporter` is seeded from `template.globalSeed`. The third is
/// the classic random path, whose behaviour is untouched by this feature.
///
/// The raw values are persisted on `Career.leagueSourceRaw`, so they are part
/// of the save format — rename a case and old careers lose their provenance.
enum LeagueSource: String, CaseIterable, Identifiable, Hashable {

    /// The classic path: `LeagueGenerator.generate` rolls 32 fresh rosters, a
    /// different league every career. Unchanged default behaviour.
    case generated

    /// `league_2026_publish.json` — the fixed February-2026 snapshot that ships
    /// in every build (fictional players and nicknames, real team strengths).
    case fixed2026

    /// `league_2026_dev.json` — the same fixed league with the development
    /// naming set. Bundled in DEBUG builds only and never offered in Release.
    case fixed2026Dev

    var id: String { rawValue }

    // MARK: - Template binding

    /// The template profile this source imports, `nil` for the random path.
    var templateProfile: LeagueTemplate.Profile? {
        switch self {
        case .generated:    return nil
        case .fixed2026:    return .publish
        case .fixed2026Dev: return .dev
        }
    }

    /// Whether starting this source means importing a fixed template.
    var isTemplate: Bool { templateProfile != nil }

    // MARK: - Availability

    /// Sources this build can actually offer, in picker order.
    ///
    /// Release drops `.fixed2026Dev` (its file is excluded from the product and
    /// the loader refuses the profile); a DEBUG build that is missing the dev
    /// JSON degrades the same way instead of offering a dead option.
    static var available: [LeagueSource] { allCases.filter { $0.isAvailable } }

    /// Whether this source can be started in this build.
    var isAvailable: Bool {
        guard let profile = templateProfile else { return true }
        #if !DEBUG
        // Belt and braces: the loader already refuses `.dev` outside DEBUG.
        if profile == .dev { return false }
        #endif
        return LeagueTemplateLoader.isAvailable(profile)
    }

    // MARK: - Presentation

    var displayName: String {
        switch self {
        case .generated:    return "Generated"
        case .fixed2026:    return LeagueTemplate.Profile.publish.displayName
        case .fixed2026Dev: return LeagueTemplate.Profile.dev.displayName
        }
    }

    /// One-line description shown under the option in the picker.
    var blurb: String {
        switch self {
        case .generated:
            return "A fresh random league every career — 32 newly rolled rosters and staffs."
        case .fixed2026:
            return "The fixed 2026 league: real team strengths, records and traded picks, identical in every career."
        case .fixed2026Dev:
            return "Debug builds only: the same fixed 2026 league with development names and full stat histories."
        }
    }

    var icon: String {
        switch self {
        case .generated:    return "dice.fill"
        case .fixed2026:    return "calendar.badge.clock"
        case .fixed2026Dev: return "hammer.fill"
        }
    }

    /// Short badge for the option card.
    var badge: String {
        switch self {
        case .generated:    return "RANDOM"
        case .fixed2026:    return "FIXED"
        case .fixed2026Dev: return "DEBUG"
        }
    }

    /// Label for the one-line setup recap on the confirmation screen.
    var summaryLabel: String {
        switch self {
        case .generated:    return "Generated League"
        case .fixed2026:    return "Fixed 2026 League"
        case .fixed2026Dev: return "Fixed 2026 League (Dev)"
        }
    }
}
