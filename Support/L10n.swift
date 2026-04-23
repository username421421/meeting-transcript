import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: .current, arguments: arguments)
    }

    static func speakerLabel(_ index: Int) -> String {
        format("Speaker %lld", Int64(index))
    }
}
