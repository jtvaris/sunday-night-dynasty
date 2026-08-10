import SwiftUI

// MARK: - Letter Grade Colors
//
// THE grade colour. One language for every letter the app prints.
//
// This lived as `PositionGradeCalculator.gradeColorForLetter` inside
// `RosterView.swift`, which is why a dozen screens that had no business
// importing the roster's grade calculator wrote their own `switch` instead —
// and every one of them disagreed. It sits beside `Color.forRating(_:scale:)`
// now, the numeric half of the same palette, because a letter and the OVR it
// was derived from must never argue on the same row.

extension Color {

    /// The colour for a letter grade.
    ///
    ///     A+        eliteGreen
    ///     A / A-    success      (green)
    ///     B+/B/B-   accentBlue   (blue)
    ///     C+/C/C-   warning      (yellow)
    ///     D+/D/D-   alertOrange  (orange)
    ///     F         danger       (red)
    ///
    /// Plus/minus variants deliberately share the letter's colour — the tier is
    /// the thing being read across a 350-row board, and six hues plus twelve
    /// shades is not a scale anybody can scan. `A+` is the one exception, and it
    /// is the same exception `Color.forRating` makes for the 90+ band.
    ///
    /// `D` used to fall through to `.danger` with `F`, which said a back-end
    /// roster player and an undraftable one are the same verdict. The ladder has
    /// six rungs now (`Color.alertOrange`), so it does not.
    ///
    /// Anything that tints a letter grade goes THROUGH here. There is no second
    /// mapping to keep in step, and a per-view `switch` on `"A"`/`"B"` prefixes
    /// is the bug this function exists to prevent — the strings the engine
    /// writes include `"D-"`, which `LetterGrade` has no case for, so a bespoke
    /// switch tends to drop it into whatever its `default` is.
    static func forGrade(_ grade: String) -> Color {
        if grade == "A+" { return .eliteGreen }
        if grade.hasPrefix("A") { return .success }
        if grade.hasPrefix("B") { return .accentBlue }
        if grade.hasPrefix("C") { return .warning }
        if grade.hasPrefix("D") { return .alertOrange }
        return .danger
    }

    /// The colour for a typed letter grade. Same ladder, no string round-trip at
    /// the call site.
    static func forGrade(_ grade: LetterGrade) -> Color {
        forGrade(grade.rawValue)
    }

    /// The colour for a scouted BAND, taken at its midpoint — the read every
    /// prospect table prints a range with ("C+/A-" tinted by the `B+` in the
    /// middle of it).
    static func forGrade(_ band: GradeRange) -> Color {
        forGrade(band.midGrade.rawValue)
    }
}

// MARK: - Semantic Status Colors
//
// UI_REDESIGN_VISION §1 P7, rule 2. The rating ladder (`Color.forRating`) is
// only allowed to touch 0–100 player/prospect quantities. Everything else that
// still needs a verdict — a contract with one year left, a vacant coordinator
// chair, a seed outside the playoff picture — is *status at a stated
// threshold*, and it gets the status palette instead.
//
// The palette is `DSStatusPill.Tone`, deliberately, so a pill and a number that
// mean the same thing on the same row cannot disagree. This function exists so
// a call site reads `Color.forStatus(.warn)` next to `Color.forRating(ovr)`
// rather than reaching into a view component for its nested enum.
//
// The THRESHOLD stays at the call site. That is not laziness: "3+ contract
// years is comfortable" and "seeds 1–7 make the tournament" are league rules,
// not palette decisions, and burying them here would make one shared function
// that silently means five different things.

extension Color {

    /// The colour for a semantic status. Five verdicts, one palette, shared
    /// with `DSStatusPill`.
    ///
    ///     .ok       success      (green)
    ///     .warn     alertOrange  (orange)
    ///     .bad      danger       (red)
    ///     .info     accentBlue   (blue)
    ///     .neutral  textSecondary
    static func forStatus(_ tone: DSStatusPill.Tone) -> Color {
        tone.tint
    }
}
