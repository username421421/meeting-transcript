import Foundation
import FluidAudio

struct PipelineProgress: Sendable {
    enum Stage: String, Sendable {
        case transcribing
        case diarizing
        case reconciling
        case writingArtifacts
        case completed
    }

    let run: RunRecord
    let stage: Stage
    let fractionCompleted: Double
    let detail: String
}

private struct TimedWord: Hashable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

private struct SpeakerSegmentAssignment: Hashable, Sendable {
    let word: TimedWord
    let speakerLabel: String
}

typealias PipelineProgressHandler = @Sendable (PipelineProgress) async -> Void

final class PipelineCoordinator: @unchecked Sendable {
    private enum ProgressStep {
        case beginTranscribing
        case transcribing
        case diarizing
        case reconciling
        case writingArtifacts
        case completed

        var stage: PipelineProgress.Stage {
            switch self {
            case .beginTranscribing, .transcribing:
                return .transcribing
            case .diarizing:
                return .diarizing
            case .reconciling:
                return .reconciling
            case .writingArtifacts:
                return .writingArtifacts
            case .completed:
                return .completed
            }
        }

        var fractionCompleted: Double {
            switch self {
            case .beginTranscribing:
                return 0.15
            case .transcribing:
                return 0.3
            case .diarizing:
                return 0.55
            case .reconciling:
                return 0.75
            case .writingArtifacts:
                return 0.9
            case .completed:
                return 1.0
            }
        }

        var detail: String {
            switch self {
            case .beginTranscribing, .transcribing:
                return L10n.tr("Transcribing")
            case .diarizing:
                return L10n.tr("Diarizing")
            case .reconciling:
                return L10n.tr("Matching Speakers")
            case .writingArtifacts:
                return L10n.tr("Finalizing")
            case .completed:
                return L10n.tr("Completed")
            }
        }
    }

    private static let maxGapWithinSpeakerTurn: TimeInterval = 1.25

    private let fileAccess: FileAccess
    private let repository: RunRepository
    private let fluidAudioClient: FluidAudioClient
    private let contentStore: RunContentStore

    init(
        fileAccess: FileAccess = FileAccess(),
        repository: RunRepository = RunRepository(),
        fluidAudioClient: FluidAudioClient? = nil,
        contentStore: RunContentStore? = nil
    ) {
        self.fileAccess = fileAccess
        self.repository = repository
        let client = fluidAudioClient ?? FluidAudioClient(fileAccess: fileAccess)
        self.fluidAudioClient = client
        self.contentStore = contentStore ?? RunContentStore(fileAccess: fileAccess)
    }

    func process(
        sourceURL: URL,
        userReportedSpeakerCount: Int?,
        progressHandler: @escaping PipelineProgressHandler
    ) async throws -> RunRecord {
        guard fileAccess.isSupportedAudioFile(sourceURL) else {
            throw PipelineError.unsupportedFile(sourceURL.lastPathComponent)
        }

        let duration = try? fileAccess.duration(of: sourceURL)
        var run = RunRecord(
            sourcePath: sourceURL.path,
            status: .processing,
            userReportedSpeakerCount: userReportedSpeakerCount,
            detectedSpeakerCount: nil,
            duration: duration,
            artifacts: []
        )

        do {
            try await persistAndReport(
                &run,
                status: .processing,
                step: .beginTranscribing,
                progressHandler: progressHandler
            )
            try Task.checkCancellation()

            try await fluidAudioClient.prepareModels()
            try Task.checkCancellation()

            await reportProgress(
                for: run,
                step: .transcribing,
                progressHandler: progressHandler
            )
            try Task.checkCancellation()

            async let asrResult = fluidAudioClient.transcribe(sourceURL)
            await reportProgress(
                for: run,
                step: .diarizing,
                progressHandler: progressHandler
            )
            async let diarizationResult = fluidAudioClient.diarize(sourceURL)

            let (transcription, diarization) = try await (asrResult, diarizationResult)
            try Task.checkCancellation()

            await reportProgress(
                for: run,
                step: .reconciling,
                progressHandler: progressHandler
            )
            try Task.checkCancellation()
            let tokenTimings = transcription.tokenTimings ?? []
            let normalizedSegments = Self.normalizedSegments(from: diarization)
            let speakerTurns = Self.reconcile(
                tokenTimings: tokenTimings,
                transcript: transcription.text,
                diarizationSegments: normalizedSegments
            )

            let detectedSpeakerCount = Self.detectedSpeakerCount(
                diarizationSegments: normalizedSegments,
                speakerTurns: speakerTurns
            )
            try await persistAndReport(
                &run,
                status: .writingArtifacts,
                detectedSpeakerCount: detectedSpeakerCount,
                duration: run.duration ?? transcription.duration,
                step: .writingArtifacts,
                progressHandler: progressHandler
            )
            try Task.checkCancellation()
            let storedContent = Self.storedContent(
                plainTranscript: transcription.text,
                speakerTurns: speakerTurns,
                tokenTimings: tokenTimings,
                diarizationSegments: normalizedSegments
            )
            let contentURL = try contentStore.save(storedContent, for: run.id)

            try await persistAndReport(
                &run,
                status: .completed,
                artifacts: [],
                contentPath: contentURL.path,
                step: .completed,
                progressHandler: progressHandler
            )
            return run
        } catch is CancellationError {
            let cancelledRun = run.updating(status: .cancelled)
            try await persist(cancelledRun)
            throw CancellationError()
        } catch {
            let failedRun = run.updating(status: .failed(message: error.localizedDescription))
            try await persist(failedRun)
            throw error
        }
    }

