import XCTest
import FluidAudio
@testable import MeetingTranscriber

final class PipelineCoordinatorTests: XCTestCase {
    private struct SyntheticWorkload {
        let tokenTimings: [TokenTiming]
        let transcript: String
        let diarizationSegments: [ArtifactDiarizationSegment]
    }

    private struct LegacyTimedWord {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    private struct LegacySpeakerSegmentAssignment {
        let word: LegacyTimedWord
        let speakerLabel: String
    }

    func testReconcileAssignsSpeakerTurnsByOverlap() {
        let tokenTimings = [
            TokenTiming(token: "Hello", tokenId: 1, startTime: 0.0, endTime: 0.3, confidence: 0.9),
            TokenTiming(token: " world", tokenId: 2, startTime: 0.35, endTime: 0.65, confidence: 0.95),
            TokenTiming(token: " again", tokenId: 3, startTime: 1.2, endTime: 1.5, confidence: 0.91),
        ]

        let diarizationSegments = [
            ArtifactDiarizationSegment(rawSpeakerID: "spkA", speakerLabel: L10n.speakerLabel(1), startTime: 0.0, endTime: 0.9, qualityScore: 0.8),
            ArtifactDiarizationSegment(rawSpeakerID: "spkB", speakerLabel: L10n.speakerLabel(2), startTime: 1.0, endTime: 1.8, qualityScore: 0.85),
        ]

        let turns = PipelineCoordinator.reconcile(
            tokenTimings: tokenTimings,
            transcript: "Hello world again",
            diarizationSegments: diarizationSegments
        )

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].speakerID, L10n.speakerLabel(1))
        XCTAssertEqual(turns[0].text, "Hello world")
        XCTAssertEqual(turns[1].speakerID, L10n.speakerLabel(2))
        XCTAssertEqual(turns[1].text, "again")
    }

    func testNormalizedSegmentsUseGenericSpeakerLabelsInFirstAppearanceOrder() {
        let diarization = DiarizationResult(
            segments: [
                TimedSpeakerSegment(speakerId: "speaker_B", embedding: [], startTimeSeconds: 0.0, endTimeSeconds: 1.0, qualityScore: 0.7),
                TimedSpeakerSegment(speakerId: "speaker_B", embedding: [], startTimeSeconds: 1.0, endTimeSeconds: 2.0, qualityScore: 0.7),
                TimedSpeakerSegment(speakerId: "speaker_A", embedding: [], startTimeSeconds: 2.0, endTimeSeconds: 3.0, qualityScore: 0.9),
            ]
        )

        let normalized = PipelineCoordinator.normalizedSegments(from: diarization)

        XCTAssertEqual(
            normalized.map(\.speakerLabel),
            [L10n.speakerLabel(1), L10n.speakerLabel(1), L10n.speakerLabel(2)]
        )
        XCTAssertEqual(normalized.map(\.rawSpeakerID), ["speaker_B", "speaker_B", "speaker_A"])
    }

    func testReconcileSplitsLongPauseIntoSeparateTurns() {
        let tokenTimings = [
            TokenTiming(token: "Opening", tokenId: 1, startTime: 0.0, endTime: 0.4, confidence: 0.9),
            TokenTiming(token: " remarks", tokenId: 2, startTime: 0.45, endTime: 0.9, confidence: 0.9),
            TokenTiming(token: " follow-up", tokenId: 3, startTime: 2.5, endTime: 2.9, confidence: 0.92),
        ]

        let diarizationSegments = [
            ArtifactDiarizationSegment(rawSpeakerID: "spkA", speakerLabel: L10n.speakerLabel(1), startTime: 0.0, endTime: 3.2, qualityScore: 0.9),
        ]

        let turns = PipelineCoordinator.reconcile(
            tokenTimings: tokenTimings,
            transcript: "Opening remarks follow-up",
            diarizationSegments: diarizationSegments
        )

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns.map(\.speakerID), [L10n.speakerLabel(1), L10n.speakerLabel(1)])
        XCTAssertEqual(turns.map(\.text), ["Opening remarks", "follow-up"])
    }

    func testDetectedSpeakerCountFallsBackToSpeakerTurnsWhenDiarizationIsEmpty() {
        let speakerTurns = [
            SpeakerTurn(speakerID: "Speaker 1", startTime: 0, endTime: 1, text: "Hello world"),
        ]

        XCTAssertEqual(
            PipelineCoordinator.detectedSpeakerCount(
                diarizationSegments: [],
                speakerTurns: speakerTurns
            ),
            1
        )
    }

    func testOptimizedReconcileMatchesLegacyImplementationOnSyntheticWorkload() {
        let workload = Self.syntheticWorkload(wordCount: 250, segmentCount: 40)
        let optimized = PipelineCoordinator.reconcile(
            tokenTimings: workload.tokenTimings,
            transcript: workload.transcript,
            diarizationSegments: workload.diarizationSegments
        )
        let legacy = Self.legacyReconcile(
            tokenTimings: workload.tokenTimings,
            transcript: workload.transcript,
            diarizationSegments: workload.diarizationSegments
        )
        let mismatch = Self.firstMismatchDescription(optimized, legacy)

        XCTAssertNil(mismatch, mismatch ?? "")
    }

    func testReconcileBenchmarkLoggingAgainstLegacyImplementation() throws {
        guard ProcessInfo.processInfo.environment["MEETING_TRANSCRIBER_RUN_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set MEETING_TRANSCRIBER_RUN_BENCHMARKS=1 to run benchmark logging.")
        }

        let workload = Self.syntheticWorkload(wordCount: 6_000, segmentCount: 360)
        let legacy = Self.legacyReconcile(
            tokenTimings: workload.tokenTimings,
            transcript: workload.transcript,
            diarizationSegments: workload.diarizationSegments
        )
        let optimized = PipelineCoordinator.reconcile(
            tokenTimings: workload.tokenTimings,
            transcript: workload.transcript,
            diarizationSegments: workload.diarizationSegments
        )
        let mismatch = Self.firstMismatchDescription(optimized, legacy)

        let iterations = 4
        let legacyMilliseconds = Self.averageMilliseconds(iterations: iterations) {
            _ = Self.legacyReconcile(
                tokenTimings: workload.tokenTimings,
                transcript: workload.transcript,
                diarizationSegments: workload.diarizationSegments
            )
        }
        let optimizedMilliseconds = Self.averageMilliseconds(iterations: iterations) {
            _ = PipelineCoordinator.reconcile(
                tokenTimings: workload.tokenTimings,
                transcript: workload.transcript,
                diarizationSegments: workload.diarizationSegments
            )
        }

        XCTAssertNil(mismatch, mismatch ?? "")

        print("BENCHMARK reconcile_legacy_ms=\(Self.formatted(legacyMilliseconds))")
        print("BENCHMARK reconcile_optimized_ms=\(Self.formatted(optimizedMilliseconds))")
    }

    func testLivePipelineBenchmarkOnGuiSample() async throws {
        guard ProcessInfo.processInfo.environment["MEETING_TRANSCRIBER_RUN_LIVE_BENCHMARK"] == "1" else {
            throw XCTSkip("Set MEETING_TRANSCRIBER_RUN_LIVE_BENCHMARK=1 to run the live pipeline benchmark.")
        }

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent("gui test sample.aiff")
        let buildHomeSupportURL = repositoryRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("Home")
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
        let expectedArtifactURL = repositoryRoot
            .appendingPathComponent("gui test sample Transcript")
            .appendingPathComponent("gui test sample.json")

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw XCTSkip("gui test sample.aiff is not available in the repository root.")
        }

        let fileAccess = FileAccess(baseDirectory: buildHomeSupportURL)
        let client = FluidAudioClient(fileAccess: fileAccess)
        let repository = RunRepository(fileAccess: fileAccess)
        let contentStore = RunContentStore(fileAccess: fileAccess)
        let coordinator = PipelineCoordinator(
            fileAccess: fileAccess,
            repository: repository,
            fluidAudioClient: client,
            contentStore: contentStore
        )

        let clock = ContinuousClock()
        let start = clock.now
        let completedRun = try await coordinator.process(
            sourceURL: sourceURL,
            userReportedSpeakerCount: 3
        ) { _ in }
        let elapsedMilliseconds = Self.milliseconds(since: start, on: clock)

        let contentPath = try XCTUnwrap(completedRun.contentPath)
        let storedContent = try contentStore.load(from: contentPath)

        XCTAssertFalse(storedContent.plainTranscript.isEmpty)
        XCTAssertFalse(storedContent.speakerTurns.isEmpty)

        if FileManager.default.fileExists(atPath: expectedArtifactURL.path) {
            let payload = try JSONDecoder().decode(
                TranscriptionArtifactPayload.self,
                from: Data(contentsOf: expectedArtifactURL)
            )
            XCTAssertEqual(storedContent.plainTranscript, payload.plainTranscript)
            XCTAssertNil(
                Self.firstMismatchDescription(storedContent.speakerTurns, payload.speakerTurns),
                "Live benchmark output diverged from the checked-in sample transcript."
            )
        }

        print("BENCHMARK live_pipeline_total_ms=\(Self.formatted(elapsedMilliseconds))")
    }

    private static func syntheticWorkload(wordCount: Int, segmentCount: Int) -> SyntheticWorkload {
        var tokenTimings: [TokenTiming] = []
        tokenTimings.reserveCapacity(wordCount)

        var transcriptWords: [String] = []
        transcriptWords.reserveCapacity(wordCount)

        var time: TimeInterval = 0
        for index in 0..<wordCount {
            let word = "word\(index)"
            transcriptWords.append(word)

            let duration = 0.18 + Double(index % 5) * 0.01
            let pause = index.isMultiple(of: 17) ? 1.35 : 0.07
            tokenTimings.append(
                TokenTiming(
                    token: index == 0 ? word : " \(word)",
                    tokenId: index + 1,
                    startTime: time,
                    endTime: time + duration,
                    confidence: 0.97
                )
            )
            time += duration + pause
        }

        var diarizationSegments: [ArtifactDiarizationSegment] = []
        diarizationSegments.reserveCapacity(segmentCount)

        var segmentStart: TimeInterval = 0
        let timelineEnd = time + 2

        for index in 0..<segmentCount {
            guard segmentStart < timelineEnd else { break }

            let segmentDuration = 3.2 + Double(index % 7) * 0.55
            let segmentEnd = min(segmentStart + segmentDuration, timelineEnd)
            diarizationSegments.append(
                ArtifactDiarizationSegment(
                    rawSpeakerID: "spk\(index % 6)",
                    speakerLabel: L10n.speakerLabel((index % 6) + 1),
                    startTime: segmentStart,
                    endTime: segmentEnd,
                    qualityScore: 0.85
                )
            )
            segmentStart = segmentEnd + 0.25
        }

        return SyntheticWorkload(
            tokenTimings: tokenTimings,
            transcript: transcriptWords.joined(separator: " "),
            diarizationSegments: diarizationSegments
        )
    }

    private static func legacyReconcile(
        tokenTimings: [TokenTiming],
        transcript: String,
        diarizationSegments: [ArtifactDiarizationSegment]
    ) -> [SpeakerTurn] {
        let words = legacyWords(from: tokenTimings, transcript: transcript)
        guard !words.isEmpty else {
            return []
        }

        guard !diarizationSegments.isEmpty else {
            return [
                SpeakerTurn(
                    speakerID: L10n.speakerLabel(1),
                    startTime: words.first?.startTime ?? 0,
                    endTime: words.last?.endTime ?? 0,
                    text: transcript
                )
            ]
        }

        let assignments = words.map { word in
            LegacySpeakerSegmentAssignment(
                word: word,
                speakerLabel: legacyBestSpeaker(for: word, in: diarizationSegments)
            )
        }

        return legacyGroup(assignments: assignments)
    }

    private static func legacyWords(from tokenTimings: [TokenTiming], transcript: String) -> [LegacyTimedWord] {
        let sortedTokens = tokenTimings.sorted(by: { $0.startTime < $1.startTime })
        guard !sortedTokens.isEmpty else {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return [LegacyTimedWord(text: trimmed, startTime: 0, endTime: 0)]
        }

        var words: [LegacyTimedWord] = []
        var currentText = ""
        var currentStart: TimeInterval?
        var currentEnd: TimeInterval = 0

        func reset() {
            currentText = ""
            currentStart = nil
            currentEnd = 0
        }

        func flush() {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let currentStart else {
                reset()
                return
            }

            words.append(LegacyTimedWord(text: trimmed, startTime: currentStart, endTime: currentEnd))
            reset()
        }

        for token in sortedTokens {
            let tokenText = token.token.replacingOccurrences(of: "\n", with: " ")
            let beginsNewWord = tokenText.first?.isWhitespace == true
            let trimmedToken = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)

            if beginsNewWord && !currentText.isEmpty {
                flush()
            }

            guard !trimmedToken.isEmpty else {
                continue
            }

            if currentStart == nil {
                currentStart = token.startTime
            }

            currentEnd = max(currentEnd, token.endTime)
            currentText += trimmedToken
        }

        flush()
        return words
    }

    private static func legacyBestSpeaker(
        for word: LegacyTimedWord,
        in segments: [ArtifactDiarizationSegment]
    ) -> String {
        let midpoint = (word.startTime + word.endTime) / 2
        let byOverlap = segments.max { lhs, rhs in
            legacyOverlap(of: word, with: lhs) < legacyOverlap(of: word, with: rhs)
        }

        if let byOverlap, legacyOverlap(of: word, with: byOverlap) > 0 {
            return byOverlap.speakerLabel
        }

        let byDistance = segments.min { lhs, rhs in
            legacyDistance(from: midpoint, to: lhs) < legacyDistance(from: midpoint, to: rhs)
        }

        return byDistance?.speakerLabel ?? L10n.speakerLabel(1)
    }

    private static func legacyGroup(assignments: [LegacySpeakerSegmentAssignment]) -> [SpeakerTurn] {
        guard !assignments.isEmpty else { return [] }

        var turns: [SpeakerTurn] = []
        var active = assignments[0]
        var buffer = [active.word.text]
        var start = active.word.startTime
        var end = active.word.endTime

        for assignment in assignments.dropFirst() {
            let gap = assignment.word.startTime - end
            let speakerChanged = assignment.speakerLabel != active.speakerLabel
            let needsSplit = speakerChanged || gap > 1.25

            if needsSplit {
                turns.append(
                    SpeakerTurn(
                        speakerID: active.speakerLabel,
                        startTime: start,
                        endTime: end,
                        text: buffer.joined(separator: " ")
                    )
                )

                active = assignment
                buffer = [assignment.word.text]
                start = assignment.word.startTime
                end = assignment.word.endTime
            } else {
                buffer.append(assignment.word.text)
                end = assignment.word.endTime
            }
        }

        turns.append(
            SpeakerTurn(
                speakerID: active.speakerLabel,
                startTime: start,
                endTime: end,
                text: buffer.joined(separator: " ")
            )
        )

        return turns
    }

    private static func legacyOverlap(of word: LegacyTimedWord, with segment: ArtifactDiarizationSegment) -> TimeInterval {
        max(0, min(word.endTime, segment.endTime) - max(word.startTime, segment.startTime))
    }

    private static func legacyDistance(from value: TimeInterval, to segment: ArtifactDiarizationSegment) -> TimeInterval {
        if segment.startTime...segment.endTime ~= value {
            return 0
        }

        return min(abs(value - segment.startTime), abs(value - segment.endTime))
    }

    private static func averageMilliseconds(iterations: Int, block: () -> Void) -> Double {
        precondition(iterations > 0)

        block()

        let clock = ContinuousClock()
        var total: Duration = .zero

        for _ in 0..<iterations {
            let start = clock.now
            block()
            total += start.duration(to: clock.now)
        }

        return ((Double(total.components.seconds) * 1_000)
            + (Double(total.components.attoseconds) / 1_000_000_000_000_000))
            / Double(iterations)
    }

    private static func milliseconds(
        since start: ContinuousClock.Instant,
        on clock: ContinuousClock
    ) -> Double {
        let duration = start.duration(to: clock.now)
        return (Double(duration.components.seconds) * 1_000)
            + (Double(duration.components.attoseconds) / 1_000_000_000_000_000)
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func firstMismatchDescription(
        _ lhs: [SpeakerTurn],
        _ rhs: [SpeakerTurn]
    ) -> String? {
        guard lhs.count == rhs.count else {
            return "Count mismatch: optimized=\(lhs.count), legacy=\(rhs.count)"
        }

        for (index, pair) in zip(lhs, rhs).enumerated() where pair.0 != pair.1 {
            let optimized = semanticTurnDescription(for: pair.0)
            let legacy = semanticTurnDescription(for: pair.1)
            if optimized != legacy {
                return "Mismatch at turn \(index): optimized=\(optimized), legacy=\(legacy)"
            }
        }

        return nil
    }

    private static func semanticTurnDescription(for turn: SpeakerTurn) -> String {
        "\(turn.speakerID)|\(turn.startTime)|\(turn.endTime)|\(turn.text)"
    }
}
