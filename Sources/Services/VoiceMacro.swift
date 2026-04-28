import Foundation

struct VoiceMacro: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var command: String
    var payload: String
}

struct PrecomputedMacro {
    let original: VoiceMacro
    let normalizedCommand: String
}

enum VoiceMacroMatcher {
    static func precompute(_ macros: [VoiceMacro]) -> [PrecomputedMacro] {
        macros.map { macro in
            PrecomputedMacro(
                original: macro,
                normalizedCommand: normalize(macro.command)
            )
        }
    }

    static func match(transcript: String, macros: [PrecomputedMacro]) -> VoiceMacro? {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return nil }

        return macros.first {
            normalizedTranscript == $0.normalizedCommand
        }?.original
    }

    static func normalize(_ text: String) -> String {
        let lowercased = text.lowercased()
        let strippedPunctuation = lowercased.components(separatedBy: CharacterSet.punctuationCharacters).joined()
        return strippedPunctuation.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
