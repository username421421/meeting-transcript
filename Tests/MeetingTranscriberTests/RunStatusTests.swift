import XCTest
@testable import MeetingTranscriber

final class RunStatusTests: XCTestCase {
    func testCancelledStatusRoundTripsThroughCodable() throws {
        let status = RunStatus.cancelled

        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RunStatus.self, from: data)

        XCTAssertEqual(decoded, .cancelled)
        XCTAssertEqual(decoded.label, "Stopped")
        XCTAssertTrue(decoded.isTerminal)
        XCTAssertEqual(decoded.terminalDetailMessage, "Stopped before completion.")
    }

    @MainActor
    func testSelectedRunDetailTextShowsStoppingMessageDuringCancellation() {
        let appState = AppState()
        let run = RunRecord(
            sourcePath: "/tmp/example.wav",
            status: .processing,
            userReportedSpeakerCount: nil,
            detectedSpeakerCount: nil,
            duration: nil,
            artifacts: []
        )

        appState.recentRuns = [run]
        appState.selectedRunID = run.id
        appState.activeRunID = run.id
        appState.activeProgress = PipelineProgress(
            run: run,
            stage: .transcribing,
            fractionCompleted: 0.4,
            detail: "Transcribing"
        )
        appState.isCancellingActiveRun = true

        XCTAssertEqual(appState.selectedRunDetailText, "Stopping")
    }
}
