import Foundation
import Combine
import AppKit
import AVFoundation
import ServiceManagement
import ApplicationServices
import ScreenCaptureKit
import os.log
private let recordingLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Recording")

final class AppState: ObservableObject, @unchecked Sendable {
    private enum ActiveAudioInterruption {
        case muted(previouslyMuted: Bool)
    }

    private let pasteAfterShortcutReleaseDelay: TimeInterval = 0.03
    private let pressEnterAfterPasteDelay: TimeInterval = 0.08
    private let clipboardRestoreDelay: TimeInterval = 1.0
    let maxPipelineHistoryCount = 20
    static let defaultAPIBaseURL = AppSettingsStore.defaultAPIBaseURL
    static let defaultContextScreenshotMaxDimension = AppSettingsStore.defaultContextScreenshotMaxDimension
    static let contextScreenshotDimensionOptions = AppSettingsStore.contextScreenshotDimensionOptions
    static let defaultTranscriptionModel = AppSettingsStore.defaultTranscriptionModel
    static let transcriptionLanguageOptions = AppSettingsStore.transcriptionLanguageOptions
    static let defaultPostProcessingModel = AppSettingsStore.defaultPostProcessingModel
    static let defaultPostProcessingFallbackModel = AppSettingsStore.defaultPostProcessingFallbackModel
    static let defaultContextModel = AppSettingsStore.defaultContextModel

