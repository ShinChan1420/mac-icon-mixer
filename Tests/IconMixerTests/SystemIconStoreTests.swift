import AppKit
import XCTest
@testable import IconMixer

/// Runs against a real temporary folder, because this is the one type that touches the disk.
final class SystemIconStoreTests: XCTestCase {
    private let store = SystemIconStore()
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func solid(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 256, height: 256).fill()
        image.unlockFocus()
        return image
    }

    private func centreRed(_ image: NSImage?) throws -> CGFloat {
        var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
        let bitmap = try XCTUnwrap(image?.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: bitmap)
        let colour = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        return colour.redComponent
    }

    func testSetAndRemoveAnIcon() throws {
        XCTAssertFalse(store.hasCustomIcon(at: folder))
        XCTAssertTrue(store.setIcon(solid(.red), at: folder))
        XCTAssertTrue(store.hasCustomIcon(at: folder))
        XCTAssertGreaterThan(try centreRed(store.icon(at: folder)), 0.8)
        XCTAssertTrue(store.setIcon(nil, at: folder))
        XCTAssertFalse(store.hasCustomIcon(at: folder))
    }

    func testSnapshotSurvivesTheIconChanging() throws {
        XCTAssertTrue(store.setIcon(solid(.red), at: folder))
        let snapshot = store.snapshot(at: folder)
        XCTAssertTrue(store.setIcon(nil, at: folder))
        XCTAssertGreaterThan(try centreRed(snapshot), 0.8)
    }

    func testRefreshKeepsTheIcon() {
        XCTAssertTrue(store.setIcon(solid(.red), at: folder))
        store.refreshFinder(at: folder)
        XCTAssertTrue(store.hasCustomIcon(at: folder), "Finder's update command deleted icons; this path must not")
    }

    func testSystemAppsCannotBeChanged() {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        XCTAssertFalse(store.setIcon(solid(.red), at: calculator))
        XCTAssertFalse(store.hasCustomIcon(at: calculator))
    }
}
