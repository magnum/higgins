import AppKit
import XCTest
@testable import Higgins

final class PasteboardSnapshotTests: XCTestCase {
    func testPasteboardSnapshotRestoresString() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("HiggnsTests.PasteboardSnapshot.Restore\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("Original", forType: .string)

        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("New", forType: .string)

        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "Original")
    }

    func testPasteboardSnapshotRestoresEmptyState() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("HigginsTests.PasteboardSnapshot.Empty\(UUID().uuidString)"))
        pasteboard.clearContents()

        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)

        pasteboard.setString("Temp", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
