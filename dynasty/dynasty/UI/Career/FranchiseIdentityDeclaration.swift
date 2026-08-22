import Foundation

// MARK: - FranchiseIdentityDeclaration
//
// F-56. The user declares a franchise identity at career creation, and that
// declaration is what the other 31 front offices price him against
// (`TradeValueEngine.FranchiseIdentityRegistry`).
//
// ## Why this file exists, and why it adds no screen
//
// A live QA pass found the identity already declared in THREE places before any
// of this was wired:
//
//   1. the portrait picker, which names twenty GM archetypes;
//   2. the career's coaching STYLE, which carries a real +10 modifier and is
//      visible on the staff screen;
//   3. the introductory press conference, whose own recap says the media read it
//      builds "shapes free-agent interest".
//
// A fourth picker would have been the wrong answer to that. The ruling is that
// the identity is DECLARED, not surfaced — and the user already declares it
// twice. So this file is a mapping and two call sites, not a screen:
//
//   * `CoachingStyle` (NewCareerView, step 3) is the SEED. It is the choice made
//     in the office, before anybody is listening.
//   * The introductory press conference's dominant `ResponseTone` is the
//     AMENDMENT. It is the first thing the league actually hears him say, and
//     when it says something about how he does business it overrules the seed.
//
// The portrait is deliberately NOT a channel. `NewCareerView` already tells the
// user so in as many words ("The portrait is yours alone — your coaching style
// and your press answers are what the league reads"), and that sentence is a
// promise this file keeps rather than a disclaimer it contradicts.
//
// ## The two properties the ruling requires
//
// **A prior, not a fact.** Nothing here is permanent. `TradeReputationRegistry`
// — which already exists, engine-side — records the chart ratio of every deal
// the user actually executes and every lowball he actually sends, and the
// league's read moves off the declaration from the first trade onward. Declare
// yourself a value hunter and then overpay twice and you are priced as a
// spender. This file supplies the seed and nothing more; it deliberately holds
// no update path of its own, because the update path is what the user DOES.
//
// **No identity may be strictly best.** The four identities are the four
// `GMArchetype`s, whose levers already point in different directions — see
// `TradeValueEngine.FranchiseIdentity`'s own note. Restated from the user's
// chair, and derived below rather than retyped so the screens cannot drift from
// the engine:
//
//   | identity      | asking premium | contact appetite | net                        |
//   |---------------|----------------|------------------|----------------------------|
//   | analytics     | 1.20 (highest) | 0.88 (lowest)    | charges most, called least  |
//   | oldSchool     | 1.16           | 1.00             | charges well, discounts picks |
//   | balanced      | 1.12           | 1.05             | no edge in either direction |
//   | aggressive    | 1.08 (lowest)  | 1.15 (highest)   | charges least, called most   |
//
// The two levers are anti-correlated by construction, which is what makes the
// choice a trade rather than a ladder. The coaching bonus rides along on a third
// axis entirely (+10 to five different coach attributes), so no bundle of
// (style, identity) dominates another either — and the strongest-reading
// coaching bonus, the Tactician's play-calling, is paired with the most
// restrictive market identity on purpose.
//
// ## Career scope
//
// `FranchiseIdentityRegistry` writes through `CareerScopedDefaults.scopedKey`,
// which resolves against `WeekAdvancer.activeCareerID`. Both call sites below
// run BEFORE `CareerShellView` binds the engine, so `TeamSelectionView` binds it
// itself immediately after the league is inserted — see the note there.

/// Maps the two declarations the user already makes onto the market identity the
/// league prices him against.
enum FranchiseIdentityDeclaration {

    typealias Identity = TradeValueEngine.FranchiseIdentity

    // MARK: - The mapping

    /// The identity a coaching style seeds.
    ///
    /// Five styles onto four identities, so one pair shares. `tactician` and
    /// `innovator` both land on `.analytics` because both are men who believe
    /// their own process over the market's: the film-room coach and the
    /// unconventional one charge retail for their own evaluations for the same
    /// reason. `TradeValueEngine.FranchiseIdentity` anticipates exactly this —
    /// "a fifth identity would map onto the nearest archetype rather than
    /// needing a fifth set of constants".
    static func seed(for style: CoachingStyle) -> Identity {
        switch style {
        case .disciplinarian: return .oldSchool
        case .playersCoach:   return .balanced
        case .tactician:      return .analytics
        case .innovator:      return .analytics
        case .motivator:      return .aggressive
        }
    }

    /// What the room takes away from the introductory press conference, or `nil`
    /// when the dominant tone says nothing about how this man does business.
    ///
    /// Three tones carry a market read and two do not, and the two that do not
    /// are the point: **every** new GM sounds confident at his own introduction,
    /// and a man who makes the room laugh has told it nothing about what he will
    /// charge for a cornerback. If the podium always overruled the office, the
    /// coaching style would stop being a declaration at all.
    static func podiumRead(for tone: ResponseTone) -> Identity? {
        switch tone {
        case .aggressive: return .aggressive   // "if the man wins us games, we pay for him"
        case .humble:     return .analytics    // the measured builder who will not pay retail
        case .diplomatic: return .balanced     // fair value both ways, no games
        case .confident:  return nil
        case .funny:      return nil
        }
    }

