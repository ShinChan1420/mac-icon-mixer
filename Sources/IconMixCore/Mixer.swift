import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

public enum MixStyle: String, CaseIterable, Identifiable, Sendable {
    case fill, sticker, tinted, stamp, cutout, picture

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fill: "Fill"
        case .sticker: "Sticker"
        case .tinted: "Tinted"
        case .stamp: "Stamp"
        case .cutout: "Cutout"
        case .picture: "Picture"
        }
    }

    /// The styles chosen for the front panel. Cutout and Picture replace the folder's layers altogether.
    public static let frontStyles: [MixStyle] = [.fill, .sticker, .tinted, .stamp]

    public var hasBackOptions: Bool { Self.frontStyles.contains(self) }

    var coversArea: Bool { self == .fill || self == .tinted || self == .cutout }

    /// Styles where the front panel's colour shows. Fill hides the panel behind the picture.
    public var usesFrontColor: Bool { self == .sticker || self == .tinted || self == .stamp }
}

/// Where the picture goes on an icon. Fractions of the icon, origin bottom-left.
public struct IconShape: Equatable, Sendable {
    public static let folder = IconShape(front: Mixer.frontPanel, body: Mixer.folderBody, followsOutline: false)

    public var front: CGRect
    public var body: CGRect
    /// True for icons with no front panel, such as apps: the picture is trimmed to the icon's own outline.
    public var followsOutline: Bool
}

/// One-click choices for what happens behind the picture.
public enum FolderLayer: String, CaseIterable, Identifiable, Sendable {
    case original, shadow, plainColor, samePosition, differentPosition, wholeCut, pictureOnly

    public var id: String { rawValue }

    /// App icons are a single layer, so only the choices that don't need a back apply.
    public var worksOnApps: Bool { self == .original || self == .wholeCut || self == .pictureOnly }

    public var title: String {
        switch self {
        case .original: "Original"
        case .shadow: "Shadow"
        case .plainColor: "Plain Colour"
        case .samePosition: "Same Position"
        case .differentPosition: "Different Position"
        case .wholeCut: "Whole Cut"
        case .pictureOnly: "Picture Only"
        }
    }

    public func isSelected(in settings: MixSettings) -> Bool {
        switch self {
        case .original: settings.style.hasBackOptions && settings.back == .folder
        case .shadow: settings.style.hasBackOptions && settings.panelShadow
        case .plainColor: settings.style.hasBackOptions && settings.back == .color
        case .samePosition: settings.style.hasBackOptions && settings.back == .samePosition
        case .differentPosition: settings.style.hasBackOptions && settings.back == .differentPosition
        case .wholeCut: settings.style == .cutout
        case .pictureOnly: settings.style == .picture
        }
    }

    /// Shadow switches on and off and combines with the back choices; the others pick one look.
    public func choose(in settings: inout MixSettings) {
        if self == .shadow {
            let turnOn = !isSelected(in: settings)
            leaveWholeImageStyles(&settings)
            settings.panelShadow = turnOn
        } else {
            select(in: &settings)
        }
    }

    /// The settings to show on this option's thumbnail.
    public func applied(to settings: MixSettings) -> MixSettings {
        var result = settings
        if self == .shadow {
            leaveWholeImageStyles(&result)
            result.panelShadow = true
        } else {
            select(in: &result)
        }
        return result
    }

    private func select(in settings: inout MixSettings) {
        switch self {
        case .wholeCut: settings.style = .cutout
        case .pictureOnly: settings.style = .picture
        case .original: setBack(.folder, &settings)
        case .plainColor: setBack(.color, &settings)
        case .samePosition: setBack(.samePosition, &settings)
        case .differentPosition: setBack(.differentPosition, &settings)
        case .shadow: break
        }
    }

    private func setBack(_ back: BackStyle, _ settings: inout MixSettings) {
        leaveWholeImageStyles(&settings)
        settings.back = back
    }

    private func leaveWholeImageStyles(_ settings: inout MixSettings) {
        if !settings.style.hasBackOptions { settings.style = .fill }
    }
}

/// What shows on the part of the folder behind the front panel.
public enum BackStyle: Sendable {
    case folder, color, samePosition, differentPosition

