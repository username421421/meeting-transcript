import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct ArtifactLocations: Sendable {
    let outputDirectory: URL
    let plainTranscript: URL
    let speakerTranscript: URL
    let transcriptionJSON: URL
    let diarizationJSON: URL
}

struct FileAccess: @unchecked Sendable {
    private static let validSpeakerCounts = 1...32
    static let supportedExtensions: Set<String> = [
        "aac",
        "aif",
        "aiff",
        "caf",
        "flac",
        "m4a",
        "mp3",
        "mp4",
        "mpeg",
        "mpga",
        "ogg",
        "wav",
    ]
    private static let requiredAsrFiles = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecision.mlmodelc",
        "parakeet_vocab.json",
    ]
    private static let requiredOfflineDiarizerFiles = [
        "Segmentation.mlmodelc",
        "FBank.mlmodelc",
        "Embedding.mlmodelc",
        "PldaRho.mlmodelc",
        "plda-parameters.json",
    ]

    private let fileManager: FileManager
    private let appName: String
    private let asrFolderName: String
    private let diarizerFolderName: String
    private let baseDirectory: URL?
    private let bundledModelsRootOverride: URL?

    init(
        fileManager: FileManager = .default,
        appName: String = "MeetingTranscriber",
        baseDirectory: URL? = nil,
        bundledModelsRootDirectory: URL? = nil,
        asrFolderName: String = "parakeet-tdt-0.6b-v3",
        diarizerFolderName: String = "speaker-diarization"
    ) {
        self.fileManager = fileManager
        self.appName = appName
        self.baseDirectory = baseDirectory
        self.bundledModelsRootOverride = bundledModelsRootDirectory
        self.asrFolderName = asrFolderName
        self.diarizerFolderName = diarizerFolderName
    }

    var applicationSupportDirectory: URL {
        let root = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root
            .appendingPathComponent(appName, isDirectory: true)
    }

    var runsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Runs", isDirectory: true)
    }

    var manifestURL: URL {
        runsDirectory.appendingPathComponent("manifest.json", isDirectory: false)
    }

    func runContentURL(for runID: UUID) -> URL {
        runsDirectory.appendingPathComponent("\(runID.uuidString).content.json", isDirectory: false)
    }

    var modelsRootDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    var asrModelsDirectory: URL {
        modelsRootDirectory.appendingPathComponent(asrFolderName, isDirectory: true)
    }

    var bundledModelsRootDirectory: URL? {
        existingDirectory(
            at: bundledModelsRootOverride
                ?? Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true)
        )
    }

    var preferredModelsRootDirectory: URL {
        guard let bundledModelsRootDirectory, bundledModelsExist(in: bundledModelsRootDirectory) else {
            return modelsRootDirectory
        }

        return bundledModelsRootDirectory
    }

    var preferredAsrModelsDirectory: URL {
        preferredModelsRootDirectory.appendingPathComponent(asrFolderName, isDirectory: true)
    }

    func ensureAppDirectories() throws {
        try directoriesToCreate.forEach {
            try fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    func artifactLocations(for sourceURL: URL, in parentDirectory: URL? = nil) throws -> ArtifactLocations {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let outputDirectory = (parentDirectory ?? sourceURL.deletingLastPathComponent())
            .appendingPathComponent("\(stem) Transcript", isDirectory: true)

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        return ArtifactLocations(
            outputDirectory: outputDirectory,
            plainTranscript: artifactURL(for: .plainTranscript, stem: stem, in: outputDirectory),
            speakerTranscript: artifactURL(for: .speakerTranscript, stem: stem, in: outputDirectory),
            transcriptionJSON: artifactURL(for: .transcriptionJSON, stem: stem, in: outputDirectory),
            diarizationJSON: artifactURL(for: .diarizationJSON, stem: stem, in: outputDirectory)
        )
    }

    func isSupportedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if Self.supportedExtensions.contains(ext) {
            return true
        }

        guard let type = UTType(filenameExtension: ext) else {
            return false
        }

        return type.conforms(to: .audio)
    }

    func duration(of url: URL) throws -> TimeInterval {
        let audioFile = try AVAudioFile(forReading: url)
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    func validatedUserReportedSpeakerCount(from rawValue: String) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let count = Int(trimmed), Self.validSpeakerCounts.contains(count) else {
            return nil
        }

        return count
    }

    func bundledModelsExist() -> Bool {
        guard let bundledModelsRootDirectory else {
            return false
        }

        return bundledModelsExist(in: bundledModelsRootDirectory)
    }

    func offlineDiarizerModelsExist() -> Bool {
        offlineDiarizerModelsExist(in: modelsRootDirectory)
    }

    func offlineDiarizerModelsExist(in modelsRootDirectory: URL) -> Bool {
        hasRequiredFiles(Self.requiredOfflineDiarizerFiles, in: diarizerDirectory(in: modelsRootDirectory))
    }

    private func asrModelsExist(in directory: URL) -> Bool {
        hasRequiredFiles(Self.requiredAsrFiles, in: directory)
    }

    private func bundledModelsExist(in rootDirectory: URL) -> Bool {
        asrModelsExist(in: rootDirectory.appendingPathComponent(asrFolderName, isDirectory: true))
            && offlineDiarizerModelsExist(in: rootDirectory)
    }

    private func artifactURL(
        for kind: RunArtifact.Kind,
        stem: String,
        in outputDirectory: URL
    ) -> URL {
        outputDirectory.appendingPathComponent(kind.filename(for: stem))
    }

    private func hasRequiredFiles(_ paths: [String], in directory: URL) -> Bool {
        paths.allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    private func diarizerDirectory(in modelsRootDirectory: URL) -> URL {
        modelsRootDirectory.appendingPathComponent(diarizerFolderName, isDirectory: true)
    }

    private func existingDirectory(at url: URL?) -> URL? {
        guard let url, fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return url
    }

    private var directoriesToCreate: [URL] {
        [applicationSupportDirectory, runsDirectory, modelsRootDirectory]
    }
}
