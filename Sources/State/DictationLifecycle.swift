import Foundation

enum DictationLifecycleIntent: Equatable {
    case dictation
    case journal

    var isJournalMode: Bool {
        self == .journal
    }
}

struct DictationLifecycleSession: Equatable {
    let triggerMode: RecordingTriggerMode
    let intent: DictationLifecycleIntent
    let journalModeRequested: Bool

    init(
        triggerMode: RecordingTriggerMode,
        intent: DictationLifecycleIntent,
        journalModeRequested: Bool
    ) {
        self.triggerMode = triggerMode
        self.intent = intent
        self.journalModeRequested = journalModeRequested
    }
}

struct PendingShortcutStart: Equatable {
    let session: DictationLifecycleSession
    let delay: TimeInterval
}

struct PendingMicrophonePermission: Equatable {
    let session: DictationLifecycleSession
}

struct RecordingLifecycleSession: Equatable {
    let session: DictationLifecycleSession
    let isReady: Bool
}

struct StoppingLifecycleSession: Equatable {
    let session: DictationLifecycleSession
}

struct TranscriptionLifecycleSession: Equatable {
    let session: DictationLifecycleSession
    let audioFileAvailable: Bool
}

struct CancelledLifecycleSession: Equatable {
    let previousPhaseDescription: String
}

struct FailedLifecycleSession: Equatable {
    let message: String
}

enum DictationPhase: Equatable {
    case idle
    case pendingShortcutStart(PendingShortcutStart)
    case awaitingMicrophonePermission(PendingMicrophonePermission)
    case recording(RecordingLifecycleSession)
    case stopping(StoppingLifecycleSession)
    case transcribing(TranscriptionLifecycleSession)
    case cancelled(CancelledLifecycleSession)
    case failed(FailedLifecycleSession)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isTranscribing: Bool {
        switch self {
        case .stopping, .transcribing:
            return true
        case .idle, .pendingShortcutStart, .awaitingMicrophonePermission, .recording, .cancelled, .failed:
            return false
        }
    }

    var allowsNewRecordingRequest: Bool {
        switch self {
        case .idle, .cancelled, .failed:
            return true
        case .pendingShortcutStart, .awaitingMicrophonePermission, .recording, .stopping, .transcribing:
            return false
        }
    }

    var activeSession: DictationLifecycleSession? {
        switch self {
        case .idle, .cancelled, .failed:
            return nil
        case .pendingShortcutStart(let pending):
            return pending.session
        case .awaitingMicrophonePermission(let pending):
            return pending.session
        case .recording(let recording):
            return recording.session
        case .stopping(let stopping):
            return stopping.session
        case .transcribing(let transcribing):
            return transcribing.session
        }
    }
}

enum DictationLifecycleEvent: Equatable {
    case startRequested(
        triggerMode: RecordingTriggerMode,
        intent: DictationLifecycleIntent,
        journalModeRequested: Bool,
        delay: TimeInterval
    )
    case pendingStartElapsed
    case pendingStartCancelled
    case microphonePermissionRequired
    case microphonePermissionResolved(granted: Bool)
    case recordingReady
    case stopRequested
    case audioFilePrepared(available: Bool)
    case transcriptionSucceeded
    case transcriptionFailed(message: String)
    case recordingFailed(message: String)
    case cancelRequested
    case readyReset
}

enum DictationLifecycleEffect: Equatable {
    case scheduleShortcutStart(delay: TimeInterval)
    case cancelPendingShortcutStart
    case requestMicrophonePermission
    case pauseHotkeysForPermission
    case resumeHotkeysAfterPermission
    case startRecording(DictationLifecycleSession)
    case stopRecording(DictationLifecycleSession)
    case startTranscription(DictationLifecycleSession)
    case cancelRecording
    case cancelTranscription
    case resetShortcutSession
    case resetToReady
    case reportFailure(String)
}

struct DictationLifecycleTransition: Equatable {
    let phase: DictationPhase
    let effects: [DictationLifecycleEffect]
}

struct DictationLifecycleReducer {
    func reduce(
        phase: DictationPhase,
        event: DictationLifecycleEvent
    ) -> DictationLifecycleTransition {
        switch event {
        case .startRequested(let triggerMode, let intent, let journalModeRequested, let delay):
            guard phase.allowsNewRecordingRequest else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }

            let session = DictationLifecycleSession(
                triggerMode: triggerMode,
                intent: intent,
                journalModeRequested: journalModeRequested
            )

            guard delay > 0 else {
                return DictationLifecycleTransition(
                    phase: .recording(RecordingLifecycleSession(session: session, isReady: false)),
                    effects: [.startRecording(session)]
                )
            }

            return DictationLifecycleTransition(
                phase: .pendingShortcutStart(PendingShortcutStart(session: session, delay: delay)),
                effects: [.scheduleShortcutStart(delay: delay)]
            )

        case .pendingStartElapsed:
            guard case .pendingShortcutStart(let pending) = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
            return DictationLifecycleTransition(
                phase: .recording(RecordingLifecycleSession(session: pending.session, isReady: false)),
                effects: [.startRecording(pending.session)]
            )

        case .pendingStartCancelled:
            guard case .pendingShortcutStart = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
            return DictationLifecycleTransition(
                phase: .idle,
                effects: [.cancelPendingShortcutStart, .resetShortcutSession, .resetToReady]
            )

        case .microphonePermissionRequired:
            guard let session = phase.activeSession else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
            return DictationLifecycleTransition(
                phase: .awaitingMicrophonePermission(PendingMicrophonePermission(session: session)),
                effects: [.pauseHotkeysForPermission, .requestMicrophonePermission]
            )

        case .microphonePermissionResolved(let granted):
            guard case .awaitingMicrophonePermission(let pending) = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }

