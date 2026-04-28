import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case prompts
    case macros
    case runLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .prompts: return "Prompts"
        case .macros: return "Voice Macros"
        case .runLog: return "Run Log"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .prompts: return "text.bubble"
        case .macros: return "music.mic"
        case .runLog: return "clock.arrow.circlepath"
        }
    }
}
