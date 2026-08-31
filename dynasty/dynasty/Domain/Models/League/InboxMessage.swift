import Foundation

// MARK: - Inbox Message Model

/// A message in the coach's inbox, inspired by Football Manager's email system.
/// Messages come from the owner, coordinators, scouts, media, and league office,
/// creating an immersive management experience.
struct InboxMessage: Identifiable, Codable {
    let id: UUID
    let sender: MessageSender
    let subject: String
    let body: String
    /// Human-readable date context, e.g. "Week 1, Season 2026" or "Offseason - Coaching Changes"
    let date: String
    let category: MessageCategory
    let actionRequired: Bool
    let actionDestination: TaskDestination?
    var isRead: Bool
    let attachments: [MessageAttachment]

    // MARK: - Game time
    //
    // `date` is a *display* string baked by `InboxEngine.dateLabel` — one label
    // per phase, so every letter in a batch printed the same coarse text and
    // nothing on the model could say how long ago a letter arrived. These three
    // carry the moment itself. They are optional on purpose: mail written before
    // the stamp existed (and any producer not yet threaded) decodes with `nil`
    // and falls back to `date`, so no save loses its tray.

    /// League week the message was written in, if the producer knew it.
    let sentWeek: Int?
    /// League season the message was written in.
    let sentSeason: Int?
    /// Phase the message was written in.
    let sentPhase: SeasonPhase?

    // MARK: - Tray state

    /// Pinned letters hold the top of the tray regardless of age.
    var isPinned: Bool
    /// Archived letters drop out of every lens except `.archived`.
    var isArchived: Bool
    /// Set once an `actionRequired` letter has been dealt with — either the user
    /// followed its call to action or marked it handled by hand. Reading a letter
    /// is not the same as doing what it asked, which is why `isRead` cannot serve.
    var actionCompleted: Bool

    // MARK: - Replies
    //
    // The tray used to be one-way. Every letter that put a question to the
    // coach could only be read; there was nowhere to answer it and nothing an
    // answer would have moved. These four fields carry the one reply a letter
    // may take, and the receipt of what that reply actually moved.
    //
    // `nil` means "not answered" and that is ALL it means. Nothing reads an
    // unanswered letter as a refusal, a snub, or a negative of any kind — the
    // `PlayerGameStats.measures` principle, "Ask before turning an empty line
    // into a judgement", governs a blank reply exactly as it governs a blank
    // stat line. Only a reply the coach actually sent books anything.

    /// `InboxEngine.ReplyOption.id` of the reply the coach sent.
    var sentReplyID: String?
    /// The reply as it read on the button, stored so an old thread survives a
    /// later copy edit to the catalogue.
    var sentReplyLabel: String?
    /// What the reply moved, in the words the tray showed when it was sent.
    var sentReplyReceipt: String?
    /// League season the reply was sent in. The per-season reply budget in
    /// `InboxEngine.repliesBooked` counts this and nothing else, so a reply to
    /// an unstamped letter from an old save still lands in the right season.
    var repliedSeason: Int?

    /// True when the choice this letter carries is already made, with real
    /// consequences, on another screen — an owner whim is answered in Owner
    /// Relations, where `OwnerPersonaEngine.respond(to:comply:owner:)` books
    /// +3 satisfaction for complying and −4/−5 for defying. Answering it again
    /// in the tray would book one decision twice, so a letter that sets this
    /// gets no reply affordance at all.
    let decisionHandledElsewhere: Bool

    /// Whether this letter's reply has already been sent.
    var hasReplied: Bool { sentReplyID != nil }