            guard granted else {
                return DictationLifecycleTransition(
                    phase: .failed(FailedLifecycleSession(message: "Microphone permission denied")),
                    effects: [
                        .resumeHotkeysAfterPermission,
                        .resetShortcutSession,
                        .reportFailure("Microphone permission denied")
                    ]
                )
            }

            let session = pending.session
            if session.triggerMode == .toggle {
                return DictationLifecycleTransition(
                    phase: .recording(RecordingLifecycleSession(session: session, isReady: false)),
                    effects: [.resumeHotkeysAfterPermission, .startRecording(session)]
                )
            }

            return DictationLifecycleTransition(
                phase: .idle,
                effects: [.resumeHotkeysAfterPermission, .resetShortcutSession, .resetToReady]
            )

        case .recordingReady:
            guard case .recording(let recording) = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
            return DictationLifecycleTransition(
                phase: .recording(RecordingLifecycleSession(session: recording.session, isReady: true)),
                effects: []
            )

        case .stopRequested:
            guard case .recording(let recording) = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
            return DictationLifecycleTransition(
                phase: .stopping(StoppingLifecycleSession(session: recording.session)),
                effects: [.stopRecording(recording.session), .resetShortcutSession]
            )

        case .audioFilePrepared(let available):
            guard case .stopping(let stopping) = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }

            guard available else {
                return DictationLifecycleTransition(
                    phase: .failed(FailedLifecycleSession(message: "No audio recorded")),
                    effects: [.reportFailure("No audio recorded")]
                )
            }

            return DictationLifecycleTransition(
                phase: .transcribing(TranscriptionLifecycleSession(
                    session: stopping.session,
                    audioFileAvailable: true
                )),
                effects: [.startTranscription(stopping.session)]
            )

        case .transcriptionSucceeded:
            guard case .transcribing = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
            return DictationLifecycleTransition(phase: .idle, effects: [.resetToReady])

        case .transcriptionFailed(let message):
            guard case .transcribing = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
            return DictationLifecycleTransition(
                phase: .failed(FailedLifecycleSession(message: message)),
                effects: [.reportFailure(message)]
            )

        case .recordingFailed(let message):
            guard case .recording = phase else {
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
            return DictationLifecycleTransition(
                phase: .failed(FailedLifecycleSession(message: message)),
                effects: [.cancelRecording, .resetShortcutSession, .reportFailure(message)]
            )

        case .cancelRequested:
            return cancel(phase: phase)

        case .readyReset:
            switch phase {
            case .cancelled, .failed:
                return DictationLifecycleTransition(phase: .idle, effects: [.resetToReady])
            case .idle, .pendingShortcutStart, .awaitingMicrophonePermission, .recording, .stopping, .transcribing:
                return DictationLifecycleTransition(phase: phase, effects: [])
            }
        }
    }

    private func cancel(phase: DictationPhase) -> DictationLifecycleTransition {
        switch phase {
        case .idle:
            return DictationLifecycleTransition(phase: .idle, effects: [])
        case .pendingShortcutStart:
            return DictationLifecycleTransition(
                phase: .cancelled(CancelledLifecycleSession(previousPhaseDescription: "pendingShortcutStart")),
                effects: [.cancelPendingShortcutStart, .resetShortcutSession]
            )
        case .awaitingMicrophonePermission:
            return DictationLifecycleTransition(
                phase: .cancelled(CancelledLifecycleSession(previousPhaseDescription: "awaitingMicrophonePermission")),
                effects: [.resumeHotkeysAfterPermission, .resetShortcutSession]
            )
        case .recording:
            return DictationLifecycleTransition(
                phase: .cancelled(CancelledLifecycleSession(previousPhaseDescription: "recording")),
                effects: [.cancelRecording, .resetShortcutSession]
            )
        case .stopping:
            return DictationLifecycleTransition(
                phase: .cancelled(CancelledLifecycleSession(previousPhaseDescription: "stopping")),
                effects: [.cancelRecording, .resetShortcutSession]
            )
        case .transcribing:
            return DictationLifecycleTransition(
                phase: .cancelled(CancelledLifecycleSession(previousPhaseDescription: "transcribing")),
                effects: [.cancelTranscription, .resetShortcutSession]
            )
        case .cancelled, .failed:
            return DictationLifecycleTransition(phase: phase, effects: [])
        }
    }
}
