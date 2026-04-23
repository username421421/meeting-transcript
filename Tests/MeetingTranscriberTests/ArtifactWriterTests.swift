import XCTest
@testable import MeetingTranscriber

final class ArtifactWriterTests: XCTestCase {
    func testArtifactLocationsUseSiblingTranscriptFolder() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("weekly-sync.m4a")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data())

        let fileAccess = FileAccess(baseDirectory: tempDirectory)
        let writer = ArtifactWriter(fileAccess: fileAccess)

        let locations = try writer.artifactLocations(for: sourceURL)

        XCTAssertEqual(locations.outputDirectory.lastPathComponent, "weekly-sync Transcript")
        XCTAssertEqual(locations.plainTranscript.lastPathComponent, "weekly-sync.txt")
        XCTAssertEqual(locations.speakerTranscript.lastPathComponent, "weekly-sync.speakers.txt")
        XCTAssertEqual(locations.transcriptionJSON.lastPathComponent, "weekly-sync.json")
        XCTAssertEqual(locations.diarizationJSON.lastPathComponent, "weekly-sync.diarization.json")
    }

    func testPeopleCountValidationAcceptsExpectedRange() {
        let fileAccess = FileAccess(baseDirectory: FileManager.default.temporaryDirectory)

        XCTAssertNil(fileAccess.validatedUserReportedSpeakerCount(from: ""))
        XCTAssertEqual(fileAccess.validatedUserReportedSpeakerCount(from: "2"), 2)
        XCTAssertEqual(fileAccess.validatedUserReportedSpeakerCount(from: " 12 "), 12)
        XCTAssertNil(fileAccess.validatedUserReportedSpeakerCount(from: "0"))
        XCTAssertNil(fileAccess.validatedUserReportedSpeakerCount(from: "33"))
        XCTAssertNil(fileAccess.validatedUserReportedSpeakerCount(from: "abc"))
    }

    func testArtifactWriterPersistsPeopleCountAsMetadataOnly() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("planning-session.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data())

        let fileAccess = FileAccess(baseDirectory: tempDirectory)
        let writer = ArtifactWriter(fileAccess: fileAccess)

        let run = RunRecord(
            sourcePath: sourceURL.path,
            createdAt: Date(timeIntervalSince1970: 123),
            status: .writingArtifacts,
            userReportedSpeakerCount: 5,
            detectedSpeakerCount: 2,
            duration: 180,
            artifacts: []
        )

        let content = StoredRunContent(
            plainTranscript: "Project update",
            speakerTurns: [
                SpeakerTurn(speakerID: "Speaker 1", startTime: 0, endTime: 1, text: "Project update"),
            ],
            tokenTimings: [
                ArtifactTokenTiming(token: "Project", startTime: 0, endTime: 0.5, confidence: 0.9),
            ],
            diarizationSegments: [
                ArtifactDiarizationSegment(rawSpeakerID: "spk1", speakerLabel: "Speaker 1", startTime: 0, endTime: 1, qualityScore: 0.8),
            ]
        )

        _ = try writer.writeArtifacts(run: run, content: content)

        let locations = try writer.artifactLocations(for: sourceURL)
        let payload = try JSONDecoder().decode(
            TranscriptionArtifactPayload.self,
            from: Data(contentsOf: locations.transcriptionJSON)
        )

        XCTAssertEqual(payload.userReportedSpeakerCount, 5)
        XCTAssertEqual(payload.detectedSpeakerCount, 2)
    }

    func testPreferredModelsRootDirectoryUsesBundledModelsWhenComplete() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let bundledModelsRoot = tempDirectory.appendingPathComponent("BundledModels", isDirectory: true)
        try createBundledModels(at: bundledModelsRoot)

        let fileAccess = FileAccess(
            baseDirectory: tempDirectory,
            bundledModelsRootDirectory: bundledModelsRoot
        )

        XCTAssertTrue(fileAccess.bundledModelsExist())
        XCTAssertEqual(fileAccess.preferredModelsRootDirectory, bundledModelsRoot)
        XCTAssertEqual(
            fileAccess.preferredAsrModelsDirectory,
            bundledModelsRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
        )
    }

    func testPreferredModelsRootDirectoryFallsBackWhenBundledModelsAreIncomplete() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let bundledModelsRoot = tempDirectory.appendingPathComponent("BundledModels", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledModelsRoot, withIntermediateDirectories: true)

        let fileAccess = FileAccess(
            baseDirectory: tempDirectory,
            bundledModelsRootDirectory: bundledModelsRoot
        )

        XCTAssertFalse(fileAccess.bundledModelsExist())
        XCTAssertEqual(fileAccess.preferredModelsRootDirectory, fileAccess.modelsRootDirectory)
        XCTAssertEqual(fileAccess.preferredAsrModelsDirectory, fileAccess.asrModelsDirectory)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createBundledModels(at root: URL) throws {
        let asrDirectory = root.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
        let diarizerDirectory = root.appendingPathComponent("speaker-diarization", isDirectory: true)
        try FileManager.default.createDirectory(at: asrDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: diarizerDirectory, withIntermediateDirectories: true)

        let asrFiles = [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc",
            "parakeet_vocab.json",
        ]
        let diarizerFiles = [
            "Segmentation.mlmodelc",
            "FBank.mlmodelc",
            "Embedding.mlmodelc",
            "PldaRho.mlmodelc",
            "plda-parameters.json",
        ]

        for path in asrFiles {
            FileManager.default.createFile(
                atPath: asrDirectory.appendingPathComponent(path).path,
                contents: Data()
            )
        }

        for path in diarizerFiles {
            FileManager.default.createFile(
                atPath: diarizerDirectory.appendingPathComponent(path).path,
                contents: Data()
            )
        }
    }
}
