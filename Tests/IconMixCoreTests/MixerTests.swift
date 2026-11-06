import CoreGraphics
import XCTest
@testable import IconMixCore

final class MixerTests: XCTestCase {
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, width: Int = 64, height: Int = 64) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// RGBA at unit coordinates, origin bottom-left.
    private func pixel(_ image: CGImage, _ x: Double, _ y: Double) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &out, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let size = CGFloat(image.width)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: -x * size, y: -y * size, width: size, height: size))
        return out
    }

    private func render(_ settings: MixSettings, photo: CGImage? = nil) -> CGImage {
        Mixer.render(icon: solid(0, 0, 1), photo: photo ?? solid(1, 0, 0), settings: settings, size: 256)!
    }

    func testFillCoversThePanelAndLeavesTheTabAlone() {
        let out = render(MixSettings())
        XCTAssertEqual(pixel(out, 0.5, 0.4), [255, 0, 0, 255])
        XCTAssertEqual(pixel(out, 0.5, 0.8), [0, 0, 255, 255], "above the front panel stays folder")
    }

    func testWideImageStillCoversPanel() {
        let out = render(MixSettings(), photo: solid(1, 0, 0, width: 400, height: 40))
        XCTAssertEqual(pixel(out, 0.1, 0.2), [255, 0, 0, 255])
        XCTAssertEqual(pixel(out, 0.9, 0.7), [255, 0, 0, 255])
    }

    func testOffsetMovesTheImageRight() {
        var settings = MixSettings()
        settings.style = .sticker
        settings.offsetX = 0.3
        let out = render(settings)
        XCTAssertEqual(pixel(out, 0.75, 0.43), [255, 0, 0, 255])
        XCTAssertEqual(pixel(out, 0.2, 0.43), [0, 0, 255, 255])
    }

    func testOffsetUpIsUp() {
        var settings = MixSettings()
        settings.style = .sticker
        settings.zoom = 0.4
        settings.offsetY = 0.3
        let out = render(settings)
        XCTAssertEqual(pixel(out, 0.5, 0.62), [255, 0, 0, 255])
        XCTAssertEqual(pixel(out, 0.5, 0.25), [0, 0, 255, 255])
    }

    func testZeroOpacityShowsOnlyTheFolder() {
        var settings = MixSettings()
        settings.opacity = 0
        XCTAssertEqual(pixel(render(settings), 0.5, 0.4), [0, 0, 255, 255])
    }

    func testBrightnessChangesThePhoto() {
        var settings = MixSettings()
        settings.brightness = -0.3
        let photo = solid(0.8, 0.8, 0.8)
        let plain = pixel(render(MixSettings(), photo: photo), 0.5, 0.4)
        let darker = pixel(render(settings, photo: photo), 0.5, 0.4)
        XCTAssertLessThan(darker[0], plain[0])
    }

    func testStampInksDarkAreasOnly() {
        var settings = MixSettings()
        settings.style = .stamp
        XCTAssertNotEqual(pixel(render(settings, photo: solid(0, 0, 0)), 0.5, 0.4), [0, 0, 255, 255])
        XCTAssertEqual(pixel(render(settings, photo: solid(1, 1, 1)), 0.5, 0.4), [0, 0, 255, 255])
    }

    func testTintedKeepsFolderHue() {
        var settings = MixSettings()
        settings.style = .tinted
        let out = pixel(render(settings, photo: solid(0.6, 0.6, 0.6)), 0.5, 0.4)
        XCTAssertGreaterThan(out[2], out[0], "blue stays dominant")
    }

    /// Blue folder body with transparent surroundings, like the real icon.
    private var folderShape: CGImage {
        let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 10, y: 34, width: 236, height: 188))
        return ctx.makeImage()!
    }

    /// Red on the left half, green on the right.
    private var split: CGImage {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 32, y: 0, width: 32, height: 64))
        return ctx.makeImage()!
    }

    private func renderShape(_ settings: MixSettings, photo: CGImage? = nil) -> CGImage {
        Mixer.render(icon: folderShape, photo: photo ?? solid(1, 0, 0), settings: settings, size: 256)!
    }

    private let backPoint = (x: 0.5, y: 0.8)

    func testCutoutFollowsTheFolderOutline() {
        var settings = MixSettings()
        settings.style = .cutout
        let out = renderShape(settings)
        XCTAssertEqual(pixel(out, 0.5, 0.8), [255, 0, 0, 255], "covers the back too")
        XCTAssertEqual(pixel(out, 0.5, 0.4), [255, 0, 0, 255])
        XCTAssertEqual(pixel(out, 0.5, 0.95)[3], 0, "nothing outside the folder")
    }

    func testPictureHasNoFolderAndKeepsItsShape() {
        var settings = MixSettings()
        settings.style = .picture
        let wide = renderShape(settings, photo: solid(1, 0, 0, width: 200, height: 100))
        XCTAssertEqual(pixel(wide, 0.02, 0.5), [255, 0, 0, 255], "fills edge to edge")
        XCTAssertEqual(pixel(wide, 0.5, 0.9)[3], 0, "no folder above a wide image")
    }

    func testPlainColourBack() {
        var settings = MixSettings()
        settings.back = .color
        settings.backColor = MixColor(red: 0, green: 1, blue: 0)
        let out = renderShape(settings)
        XCTAssertEqual(pixel(out, backPoint.x, backPoint.y), [0, 255, 0, 255])
        XCTAssertEqual(pixel(out, 0.5, 0.4), [255, 0, 0, 255], "front still has the picture")
        XCTAssertEqual(pixel(out, 0.5, 0.95)[3], 0, "colour stays inside the folder")
    }

    func testSamePositionContinuesThePictureDimmed() {
        var settings = MixSettings()
        settings.back = .samePosition
        let out = pixel(renderShape(settings), backPoint.x, backPoint.y)
        XCTAssertGreaterThan(out[0], 150)
        XCTAssertLessThan(out[0], 255, "back is slightly darker than the front")
        XCTAssertLessThan(out[2], 20, "no blue folder left")
    }

    func testDifferentPositionMovesOnlyTheBack() {
        var settings = MixSettings()
        settings.back = .samePosition
        let same = renderShape(settings, photo: split)
        settings.back = .differentPosition
        settings.backOffsetX = 0.6
        settings.backOffsetY = 0
        let moved = renderShape(settings, photo: split)
        XCTAssertEqual(pixel(same, 0.55, 0.8)[1] > 100, true, "right half of the picture")
        XCTAssertEqual(pixel(moved, 0.55, 0.8)[0] > 100, true, "left half moved over")
        XCTAssertEqual(pixel(same, 0.55, 0.4), pixel(moved, 0.55, 0.4), "front unchanged")
    }

    func testShadowDarkensTheBackJustAboveThePanel() {
        var settings = MixSettings()
        settings.back = .color
        settings.backColor = MixColor(red: 1, green: 1, blue: 1)
        let plain = pixel(renderShape(settings), 0.5, 0.75)
        settings.panelShadow = true
        let shaded = renderShape(settings)
        XCTAssertLessThan(pixel(shaded, 0.5, 0.75)[0], plain[0])
        XCTAssertEqual(pixel(shaded, 0.5, 0.4), [255, 0, 0, 255], "shadow stays off the front")
    }

    func testBackOptionsWorkBehindASticker() {
        var settings = MixSettings()
        settings.style = .sticker
        settings.back = .color
        settings.backColor = MixColor(red: 0, green: 1, blue: 0)
        let out = renderShape(settings)
        XCTAssertEqual(pixel(out, 0.5, 0.8), [0, 255, 0, 255], "back is coloured")
        XCTAssertEqual(pixel(out, 0.1, 0.2), [0, 0, 255, 255], "front panel stays folder")
    }

    func testSamePictureCoversTheBackBehindASmallSticker() {
        var settings = MixSettings()
        settings.style = .sticker
        settings.back = .samePosition
        let out = pixel(renderShape(settings), 0.1, 0.8)
        XCTAssertGreaterThan(out[0], 150)
        XCTAssertLessThan(out[2], 20)
    }

    func testEveryLayerChoiceSelectsItself() {
        for layer in FolderLayer.allCases where layer != .shadow {
            var settings = MixSettings()
            layer.choose(in: &settings)
            XCTAssertTrue(layer.isSelected(in: settings), layer.title)
        }
    }

    func testShadowCombinesWithABackAndToggles() {
        var settings = MixSettings()
        FolderLayer.plainColor.choose(in: &settings)
        FolderLayer.shadow.choose(in: &settings)
        XCTAssertTrue(FolderLayer.plainColor.isSelected(in: settings))
        XCTAssertTrue(FolderLayer.shadow.isSelected(in: settings))
        FolderLayer.shadow.choose(in: &settings)
        XCTAssertFalse(FolderLayer.shadow.isSelected(in: settings))
    }

    func testBackChoicesLeaveWholeCutAndPictureOnly() {
        for whole in [FolderLayer.wholeCut, .pictureOnly] {
            for layer in [FolderLayer.shadow, .plainColor, .samePosition] {
                var settings = MixSettings()
                whole.choose(in: &settings)
                layer.choose(in: &settings)
                XCTAssertTrue(layer.isSelected(in: settings), "\(whole.title) then \(layer.title)")
                XCTAssertFalse(whole.isSelected(in: settings))
            }
        }
    }

    func testTheStripAboveThePanelIsTheSecondLayer() {
        var settings = MixSettings()
        XCTAssertEqual(settings.layer(atUnitY: 0.2), .front, "the original folder has nothing to move")
        settings.back = .differentPosition
        XCTAssertEqual(settings.layer(atUnitY: 0.2), .back)
        XCTAssertEqual(settings.layer(atUnitY: 0.5), .front)
        settings.style = .cutout
        XCTAssertEqual(settings.layer(atUnitY: 0.2), .front, "Whole Cut is a single layer")
    }

    func testMovingTheBackLeavesTheFrontAlone() {
        var settings = MixSettings()
        settings.back = .differentPosition
        let front = (settings.offsetX, settings.offsetY)
        let startX = settings.backOffsetX
        settings.move(.back, dx: 0.1, dy: 0)
        XCTAssertEqual(settings.backOffsetX, startX + 0.1 / Mixer.folderBody.width, accuracy: 0.0001)
        XCTAssertEqual(settings.offsetX, front.0)
        XCTAssertEqual(settings.offsetY, front.1)
    }

    func testEditingASamePositionBackDetachesItWithoutAJump() {
        var settings = MixSettings()
        settings.back = .samePosition
        settings.offsetX = 0.2
        let before = pixel(renderShape(settings, photo: split), 0.5, 0.8)
        settings.move(.back, dx: 0, dy: 0)
        XCTAssertEqual(settings.back, .differentPosition)
        XCTAssertEqual(settings.backOffsetX, 0.2)
        XCTAssertEqual(pixel(renderShape(settings, photo: split), 0.5, 0.8), before)
    }

    func testZoomStaysInRangeForEachLayer() {
        var settings = MixSettings()
        settings.back = .differentPosition
        settings.setZoom(100, of: .back)
        XCTAssertEqual(settings.zoom(of: .back), 4)
        XCTAssertEqual(settings.zoom(of: .front), 1, "front unchanged")
        settings.setZoom(0, of: .front)
        XCTAssertEqual(settings.zoom(of: .front), 0.2)
    }

    func testBackZoomChangesOnlyTheBack() {
        var settings = MixSettings()
        settings.back = .differentPosition
        settings.backOffsetX = 0
        settings.backOffsetY = 0
        settings.backZoom = 1
        let plain = renderShape(settings, photo: split)
        settings.backZoom = 0.3
        let small = renderShape(settings, photo: split)
        XCTAssertNotEqual(pixel(plain, 0.1, 0.8), pixel(small, 0.1, 0.8))
        XCTAssertEqual(pixel(plain, 0.1, 0.4), pixel(small, 0.1, 0.4))
    }

    func testFadingTheFrontRevealsTheSecondLayer() {
        var settings = MixSettings()
        settings.back = .color
        settings.backColor = MixColor(red: 0, green: 1, blue: 0)
        let faded = Mixer.render(icon: folderShape, photo: solid(1, 0, 0), settings: settings, size: 256,
                                 frontOpacity: 0.4)!
        let front = pixel(faded, 0.5, 0.4)
        XCTAssertEqual(Double(front[0]), 0.4 * 255, accuracy: 3, "40% front picture")
        XCTAssertEqual(Double(front[1]), 0.6 * 255, accuracy: 3, "60% second layer")
        XCTAssertEqual(front[2], 0, "no opaque blue panel in the way")
    }

    func testFullOpacityMatchesTheDefaultRender() {
        var settings = MixSettings()
        settings.back = .samePosition
        settings.panelShadow = true
        let plain = renderShape(settings)
        let explicit = Mixer.render(icon: folderShape, photo: solid(1, 0, 0), settings: settings, size: 256,
                                    frontOpacity: 1)!
        XCTAssertEqual(plain.dataProvider?.data, explicit.dataProvider?.data)
    }

    func testFadeLeavesSingleLayerStylesAlone() {
        var settings = MixSettings()
        settings.style = .cutout
        let faded = Mixer.render(icon: folderShape, photo: solid(1, 0, 0), settings: settings, size: 256,
                                 frontOpacity: 0.4)!
        XCTAssertEqual(pixel(faded, 0.5, 0.4), [255, 0, 0, 255])
    }

    func testTintedTakesTheChosenFrontColour() {
        var settings = MixSettings()
        settings.style = .tinted
        settings.frontColor = MixColor(red: 1, green: 0, blue: 0)
        let out = pixel(renderShape(settings, photo: solid(0.5, 0.5, 0.5)), 0.5, 0.4)
        XCTAssertGreaterThan(out[0], out[2], "red replaces the folder blue")
    }

    func testStickerSitsOnTheChosenFrontColour() {
        var settings = MixSettings()
        settings.style = .sticker
        settings.frontColor = MixColor(red: 0, green: 1, blue: 0)
        let out = renderShape(settings)
        XCTAssertEqual(pixel(out, 0.1, 0.2), [0, 255, 0, 255], "panel is coloured")
        XCTAssertEqual(pixel(out, 0.5, 0.8), [0, 0, 255, 255], "back stays folder")
    }

    func testStampInkFollowsTheChosenFrontColour() {
        var settings = MixSettings()
        settings.style = .stamp
        settings.frontColor = MixColor(red: 1, green: 0, blue: 0)
        let ink = pixel(renderShape(settings, photo: solid(0, 0, 0)), 0.5, 0.4)
        XCTAssertGreaterThan(ink[0], 100)
        XCTAssertLessThan(ink[0], 255, "darker than the panel")
        XCTAssertLessThan(ink[2], 20)
    }

    func testFrontColourIsIgnoredWhereItCannotShow() {
        var settings = MixSettings()
        settings.opacity = 0
        let plain = renderShape(settings)
        settings.frontColor = MixColor(red: 0, green: 1, blue: 0)
        XCTAssertEqual(pixel(renderShape(settings), 0.5, 0.4), pixel(plain, 0.5, 0.4))
    }

    func testFrontColourWorksWithASecondLayerAndFade() {
        var settings = MixSettings()
        settings.style = .sticker
        settings.frontColor = MixColor(red: 1, green: 0, blue: 0)
        settings.back = .color
        settings.backColor = MixColor(red: 0, green: 1, blue: 0)
        let faded = Mixer.render(icon: folderShape, photo: solid(1, 1, 1), settings: settings, size: 256,
                                 frontOpacity: 0.4)!
        let out = pixel(faded, 0.1, 0.2)
        XCTAssertEqual(Double(out[0]), 0.4 * 255, accuracy: 3)
        XCTAssertEqual(Double(out[1]), 0.6 * 255, accuracy: 3)
    }

    /// A rounded-square-ish app icon: opaque blue in the middle, transparent margin.
    private var appIcon: CGImage {
        let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 32, y: 32, width: 192, height: 192))
        return ctx.makeImage()!
    }

    func testShapeFindsTheSolidPartOfAnIcon() {
        let shape = Mixer.shape(ofIcon: appIcon)
        XCTAssertTrue(shape.followsOutline)
        XCTAssertEqual(shape.front.minX, 0.125, accuracy: 0.01)
        XCTAssertEqual(shape.front.width, 0.75, accuracy: 0.01)
        XCTAssertEqual(shape.front.minY, 0.125, accuracy: 0.01)
    }

    func testAppFillFollowsTheIconOutline() {
        let icon = appIcon
        let out = Mixer.render(icon: icon, photo: solid(1, 0, 0), settings: MixSettings(), size: 256,
                               shape: Mixer.shape(ofIcon: icon))!
        XCTAssertEqual(pixel(out, 0.5, 0.5), [255, 0, 0, 255])
        XCTAssertEqual(pixel(out, 0.5, 0.82), [255, 0, 0, 255], "reaches the top of the icon")
        XCTAssertEqual(pixel(out, 0.05, 0.5)[3], 0, "nothing outside the icon")
    }

    func testAppStickerKeepsTheAppIconAroundIt() {
        let icon = appIcon
        var settings = MixSettings()
        settings.style = .sticker
        let out = Mixer.render(icon: icon, photo: solid(1, 0, 0), settings: settings, size: 256,
                               shape: Mixer.shape(ofIcon: icon))!
        XCTAssertEqual(pixel(out, 0.5, 0.5), [255, 0, 0, 255])
        XCTAssertEqual(pixel(out, 0.15, 0.2), [0, 0, 255, 255], "app icon still shows")
    }

    func testAppFrontColourCoversTheWholeIcon() {
        let icon = appIcon
        var settings = MixSettings()
        settings.style = .sticker
        settings.frontColor = MixColor(red: 0, green: 1, blue: 0)
        let out = Mixer.render(icon: icon, photo: solid(1, 0, 0), settings: settings, size: 256,
                               shape: Mixer.shape(ofIcon: icon))!
        XCTAssertEqual(pixel(out, 0.15, 0.85), [0, 255, 0, 255])
        XCTAssertEqual(pixel(out, 0.05, 0.5)[3], 0)
    }

    func testBackOptionsNeverPaintOnAnApp() {
        let icon = appIcon
        var settings = MixSettings()
        settings.back = .color
        settings.backColor = MixColor(red: 0, green: 1, blue: 0)
        settings.panelShadow = true
        let out = Mixer.render(icon: icon, photo: solid(1, 0, 0), settings: settings, size: 256,
                               shape: Mixer.shape(ofIcon: icon))!
        XCTAssertEqual(pixel(out, 0.5, 0.82), [255, 0, 0, 255])
    }

    private func finished(_ finish: Finish, _ change: (inout MixSettings) -> Void = { _ in }, photo: CGImage? = nil) -> CGImage {
        var settings = MixSettings()
        settings.finish = finish
        change(&settings)
        return renderShape(settings, photo: photo)
    }

    func testNoFinishChangesNothing() {
        XCTAssertEqual(finished(.none).dataProvider?.data, renderShape(MixSettings()).dataProvider?.data)
    }

    func testFinishesStayOffTheBackOfTheFolder() {
        for finish in [Finish.liquidGlass, .frosted] {
            XCTAssertEqual(pixel(finished(finish), 0.5, 0.8), [0, 0, 255, 255], finish.title)
            XCTAssertEqual(pixel(finished(finish), 0.5, 0.95)[3], 0, "\(finish.title) stays inside the icon")
        }
    }

    func testFrostedBlursAndLightens() {
        let sharp = renderShape(MixSettings(), photo: split)
        let frost = finished(.frosted, photo: split)
        // The red and green halves meet at the centre; frost mixes them there.
        XCTAssertEqual(pixel(sharp, 0.49, 0.4)[1], 0)
        XCTAssertGreaterThan(pixel(frost, 0.49, 0.4)[1], 40)
        XCTAssertGreaterThan(pixel(frost, 0.15, 0.4)[1], 20, "white tint lightens solid red")
    }

    func testStrongerFrostIsWhiter() {
        let photo = solid(0.2, 0.2, 0.2)
        let light = finished(.frosted, { $0.finishStrength = 0.1 }, photo: photo)
        let heavy = finished(.frosted, { $0.finishStrength = 1 }, photo: photo)
        XCTAssertGreaterThan(pixel(heavy, 0.5, 0.4)[0], pixel(light, 0.5, 0.4)[0])
    }

    func testLiquidGlassStaysClearInTheMiddleAndLightsTheRim() {
        let photo = solid(0.2, 0.2, 0.2)
        let glass = finished(.liquidGlass, photo: photo)
        XCTAssertLessThan(pixel(glass, 0.5, 0.2)[0], 90, "centre is not frosted over")
        let rimLevels = stride(from: 0.70, to: 0.74, by: 0.002).map { pixel(glass, 0.5, $0)[0] }
        XCTAssertGreaterThan(rimLevels.max()!, 150, "top edge catches the light")
    }

    func testLiquidGlassBendsNearTheEdge() {
        // Top of the photo is red and bottom green, so bending near the edge changes what's there.
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 64))
        let photo = ctx.makeImage()!
        let plain = pixel(renderShape(MixSettings(), photo: photo), 0.09, 0.4)
        let bent = pixel(finished(.liquidGlass, photo: photo), 0.09, 0.4)
        XCTAssertGreaterThan(plain[0], 200, "red strip at the left edge")
        XCTAssertLessThan(bent[0], 120, "lens pulls in the green from further inside")
    }

    func testStickerStaysSharpOnGlass() {
        let plain = renderShape({ var s = MixSettings(); s.style = .sticker; return s }(), photo: solid(1, 0, 0))
        let frost = finished(.frosted, { $0.style = .sticker }, photo: solid(1, 0, 0))
        XCTAssertEqual(pixel(plain, 0.5, 0.43), pixel(frost, 0.5, 0.43))
    }

    func testSecondLayerShowsThroughGlassWithoutADarkPanel() {
        let out = finished(.frosted, {
            $0.style = .sticker
            $0.back = .color
            $0.backColor = MixColor(red: 0, green: 1, blue: 0)
            $0.panelShadow = true
        })
        let panel = pixel(out, 0.1, 0.2)
        XCTAssertGreaterThan(panel[1], 100, "green shows through")
        XCTAssertGreaterThan(panel[2], 60, "no black under the panel")
    }

    func testPictureOnlyIgnoresFinishes() {
        var plain = MixSettings()
        plain.style = .picture
        var glass = plain
        glass.finish = .frosted
        XCTAssertEqual(renderShape(glass).dataProvider?.data, renderShape(plain).dataProvider?.data)
    }

    func testFadeTurnsTheFinishOffWhileEditing() {
        var settings = MixSettings()
        settings.back = .color
        let plain = Mixer.render(icon: folderShape, photo: split, settings: settings, size: 256, frontOpacity: 0.4)!
        settings.finish = .frosted
        let glass = Mixer.render(icon: folderShape, photo: split, settings: settings, size: 256, frontOpacity: 0.4)!
        XCTAssertEqual(plain.dataProvider?.data, glass.dataProvider?.data)
    }

    func testFinishFollowsAnAppsOutline() {
        let icon = appIcon
        var settings = MixSettings()
        settings.finish = .frosted
        let out = Mixer.render(icon: icon, photo: solid(1, 0, 0), settings: settings, size: 256,
                               shape: Mixer.shape(ofIcon: icon))!
        XCTAssertEqual(pixel(out, 0.05, 0.5)[3], 0, "nothing outside the icon")
        XCTAssertGreaterThan(pixel(out, 0.5, 0.5)[1], 20)
    }

    func testFinishRendersTheSameEveryTime() {
        XCTAssertEqual(finished(.frosted).dataProvider?.data, finished(.frosted).dataProvider?.data)
    }

    func testFirstLayerOpacityShowsTheSecondLayerThrough() {
        var settings = MixSettings()
        settings.back = .color
        settings.backColor = MixColor(red: 0, green: 1, blue: 0)
        settings.opacity = 0.5
        let out = pixel(renderShape(settings), 0.5, 0.4)
        XCTAssertEqual(Double(out[0]), 127, accuracy: 3, "half the red picture")
        XCTAssertEqual(Double(out[1]), 127, accuracy: 3, "half the green second layer")
        XCTAssertEqual(out[2], 0, "no blue panel between them")
    }

    func testSecondLayerOpacityIsSeparateFromTheFirst() {
        var settings = MixSettings()
        settings.back = .color
        settings.backColor = MixColor(red: 0, green: 1, blue: 0)
        settings.backOpacity = 0.5
        let out = renderShape(settings)
        XCTAssertEqual(pixel(out, 0.5, 0.4), [255, 0, 0, 255], "first layer stays solid")
        let back = pixel(out, 0.5, 0.8)
        XCTAssertEqual(Double(back[1]), 127, accuracy: 3, "half green")
        XCTAssertEqual(Double(back[2]), 127, accuracy: 3, "half folder blue")
    }

    func testFirstLayerOpacityLeavesTheSecondLayerAlone() {
        var settings = MixSettings()
        settings.back = .samePosition
        let solidBack = pixel(renderShape(settings), 0.5, 0.8)
        settings.opacity = 0.2
        XCTAssertEqual(pixel(renderShape(settings), 0.5, 0.8), solidBack)
    }

    func testZeroSecondLayerOpacityShowsTheFolderBack() {
        var settings = MixSettings()
        settings.back = .samePosition
        settings.backOpacity = 0
        XCTAssertEqual(pixel(renderShape(settings), 0.5, 0.8), [0, 0, 255, 255])
    }

    func testEachLayerHasItsOwnPhotoControls() {
        var settings = MixSettings()
        settings.back = .samePosition
        let photo = solid(0.8, 0.8, 0.8)
        let plain = renderShape(settings, photo: photo)
        settings.backBrightness = -0.3
        let darkBack = renderShape(settings, photo: photo)
        XCTAssertLessThan(pixel(darkBack, 0.5, 0.8)[0], pixel(plain, 0.5, 0.8)[0])
        XCTAssertEqual(pixel(darkBack, 0.5, 0.4), pixel(plain, 0.5, 0.4), "front unchanged")
        settings.backBrightness = 0
        settings.brightness = -0.3
        let darkFront = renderShape(settings, photo: photo)
        XCTAssertLessThan(pixel(darkFront, 0.5, 0.4)[0], pixel(plain, 0.5, 0.4)[0])
        XCTAssertEqual(pixel(darkFront, 0.5, 0.8), pixel(plain, 0.5, 0.8), "back unchanged")
    }

    func testBackRotationTurnsOnlyTheBack() {
        var settings = MixSettings()
        settings.back = .differentPosition
        settings.backOffsetX = 0
        settings.backOffsetY = 0
        let plain = renderShape(settings, photo: split)
        settings.backRotation = 180
        let turned = renderShape(settings, photo: split)
        XCTAssertNotEqual(pixel(plain, 0.25, 0.8), pixel(turned, 0.25, 0.8))
        XCTAssertEqual(pixel(plain, 0.25, 0.4), pixel(turned, 0.25, 0.4))
    }

    func testDetachingKeepsTheFrontsRotation() {
        var settings = MixSettings()
        settings.back = .samePosition
        settings.rotation = 30
        settings.detachBack()
        XCTAssertEqual(settings.backRotation, 30)
        XCTAssertEqual(settings.back, .differentPosition)
    }

    private func onTarget(_ target: FinishTarget, _ change: (inout MixSettings) -> Void = { _ in }) -> CGImage {
        finished(.frosted, {
            $0.finishTarget = target
            $0.back = .samePosition
            change(&$0)
        }, photo: split)
    }

    private var noGlass: CGImage {
        var settings = MixSettings()
        settings.back = .samePosition
        return renderShape(settings, photo: split)
    }

    /// Red meets green at the centre, so a blur shows up as mixing there.
    private func isBlurred(_ image: CGImage, y: Double) -> Bool {
        let p = pixel(image, 0.49, y)
        return p[1] > 40 && p[0] > 40
    }

    func testFirstLayerTargetLeavesTheSecondLayerSharp() {
        let out = onTarget(.firstLayer)
        XCTAssertTrue(isBlurred(out, y: 0.4))
        XCTAssertEqual(pixel(out, 0.49, 0.8), pixel(noGlass, 0.49, 0.8))
    }

    func testSecondLayerTargetLeavesTheFirstLayerSharp() {
        let out = onTarget(.secondLayer)
        XCTAssertTrue(isBlurred(out, y: 0.8))
        XCTAssertEqual(pixel(out, 0.49, 0.4), pixel(noGlass, 0.49, 0.4))
    }

    func testBothAndWholeReachBothLayers() {
        for target in [FinishTarget.bothLayers, .wholeIcon] {
            let out = onTarget(target)
            XCTAssertTrue(isBlurred(out, y: 0.4), "\(target) front")
            XCTAssertTrue(isBlurred(out, y: 0.8), "\(target) back")
        }
    }

    func testBothLayersHasASeamWholeIconDoesNot() {
        let both = onTarget(.bothLayers)
        let whole = onTarget(.wholeIcon)
        XCTAssertNotEqual(both.dataProvider?.data, whole.dataProvider?.data)
    }

    func testSecondLayerGlassWorksOnTheOriginalFolderBack() {
        let out = finished(.frosted, { $0.finishTarget = .secondLayer })
        XCTAssertGreaterThan(pixel(out, 0.5, 0.8)[0], 30, "white tint on the blue back")
        XCTAssertEqual(pixel(out, 0.5, 0.4), [255, 0, 0, 255], "front stays solid")
    }

    func testStickerStaysSharpUnderEveryTarget() {
        for target in FinishTarget.allCases {
            let out = onTarget(target) { $0.style = .sticker }
            var plain = MixSettings()
            plain.style = .sticker
            plain.back = .samePosition
            XCTAssertEqual(pixel(out, 0.45, 0.43), pixel(renderShape(plain, photo: split), 0.45, 0.43), "\(target)")
        }
    }

    func testWholeIconKeepsLayerOpacityOnASticker() {
        let solidOut = onTarget(.wholeIcon) { $0.style = .sticker }
        let faded = onTarget(.wholeIcon) {
            $0.style = .sticker
            $0.opacity = 0.3
        }
        XCTAssertNotEqual(pixel(solidOut, 0.45, 0.43), pixel(faded, 0.45, 0.43))
    }

    func testSingleLayerLooksIgnoreTheTarget() {
        var settings = MixSettings()
        settings.style = .cutout
        settings.finish = .frosted
        let first = renderShape(settings, photo: split)
        settings.finishTarget = .secondLayer
        XCTAssertEqual(first.dataProvider?.data, renderShape(settings, photo: split).dataProvider?.data)
    }

    func testSecondLayerGlassStaysOnDuringTheEditFade() {
        var settings = MixSettings()
        settings.back = .samePosition
        settings.finish = .frosted
        settings.finishTarget = .secondLayer
        let out = Mixer.render(icon: folderShape, photo: split, settings: settings, size: 256, frontOpacity: 0.4)!
        XCTAssertTrue(isBlurred(out, y: 0.8))
    }

    private func toned(_ finish: Finish, _ tone: GlassTone, systemIsDark: Bool = false,
                       color: MixColor? = nil) -> CGImage {
        var settings = MixSettings()
        settings.finish = finish
        settings.glassTone = tone
        if let color { settings.glassColor = color }
        return Mixer.render(icon: folderShape, photo: solid(0.6, 0.6, 0.6), settings: settings, size: 256,
                            systemIsDark: systemIsDark)!
    }

    func testDarkGlassIsDarkerThanLightGlass() {
        for finish in [Finish.frosted, .liquidGlass] {
            XCTAssertLessThan(pixel(toned(finish, .dark), 0.5, 0.3)[0], pixel(toned(finish, .light), 0.5, 0.3)[0] - 40,
                              finish.title)
        }
    }

    func testAutoGlassFollowsTheSystemMode() {
        XCTAssertEqual(toned(.frosted, .auto, systemIsDark: true).dataProvider?.data,
                       toned(.frosted, .dark).dataProvider?.data)
        XCTAssertEqual(toned(.frosted, .auto, systemIsDark: false).dataProvider?.data,
                       toned(.frosted, .light).dataProvider?.data)
    }

    func testFixedTonesIgnoreTheSystemMode() {
        XCTAssertEqual(toned(.frosted, .light, systemIsDark: true).dataProvider?.data,
                       toned(.frosted, .light).dataProvider?.data)
    }

    func testCustomGlassTakesTheChosenColour() {
        for finish in [Finish.frosted, .liquidGlass] {
            let p = pixel(toned(finish, .custom, color: MixColor(red: 1, green: 0, blue: 0)), 0.5, 0.3)
            XCTAssertGreaterThan(p[0], p[1] + 40, finish.title)
        }
    }

    func testToneMattersOnlyWithAFinish() {
        XCTAssertEqual(toned(.none, .dark).dataProvider?.data, toned(.none, .light).dataProvider?.data)
    }

    func testTargetTitlesFollowTheObject() {
        XCTAssertEqual(FinishTarget.wholeIcon.title(object: "Folder"), "Folder")
        XCTAssertEqual(FinishTarget.wholeIcon.title(object: "App"), "App")
    }

    func testStrengthZeroKeepsThePictureSharp() {
        let frost = finished(.frosted, { $0.finishStrength = 0; $0.glassTone = .light }, photo: split)
        let glass = finished(.liquidGlass, { $0.finishStrength = 0; $0.glassTone = .light }, photo: split)
        let plain = renderShape(MixSettings(), photo: split)
        // Red meets green at the centre. Without blur the two sides stay apart.
        for image in [frost, glass] {
            XCTAssertGreaterThan(pixel(image, 0.47, 0.4)[0], pixel(image, 0.47, 0.4)[1] + 60)
            XCTAssertGreaterThan(pixel(image, 0.53, 0.4)[1], pixel(image, 0.53, 0.4)[0] + 60)
        }
        XCTAssertEqual(pixel(plain, 0.09, 0.4)[0], 255)
    }

    func testStrengthZeroStillShowsTheGlassSurface() {
        let photo = solid(0.2, 0.2, 0.2)
        let plain = renderShape(MixSettings(), photo: photo)
        for finish in [Finish.frosted, .liquidGlass] {
            let out = finished(finish, { $0.finishStrength = 0; $0.glassTone = .light }, photo: photo)
            XCTAssertNotEqual(out.dataProvider?.data, plain.dataProvider?.data, finish.title)
            let rim = stride(from: 0.70, to: 0.74, by: 0.002).map { pixel(out, 0.5, $0)[0] }.max()!
            XCTAssertGreaterThan(rim, 110, "\(finish.title) lit edge")
        }
    }

    func testMoreStrengthBlursMore() {
        let low = finished(.frosted, { $0.finishStrength = 0.2; $0.glassTone = .light }, photo: split)
        let high = finished(.frosted, { $0.finishStrength = 1; $0.glassTone = .light }, photo: split)
        XCTAssertGreaterThan(pixel(high, 0.43, 0.4)[1], pixel(low, 0.43, 0.4)[1])
    }

    func testSecondLayerCanUseItsOwnPicture() {
        var settings = MixSettings()
        settings.back = .differentPosition
        settings.backOffsetX = 0
        settings.backOffsetY = 0
        settings.backZoom = 1
        let out = Mixer.render(icon: folderShape, photo: solid(1, 0, 0), settings: settings, size: 256,
                               secondPhoto: solid(0, 1, 0))!
        XCTAssertEqual(pixel(out, 0.5, 0.4), [255, 0, 0, 255], "first layer keeps its picture")
        let back = pixel(out, 0.5, 0.8)
        XCTAssertGreaterThan(back[1], 150, "second layer shows the second picture")
        XCTAssertLessThan(back[0], 20)
    }

    func testSecondPictureGetsItsOwnPhotoControls() {
        var settings = MixSettings()
        settings.back = .samePosition
        let bright = pixel(Mixer.render(icon: folderShape, photo: solid(1, 0, 0), settings: settings, size: 256,
                                        secondPhoto: solid(0.8, 0.8, 0.8))!, 0.5, 0.8)
        settings.backBrightness = -0.3
        let dim = pixel(Mixer.render(icon: folderShape, photo: solid(1, 0, 0), settings: settings, size: 256,
                                     secondPhoto: solid(0.8, 0.8, 0.8))!, 0.5, 0.8)
        XCTAssertLessThan(dim[0], bright[0])
    }

    func testWideSecondPictureStillCoversTheFolder() {
        var settings = MixSettings()
        settings.back = .samePosition
        let out = Mixer.render(icon: folderShape, photo: solid(1, 0, 0), settings: settings, size: 256,
                               secondPhoto: solid(0, 1, 0, width: 400, height: 40))!
        XCTAssertGreaterThan(pixel(out, 0.1, 0.8)[1], 150)
        XCTAssertGreaterThan(pixel(out, 0.9, 0.8)[1], 150)
    }

    func testFinishOnAnAppWithNoPicture() {
        let icon = appIcon
        var settings = MixSettings()
        let plain = Mixer.render(icon: icon, photo: Mixer.noPhoto, settings: settings, size: 256,
                                 shape: Mixer.shape(ofIcon: icon))!
        XCTAssertEqual(pixel(plain, 0.5, 0.5), [0, 0, 255, 255], "the app's own icon shows")
        settings.finish = .frosted
        settings.glassTone = .light
        let glass = Mixer.render(icon: icon, photo: Mixer.noPhoto, settings: settings, size: 256,
                                 shape: Mixer.shape(ofIcon: icon))!
        XCTAssertGreaterThan(pixel(glass, 0.5, 0.5)[0], 30, "white film on top")
        XCTAssertGreaterThan(pixel(glass, 0.5, 0.5)[2], 150, "still the app's colour")
        XCTAssertEqual(pixel(glass, 0.05, 0.5)[3], 0)
    }

    func testGlassFollowsTheSystemByDefault() {
        XCTAssertEqual(MixSettings().glassTone, .auto)
    }

    func testToggleSwitchesBetweenLightAndDark() {
        var settings = MixSettings()
        settings.glassTone = .light
        settings.toggleGlassTone(systemIsDark: true)
        XCTAssertEqual(settings.glassTone, .dark)
        settings.toggleGlassTone(systemIsDark: true)
        XCTAssertEqual(settings.glassTone, .light)
    }

    func testToggleFromAutoAlwaysChangesWhatYouSee() {
        var settings = MixSettings()
        settings.glassTone = .auto
        settings.toggleGlassTone(systemIsDark: true)
        XCTAssertEqual(settings.glassTone, .light, "auto was showing dark")
        settings.glassTone = .auto
        settings.toggleGlassTone(systemIsDark: false)
        XCTAssertEqual(settings.glassTone, .dark, "auto was showing light")
    }

    func testThumbnailsDoNotChangeTheCurrentSettings() {
        let settings = MixSettings()
        _ = FolderLayer.wholeCut.applied(to: settings)
        XCTAssertEqual(settings, MixSettings())
        XCTAssertEqual(FolderLayer.shadow.applied(to: settings).panelShadow, true)
    }

    func testAverageColor() {
        let color = Mixer.averageColor(of: solid(1, 0, 0))
        XCTAssertEqual(color.red, 1, accuracy: 0.02)
        XCTAssertEqual(color.green, 0, accuracy: 0.02)
    }

    func testRendersRequestedSizeWithTransparentCorners() {
        let folderWithHole: CGImage = {
            let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return ctx.makeImage()!
        }()
        let out = Mixer.render(icon: folderWithHole, photo: solid(1, 0, 0), settings: MixSettings(), size: 512)!
        XCTAssertEqual(out.width, 512)
        XCTAssertEqual(pixel(out, 0.01, 0.99)[3], 0)
    }
}
