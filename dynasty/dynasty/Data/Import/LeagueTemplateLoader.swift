import Foundation

/// Reads a baked league template out of the app bundle.
///
/// ## Bundling contract (`docs/ANONYMIZATION_SPEC.md` §6.1)
///
/// Both templates are copies of the transform tool's output
/// (`tools/league-data/out/`) placed in `dynasty/dynasty/Resources/`, which the
/// target picks up through its file-system-synchronized root group — re-copy
/// them whenever `make_templates.py` is re-run. The dev template must never
/// reach a shipped product, which is enforced on **two independent levels**:
///
/// 1. **Build level (the one that matters).** The Release build configuration
///    sets `EXCLUDED_SOURCE_FILE_NAMES = league_2026_dev.json`, so the file is
///    filtered out of the target's file list before the Resources phase runs.
///    The bytes are not in a Release `.app` at all — verified by building
///    `-configuration Release` and listing the product.
/// 2. **Source level.** Everything that can name the dev profile is inside
///    `#if DEBUG`, so a Release binary contains no code path that could load
///    it even if a file somehow appeared next to the executable.
enum LeagueTemplateLoader {

    // MARK: - Errors

    enum LoadError: LocalizedError {
        case notBundled(LeagueTemplate.Profile)
        case unreadable(LeagueTemplate.Profile, underlying: Error)
        case malformed(LeagueTemplate.Profile, underlying: Error)
        case profileMismatch(expected: LeagueTemplate.Profile, found: LeagueTemplate.Profile)

        var errorDescription: String? {
            switch self {
            case .notBundled(let profile):
                return "League template \"\(profile.resourceName).json\" is not bundled in this build."
            case .unreadable(let profile, let underlying):
                return "Could not read league template \"\(profile.resourceName).json\": \(underlying.localizedDescription)"
            case .malformed(let profile, let underlying):
                return "League template \"\(profile.resourceName).json\" is malformed: \(underlying)"
            case .profileMismatch(let expected, let found):
                return "League template mismatch: asked for \(expected.rawValue), file declares \(found.rawValue)."
            }
        }
    }

    // MARK: - Availability

    /// Profiles this build can actually offer in the new-career league picker.
    ///
    /// Release ships exactly one; DEBUG offers the dev profile as well, and only
    /// when its file really is in the bundle (so a stripped local build degrades
    /// to the publish template instead of crashing).
    static var availableProfiles: [LeagueTemplate.Profile] {
        LeagueTemplate.Profile.allCases.filter(isAvailable)
    }

    /// Whether `profile` is loadable in this build.
    static func isAvailable(_ profile: LeagueTemplate.Profile) -> Bool {
        #if !DEBUG
        // Release: the dev profile is not bundled and must never be named.
        if profile == .dev { return false }
        #endif
        return url(for: profile) != nil
    }

    // MARK: - Loading

    /// Decodes the bundled template for `profile`.
    ///
    /// The whole file is read at once (1.5 MB publish / 2.6 MB dev) and decoded
    /// on the calling thread — it runs once, behind the career-creation spinner.
    static func load(_ profile: LeagueTemplate.Profile) throws -> LeagueTemplate {
        #if !DEBUG
        if profile == .dev { throw LoadError.notBundled(profile) }
        #endif

        guard let url = url(for: profile) else {
            throw LoadError.notBundled(profile)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw LoadError.unreadable(profile, underlying: error)
        }

        let template: LeagueTemplate
        do {
            template = try JSONDecoder().decode(LeagueTemplate.self, from: data)
        } catch {
            throw LoadError.malformed(profile, underlying: error)
        }

        guard template.profile == profile else {
            throw LoadError.profileMismatch(expected: profile, found: template.profile)
        }
        return template
    }

    /// The publish template, which every build is guaranteed to carry.
    static func loadPublish() throws -> LeagueTemplate {
        try load(.publish)
    }

    // MARK: - Resource lookup

    /// Bundle URL for a profile's JSON, `nil` when it is not in this product.
    ///
    /// The synchronized group flattens `dynasty/Resources/*` into the bundle
    /// root (verified against a built `.app`), so the flat lookup is the one
    /// that fires; the subdirectory probe is a cheap guard in case the files are
    /// ever moved into a nested folder, the way `Resources/Audio` already is.
    private static func url(for profile: LeagueTemplate.Profile) -> URL? {
        Bundle.main.url(forResource: profile.resourceName, withExtension: "json")
            ?? Bundle.main.url(forResource: profile.resourceName, withExtension: "json", subdirectory: "League")
    }
}
