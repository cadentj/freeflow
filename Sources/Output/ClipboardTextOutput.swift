import AppKit
import Carbon

private struct PreservedPasteboardEntry {
    let type: NSPasteboard.PasteboardType
    let value: Value

    enum Value {
        case string(String)
        case propertyList(Any)
        case data(Data)
    }
}

private struct PreservedPasteboardItem {
    let entries: [PreservedPasteboardEntry]

    init(item: NSPasteboardItem) {
        self.entries = item.types.compactMap { type in
            if let string = item.string(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .string(string))
            }
            if let propertyList = item.propertyList(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .propertyList(propertyList))
            }
            if let data = item.data(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .data(data))
            }
            return nil
        }
    }

    func makePasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for entry in entries {
            switch entry.value {
            case .string(let string):
                item.setString(string, forType: entry.type)
            case .propertyList(let propertyList):
                item.setPropertyList(propertyList, forType: entry.type)
            case .data(let data):
                item.setData(data, forType: entry.type)
            }
        }
        return item
    }
}

private struct PreservedPasteboardSnapshot {
    let items: [PreservedPasteboardItem]

    init(pasteboard: NSPasteboard) {
        self.items = (pasteboard.pasteboardItems ?? []).map(PreservedPasteboardItem.init)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        _ = pasteboard.writeObjects(items.map { $0.makePasteboardItem() })
    }
}

struct PendingClipboardRestore {
    fileprivate let snapshot: PreservedPasteboardSnapshot
    fileprivate let expectedChangeCount: Int
}

enum ClipboardTextOutput {
    static func pasteAtCursor() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode = keyCodeForCharacter("v") ?? 9

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }

    static func pressEnter() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        keyUp?.post(tap: .cgSessionEventTap)
    }

    static func writeTranscriptToPasteboard(
        _ transcript: String,
        preserveClipboard: Bool
    ) -> PendingClipboardRestore? {
        let pasteboard = NSPasteboard.general
        let snapshot = preserveClipboard ? PreservedPasteboardSnapshot(pasteboard: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)

        guard let snapshot else { return nil }
        return PendingClipboardRestore(snapshot: snapshot, expectedChangeCount: pasteboard.changeCount)
    }

    static func restoreClipboardIfNeeded(_ pendingRestore: PendingClipboardRestore?) {
        guard let pendingRestore else { return }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == pendingRestore.expectedChangeCount else { return }
        pendingRestore.snapshot.restore(to: pasteboard)
    }

    private static func keyCodeForCharacter(_ character: String) -> CGKeyCode? {
        guard let char = character.lowercased().utf16.first else { return nil }
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        return layoutData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> CGKeyCode? in
            guard let layout = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            for keyCode in UInt16(0)..<UInt16(128) {
                var chars = [UniChar](repeating: 0, count: 4)
                var charCount = 0
                var deadKeyState: UInt32 = 0
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, 4, &charCount, &chars
                )
                if status == noErr, charCount > 0, chars[0] == char {
                    return CGKeyCode(keyCode)
                }
            }
            return nil
        }
    }
}
