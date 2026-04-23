import SwiftUI

struct ImportView: View {
    @Bindable var appState: AppState
    let isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                dropSurface

                if !appState.recentRuns.isEmpty {
                    recentRunsSurface
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var dropSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            if appState.modelState.shouldDisplayInImportView {
                responsivePair {
                    intro
                } trailing: {
                    modelBadge
                }
            } else {
                intro
            }

            dropTarget

            responsivePair(horizontalAlignment: .center) {
                peopleField
            } trailing: {
                importButton
            }
        }
        .padding(22)
        .frame(maxWidth: 760, alignment: .leading)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 32))
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "waveform.and.mic")
                .font(.system(size: 28, weight: .medium))
                .padding(14)
                .glassEffect(.regular.interactive(), in: .circle)

            Text(isDropTargeted ? L10n.tr("Drop Audio") : L10n.tr("Transcribe Audio"))
                .font(.title3.weight(.semibold))
        }
    }

    private var modelBadge: some View {
        Text(appState.modelState.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.clear, in: .capsule)
    }

    private var dropTarget: some View {
        VStack(spacing: 10) {
            Image(systemName: isDropTargeted ? "sparkles.rectangle.stack.fill" : "arrow.down.doc")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isDropTargeted ? .primary : .secondary)

            Text(isDropTargeted ? L10n.tr("Release to Start") : L10n.tr("Drop Audio Here"))
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
    }

    private var peopleField: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("People"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Auto", text: $appState.importSpeakerCount)
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
        }
        .controlSize(.small)
    }

    private var importButton: some View {
        Button {
            appState.presentImportPanel()
        } label: {
            Label(L10n.tr("Choose Audio"), systemImage: "folder.badge.plus")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: 156, minHeight: 42)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func responsivePair<Leading: View, Trailing: View>(
        horizontalAlignment: VerticalAlignment = .top,
        verticalSpacing: CGFloat = 12,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: horizontalAlignment, spacing: 16) {
                leading()
                Spacer(minLength: 0)
                trailing()
            }

            VStack(alignment: .leading, spacing: verticalSpacing) {
                leading()
                trailing()
            }
        }
    }

    private var recentRunsSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(L10n.tr("Recent transcripts"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    Task {
                        await appState.clearRecentRuns()
                    }
                } label: {
                    Text(L10n.tr("Clear"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(minHeight: 30)
                        .contentShape(Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(appState.recentRuns.prefix(6)) { run in
                        Button {
                            appState.selectRun(run.id)
                        } label: {
                            RecentRunChip(run: run)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: 760, alignment: .leading)
        .glassEffect(.clear, in: .rect(cornerRadius: 28))
    }
}

private struct RecentRunChip: View {
    let run: RunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(run.displayName)
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(run.status.label)
                    .foregroundStyle(run.status.tintColor)

                Text(run.createdAt.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .frame(width: 180, alignment: .leading)
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}
