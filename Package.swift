// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FreeFlowCoreTestRunner", targets: ["FreeFlowCoreTestRunner"])
    ],
    targets: [
        .executableTarget(
            name: "FreeFlowCoreTestRunner",
            path: ".",
            exclude: [
                ".agents",
                ".github",
                ".gitignore",
                "CHANGELOG.md",
                "FreeFlow.entitlements",
                "Info.plist",
                "LICENSE",
                "Makefile",
                "README.md",
                "Resources",
                "build",
                "website",
                "Sources/App",
                "Sources/Debug",
                "Sources/History",
                "Sources/Output",
                "Sources/Recording",
                "Sources/Services",
                "Sources/Settings",
                "Sources/Transcription",
                "Sources/Shortcuts/GlobalShortcutBackend.swift",
                "Sources/Shortcuts/HotkeyManager.swift",
                "Sources/Shortcuts/LocalShortcutCaptureBackend.swift",
                "Sources/Shortcuts/ModifierKeyEventState.swift",
                "Sources/Shortcuts/ShortcutBinding.swift",
                "Sources/Shortcuts/ShortcutComponents.swift",
                "Sources/Shortcuts/ShortcutCore/ShortcutMatcher.swift",
                "Sources/State/AppSettingsStore.swift",
                "Sources/State/AppState.swift",
                "Sources/State/SessionIntent.swift"
            ],
            sources: [
                "Sources/Shortcuts/ShortcutCore/ShortcutModels.swift",
                "Sources/Shortcuts/ShortcutCore/DictationShortcutSessionController.swift",
                "Sources/State/DictationLifecycle.swift",
                "Tests/FreeFlowCoreTests/TestSupport.swift",
                "Tests/FreeFlowCoreTests/DictationLifecycleTests.swift",
                "Tests/FreeFlowCoreTests/DictationShortcutSessionControllerTests.swift",
                "Tests/FreeFlowCoreTests/TestRunner.swift"
            ]
        )
    ]
)
