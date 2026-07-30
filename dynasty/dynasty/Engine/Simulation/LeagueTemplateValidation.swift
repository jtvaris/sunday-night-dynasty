#if DEBUG
import Foundation
import SwiftData

// MARK: - League Template Validation (phase-3 stage-4 harness)
//
// Two executed checks on a baked league template — not arguments, measurements:
//
//  1. DETERMINISM — the template is imported TWICE, each import inserted into
//     its OWN isolated in-memory `ModelContainer`, both graphs fetched back out
//     and diffed field by field. The contract under test is the one
//     `LeagueTemplateImporter` documents: "two imports of the same template
//     file produce byte-identical leagues". Every field a career actually reads
//     is compared — physical / mental / position attributes, overall,
//     truePotential, learning, competitiveness, morale, contract, personality,
//     biography, scheme + position familiarity — plus teams, the full 16-role
//     staffs, 2026 pick ownership and the imported career history.
//
//  2. ORDERING — team mean OVR of the imported league is ranked against the
//     real 2025 records the template carries, with the acceptance rule from the
//     phase-3 brief: every top-5 2025 team must land in the template's top 10
//     by OVR, every bottom-5 team in the bottom 10. Spearman rho over all 32
//     teams rides along as the continuous measure.
//
// Runs only from the env hook in `ContentView`
// (`SIMCTL_CHILD_LEAGUE_TEMPLATE_VALIDATE=publish simctl launch --console-pty …`)
// and is compiled out of Release entirely.
@MainActor
enum LeagueTemplateValidation {

    // MARK: - Entry point

    /// Runs both checks against `profile` and prints one PASS/FAIL verdict line.
    static func run(profile: LeagueTemplate.Profile) {
        print("TVAL: ===== league template validation — profile=\(profile.rawValue) =====")

        guard LeagueTemplateLoader.isAvailable(profile) else {
            print("TVAL: FAILED — \(profile.resourceName).json is not bundled in this build")
            print("TVAL: ===== verdict: FAIL =====")
            return
        }

        let determinism = checkDeterminism(profile: profile)
        let ordering = checkOrdering(profile: profile)
        // Runs LAST on purpose: it claims faces out of the shared
        // `FaceLibrary` registry, and the determinism check needs a registry
        // nobody has touched (a template import must produce identical faceIDs
        // whether or not another league was built first).
        let faces = checkFaceUniqueness(profile: profile)

        print("TVAL: ===== verdict determinism=\(determinism ? "PASS" : "FAIL") "
              + "ordering=\(ordering ? "PASS" : "FAIL") "
              + "faceUniqueness=\(faces ? "PASS" : "FAIL") =====")
    }

    /// Convenience for the env hook: accepts the raw profile name.
    static func run(profileNamed name: String) {
        guard let profile = LeagueTemplate.Profile(rawValue: name) else {
            print("TVAL: FAILED — unknown profile \"\(name)\" "
                  + "(expected one of \(LeagueTemplate.Profile.allCases.map(\.rawValue).joined(separator: ", ")))")
            return
        }
        run(profile: profile)
    }

    // MARK: - Check 1: determinism

