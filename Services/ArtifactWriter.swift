import Foundation

struct ArtifactTokenTiming: Codable, Hashable, Sendable {
    let token: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
}

struct ArtifactDiarizationSegment: Codable, Hashable, Sendable {
    let rawSpeakerID: String
    let speakerLabel: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let qualityScore: Float
}

struct TranscriptionArtifactPayload: Codable, Sendable {
    let runID: UUID
    let sourcePath: String
    let createdAt: Date
    let duration: TimeInterval?
    let userReportedSpeakerCount: Int?
    let detectedSpeakerCount: Int
    let plainTranscript: String
    let speakerTurns: [SpeakerTurn]
    let tokenTimings: [ArtifactTokenTiming]
}

struct DiarizationArtifactPayload: Codable, Sendable {
    let runID: UUID
    let sourcePath: String
    let createdAt: Date
    let detectedSpeakerCount: Int
    let segments: [ArtifactDiarizationSegment]
}

struct ArtifactWriter {
    private let fileAccess: FileAccess
    private let encoder: JSONEncoder

    init(fileAccess: FileAccess = FileAccess()) {
        self.fileAccess = fileAccess

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func artifactLocations(for sourceURL: URL, in parentDirectory: URL? = nil) throws -> ArtifactLocations {
        try fileAccess.artifactLocations(for: sourceURL, in: parentDirectory)
    }

    func writeArtifacts(
        run: RunRecord,
        content: StoredRunContent,
        destinationDirectory: URL? = nil
    ) throws -> [RunArtifact] {
        let locations = try fileAccess.artifactLocations(for: run.sourceURL, in: destinationDirectory)

        try content.plainTranscript.write(to: locations.plainTranscript, atomically: true, encoding: .utf8)
        try speakerTranscript(from: content.speakerTurns).write(
            to: locations.speakerTranscript,
            atomically: true,
            encoding: .utf8
        )

        let transcriptionPayload = TranscriptionArtifactPayload(
            runID: run.id,
            sourcePath: run.sourcePath,
            createdAt: run.createdAt,
            duration: run.duration,
            userReportedSpeakerCount: run.userReportedSpeakerCount,
            detectedSpeakerCount: run.detectedSpeakerCount ?? 0,
            plainTranscript: content.plainTranscript,
            speakerTurns: content.speakerTurns,
            tokenTimings: content.tokenTimings
        )

        let diarizationPayload = DiarizationArtifactPayload(
            runID: run.id,
            sourcePath: run.sourcePath,
            createdAt: run.createdAt,
            detectedSpeakerCount: run.detectedSpeakerCount ?? 0,
            segments: content.diarizationSegments
        )

        try encoder.encode(transcriptionPayload).write(to: locations.transcriptionJSON, options: .atomic)
        try encoder.encode(diarizationPayload).write(to: locations.diarizationJSON, options: .atomic)

        return [
            RunArtifact(kind: .plainTranscript, path: locations.plainTranscript.path),
            RunArtifact(kind: .speakerTranscript, path: locations.speakerTranscript.path),
            RunArtifact(kind: .transcriptionJSON, path: locations.transcriptionJSON.path),
            RunArtifact(kind: .diarizationJSON, path: locations.diarizationJSON.path),
        ]
    }

    private func speakerTranscript(from turns: [SpeakerTurn]) -> String {
        turns.map { turn in
            let range = "\(TimecodeFormatter.string(from: turn.startTime))-\(TimecodeFormatter.string(from: turn.endTime))"
            return "[\(range)] \(turn.speakerID)\n\(turn.text)"
        }
        .joined(separator: "\n\n")
    }
}
