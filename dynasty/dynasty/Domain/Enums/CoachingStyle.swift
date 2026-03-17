import Foundation

enum CoachingStyle: String, Codable, CaseIterable {
    case tactician
    case playersCoach
    case disciplinarian
    case innovator
    case motivator

    var displayName: String {
        switch self {
        case .tactician:      return "The Tactician"
        case .playersCoach:   return "The Players' Coach"
        case .disciplinarian: return "The Disciplinarian"
        case .innovator:      return "The Innovator"
        case .motivator:      return "The Motivator"
        }
    }

    var description: String {
        switch self {
        case .tactician:
            return "Wins through superior scheme and preparation. Film room warrior."
        case .playersCoach:
            return "Builds relationships and trust. Gets the best out of every player."
        case .disciplinarian:
            return "Old school. Demands excellence. No excuses."
        case .innovator:
            return "Pushes boundaries. Runs unconventional schemes."
        case .motivator:
            return "Inspires greatness. Known for halftime speeches that change games."
        }
    }

    var icon: String {
        switch self {
        case .tactician:      return "brain.head.profile.fill"
        case .playersCoach:   return "person.2.fill"
        case .disciplinarian: return "shield.fill"
        case .innovator:      return "lightbulb.fill"
        case .motivator:      return "flame.fill"
        }
    }

    var bonusAttribute: String {
        switch self {
        case .tactician:      return "Play-Calling"
        case .playersCoach:   return "Player Development"
        case .disciplinarian: return "Team Discipline"
        case .innovator:      return "Adaptability"
        case .motivator:      return "Morale Influence"
        }
    }

    var bonusValue: Int { 10 }
}