    /// Imports `profile` twice into two isolated in-memory stores and diffs the
    /// two graphs. Returns `true` when nothing differs.
    private static func checkDeterminism(profile: LeagueTemplate.Profile) -> Bool {
        let clock = CFAbsoluteTimeGetCurrent()

        // Each run re-reads AND re-decodes the file, so a non-deterministic
        // decode (dictionary iteration order leaking into the graph) fails here
        // too — not only a non-deterministic importer.
        guard let runA = importRun(profile: profile, label: "A"),
              let runB = importRun(profile: profile, label: "B") else {
            print("TVAL: determinism FAILED — an import run could not be staged")
            return false
        }

        var failures: [String] = []

        // --- Counts -------------------------------------------------------
        func compareCount(_ label: String, _ lhs: Int, _ rhs: Int) {
            if lhs != rhs { failures.append("count \(label): A=\(lhs) B=\(rhs)") }
        }
        compareCount("teams", runA.teams.count, runB.teams.count)
        compareCount("players", runA.players.count, runB.players.count)
        compareCount("coaches", runA.coaches.count, runB.coaches.count)
        compareCount("draftPicks", runA.picks.count, runB.picks.count)
        compareCount("seasonHistory", runA.history.count, runB.history.count)

        // --- Players ------------------------------------------------------
        let playersA = keyedPlayers(runA)
        let playersB = keyedPlayers(runB)
        let keysA = Set(playersA.map(\.key))
        let keysB = Set(playersB.map(\.key))
        if keysA != keysB {
            let onlyA = keysA.subtracting(keysB).sorted().prefix(3)
            let onlyB = keysB.subtracting(keysA).sorted().prefix(3)
            failures.append("player identity set differs "
                            + "(A-only \(keysA.subtracting(keysB).count) e.g. \(Array(onlyA)); "
                            + "B-only \(keysB.subtracting(keysA).count) e.g. \(Array(onlyB)))")
        }

        var playerFieldMismatches: [String: Int] = [:]
        var firstPlayerExample: String?
        let fingerprintsB = Dictionary(
            uniqueKeysWithValues: playersB.map { ($0.key, PlayerFingerprint($0.player)) }
        )
        for entry in playersA {
            guard let other = fingerprintsB[entry.key] else { continue }
            let mine = PlayerFingerprint(entry.player)
            let differing = mine.differences(from: other)
            if !differing.isEmpty {
                for field in differing { playerFieldMismatches[field, default: 0] += 1 }
                if firstPlayerExample == nil {
                    firstPlayerExample = "\(entry.key) → \(differing.joined(separator: ", "))"
                }
            }
        }
        if !playerFieldMismatches.isEmpty {
            let summary = playerFieldMismatches
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { "\($0.key)×\($0.value)" }
                .joined(separator: " ")
            failures.append("player fields differ: \(summary) | first: \(firstPlayerExample ?? "-")")
        }

        // --- Teams --------------------------------------------------------
        let teamsA = Dictionary(uniqueKeysWithValues: runA.teams.map { ($0.abbreviation, TeamFingerprint($0)) })
        let teamsB = Dictionary(uniqueKeysWithValues: runB.teams.map { ($0.abbreviation, TeamFingerprint($0)) })
        var teamMismatches = 0
        var firstTeamExample: String?
        for (abbr, lhs) in teamsA.sorted(by: { $0.key < $1.key }) {
            guard let rhs = teamsB[abbr] else { continue }
            let differing = lhs.differences(from: rhs)
            if !differing.isEmpty {
                teamMismatches += 1
                if firstTeamExample == nil { firstTeamExample = "\(abbr) → \(differing.joined(separator: ", "))" }
            }
        }
        if teamMismatches > 0 {
            failures.append("team fields differ on \(teamMismatches) teams | first: \(firstTeamExample ?? "-")")
        }

        // --- Coaches ------------------------------------------------------
        let coachesA = keyedCoaches(runA)
        let coachesB = keyedCoaches(runB)
        if Set(coachesA.keys) != Set(coachesB.keys) {
            failures.append("coach slot set differs (A=\(coachesA.count) B=\(coachesB.count))")
        }
        var coachMismatches = 0
        var coachFieldMismatches: [String: Int] = [:]
        var firstCoachExample: String?
        for (key, lhs) in coachesA.sorted(by: { $0.key < $1.key }) {
            guard let rhs = coachesB[key] else { continue }
            let differing = lhs.differences(from: rhs)
            if !differing.isEmpty {
                coachMismatches += 1
                for field in differing { coachFieldMismatches[field, default: 0] += 1 }
                if firstCoachExample == nil { firstCoachExample = "\(key) → \(differing.joined(separator: ", "))" }
            }
        }
        if coachMismatches > 0 {
            let summary = coachFieldMismatches
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { "\($0.key)×\($0.value)" }
                .joined(separator: " ")
            failures.append("coach fields differ on \(coachMismatches) slots: \(summary) "
                            + "| first: \(firstCoachExample ?? "-")")
        }

        // --- Draft picks ---------------------------------------------------
        let picksA = pickFingerprints(runA)
        let picksB = pickFingerprints(runB)
        if picksA != picksB {
            let diff = zip(picksA, picksB).first { $0 != $1 }
            failures.append("draft pick ownership differs | first: \(diff.map { "\($0.0) vs \($0.1)" } ?? "count \(picksA.count) vs \(picksB.count)")")
        }

        // --- Career history -------------------------------------------------
        let historyA = historyFingerprints(runA)
        let historyB = historyFingerprints(runB)
        if historyA != historyB {
            let mismatchKeys = Set(historyA.keys).symmetricDifference(Set(historyB.keys))
            if !mismatchKeys.isEmpty {
                failures.append("career-history player set differs (\(mismatchKeys.count) keys)")
            } else {
                let firstDiff = historyA.first { historyB[$0.key] != $0.value }
                failures.append("career-history rows differ | first: \(firstDiff?.key ?? "-")")
            }
        }

        // --- Report ---------------------------------------------------------
        let seconds = CFAbsoluteTimeGetCurrent() - clock
        let historyRows = runA.history.count
        print(String(
            format: "TVAL: determinism scope teams=%d players=%d coaches=%d picks=%d historyRows=%d (%.1f s for 2 imports)",
            runA.teams.count, runA.players.count, runA.coaches.count,
            runA.picks.count, historyRows, seconds
        ))
        // The fields the briefs name explicitly, called out on their own line so
        // the measurement is legible without reading the diff summary. `faceID`
        // is here for the phase-4 reason spelled out in `PlayerFingerprint`: the
        // importer re-mints every person's `UUID`, so a portrait only survives a
        // second import while it comes from the template file. A regression that
        // dropped the baked id would print ~1 800 here instead of 0.
        let named = ["attributes", "truePotential", "learning", "competitiveness", "faceID"]
        let namedHits = named.map { field -> String in
            let count: Int
            switch field {
            case "attributes":
                count = ["physical", "mental", "positionAttributes", "overall"]
                    .reduce(0) { $0 + (playerFieldMismatches[$1] ?? 0) }
            default:
                count = playerFieldMismatches[field] ?? 0
            }
            return "\(field)=\(count)"
        }.joined(separator: " ")
        print("TVAL: determinism player-field mismatches \(namedHits) (0 = identical across both imports)")
        // Coach portraits are baked only for the template's hc/oc/dc; the rest of
        // each 16-role staff is generated and gets its face from
        // `FaceLibrary.backfill` AFTER the import, so this counts the 96 baked
        // slots and must also be 0.
        print("TVAL: determinism coach-field mismatches faceID=\(coachFieldMismatches["faceID"] ?? 0) "
              + "of \(coachesA.count) staff slots")

        if failures.isEmpty {
            print("TVAL: determinism PASS — two imports produced identical leagues")
            return true
        }
        for failure in failures { print("TVAL: determinism FAIL — \(failure)") }
        return false
    }

