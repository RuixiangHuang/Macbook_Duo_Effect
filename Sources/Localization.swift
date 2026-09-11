import Foundation

enum Language: String, CaseIterable {
    case english = "en"
    case chinese = "zh"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

final class Localization: ObservableObject {
    static let shared = Localization()

    @Published var language: Language {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: "language")
            onChange?()
        }
    }
    // The status item rebuilds its titles here; SwiftUI observes the object directly.
    var onChange: (() -> Void)?

    private init() {
        // English is the default; the picker in the settings window overrides it.
        let stored = UserDefaults.standard.string(forKey: "language") ?? ""
        language = Language(rawValue: stored) ?? .english
    }
}

/// Text resolved when it is read, not when it is produced, so sensor status and
/// error messages captured earlier still follow a later language switch.
struct LocalizedText {
    let en: String
    let zh: String

    var text: String {
        switch Localization.shared.language {
        case .english: return en
        case .chinese: return zh
        }
    }
}

func t(_ en: String, _ zh: String) -> String { LocalizedText(en: en, zh: zh).text }

extension LocalizedText {
    /// System errors arrive already localized by the OS, so both languages share the text.
    static func system(_ error: Error) -> LocalizedText {
        LocalizedText(en: error.localizedDescription, zh: error.localizedDescription)
    }
}

/// Carries localizable text through a `throw` without losing it to `localizedDescription`.
struct OverlayFailure: Error {
    let text: LocalizedText
    init(_ text: LocalizedText) { self.text = text }
}
