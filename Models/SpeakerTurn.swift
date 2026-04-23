import Foundation

struct SpeakerTurn: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let speakerID: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    init(
        id: UUID = UUID(),
        speakerID: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) {
        self.id = id
        self.speakerID = speakerID
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}
