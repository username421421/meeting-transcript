import Foundation

struct StoredRunContent: Hashable, Codable, Sendable {
    let plainTranscript: String
    let speakerTurns: [SpeakerTurn]
    let tokenTimings: [ArtifactTokenTiming]
    let diarizationSegments: [ArtifactDiarizationSegment]
}

struct RunContentStore: @unchecked Sendable {
    private let fileAccess: FileAccess
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileAccess: FileAccess = FileAccess()) {
        self.fileAccess = fileAccess

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func save(_ content: StoredRunContent, for runID: UUID) throws -> URL {
        try fileAccess.ensureAppDirectories()

        let url = fileAccess.runContentURL(for: runID)
        let data = try encoder.encode(content)
        try data.write(to: url, options: .atomic)
        return url
    }

    func load(from path: String) throws -> StoredRunContent {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(StoredRunContent.self, from: data)
    }
}

actor RunRepository {
    private let fileAccess: FileAccess
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var cachedRuns: [RunRecord]?

    init(fileAccess: FileAccess = FileAccess()) {
        self.fileAccess = fileAccess

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func loadRuns() throws -> [RunRecord] {
        try runs()
    }

    func save(_ runs: [RunRecord]) throws {
        try persist(runs)
    }

    func upsert(_ run: RunRecord) throws {
        try updateRuns { runs in
            runs.removeAll(where: { $0.id == run.id })

            if shouldKeepInHistory(run) {
                runs.insert(run, at: 0)
            }
        }
    }

    private func runs() throws -> [RunRecord] {
        if let cachedRuns {
            return cachedRuns
        }

        let loadedRuns = try loadPersistedRuns()
        cachedRuns = loadedRuns
        return loadedRuns
    }

    private func updateRuns(_ update: (inout [RunRecord]) -> Void) throws {
        var updatedRuns = try runs()
        update(&updatedRuns)
        try persist(updatedRuns)
    }

    private func loadPersistedRuns() throws -> [RunRecord] {
        try fileAccess.ensureAppDirectories()

        guard FileManager.default.fileExists(atPath: fileAccess.manifestURL.path) else {
            return []
        }

        let decodedRuns = try decodeManifest()
        let normalizedRuns = normalizedHistoryRuns(decodedRuns)

        if normalizedRuns != decodedRuns {
            try writeManifest(normalizedRuns)
        }

        return normalizedRuns
    }

    private func persist(_ runs: [RunRecord]) throws {
        try fileAccess.ensureAppDirectories()
        let normalizedRuns = normalizedHistoryRuns(runs)
        try writeManifest(normalizedRuns)
        cachedRuns = normalizedRuns
    }

    private func decodeManifest() throws -> [RunRecord] {
        let data = try Data(contentsOf: fileAccess.manifestURL)
        return try decoder.decode([RunRecord].self, from: data)
    }

    private func writeManifest(_ runs: [RunRecord]) throws {
        let data = try encoder.encode(runs)
        try data.write(to: fileAccess.manifestURL, options: .atomic)
    }

    private func normalizedHistoryRuns(_ runs: [RunRecord]) -> [RunRecord] {
        sorted(runs.filter(shouldKeepInHistory))
    }

    private func shouldKeepInHistory(_ run: RunRecord) -> Bool {
        run.status == .completed
    }

    private func sorted(_ runs: [RunRecord]) -> [RunRecord] {
        runs.sorted(by: { $0.createdAt > $1.createdAt })
    }
}
