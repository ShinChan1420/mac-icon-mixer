import AppKit
import UniformTypeIdentifiers
import XCTest
import IconMixCore
@testable import IconMixer

/// Stands in for the disk, and records every write in order.
private final class FakeIconStore: IconStoring {
    enum Write: Equatable { case set, clear }

    var customIcons: Set<URL> = []
    var writes: [Write] = []
    var failSetAttempt: Int?
    var failClear = false
    var lastIcon: NSImage?
    var refreshes = 0
    var snapshots = 0
    private var attempts = 0

    private static func solid(_ gray: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return ctx.makeImage()!
    }

    var genericFolderIcon: CGImage? { Self.solid(0.5) }
    func icon(at url: URL) -> NSImage { NSImage(cgImage: Self.solid(0.5), size: NSSize(width: 32, height: 32)) }
    func hasCustomIcon(at url: URL) -> Bool { customIcons.contains(url) }
    func originalAppIcon(at url: URL, hasCustomIcon: Bool) -> CGImage? { Self.solid(0.3) }

    func snapshot(at url: URL) -> NSImage? {
        snapshots += 1
        return icon(at: url)
    }

    func setIcon(_ icon: NSImage?, at url: URL) -> Bool {
        guard let icon else {
            if failClear { return false }
            writes.append(.clear)
            customIcons.remove(url)
            return true
        }
        lastIcon = icon
        attempts += 1
        if attempts == failSetAttempt { return false }
        writes.append(.set)
        customIcons.insert(url)
        return true
    }

    func refreshFinder(at url: URL) { refreshes += 1 }
}

@MainActor
final class MixerModelTests: XCTestCase {
    private var store: FakeIconStore!
    private var model: MixerModel!
    private var folder: URL!
    private var autoFolder: URL!

