import CoreGraphics
import CoreImage
import Foundation
import ImageIO

public enum Mixer {
    /// Front panel of the system folder icon, as fractions of the icon (origin bottom-left).
    /// Measured from the 1024px icon: x 42...981, y 268...888 from the top.
    public static let frontPanel = CGRect(x: 0.041, y: 0.133, width: 0.917, height: 0.605)
    /// Whole folder including the tab, measured the same way: y 134...888 from the top.
    public static let folderBody = CGRect(x: 0.041, y: 0.133, width: 0.917, height: 0.736)

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let ciContext = CIContext(options: [.workingColorSpace: sRGB])
    // shortcut: not thread safe, fine while rendering stays on the main actor; add a lock if that changes.
    private static var maskCache: [(icon: CGImage, size: Int, mask: CGImage)] = []

    /// Stands in for the picture when an icon only gets a finish.
    public static let noPhoto: CGImage = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!

    /// `frontOpacity` fades the whole front layer, panel included, to reveal the second layer while it's edited.
    public static func render(icon: CGImage, photo: CGImage, settings: MixSettings, size: Int,
                              frontOpacity: Double = 1, shape: IconShape = .folder,
                              systemIsDark: Bool = false, secondPhoto: CGImage? = nil) -> CGImage? {
        IconComposition(icon: icon, photo: photo, settings: settings, size: size, frontOpacity: frontOpacity,
                        shape: shape, systemIsDark: systemIsDark, secondPhoto: secondPhoto)?.render()
    }

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
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        let fallback = IconShape(front: whole, body: whole, followsOutline: true)
        guard let mask = solidMask(of: icon, size: size), let gray = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let data = gray.data else { return fallback }

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
        guard maxX >= minX else { return fallback }

        let side = Double(size)
        let bounds = CGRect(x: Double(minX) / side, y: 1 - Double(maxRow + 1) / side,
                            width: Double(maxX - minX + 1) / side, height: Double(maxRow - minRow + 1) / side)
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

    /// Grayscale mask of the icon's solid body, taken from the icon itself.
    /// The steep ramp drops the icon's soft drop shadow, which is only partly opaque.
    static func solidMask(of icon: CGImage, size: Int) -> CGImage? {
        if let hit = maskCache.first(where: { $0.icon === icon && $0.size == size }) { return hit.mask }

        guard let rgba = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gray = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let source = rgba.data, let target = gray.data else { return nil }

        rgba.interpolationQuality = .high
        rgba.draw(icon, in: CGRect(x: 0, y: 0, width: size, height: size))
        let pixels = source.assumingMemoryBound(to: UInt8.self)
        let output = target.assumingMemoryBound(to: UInt8.self)
        for index in 0..<(size * size) {
            let alpha = Int(pixels[index * 4 + 3])
            output[index] = UInt8(max(0, min(255, (alpha - 191) * 4)))
        }
        guard let mask = gray.makeImage() else { return nil }
        if maskCache.count >= 4 { maskCache.removeFirst() }
        maskCache.append((icon, size, mask))
        return mask
    }

    static func makeCGImage(_ image: CIImage) -> CGImage? {
        ciContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB)
    }
}
