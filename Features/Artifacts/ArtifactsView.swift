import SwiftUI

struct ArtifactsView: View {
    @Bindable var appState: AppState
    let run: RunRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(exportFolderName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                actionButton(
                    title: "Export Files",
                    systemImage: "square.and.arrow.up",
                    action: appState.exportSelectedOutputs
                )

                Divider()

                ForEach(Array(RunArtifact.Kind.allCases.enumerated()), id: \.element) { index, kind in
                    HStack(spacing: 14) {
                        Image(systemName: kind.symbolName)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                            .padding(10)
                            .glassEffect(in: .circle)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.title)
                                .font(.headline)
                            Text(kind.filename(for: run.displayName))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)

                    if index < RunArtifact.Kind.allCases.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func actionButton(
        title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var exportFolderName: String {
        "\(run.displayName) Transcript"
    }
}
