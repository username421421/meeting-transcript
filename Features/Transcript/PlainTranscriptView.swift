import SwiftUI

struct PlainTranscriptView: View {
    let transcript: String
    let searchText: String

    var body: some View {
        if transcript.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? L10n.tr("No Transcript") : L10n.tr("No Matches"),
                systemImage: "text.page.slash"
            )
        } else {
            ScrollView {
                Text(transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.vertical, 2)
            }
        }
    }
}