    /// Whether this letter is still asking for something.
    var isActionOutstanding: Bool {
        actionRequired && !actionCompleted
    }

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        subject: String,
        body: String,
        date: String,
        category: MessageCategory,
        actionRequired: Bool = false,
        actionDestination: TaskDestination? = nil,
        isRead: Bool = false,
        attachments: [MessageAttachment] = [],
        sentWeek: Int? = nil,
        sentSeason: Int? = nil,
        sentPhase: SeasonPhase? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false,
        actionCompleted: Bool = false,
        sentReplyID: String? = nil,
        sentReplyLabel: String? = nil,
        sentReplyReceipt: String? = nil,
        repliedSeason: Int? = nil,
        decisionHandledElsewhere: Bool = false
    ) {
        self.id = id
        self.sender = sender
        self.subject = subject
        self.body = body
        self.date = date
        self.category = category
        self.actionRequired = actionRequired
        self.actionDestination = actionDestination
        self.isRead = isRead
        self.attachments = attachments
        self.sentWeek = sentWeek
        self.sentSeason = sentSeason
        self.sentPhase = sentPhase
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.actionCompleted = actionCompleted
        self.sentReplyID = sentReplyID
        self.sentReplyLabel = sentReplyLabel
        self.sentReplyReceipt = sentReplyReceipt
        self.repliedSeason = repliedSeason
        self.decisionHandledElsewhere = decisionHandledElsewhere
    }

    // MARK: - Codable
    //
    // Hand-rolled `init(from:)` for ONE reason: `Career.inbox` decodes the whole
    // mailbox with `try?` and returns `[]` on failure, so a synthesized decoder
    // meeting a save written before these keys existed would throw `keyNotFound`
    // and silently erase the user's tray. Every new key is `decodeIfPresent`.

    private enum CodingKeys: String, CodingKey {
        case id, sender, subject, body, date, category
        case actionRequired, actionDestination, isRead, attachments
        case sentWeek, sentSeason, sentPhase
        case isPinned, isArchived, actionCompleted
        case sentReplyID, sentReplyLabel, sentReplyReceipt, repliedSeason
        case decisionHandledElsewhere
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sender = try container.decode(MessageSender.self, forKey: .sender)
        subject = try container.decode(String.self, forKey: .subject)
        body = try container.decode(String.self, forKey: .body)
        date = try container.decode(String.self, forKey: .date)
        category = try container.decode(MessageCategory.self, forKey: .category)
        actionRequired = try container.decode(Bool.self, forKey: .actionRequired)
        actionDestination = try container.decodeIfPresent(TaskDestination.self, forKey: .actionDestination)
        isRead = try container.decode(Bool.self, forKey: .isRead)
        attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments) ?? []
        sentWeek = try container.decodeIfPresent(Int.self, forKey: .sentWeek)
        sentSeason = try container.decodeIfPresent(Int.self, forKey: .sentSeason)
        sentPhase = try container.decodeIfPresent(SeasonPhase.self, forKey: .sentPhase)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        actionCompleted = try container.decodeIfPresent(Bool.self, forKey: .actionCompleted) ?? false
        sentReplyID = try container.decodeIfPresent(String.self, forKey: .sentReplyID)
        sentReplyLabel = try container.decodeIfPresent(String.self, forKey: .sentReplyLabel)
        sentReplyReceipt = try container.decodeIfPresent(String.self, forKey: .sentReplyReceipt)
        repliedSeason = try container.decodeIfPresent(Int.self, forKey: .repliedSeason)
        decisionHandledElsewhere = try container.decodeIfPresent(Bool.self, forKey: .decisionHandledElsewhere) ?? false
    }

    // MARK: - Stamping

    /// A copy of this message stamped with the game time it was written at.
    ///
    /// Lets a producer stamp a whole batch on the way out rather than repeat
    /// three arguments at ninety construction sites.
    func stamped(week: Int, season: Int, phase: SeasonPhase) -> InboxMessage {
        InboxMessage(
            id: id,
            sender: sender,
            subject: subject,
            body: body,
            date: date,
            category: category,
            actionRequired: actionRequired,
            actionDestination: actionDestination,
            isRead: isRead,
            attachments: attachments,
            sentWeek: week,
            sentSeason: season,
            sentPhase: phase,
            isPinned: isPinned,
            isArchived: isArchived,
            actionCompleted: actionCompleted,
            sentReplyID: sentReplyID,
            sentReplyLabel: sentReplyLabel,
            sentReplyReceipt: sentReplyReceipt,
            repliedSeason: repliedSeason,
            decisionHandledElsewhere: decisionHandledElsewhere
        )
    }

    // MARK: - Relative time

    /// Compact, *relative* game time for a list row — "This week", "3 weeks ago",
    /// "Last season", or the phase name inside the current offseason.
    ///
    /// Falls back to the stamped `date` string for any message that carries no
    /// game time, with the redundant "Offseason - " prefix and the current
    /// season's own year trimmed off so the column still reads as one column.
    func timeLabel(currentWeek: Int, currentSeason: Int, currentPhase: SeasonPhase) -> String {
        guard let season = sentSeason, let phase = sentPhase else {
            return Self.compactedFallback(date, currentSeason: currentSeason)
        }

        if season != currentSeason {
            let gap = currentSeason - season
            guard gap > 0 else { return Self.compactedFallback(date, currentSeason: currentSeason) }
            return gap == 1 ? "Last season" : "\(gap) seasons ago"
        }

        // Only the phases that actually count game weeks can express a week gap;
        // the offseason has phases, not weeks, so it names itself instead.
        guard Self.countsGameWeeks(phase), Self.countsGameWeeks(currentPhase),
              let week = sentWeek, week > 0, currentWeek > 0 else {
            return phase.displayName
        }

        let gap = currentWeek - week
        if gap <= 0 { return "This week" }
        if gap == 1 { return "Last week" }
        return "\(gap) weeks ago"
    }

    private static func countsGameWeeks(_ phase: SeasonPhase) -> Bool {
        switch phase {
        case .regularSeason, .tradeDeadline, .playoffs: return true
        default:                                        return false
        }
    }

    /// "Offseason - The Combine, 2026" → "The Combine" in season 2026.
    private static func compactedFallback(_ raw: String, currentSeason: Int) -> String {
        var label = raw
        if label.hasPrefix("Offseason - ") {
            label = String(label.dropFirst("Offseason - ".count))
        }
        for suffix in [", Season \(currentSeason)", ", \(currentSeason)"] where label.hasSuffix(suffix) {
            label = String(label.dropLast(suffix.count))
            break
        }
        return label
    }
}

