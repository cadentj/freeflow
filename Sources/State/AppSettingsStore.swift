import Foundation

struct AppSettingsStore {
    enum Key {
        static let hasCompletedSetup = "hasCompletedSetup"
        static let apiKey = "groq_api_key"
        static let apiBaseURL = "api_base_url"
        static let transcriptionModel = "transcription_model"
        static let transcriptionAPIURL = "transcription_api_url"
        static let transcriptionAPIKey = "transcription_api_key"
        static let postProcessingModel = "post_processing_model"
        static let postProcessingFallbackModel = "post_processing_fallback_model"
        static let contextModel = "context_model"
        static let holdShortcut = "hold_shortcut"
        static let toggleShortcut = "toggle_shortcut"
        static let savedHoldCustomShortcut = "saved_hold_custom_shortcut"
        static let savedToggleCustomShortcut = "saved_toggle_custom_shortcut"
        static let customVocabulary = "custom_vocabulary"
        static let transcriptionLanguage = "transcription_language"
        static let selectedMicrophone = "selected_microphone_id"
        static let customSystemPrompt = "custom_system_prompt"
        static let customContextPrompt = "custom_context_prompt"
        static let customSystemPromptLastModified = "custom_system_prompt_last_modified"
        static let customContextPromptLastModified = "custom_context_prompt_last_modified"
        static let contextScreenshotMaxDimension = "context_screenshot_max_dimension"
        static let shortcutStartDelay = "shortcut_start_delay"
        static let preserveClipboard = "preserve_clipboard"
        static let pressEnterVoiceCommand = "press_enter_voice_command_enabled"
        static let alertSoundsEnabled = "alert_sounds_enabled"
        static let soundVolume = "sound_volume"
        static let voiceMacros = "voice_macros"
        static let journalModeEnabled = "journal_mode_enabled"
        static let journalModeModifier = "journal_mode_modifier"
        static let journalModeFolderPath = "journal_mode_folder_path"
        static let journalModeFolderBookmark = "journal_mode_folder_bookmark"
        static let outputLanguage = "output_language"
        static let realtimeStreamingEnabled = "realtime_streaming_enabled"
        static let realtimeStreamingModel = "realtime_streaming_model"
        static let dictationAudioInterruptionEnabled = "dictation_audio_interruption_enabled"
        static let legacyHotkeyOption = "hotkey_option"
        static let legacyForceHTTP2Transcription = "force_http2_transcription"
    }

