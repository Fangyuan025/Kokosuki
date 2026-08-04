import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var lang: Lang {
        didSet {
            L10n.lang = lang
            UserDefaults.standard.set(lang.rawValue, forKey: "lang")
            NotificationCenter.default.post(name: .kokosukiLangChanged, object: nil)
        }
    }
    @Published var petScale: Double {   // 0.75 small, 1.0 medium, 1.3 large
        didSet { UserDefaults.standard.set(petScale, forKey: "petScale") }
    }
    @Published var chatterEnabled: Bool {
        didSet { UserDefaults.standard.set(chatterEnabled, forKey: "chatterEnabled") }
    }
    @Published var chatterFreq: Double {  // mean minutes between spontaneous lines
        didSet { UserDefaults.standard.set(chatterFreq, forKey: "chatterFreq") }
    }
    @Published var autoSleep: Bool {
        didSet { UserDefaults.standard.set(autoSleep, forKey: "autoSleep") }
    }
    @Published var windowParkour: Bool {
        didSet { UserDefaults.standard.set(windowParkour, forKey: "windowParkour") }
    }
    @Published var thinkingEnabled: Bool {
        didSet { UserDefaults.standard.set(thinkingEnabled, forKey: "thinkingEnabled") }
    }

    private init() {
        let d = UserDefaults.standard
        let savedLang = d.string(forKey: "lang").flatMap(Lang.init(rawValue:)) ?? Lang.systemDefault
        lang = savedLang
        L10n.lang = savedLang
        petScale = d.object(forKey: "petScale") as? Double ?? 1.0
        chatterEnabled = d.object(forKey: "chatterEnabled") as? Bool ?? true
        chatterFreq = d.object(forKey: "chatterFreq") as? Double ?? 6
        autoSleep = d.object(forKey: "autoSleep") as? Bool ?? true
        windowParkour = d.object(forKey: "windowParkour") as? Bool ?? true
        thinkingEnabled = d.object(forKey: "thinkingEnabled") as? Bool ?? false
    }
}

extension Notification.Name {
    static let kokosukiLangChanged = Notification.Name("kokosukiLangChanged")
}