    var showsPicture: Bool { self == .samePosition || self == .differentPosition }
}

public struct MixColor: Equatable, Sendable {
    public static let folderBlue = MixColor(red: 0.4, green: 0.75, blue: 0.93)
    public static let white = MixColor(red: 1, green: 1, blue: 1)
    static let glassBlack = MixColor(red: 0.06, green: 0.06, blue: 0.08)

    public var red, green, blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    var luma: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    func darkened(by factor: Double) -> MixColor {
        MixColor(red: red * factor, green: green * factor, blue: blue * factor)
    }
}

public struct MixSettings: Equatable, Sendable {
    public var style: MixStyle = .fill
    public var zoom: Double = 1
    /// Offsets are fractions of the folder's front panel; positive is right / up.
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    /// Degrees, positive is clockwise.
    public var rotation: Double = 0
    public var opacity: Double = 1
    public var brightness: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    /// nil keeps the folder's own front panel.
    public var frontColor: MixColor?
    public var back: BackStyle = .folder
    public var backColor = MixColor(red: 0.25, green: 0.6, blue: 0.85)
    /// Only used by `.differentPosition`; same units as `offsetX` / `offsetY`.
    public var backOffsetX: Double = 0.25
    public var backOffsetY: Double = 0.2
    /// Only used by `.differentPosition`. Starts above 1 so the moved picture still reaches the folder's edges.
    public var backZoom: Double = 1.5
    /// Only used by `.differentPosition`; degrees, positive is clockwise.
    public var backRotation: Double = 0
    /// The second layer fades towards the folder's own back as this drops.
    public var backOpacity: Double = 1
    public var backBrightness: Double = 0
    public var backContrast: Double = 1
    public var backSaturation: Double = 1
    /// Soft shadow the front panel casts on the back of the folder.
    public var panelShadow = false
    public var finish: Finish = .none
    public var finishStrength: Double = 0.6
    /// Looks with a single layer always use the whole icon.
    public var finishTarget: FinishTarget = .firstLayer
    public var glassTone: GlassTone = .light
    public var glassColor = MixColor(red: 0.2, green: 0.55, blue: 0.9)

    public init() {}
}

/// The layer a drag or pinch acts on.
public enum EditLayer: Sendable {
    case front, back
}

extension MixSettings {
    /// Flips to whichever of light and dark the glass isn't showing now.
    public mutating func toggleGlassTone(systemIsDark: Bool) {
        let showsDark = glassTone == .dark || (glassTone == .auto && systemIsDark)
        glassTone = showsDark ? .light : .dark
    }

    func glassTint(systemIsDark: Bool) -> MixColor {
        switch glassTone {
        case .auto: systemIsDark ? .glassBlack : .white
        case .light: .white
        case .dark: .glassBlack
        case .custom: glassColor
        }
    }

    public static let frontZoomRange = 0.2...3.0
    public static let backZoomRange = 0.2...4.0

    /// True when the second layer shows the picture, so there's something to move.
    public var canEditBack: Bool { style.hasBackOptions && back.showsPicture }

    /// Which layer sits under a point on the icon; `unitY` runs from 0 at the top to 1 at the bottom.
    public func layer(atUnitY unitY: Double) -> EditLayer {
        canEditBack && unitY < 1 - Mixer.frontPanel.maxY ? .back : .front
    }

    public func zoom(of layer: EditLayer) -> Double {
        switch layer {
        case .front: zoom
        case .back: back == .samePosition ? 1 : backZoom
        }
    }

    /// Moves a layer; `dx` and `dy` are fractions of the icon, positive is right / up.
    public mutating func move(_ layer: EditLayer, dx: Double, dy: Double, shape: IconShape = .folder) {
        switch layer {
        case .front:
            let area = Mixer.placementArea(for: self, shape: shape)
            offsetX = min(1, max(-1, offsetX + dx / area.width))
            offsetY = min(1, max(-1, offsetY + dy / area.height))
        case .back:
            detachBack()
            backOffsetX = min(1, max(-1, backOffsetX + dx / Mixer.folderBody.width))
            backOffsetY = min(1, max(-1, backOffsetY + dy / Mixer.folderBody.height))
        }
    }

