import AppKit
import Foundation
import Observation

enum TranscriptWorkspaceTab: String, CaseIterable, Identifiable, Sendable {
    case speakers
    case plain
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speakers:
            return L10n.tr("Speakers")
        case .plain:
            return L10n.tr("Plain")
        case .files:
            return L10n.tr("Files")
        }
    }
}

@MainActor
@Observable
final class AppState {
    private enum RunStartValidationError: LocalizedError {
        case activeRunInProgress
        case unsupportedFile(String)
        case invalidSpeakerCount

        var errorDescription: String? {
            switch self {
            case .activeRunInProgress:
                return L10n.tr("A transcription is already running.")
            case .unsupportedFile(let filename):
                return L10n.format("%@ is not a supported audio file.", filename)
            case .invalidSpeakerCount:
                return L10n.tr("People count must be an integer between 1 and 32.")
            }
        }
    }

    @ObservationIgnored private let fileAccess: FileAccess
    @ObservationIgnored private let repository: RunRepository
    @ObservationIgnored private let contentStore: RunContentStore
    @ObservationIgnored private let fluidAudioClient: FluidAudioClient
    @ObservationIgnored private let bootstrapper: ModelBootstrapper
    @ObservationIgnored private let coordinator: PipelineCoordinator
    @ObservationIgnored private let artifactWriter: ArtifactWriter
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private var hasLoadedInitialState = false
    @ObservationIgnored private var activeRunTask: Task<RunRecord, Error>?
    @ObservationIgnored private var modelWarmupTask: Task<Void, Never>?

    var recentRuns: [RunRecord] = []
    var selectedRunID: RunRecord.ID?
    var selectedTab: TranscriptWorkspaceTab = .speakers
    var searchText = ""
    var importSpeakerCount = ""
    var isShowingImportDraft = false
    var modelState: ModelBootstrapState = .unknown
    var activeRunID: UUID?
    var activeProgress: PipelineProgress?
    var isCancellingActiveRun = false
    var selectedRunContent: StoredRunContent?
    var errorMessage: String?

    init(
        fileAccess: FileAccess = FileAccess(),
        repository: RunRepository? = nil,
        fluidAudioClient: FluidAudioClient? = nil,
        contentStore: RunContentStore? = nil,
        coordinator: PipelineCoordinator? = nil,
        artifactWriter: ArtifactWriter? = nil
    ) {
        self.fileAccess = fileAccess
        let repository = repository ?? RunRepository(fileAccess: fileAccess)
        let client = fluidAudioClient ?? FluidAudioClient(fileAccess: fileAccess)
        let contentStore = contentStore ?? RunContentStore(fileAccess: fileAccess)
        self.repository = repository
        self.contentStore = contentStore
        self.fluidAudioClient = client
        self.bootstrapper = ModelBootstrapper(client: client)
        self.artifactWriter = artifactWriter ?? ArtifactWriter(fileAccess: fileAccess)
        self.coordinator = coordinator ?? PipelineCoordinator(
            fileAccess: fileAccess,
            repository: repository,
            fluidAudioClient: client,
            contentStore: contentStore
        )
    }

    var selectedRun: RunRecord? {
        recentRuns.first(where: { $0.id == selectedRunID })
    }

    var isShowingImportView: Bool {
        isShowingImportDraft || selectedRun == nil
    }

    var canCopySelectedTranscript: Bool {
        selectedTranscriptForClipboard != nil
    }

    var canStopActiveRun: Bool {
        activeRunTask != nil
    }

    var canStopSelectedRun: Bool {
        isSelectedRunActive && canStopActiveRun
    }

    var stopMenuTitle: String {
        stopTitle(whenIdle: L10n.tr("Stop Current Transcription"))
    }

    var stopDetailTitle: String {
        stopTitle(whenIdle: L10n.tr("Stop Transcription"))
    }

    var filteredSpeakerTurns: [SpeakerTurn] {
        guard let selectedRunContent else { return [] }
        guard !searchText.isEmpty else { return selectedRunContent.speakerTurns }

        return selectedRunContent.speakerTurns.filter {
            matchesSearch($0.speakerID) || matchesSearch($0.text)
        }
    }

    var filteredPlainTranscript: String {
        guard let selectedRunContent else { return "" }
        guard !searchText.isEmpty else { return selectedRunContent.plainTranscript }

        return matchesSearch(selectedRunContent.plainTranscript)
            ? selectedRunContent.plainTranscript : ""
    }

    var selectedRunProgress: Double? {
        guard isSelectedRunActive else { return nil }
        return activeProgress?.fractionCompleted
    }

    var selectedRunDetailText: String {
        guard let selectedRun else { return "" }
        if isSelectedRunActive {
            return activeRunDetail(for: selectedRun)
        }

        return selectedRun.status.terminalDetailMessage ?? selectedRun.status.label
    }

    var modelsDirectoryPath: String {
        fileAccess.preferredModelsRootDirectory.path
    }

    var runsDirectoryPath: String {
        fileAccess.runsDirectory.path
    }

