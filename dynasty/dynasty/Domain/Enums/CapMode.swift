import Foundation

enum CapMode: String, Codable, CaseIterable {
    case simple    = "Simple"
    case realistic = "Realistic"
    /// Sandbox mode disables all salary-cap restrictions: contracts still exist
    /// for record-keeping but cap room, dead-cap, franchise tag costs, and
    /// salary-floor checks are short-circuited so the player can build any
    /// roster they want without financial constraints.
    case sandbox   = "Sandbox"
}
