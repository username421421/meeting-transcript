import SwiftUI

struct TranscriptDetailView: View {
    @Bindable var appState: AppState
    let isDropTargeted: Bool
    @Namespace private var tabSelectionNamespace
    @State private var isShowingCopyToast = false
    @State private var isShowingCopyIcon = true
    @State private var isShowingCopyToastLabel = false
    @State private var copyToastTask: Task<Void, Never>?

    var body: some View {
        content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            if showsDropHintBanner {
                DropHintBanner()
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let run = appState.selectedRun, !appState.isShowingImportView {
            workspace(for: run)
        } else {
            ImportView(appState: appState, isDropTargeted: isDropTargeted)
        }
    }

    private func workspace(for run: RunRecord) -> some View {
        GlassEffectContainer(spacing: 14) {
            headerCard(for: run)

            switch run.status {
            case .completed:
                completedContent(for: run)

            case .failed(let message):
                stateCard(
                    title: "Transcription Failed",
                    systemImage: "exclamationmark.triangle",
                    description: message
                )

            case .cancelled:
                stateCard(
                    title: "Transcription Stopped",
                    systemImage: "stop.circle",
                    description: run.status.terminalDetailMessage ?? L10n.tr("Stopped before completion.")
                )

            default:
                inProgressContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func headerCard(for run: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    titleSection(for: run)
                    Spacer(minLength: 0)
                    headerBadges(for: run)
                }

                VStack(alignment: .leading, spacing: 12) {
                    titleSection(for: run)
                    headerBadges(for: run)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(headerMetaItems(for: run), id: \.text) { item in
                        RunMetaPill(systemImage: item.systemImage, text: item.text)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .detailCard(padding: 18)
    }

    @ViewBuilder
    private func titleSection(for run: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(run.displayName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Text(run.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if run.status != .completed {
                Text(appState.selectedRunDetailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func headerBadges(for run: RunRecord) -> some View {
        GlassEffectContainer(spacing: 10) {
            statusBadge(for: run)

            if let progress = appState.selectedRunProgress {
                RunProgressBadge(progress: progress, tint: run.status.tintColor)
            }
        }
    }

    private func statusBadge(for run: RunRecord) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(run.status.tintColor)
                .frame(width: 8, height: 8)

            Text(run.status.label)
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var copyFeedbackControl: some View {
        Button {
            copyTranscript()
        } label: {
            ZStack {
                Image(systemName: "square.on.square")
                    .font(.callout.weight(.semibold))
                    .opacity(isShowingCopyIcon ? 1 : 0)
                    .scaleEffect(isShowingCopyIcon ? 1 : 0.93)

                Text("Transcript copied")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .opacity(isShowingCopyToastLabel ? 1 : 0)
                    .scaleEffect(isShowingCopyToastLabel ? 1 : 0.985)
            }
            .frame(width: isShowingCopyToast ? 126 : 36, height: 36)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isShowingCopyToast)
        .help(isShowingCopyToast ? "Transcript copied" : copyButtonHelpText)
        .animation(.snappy(duration: 0.34, extraBounce: 0.02), value: isShowingCopyToast)
        .animation(.smooth(duration: 0.16), value: isShowingCopyIcon)
        .animation(.smooth(duration: 0.18), value: isShowingCopyToastLabel)
    }

    @ViewBuilder
    private func completedContent(for run: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    LiquidGlassTabSelector(
                        selection: $appState.selectedTab,
                        namespace: tabSelectionNamespace
                    )

                    Spacer(minLength: 0)

                    if appState.canCopySelectedTranscript {
                        copyFeedbackControl
                    }
                }
            }

            selectedTabContent(for: run)
        }
        .detailCard(padding: 18, alignment: .topLeading)
        .onAppear {
            resetCopyFeedback()
        }
        .onDisappear {
            resetCopyFeedback()
        }
    }

    @ViewBuilder
    private func selectedTabContent(for run: RunRecord) -> some View {
        Group {
            switch appState.selectedTab {
            case .speakers:
                SpeakerTranscriptView(
                    turns: appState.filteredSpeakerTurns,
                    searchText: appState.searchText
                )
            case .plain:
                PlainTranscriptView(
                    transcript: appState.filteredPlainTranscript,
                    searchText: appState.searchText
                )
            case .files:
                ArtifactsView(appState: appState, run: run)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var inProgressContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(appState.selectedRunDetailText, systemImage: "waveform")
                .font(.headline)

            ProgressView(value: appState.selectedRunProgress ?? 0.08)
                .progressViewStyle(.linear)
                .controlSize(.regular)
                .frame(maxWidth: 360)

            if appState.canStopSelectedRun {
                Button(appState.stopDetailTitle, systemImage: "stop.fill") {
                    appState.cancelActiveRun()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(.red).interactive(), in: .capsule)
                .disabled(appState.isCancellingActiveRun)
            }
        }
        .detailCard(padding: 24, alignment: .center)
    }

    private func stateCard(title: String, systemImage: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(LocalizedStringKey(title), systemImage: systemImage)
                .font(.title3.weight(.semibold))

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Transcribe Another File", systemImage: "waveform.badge.plus") {
                appState.presentImportDraft()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .detailCard(padding: 24, alignment: .center)
    }

    private func speakerSummary(for run: RunRecord) -> String {
        if let detectedSpeakerCount = run.detectedSpeakerCount {
            return detectedSpeakerCount == 1
                ? L10n.format("%lld speaker", Int64(detectedSpeakerCount))
                : L10n.format("%lld speakers", Int64(detectedSpeakerCount))
        }

        if let userReportedSpeakerCount = run.userReportedSpeakerCount {
            return L10n.format("%lld reported", Int64(userReportedSpeakerCount))
        }

        return L10n.tr("Speaker count automatic")
    }

    private func headerMetaItems(for run: RunRecord) -> [(systemImage: String, text: String)] {
        var items: [(systemImage: String, text: String)] = [
            ("calendar", run.createdAt.formatted(date: .abbreviated, time: .shortened)),
            ("person.2", speakerSummary(for: run)),
        ]

        if let duration = run.duration {
            items.insert(("clock", TimecodeFormatter.string(from: duration)), at: 1)
        }

        return items
    }

    private var copyButtonHelpText: String {
        switch appState.selectedTab {
        case .speakers:
            return L10n.tr("Copy speaker transcript")
        case .plain:
            return L10n.tr("Copy plain transcript")
        case .files:
            return L10n.tr("Copy transcript")
        }
    }

    private var showsDropHintBanner: Bool {
        isDropTargeted && appState.selectedRun != nil
    }

    private func copyTranscript() {
        guard appState.copySelectedTranscriptToPasteboard() else {
            return
        }

        resetCopyFeedback(hideToast: false)

        withAnimation(.snappy(duration: 0.34, extraBounce: 0.02)) {
            isShowingCopyToast = true
        }

        copyToastTask = Task { @MainActor in
            await runCopyFeedbackSequence()
        }
    }

    private func resetCopyFeedback(hideToast: Bool = true) {
        copyToastTask?.cancel()
        isShowingCopyIcon = true
        isShowingCopyToastLabel = false

        if hideToast {
            isShowingCopyToast = false
        }
    }

    @MainActor
    private func animateCopyFeedback(
        after delay: Duration,
        animation: Animation,
        updates: () -> Void
    ) async -> Bool {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else {
            return false
        }

        withAnimation(animation, updates)
        return true
    }

    @MainActor
    private func runCopyFeedbackSequence() async {
        let steps: [(Duration, Animation, () -> Void)] = [
            (.milliseconds(50), .smooth(duration: 0.16), { isShowingCopyIcon = false }),
            (.milliseconds(95), .smooth(duration: 0.18), { isShowingCopyToastLabel = true }),
            (.seconds(0.9), .smooth(duration: 0.16), { isShowingCopyToastLabel = false }),
            (.milliseconds(55), .smooth(duration: 0.16), { isShowingCopyIcon = true }),
            (.milliseconds(90), .snappy(duration: 0.3, extraBounce: 0.01), { isShowingCopyToast = false }),
        ]

        for (delay, animation, updates) in steps {
            guard await animateCopyFeedback(after: delay, animation: animation, updates: updates) else {
                return
            }
        }
    }
}

private struct LiquidGlassTabSelector: View {
    @Binding var selection: TranscriptWorkspaceTab
    let namespace: Namespace.ID

    var body: some View {
        ZStack {
            track

            HStack(spacing: 4) {
                ForEach(TranscriptWorkspaceTab.allCases) { tab in
                    LiquidGlassTabSegment(
                        tab: tab,
                        isSelected: selection == tab,
                        namespace: namespace
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            selection = tab
                        }
                    }
                }
            }
            .padding(3)
        }
        .frame(height: 42)
        .fixedSize()
    }

    private var track: some View {
        Capsule()
            .fill(Color.black.opacity(0.08))
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.9)
            }
    }
}

private struct LiquidGlassTabSegment: View {
    let tab: TranscriptWorkspaceTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.72))
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.86), lineWidth: 0.9)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                        .frame(height: 36)
                        .matchedGeometryEffect(id: "transcript-tab-selection", in: namespace)
                }

                Text(tab.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected
                            ? Color.black.opacity(0.88)
                            : Color.black.opacity(0.62)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .frame(minWidth: 84, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RunProgressBadge: View {
    let progress: Double
    let tint: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 82, height: 8)

                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(10, 82 * clampedProgress), height: 8)
            }

            Text("\(Int(clampedProgress * 100))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
    }
}

private struct RunMetaPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(in: .capsule)
    }
}

private struct DropHintBanner: View {
    var body: some View {
        Label("Drop a file to start a new transcription", systemImage: "arrow.down.circle.fill")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

private extension View {
    func detailCard(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .glassEffect(.clear, in: .rect(cornerRadius: 30))
    }

    func detailCard(padding: CGFloat, alignment: Alignment) -> some View {
        detailCard(padding: padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