    private var trimmedImportSpeakerCount: String {
        importSpeakerCount.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start() async {
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true

        await reloadRuns()
        await refreshModelState()
        startModelWarmupIfReady()
    }

    func reloadRuns() async {
        do {
            recentRuns = try await repository.loadRuns()
            updateSelectionAfterReload()
        } catch {
            present(error)
        }
    }

    func refreshModelState() async {
        modelState = .unknown
        modelState = await bootstrapper.currentState()
    }

    func reloadSelectedRunContent() async {
        guard let selectedRun, selectedRun.status == .completed else {
            clearSelectedRunContent()
            return
        }

        clearSelectedRunContent()

        do {
            selectedRunContent = try loadContent(for: selectedRun)
        } catch {
            present(error)
            clearSelectedRunContent()
        }
    }

    func presentImportPanel() {
        let panel = makeImportPanel()
        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return
        }

        queueRun(for: sourceURL)
    }

    func presentImportDraft() {
        isShowingImportDraft = true
        selectedRunID = nil
        resetTranscriptSelection()
        importSpeakerCount = ""
        errorMessage = nil
    }

    func selectRun(_ runID: RunRecord.ID) {
        showRunDetails(for: runID)
    }

    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        guard let first = urls.first else {
            return false
        }

        queueRun(for: first)
        return true
    }

    func startRun(with sourceURL: URL) async {
        let parsedSpeakerCount: Int?

        do {
            parsedSpeakerCount = try validateRunStart(for: sourceURL)
        } catch {
            present(error)
            return
        }

        prepareForRunStart()

        let task = Task<RunRecord, Error> {
            try await coordinator.process(
                sourceURL: sourceURL,
                userReportedSpeakerCount: parsedSpeakerCount
            ) { [weak self] progress in
                await self?.apply(progress: progress)
            }
        }
        activeRunTask = task

        do {
            let completedRun = try await task.value
            await handleCompletedRun(completedRun)
        } catch is CancellationError {
            await handleCancelledRun()
        } catch {
            await handleFailedRun(error)
        }
    }

    func cancelActiveRun() {
        guard canStopActiveRun, !isCancellingActiveRun else { return }
        isCancellingActiveRun = true
        activeRunTask?.cancel()
    }

    @discardableResult
    func copySelectedTranscriptToPasteboard() -> Bool {
        guard let text = selectedTranscriptForClipboard else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func exportSelectedOutputs() {
        guard let selectedRun, selectedRun.status == .completed else { return }

        let panel = NSOpenPanel()
        panel.title = L10n.tr("Export Files")
        panel.prompt = L10n.tr("Export")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            let content = try selectedRunContent ?? loadContent(for: selectedRun)
            _ = try artifactWriter.writeArtifacts(
                run: selectedRun,
                content: content,
                destinationDirectory: destination
            )
        } catch {
            present(error)
        }
    }

    func clearRecentRuns() async {
        guard !recentRuns.isEmpty else { return }

        do {
            try clearStoredRunContentFiles()
            try await repository.save([])

            recentRuns = []
            presentImportDraft()
        } catch {
            present(error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func apply(progress: PipelineProgress) async {
        isShowingImportDraft = false
        activeRunID = progress.run.id
        activeProgress = progress
        upsert(progress.run)
        selectedRunID = progress.run.id
    }

    private func upsert(_ run: RunRecord) {
        recentRuns.removeAll(where: { $0.id == run.id })
        recentRuns.insert(run, at: 0)
        recentRuns.sort(by: { $0.createdAt > $1.createdAt })
    }

    private func stopTitle(whenIdle idleTitle: String) -> String {
        isCancellingActiveRun ? L10n.tr("Stopping...") : idleTitle
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func matchesSearch(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains(searchText)
    }

    private func activeRunDetail(for run: RunRecord) -> String {
        isCancellingActiveRun
            ? L10n.tr("Stopping")
            : (activeProgress?.detail ?? run.status.label)
    }

    private var isSelectedRunActive: Bool {
        guard let selectedRun else { return false }
        return selectedRun.id == activeRunID
    }

    private var selectedTranscriptForClipboard: String? {
        switch selectedTab {
        case .speakers:
            return speakerTranscriptForClipboard(from: filteredSpeakerTurns)
        case .plain:
            return nonEmptyTranscript(from: filteredPlainTranscript)
        case .files:
            return nil
        }
    }

    private func loadContent(for run: RunRecord) throws -> StoredRunContent {
        if let contentURL = run.contentURL {
            return try contentStore.load(from: contentURL.path)
        }

        if let transcriptionArtifact = run.artifact(.transcriptionJSON) {
            return try loadArtifactBackedContent(
                for: run,
                transcriptionArtifact: transcriptionArtifact
            )
        }

        return try loadPlainTranscriptFallback(for: run)
    }

    private func loadArtifactBackedContent(
        for run: RunRecord,
        transcriptionArtifact: RunArtifact
    ) throws -> StoredRunContent {
        let payload = try decode(
            TranscriptionArtifactPayload.self,
            from: transcriptionArtifact.url
        )
        return StoredRunContent(
            plainTranscript: payload.plainTranscript,
            speakerTurns: payload.speakerTurns,
            tokenTimings: payload.tokenTimings,
            diarizationSegments: try loadDiarizationSegments(for: run)
        )
    }

    private func loadDiarizationSegments(for run: RunRecord) throws -> [ArtifactDiarizationSegment] {
        guard let diarizationArtifact = run.artifact(.diarizationJSON) else {
            return []
        }

        let payload = try decode(DiarizationArtifactPayload.self, from: diarizationArtifact.url)
        return payload.segments
    }

    private func loadPlainTranscriptFallback(for run: RunRecord) throws -> StoredRunContent {
        let plainTranscript = try run.artifact(.plainTranscript)
            .map { try String(contentsOf: $0.url, encoding: .utf8) } ?? ""

        return StoredRunContent(
            plainTranscript: plainTranscript,
            speakerTurns: [],
            tokenTimings: [],
            diarizationSegments: []
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    private func speakerTranscriptForClipboard(from turns: [SpeakerTurn]) -> String? {
        guard !turns.isEmpty else { return nil }

        return turns.map { turn in
            "\(turn.speakerID):\n\(turn.text)"
        }
        .joined(separator: "\n\n")
    }

    private func nonEmptyTranscript(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func validateRunStart(for sourceURL: URL) throws -> Int? {
        guard activeRunTask == nil else {
            throw RunStartValidationError.activeRunInProgress
        }

        guard fileAccess.isSupportedAudioFile(sourceURL) else {
            throw RunStartValidationError.unsupportedFile(sourceURL.lastPathComponent)
        }

        let parsedSpeakerCount = fileAccess.validatedUserReportedSpeakerCount(from: importSpeakerCount)
        if !trimmedImportSpeakerCount.isEmpty, parsedSpeakerCount == nil {
            throw RunStartValidationError.invalidSpeakerCount
        }

        return parsedSpeakerCount
    }

    private func prepareForRunStart() {
        isShowingImportDraft = false
        resetTranscriptSelection(keepSearch: true)
        clearError()
    }

    private func handleCompletedRun(_ run: RunRecord) async {
        isShowingImportDraft = false
        await finalizeRun(
            modelState: .ready,
            selectedRunID: run.id,
            reloadSelectedRunContent: true
        )
    }

    private func handleCancelledRun() async {
        await finalizeRun(shouldRefreshModelState: true, reloadSelectedRunContent: true)
    }

    private func handleFailedRun(_ error: Error) async {
        await finalizeRun(
            modelState: .failed(error.localizedDescription),
            errorMessage: error.localizedDescription
        )
    }

    private func finalizeRun(
        modelState: ModelBootstrapState? = nil,
        errorMessage: String? = nil,
        selectedRunID: RunRecord.ID? = nil,
        shouldRefreshModelState: Bool = false,
        reloadSelectedRunContent: Bool = false
    ) async {
        clearActiveRunState()
        importSpeakerCount = ""
        self.errorMessage = errorMessage

        if let modelState {
            self.modelState = modelState
        }

        if shouldRefreshModelState {
            await refreshModelState()
        }

        await reloadRuns()

        if let selectedRunID {
            self.selectedRunID = selectedRunID
        }

        if reloadSelectedRunContent {
            await self.reloadSelectedRunContent()
        }
    }

    private func resetTranscriptSelection(keepSearch: Bool = false) {
        if !keepSearch {
            searchText = ""
        }
        selectedTab = .speakers
        selectedRunContent = nil
    }

    private func makeImportPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("Import Audio")
        panel.prompt = L10n.tr("Open")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        return panel
    }

    private func queueRun(for sourceURL: URL) {
        Task {
            await startRun(with: sourceURL)
        }
    }

    private func startModelWarmupIfReady() {
        guard modelState == .ready, modelWarmupTask == nil else {
            return
        }

        modelWarmupTask = Task { [weak self] in
            await self?.warmModelsInBackground()
        }
    }

    private func warmModelsInBackground() async {
        defer { modelWarmupTask = nil }

        do {
            try await fluidAudioClient.prepareModels()
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    private func updateSelectionAfterReload() {
        if !selectedRunExists(in: recentRuns) && !isShowingImportDraft {
            selectedRunID = recentRuns.first?.id
        }
    }

    private func showRunDetails(for runID: RunRecord.ID) {
        isShowingImportDraft = false
        searchText = ""
        clearSelectedRunContent()
        selectedRunID = runID
    }

    private func selectedRunExists(in runs: [RunRecord]) -> Bool {
        guard let selectedRunID else {
            return false
        }

        return runs.contains(where: { $0.id == selectedRunID })
    }

    private func clearSelectedRunContent() {
        selectedRunContent = nil
    }

    private func clearStoredRunContentFiles() throws {
        try fileAccess.ensureAppDirectories()

        let contentURLs = try FileManager.default.contentsOfDirectory(
            at: fileAccess.runsDirectory,
            includingPropertiesForKeys: nil
        )

        for url in contentURLs where url.lastPathComponent.hasSuffix(".content.json") {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func clearActiveRunState() {
        activeRunTask = nil
        activeRunID = nil
        activeProgress = nil
        isCancellingActiveRun = false
    }
}