    public mutating func setZoom(_ value: Double, of layer: EditLayer) {
        switch layer {
        case .front:
            zoom = min(Self.frontZoomRange.upperBound, max(Self.frontZoomRange.lowerBound, value))
        case .back:
            detachBack()
            backZoom = min(Self.backZoomRange.upperBound, max(Self.backZoomRange.lowerBound, value))
        }
    }

    /// Editing a back that follows the front gives it its own position, starting from where it is now.
    public mutating func detachBack() {
        guard back == .samePosition else { return }
        back = .differentPosition
        backOffsetX = offsetX
        backOffsetY = offsetY
        backRotation = rotation
        backZoom = 1
    }
}

public enum Mixer {
    /// Front panel of the system folder icon, as fractions of the icon (origin bottom-left).
    /// Measured from the 1024px icon: x 42...981, y 268...888 from the top.
    public static let frontPanel = CGRect(x: 0.041, y: 0.133, width: 0.917, height: 0.605)
    /// Whole folder including the tab, measured the same way: y 134...888 from the top.
    public static let folderBody = CGRect(x: 0.041, y: 0.133, width: 0.917, height: 0.736)
    private static let panelCorner = 0.065
    private static let backDimming = 0.16
    private static let fitInset = 0.72

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let ciContext = CIContext(options: [.workingColorSpace: sRGB])
    private static var maskCache: [(folder: CGImage, size: Int, mask: CGImage)] = []

