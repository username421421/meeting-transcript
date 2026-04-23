import SwiftUI

struct MainWindowScene: Scene {
    let appState: AppState

    var body: some Scene {
        WindowGroup("Transcribe") {
            MainWindowRootView(appState: appState)
        }
        .defaultSize(width: 560, height: 760)
        .windowResizability(.contentMinSize)
    }
}

private struct MainWindowRootView: View {
    @Bindable var appState: AppState
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            LiquidGlassBackdrop()
                .ignoresSafeArea()

            TranscriptDetailView(
                appState: appState,
                isDropTargeted: isDropTargeted
            )
            .frame(maxWidth: 600, maxHeight: .infinity, alignment: .top)
            .padding(16)
        }
        .searchable(text: $appState.searchText, placement: .toolbar, prompt: "Search transcript")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 500, minHeight: 640)
        .tint(.blue)
        .containerBackground(.ultraThinMaterial, for: .window)
        .toolbar {
            ToolbarItemGroup {
                Button("New Transcript", systemImage: "waveform.badge.plus") {
                    appState.presentImportDraft()
                }

                if appState.recentRuns.count > 1 {
                    recentRunsMenu
                }
            }
        }
        .dropDestination(
            for: URL.self,
            action: { urls, _ in appState.handleDroppedFiles(urls) },
            isTargeted: { isTargeted in
                isDropTargeted = isTargeted
            }
        )
        .alert(
            "Transcribe",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                appState.clearError()
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .task {
            await appState.start()
        }
        .task(id: appState.selectedRunID) {
            await appState.reloadSelectedRunContent()
        }
    }

    private var recentRunsMenu: some View {
        Menu("Recent", systemImage: "clock.arrow.circlepath") {
            ForEach(appState.recentRuns) { run in
                Button {
                    appState.selectRun(run.id)
                } label: {
                    RecentRunMenuLabel(run: run)
                }
            }
        }
    }

}

private struct RecentRunMenuLabel: View {
    let run: RunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(run.displayName)
            Text(run.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LiquidGlassBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color(red: 0.85, green: 0.9, blue: 0.98).opacity(0.04),
                        Color(red: 0.95, green: 0.97, blue: 0.995).opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: proxy.size.width * 0.7)
                    .blur(radius: 110)
                    .offset(x: -proxy.size.width * 0.22, y: -proxy.size.height * 0.24)

                Circle()
                    .fill(Color(red: 0.78, green: 0.86, blue: 0.99).opacity(0.07))
                    .frame(width: proxy.size.width * 0.62)
                    .blur(radius: 140)
                    .offset(x: proxy.size.width * 0.28, y: -proxy.size.height * 0.08)

                Ellipse()
                    .fill(Color(red: 0.86, green: 0.92, blue: 1.0).opacity(0.05))
                    .frame(width: proxy.size.width * 0.78, height: proxy.size.height * 0.42)
                    .blur(radius: 125)
                    .offset(x: 0, y: proxy.size.height * 0.34)
            }
            .saturation(0.74)
        }
        .allowsHitTesting(false)
    }
}