    override func setUp() async throws {
        store = FakeIconStore()
        autoFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        model = makeModel()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folder = folder.resolvingSymlinksInPath()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: autoFolder)
    }

    private func makeModel() -> MixerModel {
        MixerModel(store: store, finderSettleTime: .milliseconds(1), autoIconFolder: autoFolder)
    }

    /// Red channel at the middle of the last icon written: bright for light glass, dark for dark glass.
    private func brightnessOfLastIcon() throws -> CGFloat {
        var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
        let image = try XCTUnwrap(store.lastIcon?.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB)).redComponent
    }

    private func waitForWrites(_ count: Int) async {
        for _ in 0..<500 where store.writes.count < count {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private func applyAuto() async {
        model.accept(folder)
        model.accept(imageData: picture)
        model.settings.finish = .frosted
        model.settings.glassTone = .auto
        model.apply()
        await settled()
    }

    func testAutoShowsBothTonesAndOthersDoNot() {
        model.accept(folder)
        model.accept(imageData: picture)
        XCTAssertNil(model.tonePreviews, "no finish, no tone")
        model.settings.finish = .frosted
        model.settings.glassTone = .auto
        XCTAssertNotNil(model.tonePreviews)
        let tones = model.tonePreviews
        XCTAssertNotEqual(tones?.light.tiffRepresentation, tones?.dark.tiffRepresentation)
        model.settings.glassTone = .light
        XCTAssertNil(model.tonePreviews)
        model.settings.glassTone = .auto
        model.settings.style = .picture
        XCTAssertNil(model.tonePreviews, "Picture Only has no glass")
    }

    func testAutoIconSwapsWhenTheModeChanges() async throws {
        await applyAuto()
        XCTAssertTrue(model.keepsIconsInSync)
        XCTAssertTrue(model.message?.contains("follows Light and Dark") == true)
        let light = try brightnessOfLastIcon()

        store.writes = []
        model.systemIsDark = true
        await waitForWrites(2)
        XCTAssertEqual(store.writes, [.clear, .set])
        XCTAssertLessThan(try brightnessOfLastIcon(), light - 0.2)

        store.writes = []
        model.systemIsDark = false
        await waitForWrites(2)
        XCTAssertEqual(store.writes, [.clear, .set])
        XCTAssertEqual(try brightnessOfLastIcon(), light, accuracy: 0.02)
    }

    func testFixedToneIsNotKept() async {
        await applyAuto()
        model.settings.glassTone = .light
        model.apply()
        await settled()
        XCTAssertFalse(model.keepsIconsInSync)
        store.writes = []
        model.systemIsDark = true
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(store.writes.isEmpty)
    }

    func testRemovingOrUndoingStopsFollowing() async {
        await applyAuto()
        model.removeCustomIcon()
        XCTAssertFalse(model.keepsIconsInSync)

        model.apply()
        await settled()
        XCTAssertTrue(model.keepsIconsInSync)
        model.undoApply()
        await settled()
        XCTAssertFalse(model.keepsIconsInSync)
    }

    func testIconRemovedElsewhereStopsBeingKept() async {
        await applyAuto()
        store.customIcons = []
        store.writes = []
        model.systemIsDark = true
        for _ in 0..<200 where model.keepsIconsInSync { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertFalse(model.keepsIconsInSync)
        XCTAssertTrue(store.writes.isEmpty, "never puts back an icon you removed")
    }

    func testKeeperMatchesAFolderHoweverItsPathIsSpelled() throws {
        let real = URL(fileURLWithPath: "/private/tmp/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let keeper = AutoIconKeeper(store: store, folder: autoFolder, settleTime: .milliseconds(1))
        let image = Mixer.noPhoto
        try keeper.keep(real, light: image, dark: image, showsDark: false)
        XCTAssertTrue(keeper.hasIcons)
        keeper.remove(real.resolvingSymlinksInPath())
        XCTAssertFalse(keeper.hasIcons)
    }

    func testKeepingTheSameFolderTwiceReplacesTheEntry() async {
        await applyAuto()
        model.apply()
        await settled()
        model.removeCustomIcon()
        XCTAssertFalse(model.keepsIconsInSync, "one entry per folder")
    }

    func testKeptIconsSurviveARestart() async {
        await applyAuto()
        let reopened = makeModel()
        XCTAssertTrue(reopened.keepsIconsInSync)
        store.writes = []
        reopened.systemIsDark = true
        await waitForWrites(2)
        XCTAssertEqual(store.writes, [.clear, .set])
    }

    private var picture: Data {
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }

    private func makeApp() throws -> URL {
        let app = folder.appendingPathComponent("Sample.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        return app
    }

    private func settled() async {
        await Task.yield()
        while model.isApplying { await Task.yield() }
    }

    func testNotReadyUntilThereIsAFolderAndAPicture() {
        XCTAssertFalse(model.isReady)
        model.accept(folder)
        XCTAssertFalse(model.isReady)
        XCTAssertNil(model.preview)
        model.accept(imageData: picture)
        XCTAssertTrue(model.isReady)
        XCTAssertNotNil(model.preview)
    }

    func testApplyDoesNothingWhenNotReady() async {
        model.accept(folder)
        model.settings.finish = .frosted
        model.apply()
        await settled()
        XCTAssertTrue(store.writes.isEmpty)
    }

    func testFirstApplyWritesOnceAndCanBeUndone() async {
        model.accept(folder)
        model.accept(imageData: picture)
        model.apply()
        await settled()
        XCTAssertEqual(store.writes, [.set])
        XCTAssertEqual(model.message, "Applied to “\(folder.lastPathComponent)”.")
        XCTAssertTrue(model.targetHasCustomIcon)
        XCTAssertTrue(model.canUndo)
        XCTAssertGreaterThan(store.refreshes, 0)

        store.writes = []
        model.undoApply()
        await settled()
        XCTAssertTrue(store.writes.contains(.clear))
        XCTAssertFalse(model.targetHasCustomIcon)
        XCTAssertFalse(model.canUndo)
    }

    func testReapplyClearsTheOldIconFirst() async {
        store.customIcons = [folder]
        model.accept(folder)
        model.accept(imageData: picture)
        model.apply()
        await settled()
        XCTAssertEqual(store.writes, [.clear, .set])
        XCTAssertEqual(store.snapshots, 1, "undo keeps a copy of the old icon")
    }

    func testFailedWriteRestoresTheOldIcon() async {
        store.customIcons = [folder]
        store.failSetAttempt = 1
        model.accept(folder)
        model.accept(imageData: picture)
        model.apply()
        await settled()
        XCTAssertEqual(store.writes, [.clear, .set], "cleared, then the old icon went back")
        XCTAssertTrue(model.messageIsError)
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(store.customIcons.contains(folder))
    }

    func testFailedClearLeavesTheOldIconAlone() async {
        store.customIcons = [folder]
        store.failClear = true
        model.accept(folder)
        model.accept(imageData: picture)
        model.apply()
        await settled()
        XCTAssertTrue(store.writes.isEmpty)
        XCTAssertTrue(model.messageIsError)
    }

    func testAppTakesAFinishWithNoImage() async throws {
        let app = try makeApp()
        model.accept(app)
        XCTAssertTrue(model.targetIsApp)
        XCTAssertNotNil(model.preview, "shows the app's own icon")
        XCTAssertFalse(model.isReady, "nothing to apply yet")
        model.settings.finish = .frosted
        XCTAssertTrue(model.isReady)
        model.apply()
        await settled()
        XCTAssertEqual(store.writes, [.set])
        XCTAssertTrue(model.message?.contains("Dock") == true)
    }

    func testAppFailureExplainsAppManagement() async throws {
        store.failSetAttempt = 1
        model.accept(try makeApp())
        model.settings.finish = .liquidGlass
        model.apply()
        await settled()
        XCTAssertTrue(model.message?.contains("App Management") == true)
    }

    func testRemoveImageReturnsAnAppToFinishOnly() throws {
        model.accept(try makeApp())
        model.accept(imageData: picture)
        model.settings.style = .picture
        model.removeImage()
        XCTAssertFalse(model.hasImage)
        XCTAssertEqual(model.settings.style, .fill)
        XCTAssertNotNil(model.preview)
    }

    func testLayersFollowTheObject() throws {
        model.accept(folder)
        model.accept(imageData: picture)
        XCTAssertTrue(model.hasLayers)
        XCTAssertTrue(model.isAvailable(.plainColor))
        model.accept(try makeApp())
        XCTAssertFalse(model.hasLayers)
        XCTAssertFalse(model.isAvailable(.plainColor))
        XCTAssertTrue(model.isAvailable(.wholeCut))
    }

    func testAppClearsTheSecondLayerChoice() throws {
        model.settings.back = .samePosition
        model.settings.panelShadow = true
        model.accept(try makeApp())
        XCTAssertEqual(model.settings.back, .folder)
        XCTAssertFalse(model.settings.panelShadow)
    }

    func testSecondImageGetsItsOwnCentredPlacement() {
        model.accept(folder)
        model.accept(imageData: picture)
        model.settings.backOffsetX = 0.5
        model.acceptSecond(imageData: picture)
        XCTAssertEqual(model.secondImageName, "Dropped image")
        XCTAssertEqual(model.settings.back, .differentPosition)
        XCTAssertEqual(model.settings.backOffsetX, 0)
        model.removeSecondImage()
        XCTAssertNil(model.secondImageName)
    }

    func testNewImageResetsAdjustmentsButKeepsTheLook() {
        model.accept(folder)
        model.settings.finish = .frosted
        model.settings.style = .sticker
        model.settings.zoom = 2
        model.accept(imageData: picture)
        XCTAssertEqual(model.settings.zoom, 1)
        XCTAssertEqual(model.settings.finish, .frosted)
        XCTAssertEqual(model.settings.style, .sticker)
    }

    func testDiscardClearsEverythingAndWritesNothing() async {
        model.accept(folder)
        model.accept(imageData: picture)
        model.acceptSecond(imageData: picture)
        model.discard()
        XCTAssertNil(model.targetURL)
        XCTAssertFalse(model.hasImage)
        XCTAssertNil(model.secondImageName)
        XCTAssertNil(model.preview)
        XCTAssertTrue(model.layerThumbnails.isEmpty)
        XCTAssertTrue(store.writes.isEmpty)
    }

    func testBadInputIsRejectedWithAMessage() throws {
        let text = folder.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: text)
        model.accept(text)
        XCTAssertTrue(model.messageIsError)
        model.acceptSecond(text)
        XCTAssertNil(model.secondImageName)
        model.accept(imageData: Data("not an image".utf8))
        XCTAssertFalse(model.hasImage)
    }

    func testEditFadeOnlyChangesThePreview() async {
        model.accept(folder)
        model.accept(imageData: picture)
        model.settings.back = .color
        let plain = model.preview?.tiffRepresentation
        model.isEditingBack = true
        XCTAssertNotEqual(model.preview?.tiffRepresentation, plain)
        model.isEditingBack = false
        XCTAssertEqual(model.preview?.tiffRepresentation, plain)
    }
}
