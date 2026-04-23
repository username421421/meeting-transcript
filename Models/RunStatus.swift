import Foundation
import SwiftUI

enum RunStatus: Hashable, Codable, Sendable {
    case idle
    case preparingModels
    case processing
    case writingArtifacts
    case cancelled
    case completed
    case failed(message: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
    }

    private enum Kind: String, Codable {
        case idle
        case preparingModels
        case processing
        case writingArtifacts
        case cancelled
        case completed
        case failed
    }

    private var kind: Kind {
        switch self {
        case .idle:
            return .idle
        case .preparingModels:
            return .preparingModels
        case .processing:
            return .processing
        case .writingArtifacts:
            return .writingArtifacts
        case .cancelled:
            return .cancelled
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }

    private var failureMessage: String? {
        guard case .failed(let message) = self else {
            return nil
        }

        return message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let message = try container.decodeIfPresent(String.self, forKey: .message)
        self = try Self.makeStatus(kind: kind, message: message)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        if let failureMessage {
            try container.encode(failureMessage, forKey: .message)
        }
    }

    var label: String {
        switch self {
        case .idle:
            return L10n.tr("Ready")
        case .preparingModels:
            return L10n.tr("Preparing Models")
        case .processing:
            return L10n.tr("Processing")
        case .writingArtifacts:
            return L10n.tr("Finalizing")
        case .cancelled:
            return L10n.tr("Stopped")
        case .completed:
            return L10n.tr("Completed")
        case .failed:
            return L10n.tr("Failed")
        }
    }

    var isTerminal: Bool {
        switch self {
        case .cancelled, .completed, .failed:
            return true
        default:
            return false
        }
    }

    var terminalDetailMessage: String? {
        switch self {
        case .cancelled:
            return L10n.tr("Stopped before completion.")
        case .failed(let message):
            return message
        default:
            return nil
        }
    }

    var tintColor: Color {
        switch self {
        case .failed:
            return .red
        case .preparingModels, .processing, .writingArtifacts:
            return .blue
        case .idle, .cancelled, .completed:
            return .secondary
        }
    }

    private static func makeStatus(kind: Kind, message: String?) throws -> RunStatus {
        switch kind {
        case .idle:
            return .idle
        case .preparingModels:
            return .preparingModels
        case .processing:
            return .processing
        case .writingArtifacts:
            return .writingArtifacts
        case .cancelled:
            return .cancelled
        case .completed:
            return .completed
        case .failed:
            guard let message else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [CodingKeys.message], debugDescription: "Missing failure message.")
                )
            }
            return .failed(message: message)
        }
    }
}