    // MARK: - Call sites

    /// Records the seed. Called once, from `TeamSelectionView.startCareer`, after
    /// the career is bound.
    @discardableResult
    static func declare(style: CoachingStyle, teamID: UUID) -> Identity {
        let identity = seed(for: style)
        TradeValueEngine.FranchiseIdentityRegistry.set(identity, for: teamID)
        return identity
    }

    /// Applies the podium's amendment, if it has one, and returns the identity
    /// the league is left holding. Called once, from
    /// `IntroSequenceView.applyPressConferenceResult`.
    ///
    /// A tone with no market read leaves the seed exactly where it was rather
    /// than clearing it — silence is not a retraction.
    @discardableResult
    static func amend(tone: ResponseTone, teamID: UUID) -> Identity? {
        if let read = podiumRead(for: tone) {
            TradeValueEngine.FranchiseIdentityRegistry.set(read, for: teamID)
            return read
        }
        return TradeValueEngine.FranchiseIdentityRegistry.identity(for: teamID)
    }

    // MARK: - Copy
    //
    // Every number below is DERIVED from the engine constant it describes, never
    // retyped. §2.13's arithmetic gate: the sentence on the career-creation card
    // and the multiplier the market applies are the same number by construction.

    /// The asking premium as a percentage above chart value, e.g. `"16%"`.
    static func askText(_ identity: Identity) -> String {
        percent(identity.archetype.askingPremium - 1.0)
    }

    /// How the identity moves incoming call volume, e.g. `"+15%"` / `"-12%"`.
    static func callVolumeText(_ identity: Identity) -> String {
        signedPercent(identity.contactAppetite - 1.0)
    }

    /// The one line the coaching-style card prints under its gameplay effect —
    /// what choosing this style says to the other 31 front offices.
    static func frontOfficeLine(for style: CoachingStyle) -> String {
        let identity = seed(for: style)
        return "Front office: \(shortRead(identity))"
    }

    /// What this identity BUYS, in the user's own market.
    static func buysLine(_ identity: Identity) -> String {
        switch identity {
        case .oldSchool:
            return "Your own men carry a \(askText(identity)) premium — the league pays up to pry one loose."
        case .balanced:
            return "Nothing is priced against you. The league takes your calls at the ordinary rate."
        case .analytics:
            return "The steepest ask in the league at \(askText(identity)), and draft capital is credited in full."
        case .aggressive:
            return "The busiest phone in the league: \(callVolumeText(identity)) incoming offers."
        }
    }

    /// What this identity COSTS. There is always one — that is the ruling.
    static func costsLine(_ identity: Identity) -> String {
        switch identity {
        case .oldSchool:
            return "You discount draft capital, so a pile of picks never adds up to the man you want."
        case .balanced:
            return "And nothing is priced for you either. No edge in any direction."
        case .analytics:
            return "A front office known to charge retail gets phoned least: \(callVolumeText(identity)) incoming offers."
        case .aggressive:
            return "The softest ask in the league at \(askText(identity)). Everyone knows they can move you."
        }
    }

    /// The league's read, phrased as a headline for the press-conference recap.
    static func leagueReadHeadline(_ identity: Identity) -> String {
        switch identity {
        case .oldSchool:  return "The league files you as an old-school football man"
        case .balanced:   return "The league files you as a straight dealer"
        case .analytics:  return "The league files you as a value hunter"
        case .aggressive: return "The league files you as a buyer"
        }
    }

    /// The standing caveat that keeps the declaration a PRIOR. Printed wherever
    /// the identity is shown, because a label the user believes is permanent is
    /// exactly the costless disguise D1 exists to remove.
    static let priorCaveat =
        "That is only where they start. Every trade you make moves the read — declare yourself a value hunter and then outbid the market twice, and the league will price you as a spender."

    // MARK: - Private

    /// Half-sentence used inside `frontOfficeLine`.
    private static func shortRead(_ identity: Identity) -> String {
        switch identity {
        case .oldSchool:  return "trusts its own board — charges \(askText(identity)) for its men, discounts picks"
        case .balanced:   return "fair value both ways — \(askText(identity)) ask, no edge either direction"
        case .analytics:  return "charges retail at \(askText(identity)) — and the phone rings \(callVolumeText(identity))"
        case .aggressive: return "calls first and often (\(callVolumeText(identity))) — but asks only \(askText(identity))"
        }
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static func signedPercent(_ fraction: Double) -> String {
        let points = Int((fraction * 100).rounded())
        return points >= 0 ? "+\(points)%" : "\(points)%"
    }
}
