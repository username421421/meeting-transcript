import Foundation

enum ModelBootstrapState: Equatable, Sendable {
    case unknown
    case missing
    case preparing
    case ready
    case failed(String)

    var shouldDisplayInImportView: Bool {
        switch self {
        case .missing, .preparing, .failed:
            return true
        case .unknown, .ready:
            return false
        }
    }

    var label: String {
        switch self {
        case .unknown:
            return L10n.tr("Checking Models")
        case .missing:
            return L10n.tr("Models Need Download")
        case .preparing:
            return L10n.tr("Preparing Models")
        case .ready:
            return L10n.tr("Models Ready")
        case .failed:
            return L10n.tr("Model Setup Failed")
        }
    }
}

struct ModelBootstrapper {
    let client: FluidAudioClient

    func currentState() async -> ModelBootstrapState {
        await client.modelsReadyLocally() ? .ready : .missing
    }
}
