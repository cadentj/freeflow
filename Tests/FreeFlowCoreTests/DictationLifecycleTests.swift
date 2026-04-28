func immediateStartBeginsRecording() throws {
    let reducer = DictationLifecycleReducer()
    let transition = reducer.reduce(
        phase: .idle,
        event: .startRequested(
            triggerMode: .toggle,
            intent: .dictation,
            journalModeRequested: false,
            delay: 0
        )
    )

    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )

    try expect(
        transition.phase == .recording(RecordingLifecycleSession(session: session, isReady: false)),
        "Immediate start should enter recording"
    )
    try expect(transition.effects == [.startRecording(session)], "Immediate start should request recording")
    try expect(transition.phase.isRecording, "Recording compatibility accessor should be true")
    try expect(!transition.phase.isTranscribing, "Transcribing compatibility accessor should be false")
}

func delayedStartWaitsForPendingElapsedEvent() throws {
    let reducer = DictationLifecycleReducer()
    let start = reducer.reduce(
        phase: .idle,
        event: .startRequested(
            triggerMode: .hold,
            intent: .dictation,
            journalModeRequested: false,
            delay: 0.25
        )
    )

    try expect(start.effects == [.scheduleShortcutStart(delay: 0.25)], "Delayed start should schedule timer")
    guard case .pendingShortcutStart(let pending) = start.phase else {
        throw TestFailure(message: "Expected pending shortcut start", file: #fileID, line: #line)
    }

    let elapsed = reducer.reduce(phase: start.phase, event: .pendingStartElapsed)
    try expect(
        elapsed.phase == .recording(RecordingLifecycleSession(session: pending.session, isReady: false)),
        "Elapsed pending start should begin recording"
    )
    try expect(elapsed.effects == [.startRecording(pending.session)], "Elapsed pending start should request recording")
}

func pendingStartCanBeCancelled() throws {
    let reducer = DictationLifecycleReducer()
    let start = reducer.reduce(
        phase: .idle,
        event: .startRequested(
            triggerMode: .hold,
            intent: .dictation,
            journalModeRequested: false,
            delay: 0.1
        )
    )

    let cancelled = reducer.reduce(phase: start.phase, event: .pendingStartCancelled)

    try expect(cancelled.phase == .idle, "Cancelled pending start should return to idle")
    try expect(
        cancelled.effects == [.cancelPendingShortcutStart, .resetShortcutSession, .resetToReady],
        "Cancelled pending start should cancel timer and reset"
    )
}

func microphonePermissionGrantRestartsToggleRecording() throws {
    let reducer = DictationLifecycleReducer()
    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )
    let awaiting = DictationPhase.awaitingMicrophonePermission(PendingMicrophonePermission(session: session))

    let transition = reducer.reduce(
        phase: awaiting,
        event: .microphonePermissionResolved(granted: true)
    )

    try expect(
        transition.phase == .recording(RecordingLifecycleSession(session: session, isReady: false)),
        "Granted toggle permission should restart recording"
    )
    try expect(
        transition.effects == [.resumeHotkeysAfterPermission, .startRecording(session)],
        "Granted toggle permission should resume hotkeys and record"
    )
}

func microphonePermissionGrantReturnsHoldModeToIdle() throws {
    let reducer = DictationLifecycleReducer()
    let session = DictationLifecycleSession(
        triggerMode: .hold,
        intent: .dictation,
        journalModeRequested: false
    )
    let awaiting = DictationPhase.awaitingMicrophonePermission(PendingMicrophonePermission(session: session))

    let transition = reducer.reduce(
        phase: awaiting,
        event: .microphonePermissionResolved(granted: true)
    )

    try expect(transition.phase == .idle, "Granted hold permission should return to idle")
    try expect(
        transition.effects == [.resumeHotkeysAfterPermission, .resetShortcutSession, .resetToReady],
        "Granted hold permission should resume hotkeys and reset"
    )
}

func microphonePermissionDenialFailsAndReports() throws {
    let reducer = DictationLifecycleReducer()
    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )
    let awaiting = DictationPhase.awaitingMicrophonePermission(PendingMicrophonePermission(session: session))

    let transition = reducer.reduce(
        phase: awaiting,
        event: .microphonePermissionResolved(granted: false)
    )

    try expect(
        transition.phase == .failed(FailedLifecycleSession(message: "Microphone permission denied")),
        "Denied microphone permission should fail"
    )
    try expect(
        transition.effects == [
            .resumeHotkeysAfterPermission,
            .resetShortcutSession,
            .reportFailure("Microphone permission denied")
        ],
        "Denied microphone permission should resume hotkeys, reset, and report"
    )
}

func stopPreparedAudioStartsTranscription() throws {
    let reducer = DictationLifecycleReducer()
    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )
    let recording = DictationPhase.recording(RecordingLifecycleSession(session: session, isReady: true))

    let stopping = reducer.reduce(phase: recording, event: .stopRequested)
    try expect(stopping.phase == .stopping(StoppingLifecycleSession(session: session)), "Stop should enter stopping")
    try expect(stopping.effects == [.stopRecording(session), .resetShortcutSession], "Stop should stop recording")

    let transcribing = reducer.reduce(phase: stopping.phase, event: .audioFilePrepared(available: true))
    try expect(
        transcribing.phase == .transcribing(TranscriptionLifecycleSession(
            session: session,
            audioFileAvailable: true
        )),
        "Prepared audio should enter transcribing"
    )
    try expect(transcribing.effects == [.startTranscription(session)], "Prepared audio should start transcription")
    try expect(transcribing.phase.isTranscribing, "Transcribing compatibility accessor should be true")
}

