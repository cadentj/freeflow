import Foundation

enum SessionIntent {
    case dictation
    case journal

    var isJournalMode: Bool {
        switch self {
        case .journal:
            return true
        case .dictation:
            return false
        }
    }

    var recordingOverlayMode: RecordingOverlayMode {
        switch self {
        case .dictation:
            return .dictation
        case .journal:
            return .journal
        }
    }

    var persistedIntent: PipelineHistoryItemIntent {
        switch self {
        case .dictation:
            return .dictation
        case .journal:
            return .journal
        }
    }

    static func fromPersisted(intent: PipelineHistoryItemIntent) -> SessionIntent {
        if intent == .journal {
            return .journal
        }
        return .dictation
    }
}
