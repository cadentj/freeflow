import Foundation

@main
struct FreeFlowCoreTestRunner {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("immediateStartBeginsRecording", immediateStartBeginsRecording),
            ("delayedStartWaitsForPendingElapsedEvent", delayedStartWaitsForPendingElapsedEvent),
            ("pendingStartCanBeCancelled", pendingStartCanBeCancelled),
            ("microphonePermissionGrantRestartsToggleRecording", microphonePermissionGrantRestartsToggleRecording),
            ("microphonePermissionGrantReturnsHoldModeToIdle", microphonePermissionGrantReturnsHoldModeToIdle),
            ("microphonePermissionDenialFailsAndReports", microphonePermissionDenialFailsAndReports),
            ("stopPreparedAudioStartsTranscription", stopPreparedAudioStartsTranscription),
            ("missingAudioFileFails", missingAudioFileFails),
            ("journalIntentSurvivesStartStopTranscribe", journalIntentSurvivesStartStopTranscribe),
            ("cancellationChoosesPhaseSpecificEffect", cancellationChoosesPhaseSpecificEffect),
            ("startRequestWhileTranscribingIsIgnored", startRequestWhileTranscribingIsIgnored),
            ("stoppingCountsAsTranscribingForCompatibility", stoppingCountsAsTranscribingForCompatibility),
            ("hardTranscriptionFailureReportsFailure", hardTranscriptionFailureReportsFailure),
            ("readyResetReturnsTerminalPhasesToIdle", readyResetReturnsTerminalPhasesToIdle),
            ("stopOutsideRecordingIsIgnored", stopOutsideRecordingIsIgnored),
            ("holdActivationStopsOnRelease", holdActivationStopsOnRelease),
            ("toggleRequiresReleaseBeforeSecondActivationStops", toggleRequiresReleaseBeforeSecondActivationStops),
            ("holdCanSwitchToToggleMode", holdCanSwitchToToggleMode),
            ("transcribingBlocksNewSessions", transcribingBlocksNewSessions)
        ]

        var failures: [String] = []
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                let failure = "FAIL \(name): \(error)"
                print(failure)
                failures.append(failure)
            }
        }

        guard failures.isEmpty else {
            print("\n\(failures.count) test(s) failed")
            exit(1)
        }

        print("\nAll \(tests.count) tests passed")
    }
}
