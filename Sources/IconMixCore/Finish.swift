import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// A glass surface laid over the front of the icon.
public enum Finish: String, CaseIterable, Identifiable, Sendable {
    case none, liquidGlass, frosted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .liquidGlass: "Liquid Glass"
        case .frosted: "Frosted"
        }
    }
}

/// The colour of the glass. Icons saved to disk are single images, so `.auto` picks light or dark
/// when the icon is made and doesn't change later with the system appearance.
public enum GlassTone: String, CaseIterable, Identifiable, Sendable {
    case auto, light, dark, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        case .custom: "Custom"
        }
    }
}

/// Which part of the icon gets the finish.
public enum FinishTarget: String, CaseIterable, Identifiable, Sendable {
    /// One pane across the entire icon, tab included.
    case wholeIcon
    case firstLayer, secondLayer
    /// A separate pane on each layer, each with its own edge.
    case bothLayers

    public var id: String { rawValue }

    /// `object` names what's being changed, such as "Folder".
    public func title(object: String) -> String {
        switch self {
        case .wholeIcon: object
        case .firstLayer: "First"
        case .secondLayer: "Second"
        case .bothLayers: "Both"
        }
    }
}

extension Mixer {
    /// Replaces the part of `ctx` under `region` with its glass version. `region` is a grayscale
    /// mask and `bounds` its rectangle in pixels. The context must be in its default state.
    static func applyFinish(_ finish: Finish, strength: Double, tint: MixColor, to ctx: CGContext,
                            region: CGImage, bounds: CGRect) {
        guard finish != .none, let current = ctx.makeImage() else { return }
        let side = CGFloat(current.width)
        let source = CIImage(cgImage: current)
        let mask = CIImage(cgImage: region)
        let extent = source.extent

        let glass: CIImage?
        switch finish {
        case .none:
            glass = nil
        case .liquidGlass:
            glass = liquidGlass(current, region: region, mask: mask, bounds: bounds, strength: strength, tint: tint, side: side)
        case .frosted:
            glass = frosted(source, mask: mask, strength: strength, tint: tint, side: side)
        }
        guard let glass else { return }

        let result = glass
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: source,
                kCIInputMaskImageKey: mask,
            ])
            .cropped(to: extent)
        guard let image = makeCGImage(result) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: extent)
        ctx.restoreGState()
    }

    // Strength only drives blur and bending. At 0 the picture stays sharp and the surface effects
    // (edge light, sheen, tint, grain) remain.

    /// Mostly clear: bends what's behind it near the edges, with a sheen and a lit rim.
    private static func liquidGlass(_ image: CGImage, region: CGImage, mask: CIImage, bounds: CGRect,
                                    strength: Double, tint: MixColor, side: CGFloat) -> CIImage? {
        let extent = mask.extent
        let bendSigma = side * 0.03
        let height = mask.clampedToExtent().applyingGaussianBlur(sigma: bendSigma).cropped(to: extent)
        guard let heightImage = makeCGImage(height),
              let bent = refract(image, height: heightImage, amount: side * 0.07 * strength, sigma: bendSigma)
        else { return nil }

        let bentClear = CIImage(cgImage: bent).applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1 + 0.15 * strength,
            kCIInputBrightnessKey: 0.02 * strength,
        ])
        // White glass stays clear; any other tone washes over what's behind it.
        let washAlpha = tint.luma < 0.2 ? 0.35 + 0.6 * strength : 0.18 + 0.5 * strength
        let clear = tint == .white ? bentClear : wash(tint, alpha: washAlpha, extent: extent)
            .composited(over: bentClear)
        let lightness = 0.35 + 0.65 * tint.luma
        let sheen = CIFilter.linearGradient()
        sheen.point0 = CGPoint(x: bounds.midX, y: bounds.maxY)
        sheen.point1 = CGPoint(x: bounds.midX, y: bounds.maxY - bounds.height * 0.55)
        sheen.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: (0.2 + 0.2 * strength) * lightness)
        sheen.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        guard let light = sheen.outputImage?.cropped(to: extent) else { return nil }
        return rim(of: mask, width: side * 0.009, gain: (1.0 + 1.2 * strength) * (0.5 + 0.5 * tint.luma))
            .composited(over: light.composited(over: clear))
    }

    /// Blurs what's behind it under a soft white tint, with fine grain and a thin light edge.
    private static func frosted(_ source: CIImage, mask: CIImage, strength: Double, tint: MixColor,
                                side: CGFloat) -> CIImage {
        let extent = source.extent
        let blurred = strength <= 0 ? source : source.clampedToExtent()
            .applyingGaussianBlur(sigma: side * 0.026 * strength)
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.2])
            // Blur pulls in the transparency outside the icon, so keep the edge solid.
            .composited(over: source)
        let tintAlpha = tint == .white ? 0.2 + 0.18 * strength
            : (tint.luma < 0.2 ? 0.35 + 0.6 * strength : 0.2 + 0.55 * strength)
        let film = wash(tint, alpha: tintAlpha, extent: extent)
        let grainScale = max(1, side / 512)
        let grain = CIFilter.randomGenerator().outputImage!
            .transformed(by: CGAffineTransform(scaleX: grainScale, y: grainScale))
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.06 + 0.04 * strength),
            ])
        return rim(of: mask, width: side * 0.006, gain: (0.9 + 0.4 * strength) * (0.5 + 0.5 * tint.luma))
            .composited(over: grain.composited(over: film.composited(over: blurred)))
    }

    private static func wash(_ color: MixColor, alpha: Double, extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha, colorSpace: sRGB)!)
            .cropped(to: extent)
    }

    /// White light along the edges facing the top left and bottom right, like glass catching a lamp.
    private static func rim(of mask: CIImage, width: CGFloat, gain: Double) -> CIImage {
        let extent = mask.extent
        let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: width * 0.6)
        return soft
            .applyingFilter("CIDifferenceBlendMode", parameters: [
                kCIInputBackgroundImageKey: soft.transformed(by: CGAffineTransform(translationX: width, y: -width)),
            ])
            .cropped(to: extent)
            .applyingFilter("CIMaskToAlpha")
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: gain)])
    }

    /// Lens effect: pixels near an edge sample from further inside, following the slope of `height`.
    private static func refract(_ image: CGImage, height: CGImage, amount: CGFloat, sigma: CGFloat) -> CGImage? {
        let size = image.width
        guard let output = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let input = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let slope = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let target = output.data, let origin = input.data, let levels = slope.data else { return nil }

        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        for context in [output, input] {
            context.setBlendMode(.copy)
            context.draw(image, in: frame)
        }
        slope.draw(height, in: frame)

        let destination = target.assumingMemoryBound(to: UInt8.self)
        let pixels = origin.assumingMemoryBound(to: UInt8.self)
        let heights = levels.assumingMemoryBound(to: UInt8.self)
        // Measuring the slope across a wide span keeps 8-bit heights from stepping into jagged edges.
        let span = max(2, Int(sigma / 2))
        let rowSpan = span * size
        let factor = Double(amount) / 306 // a blurred edge rises about 102 levels across this span, summed 3 times
        let limit = Double(size - 2)
        for y in (span + 1)..<(size - span - 1) {
            for x in (span + 1)..<(size - span - 1) {
                let index = y * size + x
                // Three neighbouring spans together give a finer slope than one 8-bit difference.
                var dx = 0, dy = 0
                for step in -1...1 {
                    dx += Int(heights[index + span + step]) - Int(heights[index - span - step])
                    dy += Int(heights[index + rowSpan + step * size]) - Int(heights[index - rowSpan - step * size])
                }
                if dx == 0, dy == 0 { continue }
                let sourceX = min(limit, max(0, Double(x) + Double(dx) * factor))
                let sourceY = min(limit, max(0, Double(y) + Double(dy) * factor))
                let left = Int(sourceX), top = Int(sourceY)
                let fx = sourceX - Double(left), fy = sourceY - Double(top)
                let corner = (top * size + left) * 4
                let below = corner + size * 4
                for channel in 0..<4 {
                    let upper = Double(pixels[corner + channel]) * (1 - fx) + Double(pixels[corner + 4 + channel]) * fx
                    let lower = Double(pixels[below + channel]) * (1 - fx) + Double(pixels[below + 4 + channel]) * fx
                    destination[index * 4 + channel] = UInt8(upper * (1 - fy) + lower * fy)
                }
            }
        }
        return output.makeImage()
    }
}
