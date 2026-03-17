import Foundation

struct TradeOffer: Codable, Identifiable {
    var id: UUID
    var offeringTeamID: UUID
    var receivingTeamID: UUID
    var picksSending: [UUID]
    var picksReceiving: [UUID]
    var playersSending: [UUID]
    var playersReceiving: [UUID]
    var isAccepted: Bool?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        offeringTeamID: UUID,
        receivingTeamID: UUID,
        picksSending: [UUID] = [],
        picksReceiving: [UUID] = [],
        playersSending: [UUID] = [],
        playersReceiving: [UUID] = [],
        isAccepted: Bool? = nil
    ) {
        self.id = id
        self.offeringTeamID = offeringTeamID
        self.receivingTeamID = receivingTeamID
        self.picksSending = picksSending
        self.picksReceiving = picksReceiving
        self.playersSending = playersSending
        self.playersReceiving = playersReceiving
        self.isAccepted = isAccepted
    }
}