func missingAudioFileFails() throws {
    let reducer = DictationLifecycleReducer()
    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )
    let stopping = DictationPhase.stopping(StoppingLifecycleSession(session: session))

    let transition = reducer.reduce(phase: stopping, event: .audioFilePrepared(available: false))

    try expect(transition.phase == .failed(FailedLifecycleSession(message: "No audio recorded")), "Missing audio should fail")
    try expect(transition.effects == [.reportFailure("No audio recorded")], "Missing audio should report failure")
}

func journalIntentSurvivesStartStopTranscribe() throws {
    let reducer = DictationLifecycleReducer()
    let start = reducer.reduce(
        phase: .idle,
        event: .startRequested(
            triggerMode: .toggle,
            intent: .journal,
            journalModeRequested: true,
            delay: 0
        )
    )
    let stopping = reducer.reduce(phase: start.phase, event: .stopRequested)
    let transcribing = reducer.reduce(phase: stopping.phase, event: .audioFilePrepared(available: true))

    try expect(transcribing.phase.activeSession?.intent == .journal, "Journal intent should survive")
    try expect(transcribing.phase.activeSession?.journalModeRequested == true, "Journal request should survive")
    try expect(transcribing.phase.activeSession?.intent.isJournalMode == true, "Journal mode helper should remain true")
}

func cancellationChoosesPhaseSpecificEffect() throws {
    let reducer = DictationLifecycleReducer()
    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )

    let recording = DictationPhase.recording(RecordingLifecycleSession(session: session, isReady: true))
    let recordingCancel = reducer.reduce(phase: recording, event: .cancelRequested)
    try expect(
        recordingCancel.phase == .cancelled(CancelledLifecycleSession(previousPhaseDescription: "recording")),
        "Recording cancellation should enter cancelled"
    )
    try expect(recordingCancel.effects == [.cancelRecording, .resetShortcutSession], "Recording cancellation effect")

    let transcribing = DictationPhase.transcribing(TranscriptionLifecycleSession(
        session: session,
        audioFileAvailable: true
    ))
    let transcriptionCancel = reducer.reduce(phase: transcribing, event: .cancelRequested)
    try expect(
        transcriptionCancel.phase == .cancelled(CancelledLifecycleSession(previousPhaseDescription: "transcribing")),
        "Transcription cancellation should enter cancelled"
    )
    try expect(
        transcriptionCancel.effects == [.cancelTranscription, .resetShortcutSession],
        "Transcription cancellation effect"
    )
}

func startRequestWhileTranscribingIsIgnored() throws {
    let reducer = DictationLifecycleReducer()
    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )
    let phase = DictationPhase.transcribing(TranscriptionLifecycleSession(
        session: session,
        audioFileAvailable: true
    ))

    let transition = reducer.reduce(
        phase: phase,
        event: .startRequested(
            triggerMode: .hold,
            intent: .dictation,
            journalModeRequested: false,
            delay: 0
        )
    )

    try expect(transition.phase == phase, "Start while transcribing should be ignored")
    try expect(transition.effects.isEmpty, "Ignored start should have no effects")
}

func stoppingCountsAsTranscribingForCompatibility() throws {
    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )
    let phase = DictationPhase.stopping(StoppingLifecycleSession(session: session))

    try expect(phase.isTranscribing, "Stopping should block new transcription starts")
    try expect(!phase.isRecording, "Stopping should not count as recording")
}

func hardTranscriptionFailureReportsFailure() throws {
    let reducer = DictationLifecycleReducer()
    let session = DictationLifecycleSession(
        triggerMode: .toggle,
        intent: .dictation,
        journalModeRequested: false
    )
    let phase = DictationPhase.transcribing(TranscriptionLifecycleSession(
        session: session,
        audioFileAvailable: true
    ))

    let transition = reducer.reduce(phase: phase, event: .transcriptionFailed(message: "No route to host"))

    try expect(
        transition.phase == .failed(FailedLifecycleSession(message: "No route to host")),
        "Transcription failure should enter failed phase"
    )
    try expect(
        transition.effects == [.reportFailure("No route to host")],
        "Transcription failure should report the failure"
    )
}

func readyResetReturnsTerminalPhasesToIdle() throws {
    let reducer = DictationLifecycleReducer()

    let failed = reducer.reduce(
        phase: .failed(FailedLifecycleSession(message: "failed")),
        event: .readyReset
    )
    let cancelled = reducer.reduce(
        phase: .cancelled(CancelledLifecycleSession(previousPhaseDescription: "recording")),
        event: .readyReset
    )

    try expect(failed.phase == .idle, "Ready reset should clear failed phase")
    try expect(cancelled.phase == .idle, "Ready reset should clear cancelled phase")
}

func stopOutsideRecordingIsIgnored() throws {
    let reducer = DictationLifecycleReducer()
    let transition = reducer.reduce(phase: .idle, event: .stopRequested)

    try expect(transition.phase == .idle, "Stop outside recording should remain idle")
    try expect(transition.effects.isEmpty, "Stop outside recording should have no effects")
}