// MARK: - Message Sender

enum MessageSender: Codable, Equatable {
    case owner(name: String)
    case offensiveCoordinator(name: String)
    case defensiveCoordinator(name: String)
    case scout(name: String)
    case media(outlet: String)
    case leagueOffice
    case playerAgent(name: String)
    case developmentStaff

    var displayName: String {
        switch self {
        case .owner(let name):                  return name
        case .offensiveCoordinator(let name):   return name
        case .defensiveCoordinator(let name):   return name
        case .scout(let name):                  return name
        case .media(let outlet):                return outlet
        case .leagueOffice:                     return "League Office"
        case .playerAgent(let name):            return name
        case .developmentStaff:                 return "Player Development"
        }
    }

    /// SF Symbol for the sender type.
    var icon: String {
        switch self {
        case .owner:                    return "building.2.fill"
        case .offensiveCoordinator:     return "sportscourt.fill"
        case .defensiveCoordinator:     return "shield.lefthalf.filled"
        case .scout:                    return "binoculars.fill"
        case .media:                    return "newspaper.fill"
        case .leagueOffice:             return "building.columns.fill"
        case .playerAgent:              return "briefcase.fill"
        case .developmentStaff:         return "chart.line.uptrend.xyaxis"
        }
    }

    /// Short role label for display beneath the sender name.
    var roleLabel: String {
        switch self {
        case .owner:                    return "Owner"
        case .offensiveCoordinator:     return "Offensive Coordinator"
        case .defensiveCoordinator:     return "Defensive Coordinator"
        case .scout:                    return "Scout"
        case .media:                    return "Media"
        case .leagueOffice:             return "League Office"
        case .playerAgent:              return "Agent"
        case .developmentStaff:         return "Coaching Staff"
        }
    }
}

// MARK: - Message Category

enum MessageCategory: String, Codable, CaseIterable {
    case rosterAnalysis
    case staffUpdate
    case scoutingReport
    case tradeOffer
    case contractRequest
    case mediaRequest
    case ownerDirective
    case leagueNotice
    case playerIssue
    case gamePrep
    case draftPrep