    // MARK: - Check 2: ordering

    /// Ranks the imported league's teams by mean roster OVR and compares that
    /// ordering to the template's real 2025 records.
    private static func checkOrdering(profile: LeagueTemplate.Profile) -> Bool {
        guard let template = try? LeagueTemplateLoader.load(profile) else {
            print("TVAL: ordering FAILED — template would not load")
            return false
        }
        let imported = LeagueGenerator.generateFromTemplate(template, startYear: template.leagueYear)

        // App abbreviation → template key, so a team can be named the way both
        // sides of the comparison name it.
        var keyByAppAbbr: [String: String] = [:]
        var recordByKey: [String: LeagueTemplate.Record] = [:]
        for team in template.teams {
            keyByAppAbbr[team.identity.appAbbr] = team.identity.key
            recordByKey[team.identity.key] = team.record2025
        }

        // Mean OVR of every rostered player, measured on the IMPORTED graph —
        // i.e. after the attribute solve, not from the template's rating target.
        var meanByKey: [String: Double] = [:]
        for team in imported.teams {
            let roster = imported.players.filter { $0.teamID == team.id }
            guard !roster.isEmpty, let key = keyByAppAbbr[team.abbreviation] else { continue }
            meanByKey[key] = Double(roster.reduce(0) { $0 + $1.overall }) / Double(roster.count)
        }
        guard meanByKey.count == template.teams.count else {
            print("TVAL: ordering FAILED — only \(meanByKey.count)/\(template.teams.count) teams resolved")
            return false
        }

        // OVR ranking, 1 = strongest. Ties broken on team key so the ranking is
        // itself deterministic.
        let ovrOrder = meanByKey.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }
        var ovrRank: [String: Int] = [:]
        for (index, entry) in ovrOrder.enumerated() { ovrRank[entry.key] = index + 1 }

        // Real-2025 ranking: win percentage first (ties count as half a win),
        // then how deep the team actually went in the postseason — the honest
        // tiebreak for "who were the top 5 teams of 2025", since four teams
        // share 12-5 and four share 3-14.
        func winPct(_ record: LeagueTemplate.Record) -> Double {
            let games = Double(record.wins + record.losses + record.ties)
            guard games > 0 else { return 0 }
            return (Double(record.wins) + 0.5 * Double(record.ties)) / games
        }
        let realOrder = recordByKey.sorted { lhs, rhs in
            let (lp, rp) = (winPct(lhs.value), winPct(rhs.value))
            if lp != rp { return lp > rp }
            let (ld, rd) = (playoffDepth(lhs.value), playoffDepth(rhs.value))
            if ld != rd { return ld > rd }
            return lhs.key < rhs.key
        }
        var realRank: [String: Int] = [:]
        for (index, entry) in realOrder.enumerated() { realRank[entry.key] = index + 1 }

        let top5 = realOrder.prefix(5).map(\.key)
        let bottom5 = realOrder.suffix(5).map(\.key)
        let teamCount = realOrder.count
        let topGateLimit = 10
        let bottomGateLimit = teamCount - 9   // rank 23 on a 32-team league

        func describe(_ key: String) -> String {
            let record = recordByKey[key]!
            let tie = record.ties > 0 ? "-\(record.ties)" : ""
            return String(
                format: "%@ %d-%d%@ ovr=%.2f ovrRank=%d",
                key, record.wins, record.losses, tie, meanByKey[key] ?? 0, ovrRank[key] ?? 0
            )
        }

        let topMisses = top5.filter { (ovrRank[$0] ?? 99) > topGateLimit }
        let bottomMisses = bottom5.filter { (ovrRank[$0] ?? 0) < bottomGateLimit }

        print("TVAL: ordering top5-2025   → " + top5.map(describe).joined(separator: " | "))
        print("TVAL: ordering bottom5-2025 → " + bottom5.map(describe).joined(separator: " | "))

        let rho = spearman(realRank: realRank, ovrRank: ovrRank)
        let spread = (ovrOrder.first?.value ?? 0) - (ovrOrder.last?.value ?? 0)
        print(String(
            format: "TVAL: ordering spearman(teamOVR, 2025 record)=%.3f  best=%@ %.2f  worst=%@ %.2f  spread=%.2f OVR",
            rho,
            ovrOrder.first?.key ?? "-", ovrOrder.first?.value ?? 0,
            ovrOrder.last?.key ?? "-", ovrOrder.last?.value ?? 0,
            spread
        ))

