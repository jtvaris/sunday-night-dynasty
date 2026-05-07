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
        attachments: [MessageAttachment] = []
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

    var displayName: String {
        switch self {
        case .owner(let name):                  return name
        case .offensiveCoordinator(let name):   return name
        case .defensiveCoordinator(let name):   return name
        case .scout(let name):                  return name
        case .media(let outlet):                return outlet
        case .leagueOffice:                     return "League Office"
        case .playerAgent(let name):            return name
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
        case .leagueOffice:             return "NFL"
        case .playerAgent:              return "Agent"
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

    func matches(_ message: InboxMessage) -> Bool {
        switch self {
        case .all:
            return true
        case .actionRequired:
            return message.actionRequired
        case .unread:
            return !message.isRead
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
        case .trainingPlan:         return "Training Plan"
        case .workloadDashboard:    return "Workload"
        case .rosterCuts:           return "Roster Cuts"
        case .gameWeekPrep:         return "Game Plan"
        }
    }
}
