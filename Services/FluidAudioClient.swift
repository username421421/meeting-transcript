import Foundation
import FluidAudio

actor FluidAudioClient {
    private enum ModelSource {
        case bundled
        case downloaded(forceReload: Bool)
    }

    private let fileAccess: FileAccess
    private let asrManager = AsrManager(config: .default)
    nonisolated(unsafe) private let diarizer = OfflineDiarizerManager(config: .default)
    private var isPrepared = false
    private var preparationTask: Task<Void, Error>?

    init(fileAccess: FileAccess = FileAccess()) {
        self.fileAccess = fileAccess
    }

    func modelsReadyLocally() -> Bool {
        bundledModelsAvailable || downloadedModelsExist
    }

    func prepareModels(forceReload: Bool = false) async throws {
        if canReusePreparedModels(forceReload: forceReload) {
            return
        }

        if let preparationTask {
            try await preparationTask.value
            return
        }

        let modelSource: ModelSource = bundledModelsAvailable
            ? .bundled
            : .downloaded(forceReload: forceReload)
        let preparationTask = Task { [self] in
            try await prepareModels(from: modelSource)
        }
        self.preparationTask = preparationTask
        defer { self.preparationTask = nil }

        try await preparationTask.value
        isPrepared = true
    }

    private var bundledModelsAvailable: Bool {
        fileAccess.bundledModelsExist()
    }

    private var downloadedModelsExist: Bool {
        AsrModels.modelsExist(at: fileAccess.asrModelsDirectory, version: .v3)
            && fileAccess.offlineDiarizerModelsExist()
    }

    private func canReusePreparedModels(forceReload: Bool) -> Bool {
        isPrepared && (!forceReload || bundledModelsAvailable)
    }

    private func prepareModels(from source: ModelSource) async throws {
        switch source {
        case .bundled:
            try await prepareBundledModels()
        case .downloaded(let forceReload):
            try await prepareDownloadedModels(forceReload: forceReload)
        }
    }

    private func prepareBundledModels() async throws {
        try await prepareLoadedModels(
            modelsRootDirectory: fileAccess.preferredModelsRootDirectory,
            asrModels: {
                try await AsrModels.load(
                    from: fileAccess.preferredAsrModelsDirectory,
                    version: .v3
                )
            }
        )
    }

    private func prepareDownloadedModels(forceReload: Bool) async throws {
        try fileAccess.ensureAppDirectories()

        try await prepareLoadedModels(
            modelsRootDirectory: fileAccess.modelsRootDirectory,
            asrModels: {
                try await AsrModels.downloadAndLoad(
                    to: fileAccess.asrModelsDirectory,
                    version: .v3
                )
            },
            forceRedownloadDiarizer: forceReload
        )
    }

    private func prepareLoadedModels(
        modelsRootDirectory: URL,
        asrModels: () async throws -> AsrModels,
        forceRedownloadDiarizer: Bool = false
    ) async throws {
        let asrModels = try await asrModels()
        try await asrManager.loadModels(asrModels)
        try await diarizer.prepareModels(
            directory: modelsRootDirectory,
            forceRedownload: forceRedownloadDiarizer
        )
    }

    func transcribe(_ sourceURL: URL) async throws -> ASRResult {
        try await prepareModels()
        let decoderLayerCount = await asrManager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
        return try await asrManager.transcribe(sourceURL, decoderState: &decoderState)
    }

    func diarize(_ sourceURL: URL) async throws -> DiarizationResult {
        try await prepareModels()
        return try await diarizer.process(sourceURL)
    }
}