        guard topMisses.isEmpty, bottomMisses.isEmpty else {
            if !topMisses.isEmpty {
                print("TVAL: ordering FAIL — top-5 teams outside OVR top \(topGateLimit): "
                      + topMisses.map(describe).joined(separator: ", "))
            }
            if !bottomMisses.isEmpty {
                print("TVAL: ordering FAIL — bottom-5 teams outside OVR bottom 10: "
                      + bottomMisses.map(describe).joined(separator: ", "))
            }
            return false
        }
        print("TVAL: ordering PASS — all top-5 2025 teams inside OVR top \(topGateLimit); "
              + "all bottom-5 inside OVR bottom 10")
        return true
    }

    // MARK: - Check 3: face uniqueness

    /// Phase-4 portrait invariant: **no two ACTIVE persons in one league share
    /// a faceID** — measured on both league sources, each in its own fresh
    /// career registry, exactly the way `TeamSelectionView.startCareer` builds
    /// one (`beginNewCareer` → build the graph → `backfill`).
    ///
    /// Three things are measured, in the order they can fail:
    ///
    /// 1. the ids the transform baked into the template file (unique on their
    ///    own, before the runtime ever runs),
    /// 2. the imported template league after backfill has served the 416
    ///    generated support-staff coaches the transform does not name,
    /// 3. a random league.
    ///
    /// Images are irrelevant here — assignment is a pure function of the
    /// catalog, and the catalog synthesizes from the generator seed when
    /// `faces_manifest.json` has not shipped.
    private static func checkFaceUniqueness(profile: LeagueTemplate.Profile) -> Bool {
        guard let template = try? LeagueTemplateLoader.load(profile) else {
            print("TVAL: faceUniqueness FAILED — template would not load")
            return false
        }

        // The harness has to survive a failure to be able to report it.
        FaceLibrary.debugTrapsOnDuplicateFace = false
        defer { FaceLibrary.debugTrapsOnDuplicateFace = true }

        var failures: [String] = []

        // --- 1. Baked ids, straight off the template file ------------------
        let bakedPlayerIDs = template.teams.flatMap { $0.players.compactMap(\.faceID) }
        let bakedCoachIDs = template.teams.flatMap { team in
            [team.staff.hc, team.staff.oc, team.staff.dc].compactMap { $0?.faceID }
        }
        let bakedAll = bakedPlayerIDs + bakedCoachIDs
        let bakedDistinct = Set(bakedAll).count
        let playersWithoutFace = template.teams.reduce(0) { $0 + $1.players.filter { $0.faceID == nil }.count }
        let bakedReserve = bakedAll.filter(FaceGeneratorConstants.isReserve).count
        // Role correctness, read off the loaded catalog (synthesized or shipped).
        let bakedPlayerRoleMisses = bakedPlayerIDs.filter {
            FaceLibrary.shared.entry(for: $0)?.bucket.role != "player"
        }.count
        let bakedCoachRoleMisses = bakedCoachIDs.filter {
            FaceLibrary.shared.entry(for: $0)?.bucket.role != "coach"
        }.count
        // Gender, measured the same way as role. Everybody in the template is
        // male — the 96 named coaches and the support staff anonymize real male
        // coaches (`docs/ANONYMIZATION_SPEC.md`) — so this MUST read 0.
        //
        // Worth measuring rather than asserting in prose: the female ids live in
        // the same pool the transform draws from (`face_02560+`), and today only
        // `make_templates.py`'s lowest-id-first `_face_take` keeps them out of
        // reach. A re-cut library, a different take order or a culled id band
        // would put a woman's portrait on a baked male coordinator without any
        // other gate noticing.
        let bakedGenderMisses = bakedAll.filter {
            FaceLibrary.shared.entry(for: $0)?.bucket.gender != "male"
        }.count
        print("TVAL: faceUniqueness baked ids=\(bakedAll.count) distinct=\(bakedDistinct) "
              + "playersMissingFace=\(playersWithoutFace) reserveRange=\(bakedReserve) "
              + "roleMismatch=player:\(bakedPlayerRoleMisses)/coach:\(bakedCoachRoleMisses) "
              + "genderMismatch=\(bakedGenderMisses)")
        if bakedDistinct != bakedAll.count {
            failures.append("template bakes \(bakedAll.count - bakedDistinct) duplicate faceIDs")
        }
        if playersWithoutFace > 0 {
            failures.append("\(playersWithoutFace) template players carry no baked faceID")
        }
        if bakedPlayerRoleMisses + bakedCoachRoleMisses > 0 {
            failures.append("\(bakedPlayerRoleMisses + bakedCoachRoleMisses) baked ids sit in the wrong role bucket")
        }
        if bakedGenderMisses > 0 {
            failures.append(
                "\(bakedGenderMisses) baked ids sit in a female bucket — the template is "
                + "all-male by construction"
            )
        }

        // --- 2. Imported template league, after backfill -------------------
        let templateCareer = Career(playerName: "TVAL", role: .gm, capMode: .simple)
        FaceLibrary.shared.beginNewCareer(templateCareer)
        let imported = LeagueGenerator.generateFromTemplate(template, startYear: template.leagueYear)
        FaceLibrary.shared.backfill(players: imported.players, coaches: imported.coaches)
        let templateAudit = FaceLibrary.shared.debugAuditActiveFaces(
            players: imported.players, coaches: imported.coaches,
            label: "template/\(profile.rawValue)"
        )
        if !templateAudit.isUnique {
            failures.append("template league: \(templateAudit.duplicated) people share a portrait")
        }
        // This cannot fire from a gender-constrained nil, and that is a property
        // of the template rather than of the check: every person an imported
        // template creates is male (see the baked-gender count above), so
        // `pickLocked` never reaches its female terminal here — a nil faceID
        // would mean the 3 549-id male pool itself came up empty, which is a real
        // failure. If a future template ever bakes a female coach, this needs to
        // exempt the ones the 35-id female sub-pool cannot cover, exactly like
        // `FaceAudit.isRegression` exempts within-gender duplication.
        if templateAudit.unassigned > 0 {
            failures.append("template league: \(templateAudit.unassigned) active people have no faceID")
        }
        if templateAudit.genderMismatch > 0 {
            failures.append(
                "template league: \(templateAudit.genderMismatch) people wear a portrait of "
                + "the wrong gender"
            )
        }

        // --- 3. Random league ----------------------------------------------
        let randomCareer = Career(playerName: "TVAL", role: .gm, capMode: .simple)
        FaceLibrary.shared.beginNewCareer(randomCareer)
        let random = LeagueGenerator.generate(startYear: template.leagueYear)
        let randomAudit = FaceLibrary.shared.debugAuditActiveFaces(
            players: random.players, coaches: random.coaches, label: "generated"
        )
        // Gender-aware, unlike the template branch above: a random league hires
        // female coaches, and the female sub-pool is 163 ids (35 in the mixed range + 128 female-only) against a binomial
        // draw that averages ~31 of 512 slots (`CoachingEngine.femaleCoachShare`
        // = 0.06). Roughly one league in five therefore lands 36+ female coaches
        // and the picker legitimately hands the 36th a portrait another woman
        // already wears — with `freeFemale == 0`, i.e. exactly the case
        // `FaceAudit.isRegression` exempts.
        //
        // Failing on that would make this gate flap on a capacity limit instead
        // of on a defect, so the failure condition is `isRegression` (a duplicate
        // with a same-gender id still free) and the benign case is reported. The
        // male half keeps full teeth: 2 208 people against 3 549 male ids, so any
        // male duplicate here has free supply and still fails.
        if randomAudit.isRegression {
            failures.append("random league: \(randomAudit.duplicated) people share a portrait "
                            + "with \(randomAudit.free) faces still unused")
        } else if !randomAudit.isUnique {
            print("TVAL: faceUniqueness random league reuses \(randomAudit.duplicated) portrait(s) "
                  + "within gender (freeFemale=\(randomAudit.freeFemale)) — capacity, not a defect")
        }
        if randomAudit.unassigned > 0 {
            // Reachable for real now: a female coach gets `faceID == nil` only if
            // the catalog holds NO female coach face at all (a manifest cut
            // before the female range, or a cull that removed all 35). She then
            // renders the `coach_f*` placeholder — correct behaviour, but a
            // packaging problem worth failing on, which is why this stays a hard
            // failure rather than an exemption.
            failures.append("random league: \(randomAudit.unassigned) active people have no faceID")
        }
        if randomAudit.genderMismatch > 0 {
            failures.append(
                "random league: \(randomAudit.genderMismatch) people wear a portrait of "
                + "the wrong gender"
            )
        }

        // Keep the two throwaway careers alive until the audits are done — the
        // library holds them weakly, and a deallocated career would silently
        // drop the registry writes mid-measurement.
        _ = (templateCareer.id, randomCareer.id)

        if failures.isEmpty {
            print("TVAL: faceUniqueness PASS — every active person in both league "
                  + "sources wears a distinct portrait")
            return true
        }
        for failure in failures { print("TVAL: faceUniqueness FAIL — \(failure)") }
        return false
    }

    /// How far a team went in the 2025 postseason. Only used as the tiebreak
    /// inside a win-percentage group.
    private static func playoffDepth(_ record: LeagueTemplate.Record) -> Int {
        guard record.madePlayoffs == true, let result = record.playoffResult?.lowercased() else { return 0 }
        if result.contains("won super bowl")            { return 5 }
        if result.contains("lost super bowl")           { return 4 }
        if result.contains("conference championship")   { return 3 }
        if result.contains("divisional")                { return 2 }
        if result.contains("wild card")                 { return 1 }
        return 1
    }

    /// Spearman rank correlation between the two rankings.
    private static func spearman(realRank: [String: Int], ovrRank: [String: Int]) -> Double {
        let keys = realRank.keys.filter { ovrRank[$0] != nil }.sorted()
        let n = Double(keys.count)
        guard n > 1 else { return 0 }
        let sumSquaredDiff = keys.reduce(0.0) { total, key in
            let d = Double(realRank[key]! - ovrRank[key]!)
            return total + d * d
        }
        return 1 - (6 * sumSquaredDiff) / (n * (n * n - 1))
    }

    // MARK: - Import staging

    /// One import, round-tripped through its own in-memory SwiftData store.
    private struct ImportRun {
        let label: String
        let teams: [Team]
        let players: [Player]
        let coaches: [Coach]
        let picks: [DraftPick]
        let history: [PlayerSeasonHistory]
        /// Team id → app abbreviation, for building stable identity keys.
        let abbrByTeamID: [UUID: String]
        /// Kept alive so the fetched model objects stay valid.
        let container: ModelContainer
    }

    /// Loads, imports and inserts one league into a fresh in-memory container,
    /// then fetches the whole graph back out of it.
    private static func importRun(profile: LeagueTemplate.Profile, label: String) -> ImportRun? {
        guard let template = try? LeagueTemplateLoader.load(profile) else {
            print("TVAL: import \(label) FAILED — template would not load")
            return nil
        }
        let imported = LeagueGenerator.generateFromTemplate(template, startYear: template.leagueYear)

        let schema = Schema([
            Career.self, League.self, Team.self, Player.self, Owner.self,
            Coach.self, Game.self, Contract.self,
            Scout.self, CollegeProspect.self, DraftPick.self, DraftEvent.self,
            DraftPickGrade.self, DraftReputation.self, CareerArcState.self,
            PlayerSeasonHistory.self, FABid.self, FAVisit.self,
            FAStorylineEvent.self, Holdout.self, TrainingPlan.self,
            WorkloadEvent.self, PositionBattle.self, RosterCut.self,
            OpponentPrepWeek.self, VoluntaryWorkout.self, HardKnocksEvent.self,
            TradeRecord.self, TeamSeasonArchive.self,
        ])
        guard let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ) else {
            print("TVAL: import \(label) FAILED — could not create in-memory container")
            return nil
        }
        let context = container.mainContext
        // No `Career` row exists in this isolated store, but every row still
        // gets a careerID so the "no unscoped row may ever be persisted"
        // invariant holds here too.
        let syntheticCareerID = UUID()
        CareerScope.stamp(imported.league, careerID: syntheticCareerID)
        CareerScope.stamp(imported.teams, careerID: syntheticCareerID)
        CareerScope.stamp(imported.players, careerID: syntheticCareerID)
        CareerScope.stamp(imported.owners, careerID: syntheticCareerID)
        CareerScope.stamp(imported.coaches, careerID: syntheticCareerID)
        CareerScope.stamp(imported.draftPicks, careerID: syntheticCareerID)
        CareerScope.stamp(imported.seasonHistory, careerID: syntheticCareerID)
        context.insert(imported.league)
        imported.teams.forEach { context.insert($0) }
        imported.players.forEach { context.insert($0) }
        imported.owners.forEach { context.insert($0) }
        imported.coaches.forEach { context.insert($0) }
        imported.draftPicks.forEach { context.insert($0) }
        imported.seasonHistory.forEach { context.insert($0) }
        try? context.save()

        let teams = (try? context.fetch(FetchDescriptor<Team>())) ?? []
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        let coaches = (try? context.fetch(FetchDescriptor<Coach>())) ?? []
        let picks = (try? context.fetch(FetchDescriptor<DraftPick>())) ?? []
        let history = (try? context.fetch(FetchDescriptor<PlayerSeasonHistory>())) ?? []

        return ImportRun(
            label: label,
            teams: teams,
            players: players,
            coaches: coaches,
            picks: picks,
            history: history,
            abbrByTeamID: Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.abbreviation) }),
            container: container
        )
    }

    // MARK: - Stable identity keys
    //
    // Model `id`s are fresh UUIDs on every import by design, so nothing can be
    // matched on them. Every key below is built from content the template
    // determines, sorted first so the occurrence counter that disambiguates a
    // repeated name is itself order-independent.

    private static func keyedPlayers(_ run: ImportRun) -> [(key: String, player: Player)] {
        let sorted = run.players.sorted { lhs, rhs in
            let la = run.abbrByTeamID[lhs.teamID ?? UUID()] ?? "--"
            let ra = run.abbrByTeamID[rhs.teamID ?? UUID()] ?? "--"
            if la != ra { return la < ra }
            if lhs.position.rawValue != rhs.position.rawValue { return lhs.position.rawValue < rhs.position.rawValue }
            if lhs.lastName != rhs.lastName { return lhs.lastName < rhs.lastName }
            if lhs.firstName != rhs.firstName { return lhs.firstName < rhs.firstName }
            if lhs.overall != rhs.overall { return lhs.overall > rhs.overall }
            return (lhs.jerseyNumber ?? -1) < (rhs.jerseyNumber ?? -1)
        }
        var seen: [String: Int] = [:]
        return sorted.map { player in
            let abbr = run.abbrByTeamID[player.teamID ?? UUID()] ?? "--"
            let base = "\(abbr)|\(player.position.rawValue)|\(player.lastName),\(player.firstName)"
            let index = seen[base, default: 0]
            seen[base] = index + 1
            return (index == 0 ? base : "\(base)~\(index)", player)
        }
    }

    private static func keyedCoaches(_ run: ImportRun) -> [String: CoachFingerprint] {
        var result: [String: CoachFingerprint] = [:]
        var seen: [String: Int] = [:]
        for coach in run.coaches.sorted(by: { ($0.role.rawValue, $0.lastName) < ($1.role.rawValue, $1.lastName) }) {
            let abbr = coach.teamID.flatMap { run.abbrByTeamID[$0] } ?? "FA"
            let base = "\(abbr)|\(coach.role.rawValue)"
            let index = seen[base, default: 0]
            seen[base] = index + 1
            result[index == 0 ? base : "\(base)~\(index)"] = CoachFingerprint(coach)
        }
        return result
    }

    private static func pickFingerprints(_ run: ImportRun) -> [String] {
        run.picks
            .map { pick in
                let origin = run.abbrByTeamID[pick.originalTeamID] ?? "?"
                let owner = run.abbrByTeamID[pick.currentTeamID] ?? "?"
                return "r\(pick.round)p\(pick.pickNumber):\(origin)→\(owner)"
            }
            .sorted()
    }

    /// Player key → the compact string form of his whole imported career.
    private static func historyFingerprints(_ run: ImportRun) -> [String: String] {
        var keyByPlayerID: [UUID: String] = [:]
        for entry in keyedPlayers(run) { keyByPlayerID[entry.player.id] = entry.key }

        var rowsByPlayer: [String: [String]] = [:]
        for row in run.history {
            guard let key = keyByPlayerID[row.playerID] else { continue }
            let team = row.teamID.flatMap { run.abbrByTeamID[$0] } ?? "-"
            // The statline is part of the fingerprint on purpose: the publish
            // profile's per-season stats are SYNTHESIZED at import
            // (`SeasonStatSynthesizer`), so any non-deterministic draw shows up
            // here rather than shipping a league that differs run to run.
            let line = row.statLine
            let post = row.postStatLine
            rowsByPlayer[key, default: []].append(
                "\(row.season):\(row.overallAtEndOfSeason):\(row.gamesPlayed)/\(row.gamesStarted)"
                + ":\(row.ageAtEndOfSeason):\(team):\(row.positionRaw)"
                + ":\(row.keyStat1)/\(row.keyStat2)/\(row.keyStat3)"
                + ":\(line.passYards)/\(line.passTDs)/\(line.passInts)"
                + ":\(line.rushYards)/\(line.rushTDs)"
                + ":\(line.receptions)/\(line.recYards)/\(line.recTDs)"
                + ":\(line.tackles)/\(line.sacks)/\(line.defInts)/\(line.passesDefended)"
                + ":\(line.fieldGoalsMade)/\(line.fieldGoalsAttempted)"
                + ":\(line.punts)/\(line.puntAverage)/\(line.snapsPlayed)"
                + ":\(row.statsAreSynthesized)"
                // #20: the postseason columns are inside the gate too. They are
                // folded from the template rather than drawn, so a difference here
                // means the IMPORT moved (a dropped `post` bag, a changed key
                // mapping) — precisely what this check exists to catch.
                + "|p\(row.postGamesPlayed)"
                + ":\(post.passYards)/\(post.passTDs)/\(post.passInts)"
                + ":\(post.rushYards)/\(post.rushTDs)"
                + ":\(post.receptions)/\(post.recYards)/\(post.recTDs)"
                + ":\(post.tackles)/\(post.sacks)/\(post.defInts)/\(post.passesDefended)"
                + ":\(post.fieldGoalsMade)/\(post.fieldGoalsAttempted)"
                + ":\(post.punts)/\(post.puntAverage)/\(post.snapsPlayed)"
                + ":\(row.postStatsAreSynthesized)"
            )
        }
        return rowsByPlayer.mapValues { $0.sorted().joined(separator: " ") }
    }

    // MARK: - Fingerprints

    /// Every player field a career reads that the importer is responsible for.
    private struct PlayerFingerprint {
        let overall: Int
        let physical: PhysicalAttributes
        let mental: MentalAttributes
        let positionAttributes: PositionAttributes
        let truePotential: Int
        let draftTruePotential: Int
        let learning: Int
        let competitiveness: Int
        let morale: Int
        let personality: PlayerPersonality
        let annualSalary: Int
        let contractYearsRemaining: Int
        let age: Int
        let yearsPro: Int
        let jerseyNumber: Int?
        let college: String?
        let heightInches: Int?
        let weightPounds: Int?
        let draftPickNumber: Int?
        let draftRound: Int?
        let draftSeason: Int?
        let schemeFamiliarity: [String: Int]
        let positionFamiliarity: [String: Int]
        /// Phase-4 portrait. In the fingerprint because the runtime picker
        /// hashes the player's `UUID` — which the importer re-mints on every
        /// import — so this field only stays stable while it comes from the
        /// template. A regression that dropped the baked id would show up here
        /// as ~1 800 `faceID` mismatches.
        let faceID: String?

        init(_ player: Player) {
            overall = player.overall
            physical = player.physical
            mental = player.mental
            positionAttributes = player.positionAttributes
            truePotential = player.truePotential
            draftTruePotential = player.draftTruePotential
            learning = player.learning
            competitiveness = player.competitiveness
            morale = player.morale
            personality = player.personality
            annualSalary = player.annualSalary
            contractYearsRemaining = player.contractYearsRemaining
            age = player.age
            yearsPro = player.yearsPro
            jerseyNumber = player.jerseyNumber
            college = player.college
            heightInches = player.heightInches
            weightPounds = player.weightPounds
            draftPickNumber = player.draftPickNumber
            draftRound = player.draftRound
            draftSeason = player.draftSeason
            schemeFamiliarity = player.schemeFamiliarity
            positionFamiliarity = player.positionFamiliarity
            faceID = player.faceID
        }

        func differences(from other: PlayerFingerprint) -> [String] {
            var fields: [String] = []
            if overall != other.overall                         { fields.append("overall") }
            if physical != other.physical                       { fields.append("physical") }
            if mental != other.mental                           { fields.append("mental") }
            if positionAttributes != other.positionAttributes   { fields.append("positionAttributes") }
            if truePotential != other.truePotential             { fields.append("truePotential") }
            if draftTruePotential != other.draftTruePotential   { fields.append("draftTruePotential") }
            if learning != other.learning                       { fields.append("learning") }
            if competitiveness != other.competitiveness         { fields.append("competitiveness") }
            if morale != other.morale                           { fields.append("morale") }
            if personality != other.personality                 { fields.append("personality") }
            if annualSalary != other.annualSalary               { fields.append("annualSalary") }
            if contractYearsRemaining != other.contractYearsRemaining { fields.append("contractYears") }
            if age != other.age                                 { fields.append("age") }
            if yearsPro != other.yearsPro                       { fields.append("yearsPro") }
            if jerseyNumber != other.jerseyNumber               { fields.append("jersey") }
            if college != other.college                         { fields.append("college") }
            if heightInches != other.heightInches               { fields.append("height") }
            if weightPounds != other.weightPounds               { fields.append("weight") }
            if draftPickNumber != other.draftPickNumber         { fields.append("draftPick") }
            if draftRound != other.draftRound                   { fields.append("draftRound") }
            if draftSeason != other.draftSeason                 { fields.append("draftSeason") }
            if schemeFamiliarity != other.schemeFamiliarity     { fields.append("schemeFamiliarity") }
            if positionFamiliarity != other.positionFamiliarity { fields.append("positionFamiliarity") }
            if faceID != other.faceID                           { fields.append("faceID") }
            return fields
        }
    }

    private struct TeamFingerprint {
        let name: String
        let city: String
        let conference: Conference
        let division: Division
        let lastSeasonWins: Int
        let lastSeasonLosses: Int
        let capUsage: Int
        let rosterCount: Int

        init(_ team: Team) {
            name = team.name
            city = team.city
            conference = team.conference
            division = team.division
            lastSeasonWins = team.lastSeasonWins
            lastSeasonLosses = team.lastSeasonLosses
            capUsage = team.currentCapUsage
            // S3: counted by `teamID` query, not the creation-time
            // `Team.players` relationship (see its doc). Identical right after
            // an import; correct forever after.
            rosterCount = team.currentRoster().count
        }

        func differences(from other: TeamFingerprint) -> [String] {
            var fields: [String] = []
            if name != other.name                           { fields.append("name") }
            if city != other.city                           { fields.append("city") }
            if conference != other.conference               { fields.append("conference") }
            if division != other.division                   { fields.append("division") }
            if lastSeasonWins != other.lastSeasonWins       { fields.append("lastSeasonWins") }
            if lastSeasonLosses != other.lastSeasonLosses   { fields.append("lastSeasonLosses") }
            if capUsage != other.capUsage                   { fields.append("capUsage") }
            if rosterCount != other.rosterCount             { fields.append("rosterCount") }
            return fields
        }
    }

    private struct CoachFingerprint {
        let name: String
        let age: Int
        let offensiveScheme: OffensiveScheme?
        let defensiveScheme: DefensiveScheme?
        let ratings: [Int]
        let salary: Int
        let hireSeasonYear: Int
        let schemeExpertise: [String: Int]
        let personality: PersonalityArchetype
        /// Baked for the template's hc/oc/dc, `nil` for the generated support
        /// staff (which `FaceLibrary.backfill` serves after the import).
        let faceID: String?

        init(_ coach: Coach) {
            name = coach.fullName
            age = coach.age
            offensiveScheme = coach.offensiveScheme
            defensiveScheme = coach.defensiveScheme
            ratings = [
                coach.playCalling, coach.playerDevelopment, coach.reputation,
                coach.adaptability, coach.gamePlanning, coach.scoutingAbility,
                coach.recruiting, coach.motivation, coach.discipline,
                coach.mediaHandling, coach.contractNegotiation, coach.moraleInfluence,
                coach.potential, coach.yearsExperience,
            ]
            salary = coach.salary
            hireSeasonYear = coach.hireSeasonYear
            schemeExpertise = coach.schemeExpertise
            personality = coach.personality
            faceID = coach.faceID
        }

        func differences(from other: CoachFingerprint) -> [String] {
            var fields: [String] = []
            if name != other.name                           { fields.append("name") }
            if age != other.age                             { fields.append("age") }
            if offensiveScheme != other.offensiveScheme     { fields.append("offScheme") }
            if defensiveScheme != other.defensiveScheme     { fields.append("defScheme") }
            if ratings != other.ratings                     { fields.append("ratings") }
            if salary != other.salary                       { fields.append("salary") }
            if hireSeasonYear != other.hireSeasonYear       { fields.append("hireSeasonYear") }
            if schemeExpertise != other.schemeExpertise     { fields.append("schemeExpertise") }
            if personality != other.personality             { fields.append("personality") }
            if faceID != other.faceID                       { fields.append("faceID") }
            return fields
        }
    }
}
#endif