    static let defaultAPIBaseURL = "https://api.groq.com/openai/v1"
    static let defaultContextScreenshotMaxDimension = Int(AppContextService.defaultScreenshotMaxDimension)
    static let contextScreenshotDimensionOptions = [1024, 768, 640, 512]
    static let defaultTranscriptionModel = "whisper-large-v3"
    static let transcriptionLanguageOptions: [(code: String, name: String)] = [
        ("", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ru", "Russian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("uk", "Ukrainian"),
        ("sv", "Swedish"),
        ("no", "Norwegian"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("cs", "Czech"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("vi", "Vietnamese"),
        ("th", "Thai"),
        ("id", "Indonesian"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("ca", "Catalan")
    ]
    static let defaultPostProcessingModel = "openai/gpt-oss-20b"
    static let defaultPostProcessingFallbackModel = "meta-llama/llama-4-scout-17b-16e-instruct"
    static let defaultContextModel = "meta-llama/llama-4-scout-17b-16e-instruct"

    struct LoadedSettings {
        let hasCompletedSetup: Bool
        let apiKey: String
        let apiBaseURL: String
        let transcriptionAPIURL: String
        let transcriptionAPIKey: String
        let transcriptionModel: String
        let postProcessingModel: String
        let postProcessingFallbackModel: String
        let contextModel: String
        let shortcuts: StoredShortcutConfiguration
        let savedHoldCustomShortcut: StoredOptionalShortcut
        let savedToggleCustomShortcut: StoredOptionalShortcut
        let isJournalModeEnabled: Bool
        let journalModeModifier: JournalModeModifier
        let journalModeFolderPath: String
        let journalModeFolderBookmark: Data?
        let customVocabulary: String
        let transcriptionLanguage: String
        let customSystemPrompt: String
        let customContextPrompt: String
        let contextScreenshotMaxDimension: Int
        let customSystemPromptLastModified: String
        let customContextPromptLastModified: String
        let outputLanguage: String
        let shortcutStartDelay: TimeInterval
        let preserveClipboard: Bool
        let realtimeStreamingEnabled: Bool
        let realtimeStreamingModel: String
        let dictationAudioInterruptionEnabled: Bool
        let isPressEnterVoiceCommandEnabled: Bool
        let alertSoundsEnabled: Bool
        let soundVolume: Float
        let voiceMacros: [VoiceMacro]
        let selectedMicrophoneID: String
    }

    struct StoredShortcutConfiguration {
        let hold: ShortcutBinding
        let toggle: ShortcutBinding
        let didUpdateHoldStoredValue: Bool
        let didUpdateToggleStoredValue: Bool
    }

    struct StoredOptionalShortcut {
        let binding: ShortcutBinding?
        let didUpdateStoredValue: Bool
    }

    private struct StoredShortcutLoadResult {
        let binding: ShortcutBinding?
        let hadStoredValue: Bool
        let didNormalize: Bool
    }

    func load() -> LoadedSettings {
        UserDefaults.standard.removeObject(forKey: Key.legacyForceHTTP2Transcription)

        let shortcuts = Self.loadShortcutConfiguration(
            holdKey: Key.holdShortcut,
            toggleKey: Key.toggleShortcut
        )
        let savedHoldCustomShortcut = Self.loadSavedCustomShortcut(
            forKey: Key.savedHoldCustomShortcut,
            fallback: shortcuts.hold.isCustom ? shortcuts.hold : nil
        )
        let savedToggleCustomShortcut = Self.loadSavedCustomShortcut(
            forKey: Key.savedToggleCustomShortcut,
            fallback: shortcuts.toggle.isCustom ? shortcuts.toggle : nil
        )
        let storedContextScreenshotMaxDimension = UserDefaults.standard.object(forKey: Key.contextScreenshotMaxDimension) != nil
            ? UserDefaults.standard.integer(forKey: Key.contextScreenshotMaxDimension)
            : Self.defaultContextScreenshotMaxDimension
        let contextScreenshotMaxDimension = Self.normalizedContextScreenshotMaxDimension(
            storedContextScreenshotMaxDimension
        )
        let soundVolume: Float = UserDefaults.standard.object(forKey: Key.soundVolume) != nil
            ? UserDefaults.standard.float(forKey: Key.soundVolume)
            : 1.0
        let alertSoundsEnabled = UserDefaults.standard.object(forKey: Key.alertSoundsEnabled) != nil
            ? UserDefaults.standard.bool(forKey: Key.alertSoundsEnabled)
            : soundVolume > 0
        let voiceMacros: [VoiceMacro]
        if let data = UserDefaults.standard.data(forKey: Key.voiceMacros),
           let decoded = try? JSONDecoder().decode([VoiceMacro].self, from: data) {
            voiceMacros = decoded
        } else {
            voiceMacros = []
        }

        return LoadedSettings(
            hasCompletedSetup: UserDefaults.standard.bool(forKey: Key.hasCompletedSetup),
            apiKey: Self.loadStoredAPIKey(account: Key.apiKey),
            apiBaseURL: Self.loadStoredAPIBaseURL(account: Key.apiBaseURL),
            transcriptionAPIURL: Self.loadOptionalStoredAPIValue(account: Key.transcriptionAPIURL),
            transcriptionAPIKey: Self.loadStoredAPIKey(account: Key.transcriptionAPIKey),
            transcriptionModel: UserDefaults.standard.string(forKey: Key.transcriptionModel) ?? Self.defaultTranscriptionModel,
            postProcessingModel: UserDefaults.standard.string(forKey: Key.postProcessingModel) ?? Self.defaultPostProcessingModel,
            postProcessingFallbackModel: UserDefaults.standard.string(forKey: Key.postProcessingFallbackModel) ?? Self.defaultPostProcessingFallbackModel,
            contextModel: UserDefaults.standard.string(forKey: Key.contextModel) ?? Self.defaultContextModel,
            shortcuts: shortcuts,
            savedHoldCustomShortcut: savedHoldCustomShortcut,
            savedToggleCustomShortcut: savedToggleCustomShortcut,
            isJournalModeEnabled: UserDefaults.standard.bool(forKey: Key.journalModeEnabled),
            journalModeModifier: JournalModeModifier(
                rawValue: UserDefaults.standard.string(forKey: Key.journalModeModifier) ?? ""
            ) ?? .control,
            journalModeFolderPath: UserDefaults.standard.string(forKey: Key.journalModeFolderPath)
                ?? JournalLogStore.defaultFolderURL.path,
            journalModeFolderBookmark: UserDefaults.standard.data(forKey: Key.journalModeFolderBookmark),
            customVocabulary: UserDefaults.standard.string(forKey: Key.customVocabulary) ?? "",
            transcriptionLanguage: Self.normalizeTranscriptionLanguage(
                UserDefaults.standard.string(forKey: Key.transcriptionLanguage) ?? ""
            ),
            customSystemPrompt: UserDefaults.standard.string(forKey: Key.customSystemPrompt) ?? "",
            customContextPrompt: UserDefaults.standard.string(forKey: Key.customContextPrompt) ?? "",
            contextScreenshotMaxDimension: contextScreenshotMaxDimension,
            customSystemPromptLastModified: UserDefaults.standard.string(forKey: Key.customSystemPromptLastModified) ?? "",
            customContextPromptLastModified: UserDefaults.standard.string(forKey: Key.customContextPromptLastModified) ?? "",
            outputLanguage: UserDefaults.standard.string(forKey: Key.outputLanguage) ?? "",
            shortcutStartDelay: max(0, UserDefaults.standard.double(forKey: Key.shortcutStartDelay)),
            preserveClipboard: UserDefaults.standard.object(forKey: Key.preserveClipboard) == nil
                ? true
                : UserDefaults.standard.bool(forKey: Key.preserveClipboard),
            realtimeStreamingEnabled: UserDefaults.standard.bool(forKey: Key.realtimeStreamingEnabled),
            realtimeStreamingModel: UserDefaults.standard.string(forKey: Key.realtimeStreamingModel) ?? "",
            dictationAudioInterruptionEnabled: UserDefaults.standard.bool(forKey: Key.dictationAudioInterruptionEnabled),
            isPressEnterVoiceCommandEnabled: UserDefaults.standard.object(forKey: Key.pressEnterVoiceCommand) == nil
                ? true
                : UserDefaults.standard.bool(forKey: Key.pressEnterVoiceCommand),
            alertSoundsEnabled: alertSoundsEnabled,
            soundVolume: soundVolume,
            voiceMacros: voiceMacros,
            selectedMicrophoneID: UserDefaults.standard.string(forKey: Key.selectedMicrophone) ?? "default"
        )
    }

    func persistAPIKey(_ value: String) {
        persistRequiredAPIValue(value, account: Key.apiKey)
    }

    func persistAPIBaseURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.defaultAPIBaseURL {
            AppSettingsStorage.delete(account: Key.apiBaseURL)
        } else {
            AppSettingsStorage.save(trimmed, account: Key.apiBaseURL)
        }
    }

    func persistOptionalAPIValue(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AppSettingsStorage.delete(account: account)
        } else {
            AppSettingsStorage.save(trimmed, account: account)
        }
    }

    func persistShortcut(_ binding: ShortcutBinding, key: String) {
        let normalizedBinding = binding.normalizedForStorageMigration()
        guard let data = try? JSONEncoder().encode(normalizedBinding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func persistOptionalShortcut(_ binding: ShortcutBinding?, key: String) {
        guard let binding else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        persistShortcut(binding, key: key)
    }

    static func normalizedContextScreenshotMaxDimension(_ value: Int) -> Int {
        contextScreenshotDimensionOptions.contains(value)
            ? value
            : defaultContextScreenshotMaxDimension
    }

    static func normalizeTranscriptionLanguage(_ language: String) -> String {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard transcriptionLanguageOptions.contains(where: { $0.code == normalized }) else {
            return ""
        }
        return normalized
    }

    private func persistRequiredAPIValue(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AppSettingsStorage.delete(account: account)
        } else {
            AppSettingsStorage.save(trimmed, account: account)
        }
    }

    private static func loadStoredAPIKey(account: String) -> String {
        if let storedKey = AppSettingsStorage.load(account: account),
           !storedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedKey
        }
        return ""
    }

    private static func loadStoredAPIBaseURL(account: String) -> String {
        if let stored = AppSettingsStorage.load(account: account),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        return defaultAPIBaseURL
    }

    private static func loadOptionalStoredAPIValue(account: String) -> String {
        let stored = AppSettingsStorage.load(account: account) ?? ""
        return stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadShortcutConfiguration(holdKey: String, toggleKey: String) -> StoredShortcutConfiguration {
        let legacyPreset = ShortcutPreset(
            rawValue: UserDefaults.standard.string(forKey: Key.legacyHotkeyOption) ?? ShortcutPreset.fnKey.rawValue
        ) ?? .fnKey
        let hold = legacyPreset.binding
        let toggle = hold.withAddedModifiers(.command)
        let storedHold = loadShortcut(forKey: holdKey)
        let storedToggle = loadShortcut(forKey: toggleKey)
        return StoredShortcutConfiguration(
            hold: storedHold.binding ?? hold,
            toggle: storedToggle.binding ?? toggle,
            didUpdateHoldStoredValue: storedHold.binding == nil || storedHold.didNormalize,
            didUpdateToggleStoredValue: storedToggle.binding == nil || storedToggle.didNormalize
        )
    }

    private static func loadSavedCustomShortcut(
        forKey key: String,
        fallback: ShortcutBinding?
    ) -> StoredOptionalShortcut {
        let stored = loadShortcut(forKey: key)
        if let binding = stored.binding {
            return StoredOptionalShortcut(binding: binding, didUpdateStoredValue: stored.didNormalize)
        }

        return StoredOptionalShortcut(
            binding: fallback,
            didUpdateStoredValue: stored.hadStoredValue || fallback != nil
        )
    }

    private static func loadShortcut(forKey key: String) -> StoredShortcutLoadResult {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return StoredShortcutLoadResult(binding: nil, hadStoredValue: false, didNormalize: false)
        }
        guard let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: data) else {
            return StoredShortcutLoadResult(binding: nil, hadStoredValue: true, didNormalize: false)
        }
        let normalized = decoded.normalizedForStorageMigration()
        return StoredShortcutLoadResult(
            binding: normalized,
            hadStoredValue: true,
            didNormalize: normalized != decoded
        )
    }
}
