import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// One icon being drawn: works out every decision up front, then paints the layers back to front.
struct IconComposition {
    private static let panelCorner = 0.065
    private static let backDimming = 0.16
    private static let fitInset = 0.72

    private let ctx: CGContext
    private let icon: CGImage
    private let settings: MixSettings
    private let shape: IconShape
    private let frontOpacity: Double
    private let secondPhoto: CGImage?
    private let backSource: CGImage

    private let side: CGFloat
    private let canvas: CGRect
    private let panel: CGRect
    private let body: CGRect
    private let area: CGRect
    private let panelPath: CGPath
    private let artwork: CGImage
    private let artRect: CGRect
    private let backRect: CGRect
    private let panelColor: MixColor?
    private let mask: CGImage?

    private let dressesBack: Bool
    private let clipsToOutline: Bool
    private let singleLayer: Bool

    private let finish: Finish
    private let secondLayerFinish: Finish
    private let glassTint: MixColor
    private let glassOnFirst: Bool
    private let glassOnWhole: Bool
    private let glassOnSecond: Bool

    private let layerAlpha: Double
    private let wantsFade: Bool
    private let splitFade: Bool
    private let fadesFront: Bool
    private let artAlpha: Double

    private var style: MixStyle { settings.style }

    init?(icon: CGImage, photo: CGImage, settings: MixSettings, size: Int, frontOpacity: Double,
          shape: IconShape, systemIsDark: Bool, secondPhoto: CGImage?) {
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: Mixer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high

        let style = settings.style
        let side = CGFloat(size)
        let panel = Self.scaled(shape.front, to: side)
        let body = Self.scaled(shape.body, to: side)
        let area = Self.scaled(Mixer.placementArea(for: settings, shape: shape), to: side)
        let panelColor = style.usesFrontColor ? settings.frontColor : nil

        guard let graded = Self.applyColor(to: photo, brightness: settings.brightness, contrast: settings.contrast,
                                           saturation: settings.saturation) else { return nil }
        let stamped = style == .stamp
            ? Self.stampArtwork(from: graded, panelColor: panelColor, onOutline: shape.followsOutline) : graded
        guard let artwork = stamped else { return nil }

        let singleLayer = shape.followsOutline || style == .cutout
        let target = singleLayer ? FinishTarget.firstLayer : settings.finishTarget
        let chosenFinish = style == .picture ? Finish.none : settings.finish
        // The fade shows the second layer while it's edited, so glass in front of it stays off until release.
        let finish = frontOpacity < 1 ? Finish.none : chosenFinish
        let glassOnFirst = finish != .none && (target == .firstLayer || target == .bothLayers)
        let glassOnWhole = finish != .none && target == .wholeIcon
        let glassOnSecond = chosenFinish != .none && (target == .secondLayer || target == .bothLayers)

        let dressesBack = !shape.followsOutline && style.hasBackOptions
            && (settings.back != .folder || settings.panelShadow)
        let clipsToOutline = style == .cutout || (shape.followsOutline && style.isClippedToFront)

        var mask: CGImage?
        if clipsToOutline || dressesBack || panelColor != nil || (glassOnFirst && singleLayer)
            || glassOnWhole || glassOnSecond {
            mask = Mixer.solidMask(of: icon, size: size)
            guard mask != nil else { return nil }
        }

        // With a second layer in place, first-layer opacity fades the whole front so the back shows
        // through. A glass front is already see-through, so there only the picture fades.
        let layerAlpha = frontOpacity * (glassOnFirst ? 1 : settings.opacity)
        let wantsFade = dressesBack && layerAlpha < 1
        // A whole-icon pane under a sticker has to be drawn between the panel and the sticker,
        // which a single fade layer around both can't allow.
        let splitFade = wantsFade && glassOnWhole && style.sitsOnGlass

        self.ctx = ctx
        self.icon = icon
        self.settings = settings
        self.shape = shape
        self.frontOpacity = frontOpacity
        self.secondPhoto = secondPhoto
        self.backSource = secondPhoto ?? photo
        self.side = side
        self.canvas = CGRect(x: 0, y: 0, width: side, height: side)
        self.panel = panel
        self.body = body
        self.area = area
        self.panelPath = Self.roundedPanel(panel, side: side)
        self.artwork = artwork
        self.artRect = Self.artRect(for: photo, in: area, settings: settings)
        self.backRect = Self.backRect(for: secondPhoto ?? photo, in: body, settings: settings,
                                      followsZoom: secondPhoto == nil)
        self.panelColor = panelColor
        self.mask = mask
        self.dressesBack = dressesBack
        self.clipsToOutline = clipsToOutline
        self.singleLayer = singleLayer
        self.finish = finish
        self.secondLayerFinish = chosenFinish
        self.glassTint = settings.glassTint(systemIsDark: systemIsDark)
        self.glassOnFirst = glassOnFirst
        self.glassOnWhole = glassOnWhole
        self.glassOnSecond = glassOnSecond
        self.layerAlpha = layerAlpha
        self.wantsFade = wantsFade
        self.splitFade = splitFade
        self.fadesFront = wantsFade && !splitFade
        self.artAlpha = splitFade ? layerAlpha : (dressesBack && !glassOnFirst ? 1 : settings.opacity)
    }