    var displayName: String {
        switch self {
        case .rosterAnalysis:   return "Roster"
        case .staffUpdate:      return "Staff"
        case .scoutingReport:   return "Scouting"
        case .tradeOffer:       return "Trade"
        case .contractRequest:  return "Contract"
        case .mediaRequest:     return "Media"
        case .ownerDirective:   return "Owner"
        case .leagueNotice:     return "League"
        case .playerIssue:      return "Player"
        case .gamePrep:         return "Game Prep"
        case .draftPrep:        return "Draft"
        }
    }
}

// MARK: - Message Attachment

/// An actionable link within a message that navigates to a relevant view.
struct MessageAttachment: Codable, Identifiable {
    let id: UUID
    let title: String
    let destination: TaskDestination

    init(
        id: UUID = UUID(),
        title: String,
        destination: TaskDestination
    ) {
        self.id = id
        self.title = title
        self.destination = destination
    }
}

// MARK: - Inbox Filter

enum InboxFilter: String, CaseIterable {
    case all             = "All"
    case actionRequired  = "Action Required"
    case unread          = "Unread"
    case archived        = "Archived"

    /// R38: localized chip label — the raw value stays the stable identifier.
    var label: String {
        switch self {
        case .all:            return String(localized: "All")
        case .actionRequired: return String(localized: "Action Required")
        case .unread:         return String(localized: "Unread")
        case .archived:       return String(localized: "Archived")
        }
    }

    func matches(_ message: InboxMessage) -> Bool {
        switch self {
        case .all:
            // Archiving is the "not now" gesture: an archived letter leaves the
            // three working lenses and lives only under its own.
            return !message.isArchived
        case .actionRequired:
            // A handled letter drops out of the lens, otherwise the lens can
            // never empty — which was the whole complaint.
            return message.isActionOutstanding && !message.isArchived
        case .unread:
            return !message.isRead && !message.isArchived
        case .archived:
            return message.isArchived
        }
    }
}

// MARK: - Task Destination Display

extension TaskDestination {
    /// Human-readable label suitable for button copy in messages
    /// (e.g. "Open Combine Results →"). Falls back to a formatted version
    /// of the case name for any destinations that don't have a curated label.
    var inboxDisplayName: String {
        switch self {
        case .roster:               return "Roster"
        case .depthChart:           return "Depth Chart"
        case .gamePlan:             return "Game Plan"
        case .schedule:             return "Schedule"
        case .standings:            return "Standings"
        case .coachingStaff:        return "Coaching Staff"
        case .coachingStaffReview:  return "Staff Review"
        case .coordinatorSchemes:   return "Coordinator Schemes"
        case .hireCoach:            return "Hire Coach"
        case .hireHC:               return "Hire Head Coach"
        case .hireOC:               return "Hire Offensive Coordinator"
        case .hireDC:               return "Hire Defensive Coordinator"
        case .scouting:             return "Scouting Hub"
        case .prospectList:         return "Prospect List"
        case .bigBoard:             return "Big Board"
        case .capOverview:          return "Cap Overview"
        case .freeAgency:           return "Free Agency"
        case .contractTimeline:     return "Contract Timeline"
        case .draft:                return "Draft Room"
        case .mentoring:            return "Mentoring"
        case .trades:               return "Trades"
        case .news:                 return "News"
        case .ownerMeeting:         return "Owner Meeting"
        case .lockerRoom:           return "Locker Room"
        case .inbox:                return "Inbox"
        case .rosterEvaluation:     return "Roster Evaluation"
        case .franchiseTag:         return "Franchise Tag"
        case .interviewReport:      return "Interview Report"
        case .personalWorkouts:     return "Personal Workouts"
        // Draft-prep stages (#103)
        case .filmStudy:            return "Film Study"
        case .proDayTour:           return "Pro Day Tour"
        case .workouts:             return "Private Workouts"
        case .top30Visits:          return "Top-30 Visits"
        case .mockDraft:            return "Mock Draft"
        case .classDepth:           return "Class Depth"
        case .developmentReport:    return "Development Report"
        case .history:              return "League History"
        case .draftReportCard:      return "Draft Report Card"
        case .trainingPlan:         return "Training Plan"
        case .workloadDashboard:    return "Workload"
        case .rosterCuts:           return "Roster Cuts"
        case .preseason:            return "Preseason"
        case .gameWeekPrep:         return "Game Plan"
        }
    }
}
