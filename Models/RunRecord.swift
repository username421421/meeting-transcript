import Foundation

struct RunRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let sourcePath: String
    let createdAt: Date
    let status: RunStatus
    let userReportedSpeakerCount: Int?
    let detectedSpeakerCount: Int?
    let duration: TimeInterval?
    let artifacts: [RunArtifact]
    let contentPath: String?

    init(
        id: UUID = UUID(),
        sourcePath: String,
        createdAt: Date = .now,
        status: RunStatus,
        userReportedSpeakerCount: Int?,
        detectedSpeakerCount: Int?,
        duration: TimeInterval?,
        artifacts: [RunArtifact],
        contentPath: String? = nil
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.createdAt = createdAt
        self.status = status
        self.userReportedSpeakerCount = userReportedSpeakerCount
        self.detectedSpeakerCount = detectedSpeakerCount
        self.duration = duration
        self.artifacts = artifacts.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
        self.contentPath = contentPath
    }

    var sourceURL: URL {
        URL(fileURLWithPath: sourcePath)
    }

    var displayName: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }

    var subtitle: String {
        sourceURL.lastPathComponent
    }

    var contentURL: URL? {
        contentPath.map(URL.init(fileURLWithPath:))
    }

    func artifact(_ kind: RunArtifact.Kind) -> RunArtifact? {
        artifacts.first(where: { $0.kind == kind })
    }

    func updating(
        createdAt: Date? = nil,
        status: RunStatus? = nil,
        detectedSpeakerCount: Int? = nil,
        duration: TimeInterval? = nil,
        artifacts: [RunArtifact]? = nil,
        contentPath: String? = nil
    ) -> RunRecord {
        RunRecord(
            id: id,
            sourcePath: sourcePath,
            createdAt: createdAt ?? self.createdAt,
            status: status ?? self.status,
            userReportedSpeakerCount: self.userReportedSpeakerCount,
            detectedSpeakerCount: detectedSpeakerCount ?? self.detectedSpeakerCount,
            duration: duration ?? self.duration,
            artifacts: artifacts ?? self.artifacts,
            contentPath: contentPath ?? self.contentPath
        )
    }
}
