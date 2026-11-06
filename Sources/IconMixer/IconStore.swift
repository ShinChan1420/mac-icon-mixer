import AppKit

/// Reads and writes icons on disk, so the model's Apply and Undo rules can be tested without real files.
protocol IconStoring {
    var genericFolderIcon: CGImage? { get }
    func icon(at url: URL) -> NSImage
    func hasCustomIcon(at url: URL) -> Bool
    func originalAppIcon(at url: URL, hasCustomIcon: Bool) -> CGImage?
    /// A copy of the current icon that stays the same after the icon on disk changes.
    func snapshot(at url: URL) -> NSImage?
    func setIcon(_ icon: NSImage?, at url: URL) -> Bool
    func refreshFinder(at url: URL)
}

extension IconStoring {
    /// An existing icon is cleared first, with Finder refreshed in between, so every change
    /// reaches Finder as a folder gaining an icon rather than a swap it could keep cached.
    func replaceIcon(at target: URL, with icon: NSImage?, previous: NSImage?, settleTime: Duration) async -> Bool {
        if previous != nil {
            guard setIcon(nil, at: target) else { return false }
            refreshFinder(at: target)
            try? await Task.sleep(for: settleTime)
        }
        defer { refreshFinder(at: target) }
        if setIcon(icon, at: target) { return true }
        if let previous { _ = setIcon(previous, at: target) }
        return false
    }
}

struct SystemIconStore: IconStoring {
    private static let side = 1024

    private var iconRect: NSRect { NSRect(x: 0, y: 0, width: Self.side, height: Self.side) }

    var genericFolderIcon: CGImage? { bitmap(of: NSWorkspace.shared.icon(for: .folder)) }

    func icon(at url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    func hasCustomIcon(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("Icon\r").path)
    }

    /// A custom icon is skipped where possible, so mixes don't stack on old mixes.
    func originalAppIcon(at url: URL, hasCustomIcon: Bool) -> CGImage? {
        let current = icon(at: url)
        guard hasCustomIcon,
              let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        else { return bitmap(of: current) }

        let file = url.appendingPathComponent("Contents/Resources").appendingPathComponent(name)
        let path = file.pathExtension.isEmpty ? file.appendingPathExtension("icns") : file
        return bitmap(of: NSImage(contentsOf: path) ?? current)
    }

    func snapshot(at url: URL) -> NSImage? {
        guard let image = bitmap(of: icon(at: url)), let copy = CGContext(
            data: nil, width: Self.side, height: Self.side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        copy.draw(image, in: iconRect)
        return copy.makeImage().map { NSImage(cgImage: $0, size: iconRect.size) }
    }

    func setIcon(_ icon: NSImage?, at url: URL) -> Bool {
        NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
    }

    /// Nudges Finder through the file system only. Don't script Finder's `update` command here:
    /// on macOS 26 running it on a folder deletes the folder's custom icon.
    func refreshFinder(at url: URL) {
        NSWorkspace.shared.noteFileSystemChanged(url.path)
        NSWorkspace.shared.noteFileSystemChanged(url.deletingLastPathComponent().path)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func bitmap(of image: NSImage) -> CGImage? {
        var rect = iconRect
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