    private func persist(_ run: RunRecord) async throws {
        try await repository.upsert(run)
    }

    private func persistAndReport(
        _ run: inout RunRecord,
        status: RunStatus? = nil,
        detectedSpeakerCount: Int? = nil,
        duration: TimeInterval? = nil,
        artifacts: [RunArtifact]? = nil,
        contentPath: String? = nil,
        step: ProgressStep,
        progressHandler: PipelineProgressHandler
    ) async throws {
        run = run.updating(
            status: status,
            detectedSpeakerCount: detectedSpeakerCount,
            duration: duration,
            artifacts: artifacts,
            contentPath: contentPath
        )
        try await persist(run)
        await reportProgress(
            for: run,
            step: step,
            progressHandler: progressHandler
        )
    }

    private func reportProgress(
        for run: RunRecord,
        step: ProgressStep,
        progressHandler: PipelineProgressHandler
    ) async {
        await progressHandler(
            PipelineProgress(
                run: run,
                stage: step.stage,
                fractionCompleted: step.fractionCompleted,
                detail: step.detail
            )
        )
    }

    private static func storedContent(
        plainTranscript: String,
        speakerTurns: [SpeakerTurn],
        tokenTimings: [TokenTiming],
        diarizationSegments: [ArtifactDiarizationSegment]
    ) -> StoredRunContent {
        StoredRunContent(
            plainTranscript: plainTranscript,
            speakerTurns: speakerTurns,
            tokenTimings: tokenTimings.map {
                ArtifactTokenTiming(
                    token: $0.token,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    confidence: $0.confidence
                )
            },
            diarizationSegments: diarizationSegments
        )
    }

    static func detectedSpeakerCount(
        diarizationSegments: [ArtifactDiarizationSegment],
        speakerTurns: [SpeakerTurn]
    ) -> Int {
        max(
            Set(diarizationSegments.map(\.speakerLabel)).count,
            Set(speakerTurns.map(\.speakerID)).count
        )
    }

