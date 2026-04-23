import XCTest
@testable import MeetingTranscriber

final class RunRepositoryTests: XCTestCase {
    func testRunRepositoryPersistsManifest() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileAccess = FileAccess(baseDirectory: tempDirectory)
        let repository = RunRepository(fileAccess: fileAccess)

        let run = RunRecord(
            sourcePath: "/tmp/example.wav",
            createdAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            userReportedSpeakerCount: 3,
            detectedSpeakerCount: 2,
            duration: 120,
            artifacts: [RunArtifact(kind: .plainTranscript, path: "/tmp/example.txt")]
        )

        try await repository.save([run])
        let loaded = try await repository.loadRuns()

        XCTAssertEqual(loaded, [run])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileAccess.manifestURL.path))
    }

    func testRunRepositoryUpsertMatchesLegacyPersistenceSequence() async throws {
        let optimizedDirectory = try makeTemporaryDirectory()
        let legacyDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: optimizedDirectory)
            try? FileManager.default.removeItem(at: legacyDirectory)
        }

        let optimizedFileAccess = FileAccess(baseDirectory: optimizedDirectory)
        let legacyFileAccess = FileAccess(baseDirectory: legacyDirectory)
        let repository = RunRepository(fileAccess: optimizedFileAccess)

        let baselineRuns = Self.syntheticRuns(count: 800)
        try await repository.save(baselineRuns)
        try Self.writeLegacyManifest(baselineRuns, fileAccess: legacyFileAccess)

        let targetID = baselineRuns[baselineRuns.count / 2].id
        let updateSequence = [
            Self.updatedRun(baselineRuns[baselineRuns.count / 2], status: .preparingModels),
            Self.updatedRun(baselineRuns[baselineRuns.count / 2], status: .processing),
            Self.updatedRun(baselineRuns[baselineRuns.count / 2], status: .writingArtifacts),
            Self.updatedRun(baselineRuns[baselineRuns.count / 2], status: .completed, contentPath: "/tmp/\(targetID.uuidString).json"),
        ]

        for run in updateSequence {
            try await repository.upsert(run)
            try Self.legacyPersist(run, fileAccess: legacyFileAccess)
        }

        let optimized = try await repository.loadRuns()
        let legacy = try Self.readLegacyRuns(fileAccess: legacyFileAccess)

        XCTAssertEqual(optimized, legacy)
        XCTAssertEqual(optimized.first?.id, targetID)
        XCTAssertEqual(optimized.first?.status, .completed)
    }

    func testRunRepositoryOnlyKeepsCompletedRunsInHistory() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileAccess = FileAccess(baseDirectory: tempDirectory)
        let repository = RunRepository(fileAccess: fileAccess)

        let completedRun = RunRecord(
            sourcePath: "/tmp/completed.wav",
            createdAt: Date(timeIntervalSince1970: 300),
            status: .completed,
            userReportedSpeakerCount: 2,
            detectedSpeakerCount: 2,
            duration: 90,
            artifacts: [RunArtifact(kind: .plainTranscript, path: "/tmp/completed.txt")]
        )
        let cancelledRun = RunRecord(
            sourcePath: "/tmp/cancelled.wav",
            createdAt: Date(timeIntervalSince1970: 200),
            status: .cancelled,
            userReportedSpeakerCount: 2,
            detectedSpeakerCount: nil,
            duration: 45,
            artifacts: []
        )
        let failedRun = RunRecord(
            sourcePath: "/tmp/failed.wav",
            createdAt: Date(timeIntervalSince1970: 100),
            status: .failed(message: "Boom"),
            userReportedSpeakerCount: nil,
            detectedSpeakerCount: nil,
            duration: 30,
            artifacts: []
        )

        try await repository.save([completedRun, cancelledRun, failedRun])

        let loaded = try await repository.loadRuns()
        let manifestData = try Data(contentsOf: fileAccess.manifestURL)
        let persisted = try JSONDecoder().decode([RunRecord].self, from: manifestData)

        XCTAssertEqual(loaded, [completedRun])
        XCTAssertEqual(persisted, [completedRun])
    }

    func testRunRepositoryBenchmarkLoggingAgainstLegacyPersistenceSequence() async throws {
        guard ProcessInfo.processInfo.environment["MEETING_TRANSCRIBER_RUN_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set MEETING_TRANSCRIBER_RUN_BENCHMARKS=1 to run benchmark logging.")
        }

        let optimizedDirectory = try makeTemporaryDirectory()
        let legacyDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: optimizedDirectory)
            try? FileManager.default.removeItem(at: legacyDirectory)
        }

        let optimizedFileAccess = FileAccess(baseDirectory: optimizedDirectory)
        let legacyFileAccess = FileAccess(baseDirectory: legacyDirectory)
        let repository = RunRepository(fileAccess: optimizedFileAccess)

        let baselineRuns = Self.syntheticRuns(count: 2_500)
        try await repository.save(baselineRuns)
        try Self.writeLegacyManifest(baselineRuns, fileAccess: legacyFileAccess)

        let sourceRun = baselineRuns[baselineRuns.count / 2]
        let updateSequence = [
            Self.updatedRun(sourceRun, status: .preparingModels),
            Self.updatedRun(sourceRun, status: .processing),
            Self.updatedRun(sourceRun, status: .writingArtifacts),
            Self.updatedRun(sourceRun, status: .completed, contentPath: "/tmp/\(sourceRun.id.uuidString).json"),
        ]

        let legacyMilliseconds = try await Self.averageMilliseconds(iterations: 5) {
            for run in updateSequence {
                try Self.legacyPersist(run, fileAccess: legacyFileAccess)
            }
        }
        let optimizedMilliseconds = try await Self.averageMilliseconds(iterations: 5) {
            for run in updateSequence {
                try await repository.upsert(run)
            }
        }

        print("BENCHMARK repository_legacy_ms=\(Self.formatted(legacyMilliseconds))")
        print("BENCHMARK repository_optimized_ms=\(Self.formatted(optimizedMilliseconds))")
    }

    private static func syntheticRuns(count: Int) -> [RunRecord] {
        (0..<count).map { index in
            RunRecord(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID(),
                sourcePath: "/tmp/audio-\(index).wav",
                createdAt: Date(timeIntervalSince1970: 10_000 - Double(index)),
                status: .completed,
                userReportedSpeakerCount: index.isMultiple(of: 3) ? 3 : nil,
                detectedSpeakerCount: 2,
                duration: 60 + Double(index % 120),
                artifacts: [RunArtifact(kind: .plainTranscript, path: "/tmp/audio-\(index).txt")],
                contentPath: "/tmp/audio-\(index).content.json"
            )
        }
    }

    private static func updatedRun(
        _ run: RunRecord,
        status: RunStatus,
        contentPath: String? = nil
    ) -> RunRecord {
        run.updating(
            createdAt: Date(timeIntervalSince1970: 20_000),
            status: status,
            contentPath: contentPath
        )
    }

    private static func legacyPersist(_ run: RunRecord, fileAccess: FileAccess) throws {
        let existing = try readLegacyRuns(fileAccess: fileAccess)
        var updated = existing.filter { $0.id != run.id }
        updated.insert(run, at: 0)
        try writeLegacyManifest(updated, fileAccess: fileAccess)
    }

    private static func readLegacyRuns(fileAccess: FileAccess) throws -> [RunRecord] {
        try fileAccess.ensureAppDirectories()

        guard FileManager.default.fileExists(atPath: fileAccess.manifestURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileAccess.manifestURL)
        return try JSONDecoder().decode([RunRecord].self, from: data)
            .sorted(by: { $0.createdAt > $1.createdAt })
    }

    private static func writeLegacyManifest(_ runs: [RunRecord], fileAccess: FileAccess) throws {
        try fileAccess.ensureAppDirectories()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let normalizedRuns = runs.sorted(by: { $0.createdAt > $1.createdAt })
        let data = try encoder.encode(normalizedRuns)
        try data.write(to: fileAccess.manifestURL, options: .atomic)
    }

    private static func averageMilliseconds(
        iterations: Int,
        block: () async throws -> Void
    ) async throws -> Double {
        try await block()

        let clock = ContinuousClock()
        var total: Duration = .zero

        for _ in 0..<iterations {
            let start = clock.now
            try await block()
            total += start.duration(to: clock.now)
        }

        return ((Double(total.components.seconds) * 1_000)
            + (Double(total.components.attoseconds) / 1_000_000_000_000_000))
            / Double(iterations)
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
