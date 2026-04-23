import Foundation

struct RunArtifact: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case plainTranscript
        case speakerTranscript
        case transcriptionJSON
        case diarizationJSON

        var title: String {
            switch self {
            case .plainTranscript:
                return L10n.tr("Plain Transcript")
            case .speakerTranscript:
                return L10n.tr("Speaker Transcript")
            case .transcriptionJSON:
                return L10n.tr("Transcription JSON")
            case .diarizationJSON:
                return L10n.tr("Diarization JSON")
            }
        }

        var symbolName: String {
            switch self {
            case .plainTranscript:
                return "doc.text"
            case .speakerTranscript:
                return "person.2"
            case .transcriptionJSON:
                return "curlybraces.square"
            case .diarizationJSON:
                return "waveform"
            }
        }

        var sortOrder: Int {
            switch self {
            case .plainTranscript:
                return 0
            case .speakerTranscript:
                return 1
            case .transcriptionJSON:
                return 2
            case .diarizationJSON:
                return 3
            }
        }

        func filename(for stem: String) -> String {
            switch self {
            case .plainTranscript:
                return "\(stem).txt"
            case .speakerTranscript:
                return "\(stem).speakers.txt"
            case .transcriptionJSON:
                return "\(stem).json"
            case .diarizationJSON:
                return "\(stem).diarization.json"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let path: String

    init(id: UUID = UUID(), kind: Kind, path: String) {
        self.id = id
        self.kind = kind
        self.path = path
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }
}