    static func normalizedSegments(from diarization: DiarizationResult) -> [ArtifactDiarizationSegment] {
        let sortedSegments = diarization.segments
            .sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds })
        var speakerLabelsByID: [String: String] = [:]
        var nextSpeakerIndex = 1

        func speakerLabel(for rawSpeakerID: String) -> String {
            if let existingLabel = speakerLabelsByID[rawSpeakerID] {
                return existingLabel
            }

            let newLabel = L10n.speakerLabel(nextSpeakerIndex)
            speakerLabelsByID[rawSpeakerID] = newLabel
            nextSpeakerIndex += 1
            return newLabel
        }

        return sortedSegments.map { segment in
            ArtifactDiarizationSegment(
                rawSpeakerID: segment.speakerId,
                speakerLabel: speakerLabel(for: segment.speakerId),
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                qualityScore: segment.qualityScore
            )
        }
    }

    static func reconcile(
        tokenTimings: [TokenTiming],
        transcript: String,
        diarizationSegments: [ArtifactDiarizationSegment]
    ) -> [SpeakerTurn] {
        let words = words(from: tokenTimings, transcript: transcript)
        guard !words.isEmpty else {
            return []
        }

        guard !diarizationSegments.isEmpty else {
            return [fallbackSpeakerTurn(from: words, transcript: transcript)]
        }

        let assignments = assignments(for: words, in: diarizationSegments)

        return group(assignments: assignments)
    }

    private static func fallbackSpeakerTurn(from words: [TimedWord], transcript: String) -> SpeakerTurn {
        SpeakerTurn(
            speakerID: L10n.speakerLabel(1),
            startTime: words.first?.startTime ?? 0,
            endTime: words.last?.endTime ?? 0,
            text: transcript
        )
    }

    private static func words(from tokenTimings: [TokenTiming], transcript: String) -> [TimedWord] {
        let sortedTokens = tokenTimings.sorted(by: { $0.startTime < $1.startTime })
        guard !sortedTokens.isEmpty else {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return [TimedWord(text: trimmed, startTime: 0, endTime: 0)]
        }

        var words: [TimedWord] = []
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

            words.append(TimedWord(text: trimmed, startTime: currentStart, endTime: currentEnd))
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

    private static func assignments(
        for words: [TimedWord],
        in segments: [ArtifactDiarizationSegment]
    ) -> [SpeakerSegmentAssignment] {
        var assignments: [SpeakerSegmentAssignment] = []
        assignments.reserveCapacity(words.count)

        var firstCandidateIndex = 0

        for word in words {
            while firstCandidateIndex < segments.count, segments[firstCandidateIndex].endTime < word.startTime {
                firstCandidateIndex += 1
            }

            var bestOverlap: TimeInterval = 0
            var bestOverlapLabel: String?
            var candidateIndex = firstCandidateIndex

            while candidateIndex < segments.count, segments[candidateIndex].startTime <= word.endTime {
                let overlap = overlap(of: word, with: segments[candidateIndex])
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestOverlapLabel = segments[candidateIndex].speakerLabel
                }
                candidateIndex += 1
            }

            let speakerLabel: String
            if let bestOverlapLabel, bestOverlap > 0 {
                speakerLabel = bestOverlapLabel
            } else {
                speakerLabel = nearestSpeaker(
                    to: (word.startTime + word.endTime) / 2,
                    previous: firstCandidateIndex > 0 ? segments[firstCandidateIndex - 1] : nil,
                    next: firstCandidateIndex < segments.count ? segments[firstCandidateIndex] : nil
                )
            }

            assignments.append(SpeakerSegmentAssignment(word: word, speakerLabel: speakerLabel))
        }

        return assignments
    }

    private static func nearestSpeaker(
        to value: TimeInterval,
        previous: ArtifactDiarizationSegment?,
        next: ArtifactDiarizationSegment?
    ) -> String {
        let previousDistance = previous.map { distance(from: value, to: $0) }
        let nextDistance = next.map { distance(from: value, to: $0) }

        switch (previous, previousDistance, next, nextDistance) {
        case let (.some(previous), .some(previousDistance), .some(next), .some(nextDistance)):
            return previousDistance <= nextDistance ? previous.speakerLabel : next.speakerLabel
        case let (.some(previous), .some, _, _):
            return previous.speakerLabel
        case let (_, _, .some(next), .some):
            return next.speakerLabel
        default:
            return L10n.speakerLabel(1)
        }
    }

    private static func group(assignments: [SpeakerSegmentAssignment]) -> [SpeakerTurn] {
        guard !assignments.isEmpty else { return [] }

        var turns: [SpeakerTurn] = []
        var active = assignments[0]
        var buffer = [active.word.text]
        var start = active.word.startTime
        var end = active.word.endTime

        func appendTurn() {
            turns.append(
                SpeakerTurn(
                    speakerID: active.speakerLabel,
                    startTime: start,
                    endTime: end,
                    text: buffer.joined(separator: " ")
                )
            )
        }

        for assignment in assignments.dropFirst() {
            let gap = assignment.word.startTime - end
            let speakerChanged = assignment.speakerLabel != active.speakerLabel
            let needsSplit = speakerChanged || gap > maxGapWithinSpeakerTurn

            if needsSplit {
                appendTurn()
                active = assignment
                buffer = [assignment.word.text]
                start = assignment.word.startTime
                end = assignment.word.endTime
            } else {
                buffer.append(assignment.word.text)
                end = assignment.word.endTime
            }
        }

        appendTurn()
        return turns
    }

    private static func overlap(of word: TimedWord, with segment: ArtifactDiarizationSegment) -> TimeInterval {
        max(0, min(word.endTime, segment.endTime) - max(word.startTime, segment.startTime))
    }

    private static func distance(from value: TimeInterval, to segment: ArtifactDiarizationSegment) -> TimeInterval {
        if segment.startTime...segment.endTime ~= value {
            return 0
        }

        return min(abs(value - segment.startTime), abs(value - segment.endTime))
    }
}

enum PipelineError: LocalizedError {
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name):
            return L10n.format("%@ is not a supported audio file.", name)
        }
    }
}