    @Published var hasCompletedSetup: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedSetup, forKey: AppSettingsStore.Key.hasCompletedSetup)
        }
    }

    @Published var apiKey: String {
        didSet {
            settingsStore.persistAPIKey(apiKey)
            rebuildContextService()
        }
    }

    @Published var apiBaseURL: String {
        didSet {
            settingsStore.persistAPIBaseURL(apiBaseURL)
            rebuildContextService()
        }
    }

    @Published var transcriptionAPIURL: String {
        didSet {
            settingsStore.persistOptionalAPIValue(transcriptionAPIURL, account: AppSettingsStore.Key.transcriptionAPIURL)
        }
    }

    @Published var transcriptionAPIKey: String {
        didSet {
            settingsStore.persistOptionalAPIValue(transcriptionAPIKey, account: AppSettingsStore.Key.transcriptionAPIKey)
        }
    }

    @Published var transcriptionModel: String {
        didSet {
            UserDefaults.standard.set(transcriptionModel, forKey: AppSettingsStore.Key.transcriptionModel)
        }
    }

    @Published var postProcessingModel: String {
        didSet {
            UserDefaults.standard.set(postProcessingModel, forKey: AppSettingsStore.Key.postProcessingModel)
        }
    }

    @Published var postProcessingFallbackModel: String {
        didSet {
            UserDefaults.standard.set(postProcessingFallbackModel, forKey: AppSettingsStore.Key.postProcessingFallbackModel)
        }
    }

    @Published var contextModel: String {
        didSet {
            UserDefaults.standard.set(contextModel, forKey: AppSettingsStore.Key.contextModel)
            rebuildContextService()
        }
    }

    @Published var holdShortcut: ShortcutBinding {
        didSet {
            settingsStore.persistShortcut(holdShortcut, key: AppSettingsStore.Key.holdShortcut)
            restartHotkeyMonitoring()
        }
    }

    @Published var toggleShortcut: ShortcutBinding {
        didSet {
            settingsStore.persistShortcut(toggleShortcut, key: AppSettingsStore.Key.toggleShortcut)
            restartHotkeyMonitoring()
        }
    }

    @Published private(set) var savedHoldCustomShortcut: ShortcutBinding? {
        didSet {
            settingsStore.persistOptionalShortcut(savedHoldCustomShortcut, key: AppSettingsStore.Key.savedHoldCustomShortcut)
        }
    }

    @Published private(set) var savedToggleCustomShortcut: ShortcutBinding? {
        didSet {
            settingsStore.persistOptionalShortcut(
                savedToggleCustomShortcut,
                key: AppSettingsStore.Key.savedToggleCustomShortcut
            )
        }
    }

    @Published private(set) var isJournalModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isJournalModeEnabled, forKey: AppSettingsStore.Key.journalModeEnabled)
            restartHotkeyMonitoring()
        }
    }

    @Published private(set) var journalModeModifier: JournalModeModifier {
        didSet {
            UserDefaults.standard.set(journalModeModifier.rawValue, forKey: AppSettingsStore.Key.journalModeModifier)
            restartHotkeyMonitoring()
        }
    }

    @Published private(set) var journalModeFolderPath: String {
        didSet {
            UserDefaults.standard.set(journalModeFolderPath, forKey: AppSettingsStore.Key.journalModeFolderPath)
        }
    }

    @Published private(set) var journalModeFolderBookmark: Data? {
        didSet {
            if let journalModeFolderBookmark {
                UserDefaults.standard.set(journalModeFolderBookmark, forKey: AppSettingsStore.Key.journalModeFolderBookmark)
            } else {
                UserDefaults.standard.removeObject(forKey: AppSettingsStore.Key.journalModeFolderBookmark)
            }
        }
    }

    @Published var customVocabulary: String {
        didSet {
            UserDefaults.standard.set(customVocabulary, forKey: AppSettingsStore.Key.customVocabulary)
        }
    }

    @Published var transcriptionLanguage: String {
        didSet {
            let normalized = AppSettingsStore.normalizeTranscriptionLanguage(transcriptionLanguage)
            if normalized != transcriptionLanguage {
                transcriptionLanguage = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: AppSettingsStore.Key.transcriptionLanguage)
        }
    }

    @Published var customSystemPrompt: String {
        didSet {
            UserDefaults.standard.set(customSystemPrompt, forKey: AppSettingsStore.Key.customSystemPrompt)
        }
    }

    @Published var customContextPrompt: String {
        didSet {
            UserDefaults.standard.set(customContextPrompt, forKey: AppSettingsStore.Key.customContextPrompt)
            rebuildContextService()
        }
    }

    @Published var contextScreenshotMaxDimension: Int {
        didSet {
            let normalizedDimension = Self.normalizedContextScreenshotMaxDimension(contextScreenshotMaxDimension)
            if normalizedDimension != contextScreenshotMaxDimension {
                contextScreenshotMaxDimension = normalizedDimension
            }
            UserDefaults.standard.set(contextScreenshotMaxDimension, forKey: AppSettingsStore.Key.contextScreenshotMaxDimension)
            rebuildContextService()
        }
    }

    @Published var customSystemPromptLastModified: String {
        didSet {
            UserDefaults.standard.set(customSystemPromptLastModified, forKey: AppSettingsStore.Key.customSystemPromptLastModified)
        }
    }

    @Published var customContextPromptLastModified: String {
        didSet {
            UserDefaults.standard.set(customContextPromptLastModified, forKey: AppSettingsStore.Key.customContextPromptLastModified)
        }
    }

    @Published var outputLanguage: String {
        didSet {
            UserDefaults.standard.set(outputLanguage, forKey: AppSettingsStore.Key.outputLanguage)
        }
    }

    @Published var shortcutStartDelay: TimeInterval {
        didSet {
            UserDefaults.standard.set(shortcutStartDelay, forKey: AppSettingsStore.Key.shortcutStartDelay)
        }
    }

    /// Stream audio to the transcription backend during recording via the
    /// OpenAI Realtime WebSocket. Reduces wall-clock latency between "stop"
    /// and text-ready because most of the transcription work happens while
    /// the user is still speaking.
    @Published var realtimeStreamingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(realtimeStreamingEnabled, forKey: AppSettingsStore.Key.realtimeStreamingEnabled)
        }
    }

    /// Model ID the realtime WebSocket should transcribe with. Empty means
    /// "use the server's default".
    @Published var realtimeStreamingModel: String {
        didSet {
            UserDefaults.standard.set(realtimeStreamingModel, forKey: AppSettingsStore.Key.realtimeStreamingModel)
        }
    }

    @Published var dictationAudioInterruptionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                dictationAudioInterruptionEnabled,
                forKey: AppSettingsStore.Key.dictationAudioInterruptionEnabled
            )
        }
    }

    @Published var preserveClipboard: Bool {
        didSet {
            UserDefaults.standard.set(preserveClipboard, forKey: AppSettingsStore.Key.preserveClipboard)
        }
    }

    @Published var isPressEnterVoiceCommandEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPressEnterVoiceCommandEnabled, forKey: AppSettingsStore.Key.pressEnterVoiceCommand)
        }
    }

    @Published var alertSoundsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(alertSoundsEnabled, forKey: AppSettingsStore.Key.alertSoundsEnabled)
        }
    }

    @Published var soundVolume: Float {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: AppSettingsStore.Key.soundVolume)
        }
    }

    private var precomputedMacros: [PrecomputedMacro] = []

    @Published var voiceMacros: [VoiceMacro] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(voiceMacros) {
                UserDefaults.standard.set(data, forKey: AppSettingsStore.Key.voiceMacros)
            }
            precomputeMacros()
        }
    }

    @Published var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            RecordingStateFlagStore.writeRecordingStateFlag(isRecording)
        }
    }
    @Published var isTranscribing = false
    @Published var retryingItemIDs: Set<UUID> = []
    @Published var lastTranscript: String = ""
    @Published var errorMessage: String?
    @Published var statusText: String = "Ready"
    @Published var hasAccessibility = false
    @Published var hotkeyMonitoringErrorMessage: String?
    @Published var isDebugOverlayActive = false
    @Published var selectedSettingsTab: SettingsTab? = .general
    @Published var pipelineHistory: [PipelineHistoryItem] = []
    @Published var debugStatusMessage = "Idle"
    @Published var lastRawTranscript = ""
    @Published var lastPostProcessedTranscript = ""
    @Published var lastPostProcessingPrompt = ""
    @Published var lastContextSummary = ""
    @Published var lastPostProcessingStatus = ""
    @Published var lastContextScreenshotDataURL: String? = nil
    @Published var lastContextScreenshotStatus = "No screenshot"
    @Published var lastContextAppName: String = ""
    @Published var lastContextBundleIdentifier: String = ""
    @Published var lastContextWindowTitle: String = ""
    @Published var lastContextSelectedText: String = ""
    @Published var lastContextLLMPrompt: String = ""
    @Published var hasScreenRecordingPermission = false
    @Published var launchAtLogin: Bool {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    @Published var selectedMicrophoneID: String {
        didSet {
            UserDefaults.standard.set(selectedMicrophoneID, forKey: AppSettingsStore.Key.selectedMicrophone)
        }
    }
    @Published var availableMicrophones: [AudioDevice] = []

    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let overlayManager = RecordingOverlayManager()
    private let settingsStore: AppSettingsStore
    private var accessibilityTimer: Timer?
    private var audioLevelCancellable: AnyCancellable?
    private var debugOverlayTimer: Timer?
    private var recordingInitializationTimer: DispatchSourceTimer?
    private var transcriptionTask: Task<Void, Never>?
    private var transcribingAudioFileName: String?
    private var contextService: AppContextService
    private var contextCaptureTask: Task<AppContext?, Never>?
    private var capturedContext: AppContext?
    private var hasShownScreenshotPermissionAlert = false
    private var audioDeviceObservers: [NSObjectProtocol] = []
    private var needsMicrophoneRefreshAfterRecording = false
    private let pipelineHistoryStore = PipelineHistoryStore()
    private let shortcutSessionController = DictationShortcutSessionController()
    private var activeRecordingTriggerMode: RecordingTriggerMode?
    private var currentSessionIntent: SessionIntent = .dictation
    private var pendingJournalModeInvocation = false
    private var pendingShortcutStartTask: Task<Void, Never>?
    private var pendingShortcutStartMode: RecordingTriggerMode?
    private var realtimeService: RealtimeTranscriptionService?
    private var activeAudioInterruption: ActiveAudioInterruption?
    private var pendingOverlayDismissToken: UUID?
    private var shouldMonitorHotkeys = false
    private var isCapturingShortcut = false
    private var isAwaitingMicrophonePermission = false
    private var pendingMicrophonePermissionTriggerMode: RecordingTriggerMode?
    private var pendingMicrophonePermissionJournalRequested: Bool?
    private let postTranscriptionUpdateReminderDuration: TimeInterval = 7

    init() {
        let settingsStore = AppSettingsStore()
        let loadedSettings = settingsStore.load()

        let initialAccessibility = AXIsProcessTrusted()
        let initialScreenCapturePermission = CGPreflightScreenCaptureAccess()
        var removedAudioFileNames: [String] = []
        do {
            removedAudioFileNames = try pipelineHistoryStore.trim(to: maxPipelineHistoryCount)
        } catch {
            print("Failed to trim pipeline history during init: \(error)")
        }
        for audioFileName in removedAudioFileNames {
            AudioFileStore.deleteAudioFile(audioFileName)
        }
        let savedHistory = pipelineHistoryStore.loadAllHistory()

        self.contextService = Self.makeAppContextService(
            apiKey: loadedSettings.apiKey,
            baseURL: loadedSettings.apiBaseURL,
            customContextPrompt: loadedSettings.customContextPrompt,
            contextModel: loadedSettings.contextModel,
            contextScreenshotMaxDimension: loadedSettings.contextScreenshotMaxDimension
        )
        self.settingsStore = settingsStore
        self.hasCompletedSetup = loadedSettings.hasCompletedSetup
        self.apiKey = loadedSettings.apiKey
        self.apiBaseURL = loadedSettings.apiBaseURL
        self.transcriptionAPIURL = loadedSettings.transcriptionAPIURL
        self.transcriptionAPIKey = loadedSettings.transcriptionAPIKey
        self.transcriptionModel = loadedSettings.transcriptionModel
        self.postProcessingModel = loadedSettings.postProcessingModel
        self.postProcessingFallbackModel = loadedSettings.postProcessingFallbackModel
        self.contextModel = loadedSettings.contextModel
        self.holdShortcut = loadedSettings.shortcuts.hold
        self.toggleShortcut = loadedSettings.shortcuts.toggle
        self.savedHoldCustomShortcut = loadedSettings.savedHoldCustomShortcut.binding
        self.savedToggleCustomShortcut = loadedSettings.savedToggleCustomShortcut.binding
        self.isJournalModeEnabled = loadedSettings.isJournalModeEnabled
        self.journalModeModifier = loadedSettings.journalModeModifier
        self.journalModeFolderPath = loadedSettings.journalModeFolderPath
        self.journalModeFolderBookmark = loadedSettings.journalModeFolderBookmark
        self.customVocabulary = loadedSettings.customVocabulary
        self.transcriptionLanguage = loadedSettings.transcriptionLanguage
        self.customSystemPrompt = loadedSettings.customSystemPrompt
        self.customContextPrompt = loadedSettings.customContextPrompt
        self.contextScreenshotMaxDimension = loadedSettings.contextScreenshotMaxDimension
        self.customSystemPromptLastModified = loadedSettings.customSystemPromptLastModified
        self.customContextPromptLastModified = loadedSettings.customContextPromptLastModified
        self.outputLanguage = loadedSettings.outputLanguage
        self.shortcutStartDelay = loadedSettings.shortcutStartDelay
        self.preserveClipboard = loadedSettings.preserveClipboard
        self.realtimeStreamingEnabled = loadedSettings.realtimeStreamingEnabled
        self.realtimeStreamingModel = loadedSettings.realtimeStreamingModel
        self.dictationAudioInterruptionEnabled = loadedSettings.dictationAudioInterruptionEnabled
        self.isPressEnterVoiceCommandEnabled = loadedSettings.isPressEnterVoiceCommandEnabled
        self.alertSoundsEnabled = loadedSettings.alertSoundsEnabled
        self.soundVolume = loadedSettings.soundVolume
        self.voiceMacros = loadedSettings.voiceMacros
        self.pipelineHistory = savedHistory
        self.hasAccessibility = initialAccessibility
        self.hasScreenRecordingPermission = initialScreenCapturePermission
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.selectedMicrophoneID = loadedSettings.selectedMicrophoneID
        self.precomputeMacros()

        refreshAvailableMicrophones()
        installAudioDeviceObservers()

        if loadedSettings.shortcuts.didUpdateHoldStoredValue {
            settingsStore.persistShortcut(loadedSettings.shortcuts.hold, key: AppSettingsStore.Key.holdShortcut)
        }
        if loadedSettings.shortcuts.didUpdateToggleStoredValue {
            settingsStore.persistShortcut(loadedSettings.shortcuts.toggle, key: AppSettingsStore.Key.toggleShortcut)
        }
        if loadedSettings.savedHoldCustomShortcut.didUpdateStoredValue {
            settingsStore.persistOptionalShortcut(
                loadedSettings.savedHoldCustomShortcut.binding,
                key: AppSettingsStore.Key.savedHoldCustomShortcut
            )
        }
        if loadedSettings.savedToggleCustomShortcut.didUpdateStoredValue {
            settingsStore.persistOptionalShortcut(
                loadedSettings.savedToggleCustomShortcut.binding,
                key: AppSettingsStore.Key.savedToggleCustomShortcut
            )
        }

        overlayManager.onStopButtonPressed = { [weak self] in
            DispatchQueue.main.async {
                self?.handleOverlayStopButtonPressed()
            }
        }
        overlayManager.onUpdateOverlayPressed = { [weak self] in
            DispatchQueue.main.async {
                self?.handleUpdateOverlayPressed()
            }
        }

        // Clear any stale recording flag left over from an unclean exit.
        RecordingStateFlagStore.writeRecordingStateFlag(false)
    }

    deinit {
        removeAudioDeviceObservers()
        RecordingStateFlagStore.writeRecordingStateFlag(false)
    }

    private func removeAudioDeviceObservers() {
        let notificationCenter = NotificationCenter.default
        for observer in audioDeviceObservers {
            notificationCenter.removeObserver(observer)
        }
        audioDeviceObservers.removeAll()
    }

    static func normalizedContextScreenshotMaxDimension(_ value: Int) -> Int {
        AppSettingsStore.normalizedContextScreenshotMaxDimension(value)
    }

    static func makeAppContextService(
        apiKey: String,
        baseURL: String,
        customContextPrompt: String,
        contextModel: String,
        contextScreenshotMaxDimension: Int
    ) -> AppContextService {
        AppContextService(
            apiKey: apiKey,
            baseURL: baseURL,
            customContextPrompt: customContextPrompt,
            contextModel: contextModel,
            screenshotMaxDimension: CGFloat(normalizedContextScreenshotMaxDimension(contextScreenshotMaxDimension))
        )
    }

    func makeAppContextService() -> AppContextService {
        Self.makeAppContextService(
            apiKey: apiKey,
            baseURL: apiBaseURL,
            customContextPrompt: customContextPrompt,
            contextModel: contextModel,
            contextScreenshotMaxDimension: contextScreenshotMaxDimension
        )
    }

    private func rebuildContextService() {
        contextService = makeAppContextService()
    }

    private var resolvedTranscriptionBaseURL: String {
        let trimmed = transcriptionAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? apiBaseURL : trimmed
    }

    private var resolvedTranscriptionAPIKey: String {
        let trimmed = transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? apiKey : trimmed
    }

    func makeTranscriptionService() throws -> TranscriptionService {
        try TranscriptionService(
            apiKey: resolvedTranscriptionAPIKey,
            baseURL: resolvedTranscriptionBaseURL,
            transcriptionModel: transcriptionModel,
            language: resolvedTranscriptionLanguage
        )
    }

    private var resolvedTranscriptionLanguage: String? {
        let normalized = AppSettingsStore.normalizeTranscriptionLanguage(transcriptionLanguage)
        return normalized.isEmpty ? nil : normalized
    }

    func clearPipelineHistory() {
        do {
            let removedAudioFileNames = try pipelineHistoryStore.clearAll()
            for audioFileName in removedAudioFileNames {
                AudioFileStore.deleteAudioFile(audioFileName)
            }
            pipelineHistory = []
        } catch {
            errorMessage = "Unable to clear run history: \(error.localizedDescription)"
        }
    }

    func deleteHistoryEntry(id: UUID) {
        guard let index = pipelineHistory.firstIndex(where: { $0.id == id }) else { return }
        do {
            if let audioFileName = try pipelineHistoryStore.delete(id: id) {
                AudioFileStore.deleteAudioFile(audioFileName)
            }
            pipelineHistory.remove(at: index)
        } catch {
            errorMessage = "Unable to delete run history entry: \(error.localizedDescription)"
        }
    }

    func retryTranscription(item: PipelineHistoryItem) {
        guard let audioFileName = item.audioFileName else { return }
        guard !retryingItemIDs.contains(item.id) else { return }

        retryingItemIDs.insert(item.id)

        let audioURL = AudioFileStore.audioStorageDirectory().appendingPathComponent(audioFileName)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            retryingItemIDs.remove(item.id)
            errorMessage = "Audio file not found for retry."
            return
        }

        let restoredContext = AppContext(
            appName: nil,
            bundleIdentifier: nil,
            windowTitle: nil,
            selectedText: nil,
            currentActivity: item.contextSummary,
            contextSystemPrompt: item.contextSystemPrompt,
            contextPrompt: item.contextPrompt,
            screenshotDataURL: item.contextScreenshotDataURL,
            screenshotMimeType: item.contextScreenshotDataURL != nil ? "image/jpeg" : nil,
            screenshotError: nil
        )

        let postProcessingService = PostProcessingService(
            apiKey: apiKey,
            baseURL: apiBaseURL,
            preferredModel: postProcessingModel,
            preferredFallbackModel: postProcessingFallbackModel
        )
        let capturedCustomVocabulary = customVocabulary
        let capturedCustomSystemPrompt = customSystemPrompt

        Task {
            do {
                let transcriptionService = try makeTranscriptionService()
                let rawTranscript = try await transcriptionService.transcribe(fileURL: audioURL)
                let restoredIntent = SessionIntent.fromPersisted(intent: item.intent)
                if restoredIntent.isJournalMode {
                    let trimmedRawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    let journalFileURL = try JournalLogStore(
                        folderURL: self.resolvedJournalModeFolderURL
                    ).append(rawTranscript: rawTranscript)
                    let processingStatus = journalFileURL == nil
                        ? "Skipped empty raw transcript (retried)"
                        : "Logged raw transcript to journal (retried)"

                    await MainActor.run {
                        let updatedItem = PipelineHistoryItem(
                            intent: item.intent,
                            capturedSelection: item.capturedSelection,
                            id: item.id,
                            timestamp: item.timestamp,
                            rawTranscript: trimmedRawTranscript,
                            postProcessedTranscript: trimmedRawTranscript,
                            postProcessingPrompt: "",
                            systemPrompt: item.systemPrompt,
                            contextSummary: item.contextSummary,
                            contextSystemPrompt: item.contextSystemPrompt,
                            contextPrompt: item.contextPrompt,
                            contextScreenshotDataURL: item.contextScreenshotDataURL,
                            contextScreenshotStatus: item.contextScreenshotStatus,
                            postProcessingStatus: processingStatus,
                            debugStatus: "Retried",
                            customVocabulary: item.customVocabulary,
                            audioFileName: item.audioFileName,
                            contextAppName: item.contextAppName,
                            contextBundleIdentifier: item.contextBundleIdentifier,
                            contextWindowTitle: item.contextWindowTitle
                        )
                        do {
                            try pipelineHistoryStore.update(updatedItem)
                            pipelineHistory = pipelineHistoryStore.loadAllHistory()
                        } catch {
                            errorMessage = "Failed to save retry result: \(error.localizedDescription)"
                        }
                        retryingItemIDs.remove(item.id)
                    }
                    return
                }
                let parsedTranscript = TranscriptCommandParser.parse(
                    transcript: rawTranscript,
                    pressEnterCommandEnabled: self.isPressEnterVoiceCommandEnabled
                )

                let finalTranscript: String
                let processingStatus: String
                let postProcessingPrompt: String
                let result = await self.processTranscript(
                    parsedTranscript.transcript,
                    intent: restoredIntent,
                    context: restoredContext,
                    postProcessingService: postProcessingService,
                    customVocabulary: capturedCustomVocabulary,
                    customSystemPrompt: capturedCustomSystemPrompt,
                    outputLanguage: self.outputLanguage
                )
                finalTranscript = result.finalTranscript
                processingStatus = Self.statusMessage(
                    for: result.outcome,
                    parsedTranscript: parsedTranscript,
                    isRetry: true
                )
                postProcessingPrompt = result.prompt

                await MainActor.run {
                    let updatedItem = PipelineHistoryItem(
                        intent: item.intent,
                        capturedSelection: item.capturedSelection,
                        id: item.id,
                        timestamp: item.timestamp,
                        rawTranscript: parsedTranscript.transcript,
                        postProcessedTranscript: finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
                        postProcessingPrompt: postProcessingPrompt,
                        systemPrompt: item.systemPrompt,
                        contextSummary: item.contextSummary,
                        contextSystemPrompt: item.contextSystemPrompt,
                        contextPrompt: item.contextPrompt,
                        contextScreenshotDataURL: item.contextScreenshotDataURL,
                        contextScreenshotStatus: item.contextScreenshotStatus,
                        postProcessingStatus: processingStatus,
                        debugStatus: "Retried",
                        customVocabulary: item.customVocabulary,
                        audioFileName: item.audioFileName,
                        contextAppName: item.contextAppName,
                        contextBundleIdentifier: item.contextBundleIdentifier,
                        contextWindowTitle: item.contextWindowTitle
                    )
                    do {
                        try pipelineHistoryStore.update(updatedItem)
                        pipelineHistory = pipelineHistoryStore.loadAllHistory()
                    } catch {
                        errorMessage = "Failed to save retry result: \(error.localizedDescription)"
                    }
                    retryingItemIDs.remove(item.id)
                }
            } catch {
                await MainActor.run {
                    let updatedItem = PipelineHistoryItem(
                        intent: item.intent,
                        capturedSelection: item.capturedSelection,
                        id: item.id,
                        timestamp: item.timestamp,
                        rawTranscript: item.rawTranscript,
                        postProcessedTranscript: item.postProcessedTranscript,
                        postProcessingPrompt: item.postProcessingPrompt,
                        systemPrompt: item.systemPrompt,
                        contextSummary: item.contextSummary,
                        contextSystemPrompt: item.contextSystemPrompt,
                        contextPrompt: item.contextPrompt,
                        contextScreenshotDataURL: item.contextScreenshotDataURL,
                        contextScreenshotStatus: item.contextScreenshotStatus,
                        postProcessingStatus: "Error: \(error.localizedDescription)",
                        debugStatus: "Retry failed",
                        customVocabulary: item.customVocabulary,
                        audioFileName: item.audioFileName,
                        contextAppName: item.contextAppName,
                        contextBundleIdentifier: item.contextBundleIdentifier,
                        contextWindowTitle: item.contextWindowTitle
                    )
                    do {
                        try pipelineHistoryStore.update(updatedItem)
                        pipelineHistory = pipelineHistoryStore.loadAllHistory()
                    } catch {}
                    retryingItemIDs.remove(item.id)
                }
            }
        }
    }

    func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        hasAccessibility = AXIsProcessTrusted()
        hasScreenRecordingPermission = hasScreenCapturePermission()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hasAccessibility = AXIsProcessTrusted()
                self?.hasScreenRecordingPermission = self?.hasScreenCapturePermission() ?? false
            }
        }
    }

    func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }

    func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openPrivacySettingsPane("Privacy_Accessibility")
        }
    }

    func openMicrophoneSettings() {
        openPrivacySettingsPane("Privacy_Microphone")
    }

    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            refreshAvailableMicrophones()
            DispatchQueue.main.async {
                completion(true)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.refreshAvailableMicrophones()
                    }
                    completion(granted)
                }
            }
        case .denied, .restricted:
            openMicrophoneSettings()
            DispatchQueue.main.async {
                completion(false)
            }
        @unknown default:
            openMicrophoneSettings()
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }

    func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCapturePermission() {
        // ScreenCaptureKit triggers the "Screen & System Audio Recording"
        // permission dialog on macOS Sequoia+, correctly identifying the
        // running app (unlike the legacy CGWindowListCreateImage path).
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] _, _ in
            DispatchQueue.main.async {
                let granted = CGPreflightScreenCaptureAccess()
                self?.hasScreenRecordingPermission = granted
                if !granted {
                    self?.openScreenCaptureSettings()
                }
            }
        }

        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }

    func openScreenCaptureSettings() {
        openPrivacySettingsPane("Privacy_ScreenCapture")
    }

    private func openPrivacySettingsPane(_ pane: String) {
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle on failure without re-triggering didSet
            let current = SMAppService.mainApp.status == .enabled
            if current != launchAtLogin {
                launchAtLogin = current
            }
        }
    }

    func refreshLaunchAtLoginStatus() {
        let current = SMAppService.mainApp.status == .enabled
        if current != launchAtLogin {
            launchAtLogin = current
        }
    }

    func refreshAvailableMicrophones() {
        guard !isRecording, !audioRecorder.isRecording else {
            needsMicrophoneRefreshAfterRecording = true
            return
        }

        needsMicrophoneRefreshAfterRecording = false
        availableMicrophones = AudioDevice.availableInputDevices()
    }

    private func refreshAvailableMicrophonesIfNeeded() {
        guard needsMicrophoneRefreshAfterRecording else { return }
        refreshAvailableMicrophones()
    }

    private func installAudioDeviceObservers() {
        removeAudioDeviceObservers()

        let notificationCenter = NotificationCenter.default
        let refreshOnAudioDeviceChange: (Notification) -> Void = { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice,
                  device.hasMediaType(.audio) else {
                return
            }
            self?.refreshAvailableMicrophones()
        }

        audioDeviceObservers.append(
            notificationCenter.addObserver(
                forName: .AVCaptureDeviceWasConnected,
                object: nil,
                queue: .main,
                using: refreshOnAudioDeviceChange
            )
        )
        audioDeviceObservers.append(
            notificationCenter.addObserver(
                forName: .AVCaptureDeviceWasDisconnected,
                object: nil,
                queue: .main,
                using: refreshOnAudioDeviceChange
            )
        )
    }

    var usesFnShortcut: Bool {
        holdShortcut.usesFnKey || toggleShortcut.usesFnKey
    }

    var hasEnabledHoldShortcut: Bool {
        !holdShortcut.isDisabled
    }

    var hasEnabledToggleShortcut: Bool {
        !toggleShortcut.isDisabled
    }

    var shortcutStatusText: String {
        if hotkeyMonitoringErrorMessage != nil {
            return "Global shortcuts unavailable"
        }

        switch (hasEnabledHoldShortcut, hasEnabledToggleShortcut) {
        case (true, true):
            return "Hold \(holdShortcut.displayName) or tap \(toggleShortcut.displayName) to dictate"
        case (true, false):
            return "Hold \(holdShortcut.displayName) to dictate"
        case (false, true):
            return "Tap \(toggleShortcut.displayName) to dictate"
        case (false, false):
            return "No dictation shortcut enabled"
        }
    }

    var shortcutStartDelayMilliseconds: Int {
        Int((shortcutStartDelay * 1000).rounded())
    }

    func savedCustomShortcut(for role: ShortcutRole) -> ShortcutBinding? {
        switch role {
        case .hold:
            return savedHoldCustomShortcut
        case .toggle:
            return savedToggleCustomShortcut
        }
    }

    var journalModeModifierValidationMessage: String? {
        guard isJournalModeEnabled else { return nil }
        return journalModeModifierCollisionMessage(for: journalModeModifier)
    }

    var resolvedJournalModeFolderURL: URL {
        JournalLogStore.resolveFolderURL(
            bookmarkData: journalModeFolderBookmark,
            plainPath: journalModeFolderPath
        )
    }

    var resolvedJournalModeFolderDisplayPath: String {
        resolvedJournalModeFolderURL.path
    }

    @discardableResult
    func setJournalModeEnabled(_ enabled: Bool) -> String? {
        isJournalModeEnabled = enabled
        if enabled {
            return journalModeModifierCollisionMessage(for: journalModeModifier)
        }
        return nil
    }

    @discardableResult
    func setJournalModeModifier(_ modifier: JournalModeModifier) -> String? {
        if isJournalModeEnabled,
           let message = journalModeModifierCollisionMessage(for: modifier) {
            return message
        }

        journalModeModifier = modifier
        return nil
    }

    func setJournalModeFolderURL(_ url: URL) {
        journalModeFolderPath = url.path
        journalModeFolderBookmark = JournalLogStore.makeBookmarkData(for: url)
    }

    func resetJournalModeFolder() {
        journalModeFolderPath = JournalLogStore.defaultFolderURL.path
        journalModeFolderBookmark = nil
    }

    @discardableResult
    func setShortcut(_ binding: ShortcutBinding, for role: ShortcutRole) -> String? {
        let binding = binding.normalizedForStorageMigration()
        let nextHoldShortcut = role == .hold ? binding : holdShortcut
        let nextToggleShortcut = role == .toggle ? binding : toggleShortcut
        let otherBinding = role == .hold ? toggleShortcut : holdShortcut
        if binding.isDisabled && otherBinding.isDisabled {
            return "At least one shortcut must remain enabled."
        }
        guard !binding.conflicts(with: otherBinding) else {
            return "Hold and tap shortcuts must be distinct."
        }
        if isJournalModeEnabled,
           let message = journalModeModifierCollisionMessage(
            for: journalModeModifier,
            holdBinding: nextHoldShortcut,
            toggleBinding: nextToggleShortcut
           ) {
            return message
        }

        switch role {
        case .hold:
            if binding.isCustom {
                savedHoldCustomShortcut = binding
            }
            holdShortcut = binding
        case .toggle:
            if binding.isCustom {
                savedToggleCustomShortcut = binding
            }
            toggleShortcut = binding
        }

        return nil
    }

    private func journalModeModifierCollisionMessage(
        for modifier: JournalModeModifier,
        holdBinding: ShortcutBinding? = nil,
        toggleBinding: ShortcutBinding? = nil
    ) -> String? {
        let holdBinding = holdBinding ?? holdShortcut
        let toggleBinding = toggleBinding ?? toggleShortcut
        let journalModifier = modifier.shortcutModifier

        if shortcutBinding(holdBinding, references: journalModifier) {
            return "That modifier is already part of the hold shortcut."
        }
        if shortcutBinding(toggleBinding, references: journalModifier) {
            return "That modifier is already part of the tap shortcut."
        }
        return nil
    }

    private func shortcutBinding(_ binding: ShortcutBinding, references modifier: ShortcutModifiers) -> Bool {
        guard !binding.isDisabled else { return false }
        if binding.modifiers.contains(modifier) {
            return true
        }
        if binding.kind == .modifierKey,
           ShortcutBinding.logicalModifier(forKeyCode: binding.keyCode) == modifier {
            return true
        }
        return false
    }

    func startHotkeyMonitoring() {
        shouldMonitorHotkeys = true
        hotkeyManager.onShortcutEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleShortcutEvent(event)
            }
        }
        hotkeyManager.onEscapeKeyPressed = { [weak self] in
            self?.handleEscapeKeyPress() ?? false
        }
        restartHotkeyMonitoring()
    }

    func stopHotkeyMonitoring() {
        shouldMonitorHotkeys = false
        hotkeyMonitoringErrorMessage = nil
        hotkeyManager.onShortcutEvent = nil
        hotkeyManager.onEscapeKeyPressed = nil
        hotkeyManager.stop()
    }

    func suspendHotkeyMonitoringForShortcutCapture() {
        isCapturingShortcut = true
        restartHotkeyMonitoring()
    }

    func resumeHotkeyMonitoringAfterShortcutCapture() {
        isCapturingShortcut = false
        restartHotkeyMonitoring()
    }

    private var activeShortcutConfiguration: ShortcutConfiguration {
        var permittedAdditionalExactMatchModifiers: ShortcutModifiers = []
        if isJournalModeEnabled {
            permittedAdditionalExactMatchModifiers.insert(journalModeModifier.shortcutModifier)
        }

        return ShortcutConfiguration(
            hold: holdShortcut,
            toggle: toggleShortcut,
            permittedAdditionalExactMatchModifiers: permittedAdditionalExactMatchModifiers
        )
    }

    private func restartHotkeyMonitoring() {
        guard shouldMonitorHotkeys, !isCapturingShortcut, !isAwaitingMicrophonePermission else {
            hotkeyManager.stop()
            return
        }

        do {
            try hotkeyManager.start(configuration: activeShortcutConfiguration)
            hotkeyMonitoringErrorMessage = nil
        } catch {
            hotkeyMonitoringErrorMessage = error.localizedDescription
            os_log(.error, log: recordingLog, "Hotkey monitoring failed to start: %{public}@", error.localizedDescription)
        }
    }

    private func handleShortcutEvent(_ event: ShortcutEvent) {
        guard let action = shortcutSessionController.handle(event: event, isTranscribing: isTranscribing) else {
            return
        }

        switch action {
        case .start(let mode):
            os_log(.info, log: recordingLog, "Shortcut start fired for mode %{public}@", mode.rawValue)
            scheduleShortcutStart(mode: mode)
        case .stop:
            cancelPendingShortcutStart()
            guard isRecording else {
                shortcutSessionController.reset()
                activeRecordingTriggerMode = nil
                return
            }
            stopAndTranscribe()
        case .switchedToToggle:
            if isRecording {
                activeRecordingTriggerMode = .toggle
                overlayManager.setRecordingTriggerMode(.toggle, animated: true)
            } else if pendingShortcutStartMode != nil {
                pendingShortcutStartMode = .toggle
            }
        }
    }

    private func handleEscapeKeyPress() -> Bool {
        if isTranscribing {
            cancelTranscription()
            return true
        }

        if pendingShortcutStartMode == .toggle || activeRecordingTriggerMode == .toggle {
            cancelToggleShortcutSession()
            return true
        }

        return false
    }

    func toggleRecording() {
        os_log(.info, log: recordingLog, "toggleRecording() called, isRecording=%{public}d", isRecording)
        cancelPendingShortcutStart()
        if isRecording {
            stopAndTranscribe()
        } else {
            shortcutSessionController.beginManual(mode: .toggle)
            startRecording(triggerMode: .toggle)
        }
    }

    private func handleOverlayStopButtonPressed() {
        guard isRecording, activeRecordingTriggerMode == .toggle else { return }
        stopAndTranscribe()
    }

    private func cancelToggleShortcutSession() {
        guard pendingShortcutStartMode == .toggle || activeRecordingTriggerMode == .toggle else { return }

        cancelPendingShortcutStart()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        cancelRecordingInitializationTimer()
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        currentSessionIntent = .dictation
        pendingJournalModeInvocation = false
        isRecording = false
        errorMessage = nil
        debugStatusMessage = "Cancelled"
        statusText = "Cancelled"
        overlayManager.dismiss()
        tearDownRealtimeService()
        audioRecorder.cancelRecording()
        restoreAudioInterruptionIfNeeded()
        refreshAvailableMicrophonesIfNeeded()
        if !isRecording && !isTranscribing && statusText == "Cancelled" {
            scheduleReadyStatusReset(after: 2, matching: ["Cancelled"])
        }
    }

    private func cancelTranscription() {
        guard isTranscribing else { return }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        currentSessionIntent = .dictation
        pendingJournalModeInvocation = false
        isRecording = false
        isTranscribing = false
        errorMessage = nil
        debugStatusMessage = "Cancelled"
        statusText = "Cancelled"
        overlayManager.dismiss()
        audioRecorder.cleanup()
        if let transcribingAudioFileName {
            AudioFileStore.deleteAudioFile(transcribingAudioFileName)
            self.transcribingAudioFileName = nil
        }
        refreshAvailableMicrophonesIfNeeded()
        if !isRecording && !isTranscribing && statusText == "Cancelled" {
            scheduleReadyStatusReset(after: 2, matching: ["Cancelled"])
        }
    }

    private func scheduleShortcutStart(mode: RecordingTriggerMode) {
        cancelPendingShortcutStart(resetMode: false)
        pendingJournalModeInvocation = hotkeyManager.currentPressedModifiers.contains(
            journalModeModifier.shortcutModifier
        )
        pendingShortcutStartMode = mode
        let delay = shortcutStartDelay

        guard delay > 0 else {
            pendingShortcutStartMode = nil
            startRecording(triggerMode: mode)
            return
        }

        pendingShortcutStartTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            await MainActor.run { [weak self] in
                guard let self, let pendingMode = self.pendingShortcutStartMode else { return }
                self.pendingShortcutStartTask = nil
                self.pendingShortcutStartMode = nil
                self.startRecording(triggerMode: pendingMode)
            }
        }
    }

    private func cancelPendingShortcutStart(resetMode: Bool = true) {
        pendingShortcutStartTask?.cancel()
        pendingShortcutStartTask = nil
        pendingJournalModeInvocation = false
        if resetMode {
            pendingShortcutStartMode = nil
        }
    }

    private func resolveSessionIntent(
        triggerMode: RecordingTriggerMode,
        journalModeRequested: Bool
    ) -> SessionIntent? {
        if isJournalModeEnabled,
           journalModeRequested,
           let message = journalModeModifierCollisionMessage(for: journalModeModifier) {
            rejectInvalidJournalModeModifier(triggerMode: triggerMode, message: message)
            return nil
        }

        if isJournalModeEnabled, journalModeRequested {
            return .journal
        }

        return .dictation
    }

    private func rejectInvalidJournalModeModifier(triggerMode: RecordingTriggerMode, message: String) {
        currentSessionIntent = .dictation
        activeRecordingTriggerMode = nil
        pendingJournalModeInvocation = false
        errorMessage = message
        statusText = "Fix Journal Mode modifier"
        debugStatusMessage = "Journal mode modifier conflicts with dictation shortcuts"
        shortcutSessionController.reset()
        if triggerMode == .toggle {
            cancelPendingShortcutStart()
        }
        playAlertSound(named: "Basso")
        scheduleReadyStatusReset(after: 2, matching: ["Fix Journal Mode modifier"])
    }

    private func startRecording(triggerMode: RecordingTriggerMode) {
        let t0 = CFAbsoluteTimeGetCurrent()
        os_log(.info, log: recordingLog, "startRecording() entered")
        guard !isRecording && !isTranscribing else { return }
        let scheduledJournalModeInvocation = pendingJournalModeInvocation
        cancelPendingShortcutStart()
        guard prepareRecordingStart(
            triggerMode: triggerMode,
            journalModeRequested: scheduledJournalModeInvocation,
            startedAt: t0
        ) else { return }
        guard ensureMicrophoneAccess() else { return }
        os_log(.info, log: recordingLog, "mic access check passed: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        applyAudioInterruptionIfNeeded()
        beginRecording(triggerMode: triggerMode)
        os_log(.info, log: recordingLog, "startRecording() finished: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }

    private func prepareRecordingStart(
        triggerMode: RecordingTriggerMode,
        journalModeRequested: Bool? = nil,
        startedAt: CFAbsoluteTime? = nil
    ) -> Bool {
        activeRecordingTriggerMode = triggerMode
        guard hasAccessibility else {
            errorMessage = "Accessibility permission required. Grant access in System Settings > Privacy & Security > Accessibility."
            statusText = "No Accessibility"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            shortcutSessionController.reset()
            showAccessibilityAlert()
            return false
        }
        if let startedAt {
            os_log(.info, log: recordingLog, "accessibility check passed: %.3fms", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        }

        let journalModeRequested = journalModeRequested
            ?? hotkeyManager.currentPressedModifiers.contains(journalModeModifier.shortcutModifier)
        guard let resolvedIntent = resolveSessionIntent(
            triggerMode: triggerMode,
            journalModeRequested: journalModeRequested
        ) else { return false }

        hasScreenRecordingPermission = hasScreenCapturePermission()

        currentSessionIntent = resolvedIntent
        overlayManager.setRecordingTriggerMode(triggerMode, animated: false)
        return true
    }

    private func ensureScreenCaptureAccess() -> Bool {
        let granted = hasScreenCapturePermission()
        hasScreenRecordingPermission = granted
        guard granted else {
            let message = "Screen recording permission not granted. Enable in System Settings > Privacy & Security > Screen Recording."
            errorMessage = message
            statusText = "Screenshot Required"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            shortcutSessionController.reset()
            playAlertSound(named: "Basso")
            showScreenshotPermissionAlert(message: message)
            return false
        }

        return true
    }

    private func ensureMicrophoneAccess() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            guard let triggerMode = activeRecordingTriggerMode else {
                return false
            }

            prepareForMicrophonePermissionPrompt(
                triggerMode: triggerMode,
                journalModeRequested: currentSessionIntent.isJournalMode
            )
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let strongSelf = self else { return }
                    let pendingTriggerMode = strongSelf.pendingMicrophonePermissionTriggerMode
                    let pendingJournalRequested = strongSelf.pendingMicrophonePermissionJournalRequested
                    strongSelf.pendingMicrophonePermissionTriggerMode = nil
                    strongSelf.pendingMicrophonePermissionJournalRequested = nil
                    strongSelf.isAwaitingMicrophonePermission = false
                    strongSelf.restartHotkeyMonitoring()

                    guard let triggerMode = pendingTriggerMode else { return }
                    if granted {
                        strongSelf.errorMessage = nil
                        if triggerMode == .toggle {
                            guard strongSelf.prepareRecordingStart(
                                triggerMode: .toggle,
                                journalModeRequested: pendingJournalRequested
                            ) else { return }
                            strongSelf.shortcutSessionController.beginManual(mode: .toggle)
                            strongSelf.applyAudioInterruptionIfNeeded()
                            strongSelf.beginRecording(triggerMode: .toggle)
                        } else {
                            strongSelf.currentSessionIntent = .dictation
                            strongSelf.statusText = "Microphone access granted. Press and hold again to record."
                            strongSelf.scheduleReadyStatusReset(
                                after: 2,
                                matching: ["Microphone access granted. Press and hold again to record."]
                            )
                        }
                    } else {
                        strongSelf.errorMessage = "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
                        strongSelf.statusText = "No Microphone"
                        strongSelf.activeRecordingTriggerMode = nil
                        strongSelf.currentSessionIntent = .dictation
                        strongSelf.shortcutSessionController.reset()
                        strongSelf.showMicrophonePermissionAlert()
                    }
                }
            }
            return false
        default:
            errorMessage = "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
            statusText = "No Microphone"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            shortcutSessionController.reset()
            showMicrophonePermissionAlert()
            return false
        }
    }

    private func prepareForMicrophonePermissionPrompt(
        triggerMode: RecordingTriggerMode,
        journalModeRequested: Bool?
    ) {
        isAwaitingMicrophonePermission = true
        pendingMicrophonePermissionTriggerMode = triggerMode
        pendingMicrophonePermissionJournalRequested = journalModeRequested
        hotkeyManager.stop()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        cancelRecordingInitializationTimer()
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        overlayManager.dismiss()
    }

    private func applyAudioInterruptionIfNeeded() {
        guard dictationAudioInterruptionEnabled, activeAudioInterruption == nil else { return }

        let wasMuted = SystemAudioStatus.isDefaultOutputMuted()
        if wasMuted {
            activeAudioInterruption = .muted(previouslyMuted: true)
        } else if SystemAudioStatus.setDefaultOutputMuted(true) {
            activeAudioInterruption = .muted(previouslyMuted: false)
        }
    }

    private func restoreAudioInterruptionIfNeeded() {
        guard let activeAudioInterruption else { return }
        self.activeAudioInterruption = nil

        switch activeAudioInterruption {
        case .muted(let previouslyMuted):
            if !previouslyMuted {
                _ = SystemAudioStatus.setDefaultOutputMuted(false)
            }
        }
    }

    private func beginRecording(triggerMode: RecordingTriggerMode) {
        os_log(.info, log: recordingLog, "beginRecording() entered")
        clearPendingOverlayDismissToken()
        errorMessage = nil

        isRecording = true
        statusText = "Starting..."
        hasShownScreenshotPermissionAlert = false

        // Show initializing dots only if engine takes longer than 0.2s to start
        var overlayShown = false
        cancelRecordingInitializationTimer()
        let initTimer = DispatchSource.makeTimerSource(queue: .main)
        recordingInitializationTimer = initTimer
        initTimer.schedule(deadline: .now() + 0.2)
        initTimer.setEventHandler { [weak self] in
            guard let self, !overlayShown else { return }
            overlayShown = true
            os_log(.info, log: recordingLog, "engine slow — showing initializing overlay")
            self.clearPendingOverlayDismissToken()
            self.overlayManager.showInitializing(
                mode: self.activeRecordingTriggerMode ?? triggerMode,
                recordingMode: self.currentSessionIntent.recordingOverlayMode
            )
        }
        initTimer.resume()

        // Transition to waveform when first real audio arrives (any non-zero RMS)
        let deviceUID = selectedMicrophoneID
        audioRecorder.onRecordingReady = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancelRecordingInitializationTimer()
                os_log(.info, log: recordingLog, "first real audio — transitioning to waveform")
                self.statusText = "Recording..."
                self.clearPendingOverlayDismissToken()
                if overlayShown {
                    self.overlayManager.transitionToRecording(
                        mode: self.activeRecordingTriggerMode ?? triggerMode,
                        recordingMode: self.currentSessionIntent.recordingOverlayMode
                    )
                } else {
                    self.overlayManager.showRecording(
                        mode: self.activeRecordingTriggerMode ?? triggerMode,
                        recordingMode: self.currentSessionIntent.recordingOverlayMode
                    )
                }
                overlayShown = true
                self.playAlertSound(named: "Tink")
            }
        }
        audioRecorder.onRecordingFailure = { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancelRecordingInitializationTimer()
                self.handleRecordingFailure(error)
            }
        }

        startRealtimeStreamingIfEnabled()

        // Start engine on background thread so UI isn't blocked
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                try self.audioRecorder.startRecording(deviceUID: deviceUID)
                os_log(.info, log: recordingLog, "audioRecorder.startRecording() done: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                DispatchQueue.main.async {
                    guard self.isRecording, self.activeRecordingTriggerMode != nil else { return }
                    if !self.currentSessionIntent.isJournalMode {
                        self.startContextCapture()
                    }
                    self.audioLevelCancellable = self.audioRecorder.$audioLevel
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] level in
                            self?.overlayManager.updateAudioLevel(level)
                        }
                }
            } catch {
                DispatchQueue.main.async {
                    self.cancelRecordingInitializationTimer()
                    guard self.isRecording || self.activeRecordingTriggerMode != nil else { return }
                    self.handleRecordingFailure(error)
                }
            }
        }
    }

    private func handleRecordingFailure(_ error: Error) {
        cancelRecordingInitializationTimer()
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        tearDownRealtimeService()
        audioRecorder.cleanup()
        restoreAudioInterruptionIfNeeded()
        isRecording = false
        isTranscribing = false
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if let transcribingAudioFileName {
            AudioFileStore.deleteAudioFile(transcribingAudioFileName)
            self.transcribingAudioFileName = nil
        }
        activeRecordingTriggerMode = nil
        currentSessionIntent = .dictation
        pendingJournalModeInvocation = false
        shortcutSessionController.reset()
        errorMessage = formattedRecordingStartError(error)
        statusText = "Error"
        overlayManager.dismiss()
        refreshAvailableMicrophonesIfNeeded()
    }

    private func formattedRecordingStartError(_ error: Error) -> String {
        if let recorderError = error as? AudioRecorderError {
            return "Failed to start recording: \(recorderError.localizedDescription)"
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("operation couldn't be completed") || lower.contains("operation could not be completed") {
            return "Failed to start recording: Audio input error. Verify microphone access is granted and a working mic is selected in System Settings > Sound > Input."
        }

        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain {
            return "Failed to start recording (audio subsystem error \(nsError.code)). Check microphone permissions and selected input device."
        }

        return "Failed to start recording: \(error.localizedDescription)"
    }

    func showMicrophonePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "\(AppName.displayName) cannot record audio without Microphone access.\n\nGo to System Settings > Privacy & Security > Microphone and enable \(AppName.displayName)."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openMicrophoneSettings()
        }
    }

    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "\(AppName.displayName) cannot type transcriptions without Accessibility access.\n\nGo to System Settings > Privacy & Security > Accessibility and enable \(AppName.displayName)."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func precomputeMacros() {
        precomputedMacros = VoiceMacroMatcher.precompute(voiceMacros)
    }

    private static func statusMessage(
        for outcome: TranscriptProcessingOutcome,
        parsedTranscript: TranscriptCommandParsingResult,
        isRetry: Bool = false
    ) -> String {
        let status = outcome.statusMessage(isRetry: isRetry)
        guard parsedTranscript.shouldPressEnterAfterPaste else { return status }
        return "\(status); detected press enter command"
    }

    func playAlertSound(named name: String) {
        guard alertSoundsEnabled else { return }

        let sound = NSSound(named: name)
        sound?.volume = soundVolume
        sound?.play()
    }

    private func findMatchingMacro(for transcript: String) -> VoiceMacro? {
        VoiceMacroMatcher.match(transcript: transcript, macros: precomputedMacros)
    }

    private enum TranscriptProcessingOutcome {
        case skippedEmptyRawTranscript
        case voiceMacro(command: String)
        case postProcessingSucceeded
        case postProcessingFailedFallback

        func statusMessage(isRetry: Bool = false) -> String {
            switch self {
            case .skippedEmptyRawTranscript:
                return "Skipped macros and post-processing for empty raw transcript"
            case .voiceMacro(let command):
                return "Voice macro used: \(command)"
            case .postProcessingSucceeded:
                return isRetry ? "Post-processing succeeded (retried)" : "Post-processing succeeded"
            case .postProcessingFailedFallback:
                return isRetry
                    ? "Post-processing failed on retry, using raw transcript"
                    : "Post-processing failed, using raw transcript"
            }
        }
    }

    private func processTranscript(
        _ rawTranscript: String,
        intent: SessionIntent,
        context: AppContext,
        postProcessingService: PostProcessingService,
        customVocabulary: String,
        customSystemPrompt: String,
        outputLanguage: String = ""
    ) async -> (finalTranscript: String, outcome: TranscriptProcessingOutcome, prompt: String) {
        let trimmedRawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedRawTranscript.isEmpty else {
            return ("", .skippedEmptyRawTranscript, "")
        }

        if let macro = findMatchingMacro(for: trimmedRawTranscript) {
            os_log(.info, log: recordingLog, "Voice macro triggered: %{public}@", macro.command)
            return (macro.payload, .voiceMacro(command: macro.command), "")
        }
        
        do {
            let result = try await postProcessingService.postProcess(
                transcript: trimmedRawTranscript,
                context: context,
                customVocabulary: customVocabulary,
                customSystemPrompt: customSystemPrompt,
                outputLanguage: outputLanguage
            )
            return (result.transcript, .postProcessingSucceeded, result.prompt)
        } catch {
            os_log(.error, log: recordingLog, "Post-processing failed: %{public}@", error.localizedDescription)
            return (trimmedRawTranscript, .postProcessingFailedFallback, "")
        }
    }

    /// Await the realtime WebSocket's final transcript. If it errors out (or
    /// was never started) fall back to the file-based POST so the user still
    /// gets a transcript. Runs the realtime commit and file upload in that
    /// strict order to avoid paying for both when realtime succeeds.
    private static func resolveRawTranscript(
        realtimeService: RealtimeTranscriptionService?,
        fileService: TranscriptionService,
        fileURL: URL
    ) async throws -> String {
        if let realtimeService {
            do {
                try Task.checkCancellation()
                return try await withTaskCancellationHandler {
                    try await realtimeService.commitAndAwaitFinal()
                } onCancel: {
                    realtimeService.cancel()
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                return try await fileService.transcribe(fileURL: fileURL)
            }
        }
        return try await fileService.transcribe(fileURL: fileURL)
    }

    private func stopAndTranscribe() {
        cancelPendingShortcutStart()
        cancelRecordingInitializationTimer()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        let sessionIntent = currentSessionIntent
        currentSessionIntent = .dictation
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        debugStatusMessage = "Preparing audio"
        let sessionContext = capturedContext
        let inFlightContextTask = contextCaptureTask
        capturedContext = nil
        contextCaptureTask = nil
        lastRawTranscript = ""
        lastPostProcessedTranscript = ""
        lastContextSummary = ""
        lastPostProcessingStatus = ""
        lastPostProcessingPrompt = ""
        lastContextScreenshotDataURL = nil
        lastContextScreenshotStatus = "No screenshot"
        isRecording = false
        restoreAudioInterruptionIfNeeded()
        isTranscribing = true
        statusText = "Preparing audio..."
        errorMessage = nil
        playAlertSound(named: "Pop")
        overlayManager.prepareForTranscribing()
        audioRecorder.stopRecording { [weak self] fileURL in
            guard let self else { return }
            guard let fileURL else {
                self.isTranscribing = false
                self.audioRecorder.cleanup()
                self.errorMessage = "No audio recorded"
                self.statusText = "Error"
                self.overlayManager.dismiss()
                self.refreshAvailableMicrophonesIfNeeded()
                return
            }

            guard self.isTranscribing else {
                self.tearDownRealtimeService()
                self.audioRecorder.cleanup()
                self.refreshAvailableMicrophonesIfNeeded()
                return
            }

            let savedAudioFile = AudioFileStore.saveAudioFile(from: fileURL)
            let transcriptionFileURL = savedAudioFile?.fileURL ?? fileURL
            self.transcribingAudioFileName = savedAudioFile?.fileName
            self.statusText = "Transcribing..."
            self.debugStatusMessage = "Transcribing audio"

            self.overlayManager.showTranscribing()

        let postProcessingService = PostProcessingService(
            apiKey: apiKey,
            baseURL: apiBaseURL,
            preferredModel: postProcessingModel,
            preferredFallbackModel: postProcessingFallbackModel
        )

            let activeRealtime = self.realtimeService
            self.realtimeService = nil
            self.audioRecorder.onPCM16Samples = nil
            self.transcriptionTask?.cancel()
            guard self.isTranscribing else {
                if let savedAudioFile {
                    AudioFileStore.deleteAudioFile(savedAudioFile.fileName)
                }
                self.transcribingAudioFileName = nil
                activeRealtime?.cancel()
                self.audioRecorder.cleanup()
                self.refreshAvailableMicrophonesIfNeeded()
                return
            }
            self.transcriptionTask = Task {
                defer {
                    activeRealtime?.cancel()
                }
                do {
                    let transcriptionService = try self.makeTranscriptionService()
                    async let transcript = Self.resolveRawTranscript(
                        realtimeService: activeRealtime,
                        fileService: transcriptionService,
                        fileURL: transcriptionFileURL
                    )
                    let rawTranscript = try await transcript
                    if sessionIntent.isJournalMode {
                        try Task.checkCancellation()
                        let trimmedRawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        let appContext = self.journalContextAtStop()
                        let journalFileURL: URL?
                        do {
                            journalFileURL = try JournalLogStore(
                                folderURL: self.resolvedJournalModeFolderURL
                            ).append(rawTranscript: rawTranscript)
                        } catch {
                            await MainActor.run {
                                guard self.isTranscribing else { return }
                                self.transcriptionTask = nil
                                self.transcribingAudioFileName = nil
                                self.errorMessage = "Unable to write journal: \(error.localizedDescription)"
                                self.isTranscribing = false
                                self.statusText = "Journal error"
                                self.debugStatusMessage = "Journal write failed"
                                self.lastTranscript = ""
                                self.lastRawTranscript = trimmedRawTranscript
                                self.lastPostProcessedTranscript = ""
                                self.lastContextSummary = appContext.contextSummary
                                self.lastPostProcessingStatus = "Error: \(error.localizedDescription)"
                                self.lastPostProcessingPrompt = ""
                                self.lastContextScreenshotDataURL = nil
                                self.lastContextScreenshotStatus = "Journal Mode skips app context capture"
                                self.recordPipelineHistoryEntry(
                                    rawTranscript: trimmedRawTranscript,
                                    postProcessedTranscript: "",
                                    postProcessingPrompt: "",
                                    systemPrompt: "",
                                    context: appContext,
                                    processingStatus: "Error: \(error.localizedDescription)",
                                    intent: sessionIntent,
                                    audioFileName: savedAudioFile?.fileName
                                )
                                self.overlayManager.dismiss()
                                self.audioRecorder.cleanup()
                                self.refreshAvailableMicrophonesIfNeeded()
                                self.scheduleReadyStatusReset(after: 3, matching: ["Journal error"])
                            }
                            return
                        }

                        try Task.checkCancellation()
                        await MainActor.run {
                            guard self.isTranscribing else { return }
                            self.transcriptionTask = nil
                            self.transcribingAudioFileName = nil
                            self.errorMessage = nil
                            self.isTranscribing = false
                            self.debugStatusMessage = "Done"
                            self.lastTranscript = trimmedRawTranscript
                            self.lastRawTranscript = trimmedRawTranscript
                            self.lastPostProcessedTranscript = trimmedRawTranscript
                            self.lastPostProcessingPrompt = ""
                            self.lastContextSummary = appContext.contextSummary
                            self.lastContextScreenshotDataURL = nil
                            self.lastContextScreenshotStatus = "Journal Mode skips app context capture"
                            self.lastContextAppName = appContext.appName ?? ""
                            self.lastContextBundleIdentifier = appContext.bundleIdentifier ?? ""
                            self.lastContextWindowTitle = appContext.windowTitle ?? ""
                            self.lastContextSelectedText = ""
                            self.lastContextLLMPrompt = ""

                            let processingStatus = journalFileURL == nil
                                ? "Skipped empty raw transcript"
                                : "Logged raw transcript to journal"
                            self.lastPostProcessingStatus = processingStatus
                            self.recordPipelineHistoryEntry(
                                rawTranscript: trimmedRawTranscript,
                                postProcessedTranscript: trimmedRawTranscript,
                                postProcessingPrompt: "",
                                systemPrompt: "",
                                context: appContext,
                                processingStatus: processingStatus,
                                intent: sessionIntent,
                                audioFileName: savedAudioFile?.fileName
                            )

                            let completionStatusText = journalFileURL == nil
                                ? "Nothing to journal"
                                : "Logged to journal"
                            self.statusText = completionStatusText
                            self.clearPendingOverlayDismissToken()
                            self.overlayManager.dismiss()
                            self.audioRecorder.cleanup()
                            self.refreshAvailableMicrophonesIfNeeded()
                            self.scheduleReadyStatusReset(
                                after: 3,
                                matching: ["Logged to journal", "Nothing to journal"]
                            )
                        }
                        return
                    }

                    let parsedTranscript = TranscriptCommandParser.parse(
                        transcript: rawTranscript,
                        pressEnterCommandEnabled: self.isPressEnterVoiceCommandEnabled
                    )
                    try Task.checkCancellation()
                    let appContext: AppContext
                    if let sessionContext {
                        appContext = sessionContext
                    } else if let inFlightContext = await inFlightContextTask?.value {
                        appContext = inFlightContext
                    } else {
                        appContext = self.fallbackContextAtStop()
                    }
                    try Task.checkCancellation()
                    await MainActor.run { [weak self] in
                        self?.debugStatusMessage = "Running post-processing"
                    }
                    let result = await self.processTranscript(
                        parsedTranscript.transcript,
                        intent: sessionIntent,
                        context: appContext,
                        postProcessingService: postProcessingService,
                        customVocabulary: self.customVocabulary,
                        customSystemPrompt: self.customSystemPrompt,
                        outputLanguage: self.outputLanguage
                    )
                    try Task.checkCancellation()

                    await MainActor.run {
                        guard self.isTranscribing else { return }
                        self.lastContextSummary = appContext.contextSummary
                        self.lastContextScreenshotDataURL = appContext.screenshotDataURL
                        self.lastContextScreenshotStatus = appContext.screenshotError
                            ?? "available (\(appContext.screenshotMimeType ?? "image"))"
                        self.lastContextAppName = appContext.appName ?? ""
                        self.lastContextBundleIdentifier = appContext.bundleIdentifier ?? ""
                        self.lastContextWindowTitle = appContext.windowTitle ?? ""
                        self.lastContextSelectedText = appContext.selectedText ?? ""
                        self.lastContextLLMPrompt = appContext.contextPrompt ?? ""
                        let trimmedRawTranscript = parsedTranscript.transcript
                        let trimmedFinalTranscript = result.finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        let processingStatus = Self.statusMessage(
                            for: result.outcome,
                            parsedTranscript: parsedTranscript
                        )
                        self.lastPostProcessingPrompt = result.prompt
                        self.lastRawTranscript = trimmedRawTranscript
                        self.lastPostProcessedTranscript = trimmedFinalTranscript
                        self.lastPostProcessingStatus = processingStatus
                        self.recordPipelineHistoryEntry(
                            rawTranscript: trimmedRawTranscript,
                            postProcessedTranscript: trimmedFinalTranscript,
                            postProcessingPrompt: result.prompt,
                            systemPrompt: Self.resolvedSystemPrompt(self.customSystemPrompt),
                            context: appContext,
                            processingStatus: processingStatus,
                            intent: sessionIntent,
                            audioFileName: savedAudioFile?.fileName
                        )
                        self.transcriptionTask = nil
                        self.transcribingAudioFileName = nil
                        self.lastTranscript = trimmedFinalTranscript
                        self.isTranscribing = false
                        self.debugStatusMessage = "Done"
                        let completionStatusText = self.preserveClipboard ? "Pasted at cursor!" : "Copied to clipboard!"
                        let enterOnlyStatusText = "Pressed Enter"
                        let shouldPressEnterAfterPaste = parsedTranscript.shouldPressEnterAfterPaste

                        let shouldPersistRawDictationFallback: Bool
                        switch result.outcome {
                        case .postProcessingFailedFallback:
                            shouldPersistRawDictationFallback = !trimmedFinalTranscript.isEmpty
                        default:
                            shouldPersistRawDictationFallback = false
                        }

                        if trimmedFinalTranscript.isEmpty {
                            self.statusText = shouldPressEnterAfterPaste ? enterOnlyStatusText : "Nothing to transcribe"
                            self.clearPendingOverlayDismissToken()
                            if !self.showPostTranscriptionUpdateReminderIfNeeded() {
                                self.overlayManager.dismiss()
                            }
                            if shouldPressEnterAfterPaste {
                                self.pressEnterWhenShortcutReleased()
                            }
                        } else {
                            self.statusText = completionStatusText
                            if shouldPersistRawDictationFallback {
                                self.scheduleOverlayDismissAfterFailureIndicator(after: 2.5)
                            } else {
                                self.clearPendingOverlayDismissToken()
                                if !self.showPostTranscriptionUpdateReminderIfNeeded() {
                                    self.overlayManager.dismiss()
                                }
                            }

                            let pendingClipboardRestore = self.writeTranscriptToPasteboard(trimmedFinalTranscript)
                            self.pasteAtCursorWhenShortcutReleased {
                                if shouldPressEnterAfterPaste {
                                    self.pressEnterAfterPaste {
                                        self.restoreClipboardIfNeeded(pendingClipboardRestore)
                                    }
                                } else {
                                    self.restoreClipboardIfNeeded(pendingClipboardRestore)
                                }
                            }
                        }

                        self.audioRecorder.cleanup()
                        self.refreshAvailableMicrophonesIfNeeded()

                        self.scheduleReadyStatusReset(after: 3, matching: [completionStatusText, "Nothing to transcribe", enterOnlyStatusText])
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.transcriptionTask = nil
                    }
                } catch {
                    let resolvedContext: AppContext
                    if let sessionContext {
                        resolvedContext = sessionContext
                    } else if let inFlightContext = await inFlightContextTask?.value {
                        resolvedContext = inFlightContext
                    } else {
                        resolvedContext = self.fallbackContextAtStop()
                    }
                    await MainActor.run {
                        guard self.isTranscribing else { return }
                        self.transcriptionTask = nil
                        self.transcribingAudioFileName = nil
                        self.errorMessage = error.localizedDescription
                        self.isTranscribing = false
                        self.statusText = "Error"
                        self.overlayManager.dismiss()
                        self.lastPostProcessedTranscript = ""
                        self.lastRawTranscript = ""
                        self.lastContextSummary = ""
                        self.lastPostProcessingStatus = "Error: \(error.localizedDescription)"
                        self.lastPostProcessingPrompt = ""
                        self.lastContextScreenshotDataURL = resolvedContext.screenshotDataURL
                        self.lastContextScreenshotStatus = resolvedContext.screenshotError
                            ?? "available (\(resolvedContext.screenshotMimeType ?? "image"))"
                        self.recordPipelineHistoryEntry(
                            rawTranscript: "",
                            postProcessedTranscript: "",
                            postProcessingPrompt: "",
                            systemPrompt: Self.resolvedSystemPrompt(self.customSystemPrompt),
                            context: resolvedContext,
                            processingStatus: "Error: \(error.localizedDescription)",
                            intent: sessionIntent,
                            audioFileName: savedAudioFile?.fileName
                        )
                        self.audioRecorder.cleanup()
                        self.refreshAvailableMicrophonesIfNeeded()
                    }
                }
            }
        }
    }

    static func resolvedSystemPrompt(_ customSystemPrompt: String) -> String {
        customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? PostProcessingService.defaultSystemPrompt
            : customSystemPrompt
    }

    private func recordPipelineHistoryEntry(
        rawTranscript: String,
        postProcessedTranscript: String,
        postProcessingPrompt: String,
        systemPrompt: String,
        context: AppContext,
        processingStatus: String,
        intent: SessionIntent,
        audioFileName: String? = nil
    ) {
        let newEntry = PipelineHistoryItem(
            intent: intent.persistedIntent,
            capturedSelection: context.selectedText,
            timestamp: Date(),
            rawTranscript: rawTranscript,
            postProcessedTranscript: postProcessedTranscript,
            postProcessingPrompt: postProcessingPrompt,
            systemPrompt: systemPrompt,
            contextSummary: context.contextSummary,
            contextSystemPrompt: context.contextSystemPrompt,
            contextPrompt: context.contextPrompt,
            contextScreenshotDataURL: context.screenshotDataURL,
            contextScreenshotStatus: context.screenshotError
                ?? "available (\(context.screenshotMimeType ?? "image"))",
            postProcessingStatus: processingStatus,
            debugStatus: debugStatusMessage,
            customVocabulary: customVocabulary,
            audioFileName: audioFileName,
            contextAppName: context.appName,
            contextBundleIdentifier: context.bundleIdentifier,
            contextWindowTitle: context.windowTitle
        )
        do {
            let removedAudioFileNames = try pipelineHistoryStore.append(newEntry, maxCount: maxPipelineHistoryCount)
            for audioFileName in removedAudioFileNames {
                AudioFileStore.deleteAudioFile(audioFileName)
            }
            pipelineHistory = pipelineHistoryStore.loadAllHistory()
        } catch {
            errorMessage = "Unable to save run history entry: \(error.localizedDescription)"
        }
    }

    private func startRealtimeStreamingIfEnabled() {
        guard realtimeStreamingEnabled else { return }
        let trimmedBase = resolvedTranscriptionBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else {
            os_log(.info, log: recordingLog, "realtime streaming requested but base URL is empty — skipping")
            return
        }
        let model = realtimeStreamingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = RealtimeTranscriptionService.Configuration(
            baseURL: trimmedBase,
            apiKey: resolvedTranscriptionAPIKey,
            model: model,
            language: resolvedTranscriptionLanguage
        )
        let service = RealtimeTranscriptionService(config: config)
        do {
            try service.start()
        } catch {
            os_log(.error, log: recordingLog, "failed to start realtime service: %{public}@", error.localizedDescription)
            return
        }
        realtimeService = service
        audioRecorder.onPCM16Samples = { [weak service] data in
            service?.appendPCM16(data)
        }
    }

    private func tearDownRealtimeService() {
        audioRecorder.onPCM16Samples = nil
        realtimeService?.cancel()
        realtimeService = nil
    }

    private func startContextCapture() {
        contextCaptureTask?.cancel()
        capturedContext = nil
        lastContextSummary = "Collecting app context..."
        lastPostProcessingStatus = ""
        lastContextScreenshotDataURL = nil
        lastContextScreenshotStatus = "Collecting screenshot..."

        contextCaptureTask = Task { [weak self] in
            guard let self else { return nil }
            let context = await self.contextService.collectContext()
            await MainActor.run {
                self.capturedContext = context
                self.lastContextSummary = context.contextSummary
                self.lastContextScreenshotDataURL = context.screenshotDataURL
                self.lastContextScreenshotStatus = context.screenshotError
                    ?? "available (\(context.screenshotMimeType ?? "image"))"
                self.lastContextAppName = context.appName ?? ""
                self.lastContextBundleIdentifier = context.bundleIdentifier ?? ""
                self.lastContextWindowTitle = context.windowTitle ?? ""
                self.lastContextSelectedText = context.selectedText ?? ""
                self.lastContextLLMPrompt = context.contextPrompt ?? ""
                self.lastPostProcessingStatus = "App context captured"
                self.handleScreenshotCaptureIssue(context.screenshotError)
            }
            return context
        }
    }

    private func fallbackContextAtStop() -> AppContext {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let windowTitle = focusedWindowTitle(for: frontmostApp)
        return AppContext(
            appName: frontmostApp?.localizedName,
            bundleIdentifier: frontmostApp?.bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: nil,
            currentActivity: "Could not refresh app context at stop time; using text-only post-processing.",
            contextSystemPrompt: resolvedContextSystemPrompt(),
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: "No app context captured before stop"
        )
    }

    private func journalContextAtStop() -> AppContext {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let windowTitle = focusedWindowTitle(for: frontmostApp)
        return AppContext(
            appName: frontmostApp?.localizedName,
            bundleIdentifier: frontmostApp?.bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: nil,
            currentActivity: "Journal Mode skips app context capture and writes the raw transcript to Markdown.",
            contextSystemPrompt: nil,
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: "Journal Mode skips app context capture"
        )
    }

    private func resolvedContextSystemPrompt() -> String {
        let trimmedPrompt = customContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? AppContextService.defaultContextPrompt : trimmedPrompt
    }

    private func focusedWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return focusedWindowTitle(from: appElement)
    }

    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(from: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        guard let windowTitle = accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString) else {
            return nil
        }

        return trimmedText(windowTitle)
    }

    private func accessibilityElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func accessibilityString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }

    private func trimmedText(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.isEmpty ? nil : trimmed
    }

    private func handleScreenshotCaptureIssue(_ message: String?) {
        guard let message, !message.isEmpty else {
            hasShownScreenshotPermissionAlert = false
            return
        }

        os_log(.error, "Screenshot capture issue: %{public}@", message)

        if isScreenCapturePermissionError(message) && !hasShownScreenshotPermissionAlert {
            hasScreenRecordingPermission = false
            hasShownScreenshotPermissionAlert = true
        }
        // Non-permission errors (transient failures) — continue recording without context
    }

    private func isScreenCapturePermissionError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("permission") || lowered.contains("screen recording")
    }

    private func showScreenshotPermissionAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "\(message)\n\n\(AppName.displayName) requires Screen Recording permission to capture screenshots for context-aware transcription.\n\nGo to System Settings > Privacy & Security > Screen Recording and enable \(AppName.displayName)."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openScreenCaptureSettings()
        }
    }

    private func showScreenshotCaptureErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Screenshot Capture Failed"
        alert.informativeText = "\(message)\n\nA screenshot is required for context-aware transcription. Recording has been stopped."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        _ = alert.runModal()
    }

    func toggleDebugOverlay() {
        if isDebugOverlayActive {
            stopDebugOverlay()
        } else {
            startDebugOverlay()
        }
    }

    private func startDebugOverlay() {
        isDebugOverlayActive = true
        clearPendingOverlayDismissToken()
        overlayManager.showRecording()

        // Simulate audio levels with a timer
        var phase: Double = 0.0
        debugOverlayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            phase += 0.15
            // Generate a fake audio level that oscillates like speech
            let base = 0.3 + 0.2 * sin(phase)
            let noise = Float.random(in: -0.15...0.15)
            let level = min(max(Float(base) + noise, 0.0), 1.0)
            self.overlayManager.updateAudioLevel(level)
        }
    }

    private func stopDebugOverlay() {
        debugOverlayTimer?.invalidate()
        debugOverlayTimer = nil
        isDebugOverlayActive = false
        clearPendingOverlayDismissToken()
        overlayManager.dismiss()
    }

    private func clearPendingOverlayDismissToken() {
        pendingOverlayDismissToken = nil
    }

    @MainActor
    private func showPostTranscriptionUpdateReminderIfNeeded() -> Bool {
        let updateManager = UpdateManager.shared
        guard updateManager.shouldShowPostTranscriptionReminder() else { return false }

        let dismissToken = UUID()
        pendingOverlayDismissToken = dismissToken
        updateManager.markPostTranscriptionReminderShown()
        overlayManager.showUpdateAvailable(version: updateManager.latestReleaseVersion)

        DispatchQueue.main.asyncAfter(deadline: .now() + postTranscriptionUpdateReminderDuration) { [weak self] in
            guard let self, self.pendingOverlayDismissToken == dismissToken else { return }
            self.pendingOverlayDismissToken = nil
            self.overlayManager.dismiss()
        }

        return true
    }

    @MainActor
    private func handleUpdateOverlayPressed() {
        clearPendingOverlayDismissToken()
        overlayManager.dismiss()
        selectedSettingsTab = .general
        NotificationCenter.default.post(name: .showSettings, object: nil)

        DispatchQueue.main.async {
            if UpdateManager.shared.updateAvailable {
                UpdateManager.shared.showUpdateAlert()
            }
        }
    }

    private func scheduleOverlayDismissAfterFailureIndicator(after delay: TimeInterval) {
        let dismissToken = UUID()
        pendingOverlayDismissToken = dismissToken
        overlayManager.showFailureIndicator()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.pendingOverlayDismissToken == dismissToken else { return }
            self.pendingOverlayDismissToken = nil
            self.overlayManager.dismiss()
        }
    }

    func toggleDebugPanel() {
        selectedSettingsTab = .runLog
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    private func pasteAtCursor() {
        ClipboardTextOutput.pasteAtCursor()
    }

    private func pressEnter() {
        ClipboardTextOutput.pressEnter()
    }

    private func writeTranscriptToPasteboard(_ transcript: String) -> PendingClipboardRestore? {
        ClipboardTextOutput.writeTranscriptToPasteboard(transcript, preserveClipboard: preserveClipboard)
    }

    private func restoreClipboardIfNeeded(_ pendingRestore: PendingClipboardRestore?) {
        guard let pendingRestore else { return }

        // Some apps consume Cmd-V asynchronously, so restoring too quickly can paste
        // the pre-dictation clipboard instead of the transcript.
        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
            ClipboardTextOutput.restoreClipboardIfNeeded(pendingRestore)
        }
    }

    private func performAfterShortcutReleased(attempt: Int = 0, action: @escaping () -> Void) {
        let maxAttempts = 24
        if hotkeyManager.hasPressedShortcutInputs && attempt < maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                self?.performAfterShortcutReleased(attempt: attempt + 1, action: action)
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteAfterShortcutReleaseDelay) {
            action()
        }
    }

    private func pasteAtCursorWhenShortcutReleased(completion: (() -> Void)? = nil) {
        performAfterShortcutReleased { [weak self] in
            self?.pasteAtCursor()
            completion?()
        }
    }

    private func pressEnterWhenShortcutReleased(completion: (() -> Void)? = nil) {
        performAfterShortcutReleased { [weak self] in
            self?.pressEnter()
            completion?()
        }
    }

    private func pressEnterAfterPaste(completion: (() -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + pressEnterAfterPasteDelay) { [weak self] in
            self?.pressEnter()
            completion?()
        }
    }

    private func cancelRecordingInitializationTimer() {
        recordingInitializationTimer?.cancel()
        recordingInitializationTimer = nil
    }

    private func scheduleReadyStatusReset(after delay: TimeInterval, matching statuses: Set<String>? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if let statuses, !statuses.contains(self.statusText) {
                return
            }
            self.statusText = "Ready"
        }
    }
}
