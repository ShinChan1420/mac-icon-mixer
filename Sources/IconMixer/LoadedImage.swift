import AppKit
import IconMixCore

/// A picture decoded at the sizes the app draws it: for Apply, the preview and the tiles.
struct LoadedImage {
    private static let fullPixels = 2048
    private static let previewPixels = 768
    private static let thumbnailPixels = 256

    let name: String
    let full: CGImage
    let preview: CGImage
    let thumbnail: CGImage
    let displayImage: NSImage

    init?(source: CGImageSource, name: String) {
        guard let full = Mixer.decode(source, maxPixels: Self.fullPixels),
              let preview = Mixer.decode(source, maxPixels: Self.previewPixels),
              let thumbnail = Mixer.decode(source, maxPixels: Self.thumbnailPixels)
        else { return nil }
        self.name = name
        self.full = full
        self.preview = preview
        self.thumbnail = thumbnail
        self.displayImage = NSImage(cgImage: preview, size: .zero)
    }
}