    func render() -> CGImage? {
        if style != .picture { ctx.draw(icon, in: canvas) }
        drawSecondLayer()
        applySecondLayerGlass()
        beginFade()
        drawFrontPanel()
        if style.sitsOnGlass { applyFrontGlass() }
        drawArtwork()
        endFade()
        if !style.sitsOnGlass { applyFrontGlass() }
        return ctx.makeImage()
    }

    // MARK: Second layer

    /// Paints everything behind the front panel. `drawFrontPanel` redraws the panel over the result.
    private func drawSecondLayer() {
        guard dressesBack, let mask else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: canvas, mask: mask)

        switch settings.back {
        case .folder: break
        case .color: fillBackColor()
        case .samePosition, .differentPosition: drawBackPicture()
        }
        drawPanelShadow()
    }

    private func fillBackColor() {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setAlpha(settings.backOpacity)
        ctx.setFillColor(settings.backColor.cgColor)
        ctx.fill(canvas)
    }

    private func drawBackPicture() {
        let image = Self.applyColor(to: backSource, brightness: settings.backBrightness,
                                    contrast: settings.backContrast, saturation: settings.backSaturation) ?? backSource
        let moved = settings.back == .differentPosition
        let zoom = moved ? settings.backZoom : 1

        ctx.saveGState()
        ctx.setAlpha(settings.backOpacity)
        ctx.setBlendMode(style == .tinted ? .luminosity : .normal)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        place(in: body, offsetX: moved ? settings.backOffsetX : settings.offsetX,
              offsetY: moved ? settings.backOffsetY : settings.offsetY,
              rotation: moved ? settings.backRotation : settings.rotation)
        ctx.draw(image, in: backRect.applying(CGAffineTransform(scaleX: zoom, y: zoom)))
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: Self.backDimming * settings.backOpacity))
        ctx.fill(canvas)
    }

    private func drawPanelShadow() {
        guard settings.panelShadow, frontOpacity == 1 else { return }
        if glassOnFirst || glassOnSecond || wantsFade {
            // The shape casting the shadow would show through a clear panel.
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

    private func applySecondLayerGlass() {
        guard glassOnSecond, let mask else { return }
        Mixer.applyFinish(secondLayerFinish, strength: settings.finishStrength, tint: glassTint, to: ctx,
                          region: mask, bounds: body)
    }

    // MARK: First layer

    private func beginFade() {
        guard fadesFront else { return }
        ctx.saveGState()
        ctx.setAlpha(layerAlpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    }

    private func endFade() {
        guard fadesFront else { return }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func drawFrontPanel() {
        // A glass front lets the second layer show through it.
        let panelAlpha = glassOnFirst ? 0.5 : (splitFade ? layerAlpha : 1)
        ctx.saveGState()
        defer { ctx.restoreGState() }

        if let panelColor, let mask {
            // Runs past the measured panel on the sides and bottom so the icon's outline
            // does the trimming and no blue rim is left.
            ctx.clip(to: canvas, mask: mask)
            ctx.setAlpha(panelAlpha)
            ctx.setFillColor(panelColor.cgColor)
            if shape.followsOutline {
                ctx.fill(canvas)
                return
            }
            ctx.addPath(panelPath)
            ctx.fillPath()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: panel.midY))
            return
        }

        guard dressesBack || glassOnSecond else { return }
        ctx.addPath(panelPath)
        ctx.clip()
        ctx.setAlpha(panelAlpha)
        ctx.draw(icon, in: canvas)
    }

    private func applyFrontGlass() {
        guard let region = glassRegion else { return }
        Mixer.applyFinish(finish, strength: settings.finishStrength, tint: glassTint, to: ctx, region: region,
                          bounds: glassOnWhole || style == .cutout ? body : panel)
    }

    private var glassRegion: CGImage? {
        if glassOnWhole { return mask }
        guard glassOnFirst else { return nil }
        return singleLayer ? mask : panelMask()
    }

    private func panelMask() -> CGImage? {
        guard let gray = CGContext(
            data: nil, width: ctx.width, height: ctx.height, bitsPerComponent: 8, bytesPerRow: ctx.width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        gray.setFillColor(gray: 1, alpha: 1)
        gray.addPath(panelPath)
        gray.fillPath()
        return gray.makeImage()
    }

    private func drawArtwork() {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if clipsToOutline, let mask {
            ctx.clip(to: canvas, mask: mask)
        } else if style.isClippedToFront {
            ctx.addPath(panelPath)
            ctx.clip()
        }
        ctx.setAlpha(artAlpha)
        ctx.setBlendMode(style == .tinted ? .luminosity : .normal)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { ctx.endTransparencyLayer() }
        place(in: area, offsetX: settings.offsetX, offsetY: settings.offsetY, rotation: settings.rotation)

        switch style {
        case .fill, .tinted, .cutout, .picture:
            ctx.draw(artwork, in: artRect)
        case .sticker:
            drawSticker()
        case .stamp:
            ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.003), blur: side * 0.002,
                          color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45))
            ctx.draw(artwork, in: artRect)
        }
    }

    private func drawSticker() {
        let short = min(artRect.width, artRect.height)
        let border = short * 0.04
        let radius = short * 0.08
        let card = artRect.insetBy(dx: -border, dy: -border)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.008), blur: side * 0.03,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: card, cornerWidth: radius + border, cornerHeight: radius + border, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: artRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(artwork, in: artRect)
        ctx.restoreGState()
    }

    private func place(in area: CGRect, offsetX: Double, offsetY: Double, rotation: Double) {
        ctx.translateBy(x: area.midX + offsetX * area.width, y: area.midY + offsetY * area.height)
        ctx.rotate(by: -rotation * .pi / 180)
    }

    // MARK: Geometry and artwork

    private static func scaled(_ unit: CGRect, to side: CGFloat) -> CGRect {
        CGRect(x: unit.minX * side, y: unit.minY * side, width: unit.width * side, height: unit.height * side)
    }

    private static func roundedPanel(_ panel: CGRect, side: CGFloat) -> CGPath {
        let radius = panelCorner * side
        return CGPath(roundedRect: panel, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func centered(_ image: CGImage, scale: CGFloat) -> CGRect {
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        return CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    }

    private static func artRect(for photo: CGImage, in area: CGRect, settings: MixSettings) -> CGRect {
        let widthRatio = area.width / CGFloat(photo.width)
        let heightRatio = area.height / CGFloat(photo.height)
        let baseScale: CGFloat = switch settings.style {
        case .fill, .tinted, .cutout: max(widthRatio, heightRatio)
        case .sticker, .stamp: min(widthRatio, heightRatio) * fitInset
        case .picture: min(widthRatio, heightRatio)
        }
        return centered(photo, scale: baseScale * settings.zoom)
    }

    /// The back always covers the icon, even when the front is a small sticker or stamp.
    private static func backRect(for photo: CGImage, in body: CGRect, settings: MixSettings, followsZoom: Bool) -> CGRect {
        let cover = max(body.width / CGFloat(photo.width), body.height / CGFloat(photo.height))
        return centered(photo, scale: cover * (settings.style.coversArea && followsZoom ? settings.zoom : 1))
    }

    private static func applyColor(to photo: CGImage, brightness: Double, contrast: Double,
                                   saturation: Double) -> CGImage? {
        if brightness == 0, contrast == 1, saturation == 1 { return photo }
        let filter = CIFilter.colorControls()
        filter.inputImage = CIImage(cgImage: photo)
        filter.brightness = Float(brightness)
        filter.contrast = Float(contrast)
        filter.saturation = Float(saturation)
        return filter.outputImage.flatMap(Mixer.makeCGImage)
    }

    /// Turns dark or opaque parts of the image into a darker imprint, like the glyphs on system folders.
    private static func stampArtwork(from photo: CGImage, panelColor: MixColor?, onOutline: Bool) -> CGImage? {
        let input = CIImage(cgImage: photo)
        let extent = input.extent
        let alpha = input
            .composited(over: CIImage(color: .white).cropped(to: extent))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIMaskToAlpha")
        let defaultInk = onOutline ? MixColor(red: 0.1, green: 0.1, blue: 0.12) : MixColor(red: 0.17, green: 0.53, blue: 0.78)
        let inkColor = panelColor?.darkened(by: 0.7) ?? defaultInk
        let ink = CIColor(red: inkColor.red, green: inkColor.green, blue: inkColor.blue, alpha: 1, colorSpace: Mixer.sRGB)!
        let stamped = CIImage(color: ink).cropped(to: extent)
            .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: alpha])
        return Mixer.makeCGImage(stamped)
    }
}