    /// The part of the icon the picture is sized and positioned against, as fractions of the icon.
    public static func placementArea(for settings: MixSettings, shape: IconShape = .folder) -> CGRect {
        let style = settings.style
        if style == .picture { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let spansFolder = style == .cutout || (style.coversArea && settings.back.showsPicture)
        return spansFolder ? shape.body : shape.front
    }

    /// Works out where the solid part of an icon sits, for icons without a measured layout.
    public static func shape(ofIcon icon: CGImage) -> IconShape {
        let size = 256
        var bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let mask = folderMask(icon, size: size), let gray = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let data = gray.data {
            gray.draw(mask, in: CGRect(x: 0, y: 0, width: size, height: size))
            let pixels = data.assumingMemoryBound(to: UInt8.self)
            var minX = size, maxX = -1, minRow = size, maxRow = -1
            for row in 0..<size {
                for column in 0..<size where pixels[row * size + column] > 128 {
                    minX = min(minX, column)
                    maxX = max(maxX, column)
                    minRow = min(minRow, row)
                    maxRow = max(maxRow, row)
                }
            }
            if maxX >= minX {
                let side = Double(size)
                bounds = CGRect(x: Double(minX) / side, y: 1 - Double(maxRow + 1) / side,
                                width: Double(maxX - minX + 1) / side, height: Double(maxRow - minRow + 1) / side)
            }
        }
        return IconShape(front: bounds, body: bounds, followsOutline: true)
    }

    /// Decodes an image upright (EXIF orientation applied), capped to `maxPixels` on the long edge.
    public static func decode(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Average colour of an image, used as the starting plain colour for the back of the folder.
    public static func averageColor(of image: CGImage) -> MixColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return MixColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    /// Stands in for the picture when an icon only gets a finish.
    public static let noPhoto: CGImage = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!

    /// `frontOpacity` fades the whole front layer, panel included, to reveal the second layer while it's edited.
    public static func render(folder: CGImage, photo: CGImage, settings: MixSettings, size: Int,
                              frontOpacity: Double = 1, shape: IconShape = .folder,
                              systemIsDark: Bool = false, secondPhoto: CGImage? = nil) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let side = CGFloat(size)
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let panel = scaled(shape.front, to: side)
        let style = settings.style
        ctx.interpolationQuality = .high

        let graded = applyColor(to: photo, brightness: settings.brightness, contrast: settings.contrast,
                                saturation: settings.saturation)
        let panelColor = style.usesFrontColor ? settings.frontColor : nil
        let artwork = style == .stamp ? stampArtwork(from: graded, panelColor: panelColor, onOutline: shape.followsOutline) : graded
        guard let graded, let artwork else { return nil }

        let dressesBack = !shape.followsOutline && style.hasBackOptions
            && (settings.back != .folder || settings.panelShadow)
        let body = scaled(shape.body, to: side)
        let area = scaled(placementArea(for: settings, shape: shape), to: side)

        let widthRatio = area.width / CGFloat(photo.width)
        let heightRatio = area.height / CGFloat(photo.height)
        let baseScale: CGFloat = switch style {
        case .fill, .tinted, .cutout: max(widthRatio, heightRatio)
        case .sticker, .stamp: min(widthRatio, heightRatio) * fitInset
        case .picture: min(widthRatio, heightRatio)
        }
        let scale = baseScale * settings.zoom
        let width = CGFloat(photo.width) * scale
        let height = CGFloat(photo.height) * scale
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)

        // The back always covers the folder, even when the front is a small sticker or stamp.
        let backSource = secondPhoto ?? photo
        let backScale = max(body.width / CGFloat(backSource.width), body.height / CGFloat(backSource.height))
            * (style.coversArea && secondPhoto == nil ? settings.zoom : 1)
        let backWidth = CGFloat(backSource.width) * backScale
        let backHeight = CGFloat(backSource.height) * backScale
        let backRect = CGRect(x: -backWidth / 2, y: -backHeight / 2, width: backWidth, height: backHeight)

        let panelPath = roundedPanel(panel, side: side)
        var mask: CGImage?
        let clipsToOutline = style == .cutout
            || (shape.followsOutline && (style == .fill || style == .tinted || style == .stamp))
        let singleLayer = shape.followsOutline || style == .cutout
        let glassTint = settings.glassTint(systemIsDark: systemIsDark)
        let target = singleLayer ? FinishTarget.firstLayer : settings.finishTarget
        let chosenFinish = style == .picture ? Finish.none : settings.finish
        // The fade shows the second layer while it's edited, so glass in front of it stays off until release.
        let finish = frontOpacity < 1 ? Finish.none : chosenFinish
        let glassOnFirst = finish != .none && (target == .firstLayer || target == .bothLayers)
        let glassOnWhole = finish != .none && target == .wholeIcon
        let glassOnSecond = chosenFinish != .none && (target == .secondLayer || target == .bothLayers)
        if clipsToOutline || dressesBack || panelColor != nil || (glassOnFirst && singleLayer)
            || glassOnWhole || glassOnSecond {
            guard let shape = folderMask(folder, size: size) else { return nil }
            mask = shape
        }

        if style != .picture {
            ctx.draw(folder, in: canvas)
        }
        // With a second layer in place, first-layer opacity fades the whole front so the back shows
        // through. A glass front is already see-through, so there only the picture fades.
        // Stickers and stamps sit on top of the glass and stay sharp; other pictures go behind it.
        let artOnTop = style == .sticker || style == .stamp
        let layerAlpha = frontOpacity * (glassOnFirst ? 1 : settings.opacity)
        let wantsFade = dressesBack && layerAlpha < 1
        // A whole-icon pane under a sticker has to be drawn between the panel and the sticker,
        // which a single fade layer around both can't allow.
        let splitFade = wantsFade && glassOnWhole && artOnTop
        let fadesFront = wantsFade && !splitFade
        let artAlpha = splitFade ? layerAlpha : (dressesBack && !glassOnFirst ? 1 : settings.opacity)
        if dressesBack, let mask {
            let backPhoto = applyColor(to: backSource, brightness: settings.backBrightness,
                                       contrast: settings.backContrast, saturation: settings.backSaturation) ?? backSource
            drawBack(backPhoto, rect: backRect, area: body, panelPath: panelPath, mask: mask, on: ctx,
                     settings: settings, side: side, showsShadow: settings.panelShadow && frontOpacity == 1,
                     panelIsClear: glassOnFirst || glassOnSecond || wantsFade)
        }
        if glassOnSecond, let mask {
            applyFinish(chosenFinish, strength: settings.finishStrength, tint: glassTint, to: ctx, region: mask, bounds: body)
        }
        if fadesFront {
            ctx.saveGState()
            ctx.setAlpha(layerAlpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        // A glass front lets the second layer show through it.
        let panelAlpha = glassOnFirst ? 0.5 : (splitFade ? layerAlpha : 1)
        if let panelColor, let mask {
            // Runs past the measured panel on the sides and bottom so the folder's outline
            // does the trimming and no blue rim is left.
            ctx.saveGState()
            ctx.clip(to: canvas, mask: mask)
            ctx.setAlpha(panelAlpha)
            ctx.setFillColor(panelColor.cgColor)
            if shape.followsOutline {
                ctx.fill(canvas)
            } else {
                ctx.addPath(panelPath)
                ctx.fillPath()
                ctx.fill(CGRect(x: 0, y: 0, width: side, height: panel.midY))
            }
            ctx.restoreGState()
        } else if dressesBack || glassOnSecond {
            ctx.saveGState()
            ctx.addPath(panelPath)
            ctx.clip()
            ctx.setAlpha(panelAlpha)
            ctx.draw(folder, in: canvas)
            ctx.restoreGState()
        }

        var glassRegion: CGImage?
        if glassOnWhole {
            glassRegion = mask
        } else if glassOnFirst {
            glassRegion = singleLayer ? mask : panelMask(panelPath, size: size)
        }
        let glassBounds = glassOnWhole || style == .cutout ? body : panel
        if artOnTop, let glassRegion {
            applyFinish(finish, strength: settings.finishStrength, tint: glassTint, to: ctx, region: glassRegion,
                        bounds: glassBounds)
        }

        ctx.saveGState()
        if clipsToOutline, let mask {
            ctx.clip(to: canvas, mask: mask)
        } else if style == .fill || style == .tinted || style == .stamp {
            ctx.addPath(panelPath)
            ctx.clip()
        }
        ctx.setAlpha(artAlpha)
        ctx.setBlendMode(style == .tinted ? .luminosity : .normal)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        place(on: ctx, in: area, offsetX: settings.offsetX, offsetY: settings.offsetY, rotation: settings.rotation)

        switch style {
        case .fill, .tinted, .cutout, .picture:
            ctx.draw(artwork, in: rect)
        case .sticker:
            drawSticker(artwork, in: rect, on: ctx, side: side)
        case .stamp:
            ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.003), blur: side * 0.002,
                          color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45))
            ctx.draw(artwork, in: rect)
        }

