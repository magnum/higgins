import AppKit

struct PasteboardSnapshot {
    let itemData: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        self.itemData = pasteboard.pasteboardItems?.map { item in
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            return dataByType
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !itemData.isEmpty else { return }
        let items = itemData.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}

@MainActor
final class ClipboardManager {
    enum ClipboardError: LocalizedError {
        case noTextSelected
        case textReplacementFailed
        
        var errorDescription: String? {
            switch self {
            case .noTextSelected:
                return "No text selected"
            case .textReplacementFailed:
                return "Failed to replace selected text"
            }
        }
    }
    
    private let pasteboard = NSPasteboard.general
    private var previousSnapshot: PasteboardSnapshot?
    
    func getSelectedText() async throws -> String {
        log("Attempting to get selected text")
        
        previousSnapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let initialChangeCount = pasteboard.changeCount

        log("Simulating CMD+C to capture selection")
        postCommandKey(keyCode: 0x08)
        
        let updated = await waitForPasteboardChange(from: initialChangeCount, timeout: 0.5)
        if !updated {
            log("Pasteboard did not update after copy", type: .warning)
        }
        
        guard let selectedText = pasteboard.string(forType: .string) else {
            log("No text found in clipboard", type: .warning)
            restorePreviousClipboard()
            throw ClipboardError.noTextSelected
        }
        
        log("Successfully captured text: \(selectedText.prefix(50))...")
        return selectedText
    }
    
    func replaceSelectedText(with newText: String) async throws {
        log("Attempting to replace text with new content (length: \(newText.count))")
        
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)
        defer { restorePreviousClipboard() }

        log("Simulating CMD+V to paste improved text")
        postCommandKey(keyCode: 0x09)
        try await Task.sleep(for: .milliseconds(100))
        log("Text replacement complete")
    }

    func restoreClipboard() {
        restorePreviousClipboard()
    }

    private func postCommandKey(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .privateState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func restorePreviousClipboard() {
        if let snapshot = previousSnapshot {
            snapshot.restore(to: pasteboard)
            previousSnapshot = nil
            log("Restored previous clipboard content")
        }
    }

    private func waitForPasteboardChange(from initialChangeCount: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != initialChangeCount {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
