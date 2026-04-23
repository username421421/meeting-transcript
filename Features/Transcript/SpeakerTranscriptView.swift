import SwiftUI

struct SpeakerTranscriptView: View {
    let turns: [SpeakerTurn]
    let searchText: String

    var body: some View {
        if turns.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? L10n.tr("No Speaker Transcript") : L10n.tr("No Matches"),
                systemImage: "person.2.slash"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 10) {
                                Text(turn.speakerID)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .glassEffect(in: .capsule)

                                Spacer(minLength: 0)

                                Text("\(TimecodeFormatter.string(from: turn.startTime)) – \(TimecodeFormatter.string(from: turn.endTime))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Text(turn.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)

                        if index < turns.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