        ctx.endTransparencyLayer()
        ctx.restoreGState()
        if fadesFront {
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
        if !artOnTop, let glassRegion {
            applyFinish(finish, strength: settings.finishStrength, tint: glassTint, to: ctx, region: glassRegion,
                        bounds: glassBounds)
        }
        return ctx.makeImage()
    }

    private static func panelMask(_ path: CGPath, size: Int) -> CGImage? {
        guard let gray = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        gray.setFillColor(gray: 1, alpha: 1)
        gray.addPath(path)
        gray.fillPath()
        return gray.makeImage()
    }

    private static func scaled(_ unit: CGRect, to side: CGFloat) -> CGRect {
        CGRect(x: unit.minX * side, y: unit.minY * side, width: unit.width * side, height: unit.height * side)
    }

    private static func roundedPanel(_ panel: CGRect, side: CGFloat) -> CGPath {
        let radius = panelCorner * side
        return CGPath(roundedRect: panel, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func place(on ctx: CGContext, in area: CGRect, offsetX: Double, offsetY: Double, rotation: Double) {
        ctx.translateBy(x: area.midX + offsetX * area.width, y: area.midY + offsetY * area.height)
        ctx.rotate(by: -rotation * .pi / 180)
    }

    /// Paints everything behind the front panel. The caller redraws the panel over the result.
    private static func drawBack(_ image: CGImage, rect: CGRect, area: CGRect, panelPath: CGPath, mask: CGImage,
                                 on ctx: CGContext, settings: MixSettings, side: CGFloat, showsShadow: Bool,
                                 panelIsClear: Bool) {
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.saveGState()
        ctx.clip(to: canvas, mask: mask)

        switch settings.back {
        case .folder:
            break
        case .color:
            ctx.saveGState()
            ctx.setAlpha(settings.backOpacity)
            ctx.setFillColor(settings.backColor.cgColor)
            ctx.fill(canvas)
            ctx.restoreGState()
        case .samePosition, .differentPosition:
            let moved = settings.back == .differentPosition
            let offsetX = moved ? settings.backOffsetX : settings.offsetX
            let offsetY = moved ? settings.backOffsetY : settings.offsetY
            let zoom = moved ? settings.backZoom : 1
            let zoomed = rect.applying(CGAffineTransform(scaleX: zoom, y: zoom))

            ctx.saveGState()
            ctx.setAlpha(settings.backOpacity)
            ctx.setBlendMode(settings.style == .tinted ? .luminosity : .normal)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            place(on: ctx, in: area, offsetX: offsetX, offsetY: offsetY,
                  rotation: moved ? settings.backRotation : settings.rotation)
            ctx.draw(image, in: zoomed)
            ctx.endTransparencyLayer()
            ctx.restoreGState()

            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: backDimming * settings.backOpacity))
            ctx.fill(canvas)
        }

        if showsShadow {
            if panelIsClear {
                // The shape casting the shadow would show through a glass panel.
                ctx.addRect(canvas)
                ctx.addPath(panelPath)
                ctx.clip(using: .evenOdd)
            }
            ctx.setShadow(offset: CGSize(width: 0, height: side * 0.012), blur: side * 0.05,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6))
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.addPath(panelPath)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// Grayscale mask of the folder's solid body, taken from the icon itself.
    /// The steep ramp drops the icon's soft drop shadow, which is only partly opaque.
    static func folderMask(_ folder: CGImage, size: Int) -> CGImage? {
        if let hit = maskCache.first(where: { $0.folder === folder && $0.size == size }) { return hit.mask }

        guard let rgba = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gray = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let source = rgba.data, let target = gray.data else { return nil }

        rgba.interpolationQuality = .high
        rgba.draw(folder, in: CGRect(x: 0, y: 0, width: size, height: size))
        let pixels = source.assumingMemoryBound(to: UInt8.self)
        let output = target.assumingMemoryBound(to: UInt8.self)
        for index in 0..<(size * size) {
            let alpha = Int(pixels[index * 4 + 3])
            output[index] = UInt8(max(0, min(255, (alpha - 191) * 4)))
        }
        guard let mask = gray.makeImage() else { return nil }
        if maskCache.count >= 4 { maskCache.removeFirst() }
        maskCache.append((folder, size, mask))
        return mask
    }

    private static func drawSticker(_ image: CGImage, in rect: CGRect, on ctx: CGContext, side: CGFloat) {
        let short = min(rect.width, rect.height)
        let border = short * 0.04
        let radius = short * 0.08
        let card = rect.insetBy(dx: -border, dy: -border)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.008), blur: side * 0.03,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: card, cornerWidth: radius + border, cornerHeight: radius + border, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    private static func applyColor(to photo: CGImage, brightness: Double, contrast: Double,
                                   saturation: Double) -> CGImage? {
        if brightness == 0, contrast == 1, saturation == 1 { return photo }
        let filter = CIFilter.colorControls()
        filter.inputImage = CIImage(cgImage: photo)
        filter.brightness = Float(brightness)
        filter.contrast = Float(contrast)
        filter.saturation = Float(saturation)
        return filter.outputImage.flatMap(makeCGImage)
    }

    /// Turns dark or opaque parts of the image into a darker imprint, like the glyphs on system folders.
    private static func stampArtwork(from photo: CGImage?, panelColor: MixColor?, onOutline: Bool) -> CGImage? {
        guard let photo else { return nil }
        let input = CIImage(cgImage: photo)
        let extent = input.extent
        let alpha = input
            .composited(over: CIImage(color: .white).cropped(to: extent))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIMaskToAlpha")
        let defaultInk = onOutline ? MixColor(red: 0.1, green: 0.1, blue: 0.12) : MixColor(red: 0.17, green: 0.53, blue: 0.78)
        let inkColor = panelColor?.darkened(by: 0.7) ?? defaultInk
        let ink = CIColor(red: inkColor.red, green: inkColor.green, blue: inkColor.blue, alpha: 1, colorSpace: sRGB)!
        let stamped = CIImage(color: ink).cropped(to: extent)
            .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: alpha])
        return makeCGImage(stamped)
    }

    static func makeCGImage(_ image: CIImage) -> CGImage? {
        ciContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB)
    }
}
