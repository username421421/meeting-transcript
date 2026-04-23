import XCTest
@testable import MeetingTranscriber

@MainActor
final class AppStateTests: XCTestCase {
    func testPresentImportDraftShowsEmptyImportFlow() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileAccess = FileAccess(baseDirectory: tempDirectory)
        let repository = RunRepository(fileAccess: fileAccess)
        let run = completedRun(sourcePath: "/tmp/planning.wav")
        try await repository.save([run])

        let appState = AppState(fileAccess: fileAccess, repository: repository)
        await appState.reloadRuns()

        XCTAssertEqual(appState.selectedRunID, run.id)

        appState.importSpeakerCount = "4"
        appState.searchText = "speaker"
        appState.selectedTab = .files

        appState.presentImportDraft()

        XCTAssertTrue(appState.isShowingImportView)
        XCTAssertNil(appState.selectedRunID)
        XCTAssertEqual(appState.importSpeakerCount, "")
        XCTAssertEqual(appState.searchText, "")
        XCTAssertEqual(appState.selectedTab, .speakers)
    }

    func testReloadRunsKeepsImportDraftVisibleWhenHistoryExists() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileAccess = FileAccess(baseDirectory: tempDirectory)
        let repository = RunRepository(fileAccess: fileAccess)
        let run = completedRun(sourcePath: "/tmp/retro.wav")
        try await repository.save([run])

        let appState = AppState(fileAccess: fileAccess, repository: repository)
        appState.presentImportDraft()

        await appState.reloadRuns()

        XCTAssertEqual(appState.recentRuns, [run])
        XCTAssertTrue(appState.isShowingImportView)
        XCTAssertNil(appState.selectedRunID)
    }

    private func completedRun(sourcePath: String) -> RunRecord {
        RunRecord(
            sourcePath: sourcePath,
            createdAt: Date(timeIntervalSince1970: 100),
            status: .completed,
            userReportedSpeakerCount: 2,
            detectedSpeakerCount: 2,
            duration: 60,
            artifacts: [RunArtifact(kind: .plainTranscript, path: "\(sourcePath).txt")]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
