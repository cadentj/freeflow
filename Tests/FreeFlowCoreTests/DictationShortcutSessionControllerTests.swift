func holdActivationStopsOnRelease() throws {
    let controller = DictationShortcutSessionController()

    try expect(controller.handle(event: .holdActivated, isTranscribing: false) == .start(.hold), "Hold should start")
    try expect(controller.activeMode == .hold, "Hold should become active mode")
    try expect(controller.handle(event: .holdDeactivated, isTranscribing: false) == .stop, "Hold release should stop")
    try expect(controller.activeMode == nil, "Stop should clear active mode")
}

func toggleRequiresReleaseBeforeSecondActivationStops() throws {
    let controller = DictationShortcutSessionController()

    try expect(controller.handle(event: .toggleActivated, isTranscribing: false) == .start(.toggle), "Toggle should start")
    try expect(controller.handle(event: .toggleActivated, isTranscribing: false) == nil, "Held toggle should not stop")
    try expect(controller.handle(event: .toggleDeactivated, isTranscribing: false) == nil, "Toggle release arms stop")
    try expect(controller.toggleStopArmed, "Toggle should arm stop after release")
    try expect(controller.handle(event: .toggleActivated, isTranscribing: false) == .stop, "Second toggle press should stop")
    try expect(controller.activeMode == nil, "Toggle stop should clear active mode")
}

func holdCanSwitchToToggleMode() throws {
    let controller = DictationShortcutSessionController()

    try expect(controller.handle(event: .holdActivated, isTranscribing: false) == .start(.hold), "Hold should start")
    try expect(
        controller.handle(event: .toggleActivated, isTranscribing: false) == .switchedToToggle,
        "Toggle activation during hold should switch modes"
    )
    try expect(controller.activeMode == .toggle, "Toggle should become active mode")
    try expect(!controller.toggleStopArmed, "Switching to toggle should not arm stop")
}

func transcribingBlocksNewSessions() throws {
    let controller = DictationShortcutSessionController()

    try expect(controller.handle(event: .holdActivated, isTranscribing: true) == nil, "Transcribing blocks hold")
    try expect(controller.handle(event: .toggleActivated, isTranscribing: true) == nil, "Transcribing blocks toggle")
    try expect(controller.activeMode == nil, "Transcribing should not create active mode")
}
