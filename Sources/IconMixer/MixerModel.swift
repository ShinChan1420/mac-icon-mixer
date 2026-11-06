import AppKit
import IconMixCore
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class MixerModel {
    private struct Undo {
        let folder: URL
        /// nil means the folder had the default icon before.
        let previousIcon: NSImage?
    }

    private static let previewPixels = 768
    private static let fullPixels = 2048
    private static let previewSize = 512
    private static let thumbnailPixels = 256
    private static let editingFrontOpacity = 0.4
    private static let finderSettleTime = Duration.milliseconds(400)
    private static let thumbnailSize = 160
    private static let iconSize = 1024

    private(set) var folderURL: URL?
    private(set) var targetIsApp = false
    private(set) var iconShape = IconShape.folder
    private(set) var folderIcon: NSImage?
    private(set) var folderHasCustomIcon = false
    private(set) var imageName: String?
    private(set) var imageThumbnail: NSImage?
    private(set) var secondImageName: String?
    private(set) var secondImageThumbnail: NSImage?
    private(set) var preview: NSImage?
    private(set) var layerThumbnails: [FolderLayer: NSImage] = [:]
    private(set) var message: String?
    private(set) var messageIsError = false
    private(set) var isApplying = false

    var isAdjusting = false
    /// Auto glass follows this. Icons on disk are single images, so it's baked in at Apply.
    var systemIsDark = false {
        didSet { if systemIsDark != oldValue { refreshPreview() } }
    }
    /// Which layer the Adjust panel is showing.
    var adjustingLayer = EditLayer.front
    /// While true the preview fades the front layer. Apply and the thumbnails ignore this.
    var isEditingBack = false {
        didSet { if isEditingBack != oldValue { refreshPreview() } }
    }
    var settings = MixSettings() {
        didSet { if settings != oldValue { refreshPreview() } }
    }

    var canUndo: Bool { undo != nil }
    /// True when the current look has separate layers the finish can be aimed at.
    var hasLayers: Bool { !targetIsApp && settings.style.hasBackOptions }
    var objectName: String { targetIsApp ? "App" : "Folder" }
    var hasImage: Bool { previewPhoto != nil }
    /// An app can take a finish on its own icon with no image; everything else needs a picture.
    var isReady: Bool { folderURL != nil && (hasImage || (targetIsApp && settings.finish != .none)) }
    /// What the mix uses for the picture, or nil when there isn't enough to show a preview.
    private func picture(_ photo: CGImage?) -> CGImage? { photo ?? (targetIsApp ? Mixer.noPhoto : nil) }

    private var previewPhoto: CGImage?
    private var fullPhoto: CGImage?
    private var thumbnailPhoto: CGImage?
    private var secondFull: CGImage?
    private var secondPreview: CGImage?
    private var secondThumbnail: CGImage?
    private var undo: Undo?

    private let genericFolder: CGImage? = {
        let icon = NSWorkspace.shared.icon(for: .folder)
        var rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }()
    /// What the picture is mixed onto: the plain folder, or the chosen app's icon.
    private var appIcon: CGImage?
    private var baseFolder: CGImage? { targetIsApp ? appIcon : genericFolder }

    // MARK: Input

    /// Takes any dropped or picked file and fills the matching well, whichever side it landed on.
    func accept(_ dropped: URL) {
        let url = dropped.resolvingSymlinksInPath()
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
        let isApp = values?.contentType?.conforms(to: .applicationBundle) == true
        if values?.isDirectory == true, values?.isPackage != true || isApp {
            setFolder(url, isApp: isApp)
        } else if values?.contentType?.conforms(to: .image) == true,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            setImage(source, name: url.lastPathComponent)
        } else {
            show("“\(url.lastPathComponent)” isn't a folder, an app or an image.", isError: true)
        }
    }

    func accept(imageData data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            show("That drag didn't contain a readable image.", isError: true)
            return
        }
        setImage(source, name: "Dropped image")
    }

    /// Fills the second layer with its own picture, centred and ready to adjust.
    func acceptSecond(_ dropped: URL) {
        let url = dropped.resolvingSymlinksInPath()
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        guard type?.conforms(to: .image) == true, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            show("“\(url.lastPathComponent)” isn't an image.", isError: true)
            return
        }
        setSecondImage(source, name: url.lastPathComponent)
    }

    func acceptSecond(imageData data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            show("That drag didn't contain a readable image.", isError: true)
            return
        }
        setSecondImage(source, name: "Dropped image")
    }

    private func setSecondImage(_ source: CGImageSource, name: String) {
        guard let full = Mixer.decode(source, maxPixels: Self.fullPixels),
              let small = Mixer.decode(source, maxPixels: Self.previewPixels) else {
            show("Couldn't read “\(name)”.", isError: true)
            return
        }
        secondFull = full
        secondPreview = small
        secondThumbnail = Mixer.decode(source, maxPixels: Self.thumbnailPixels)
        secondImageName = name
        secondImageThumbnail = NSImage(cgImage: small, size: .zero)
        settings.back = .differentPosition
        settings.backOffsetX = 0
        settings.backOffsetY = 0
        settings.backRotation = 0
        settings.backZoom = 1
        clearMessage()
        refreshPreview()
    }

    func removeSecondImage() {
        secondFull = nil
        secondPreview = nil
        secondThumbnail = nil
        secondImageName = nil
        secondImageThumbnail = nil
        refreshPreview()
    }

    func removeImage() {
        fullPhoto = nil
        previewPhoto = nil
        thumbnailPhoto = nil
        imageName = nil
        imageThumbnail = nil
        settings.style = .fill
        refreshPreview()
    }

    private func setFolder(_ url: URL, isApp: Bool) {
        folderURL = url
        undo = nil
        reloadFolderIcon()
        targetIsApp = isApp
        appIcon = isApp ? originalAppIcon(of: url) : nil
        iconShape = appIcon.map(Mixer.shape(ofIcon:)) ?? .folder
        if isApp {
            settings.back = .folder
            settings.panelShadow = false
            adjustingLayer = .front
            if !hasImage { settings.style = .fill }
        }
        clearMessage()
        refreshPreview()
    }

    private func setImage(_ source: CGImageSource, name: String) {
        guard let full = Mixer.decode(source, maxPixels: Self.fullPixels),
              let small = Mixer.decode(source, maxPixels: Self.previewPixels) else {
            show("Couldn't read “\(name)”.", isError: true)
            return
        }
        fullPhoto = full
        previewPhoto = small
        thumbnailPhoto = Mixer.decode(source, maxPixels: Self.thumbnailPixels)
        imageName = name
        imageThumbnail = NSImage(cgImage: small, size: .zero)
        var fresh = MixSettings()
        fresh.style = settings.style
        fresh.frontColor = settings.frontColor
        fresh.finish = settings.finish
        fresh.finishStrength = settings.finishStrength
        fresh.finishTarget = settings.finishTarget
        fresh.glassTone = settings.glassTone
        fresh.glassColor = settings.glassColor
        fresh.back = settings.back
        fresh.panelShadow = settings.panelShadow
        fresh.backColor = Mixer.averageColor(of: small)
        settings = fresh
        clearMessage()
        refreshPreview()
    }

    // MARK: Actions

    func apply() {
        guard !isApplying, isReady, let folderURL, let baseFolder, let photo = picture(fullPhoto),
              let mixed = Mixer.render(folder: baseFolder, photo: photo, settings: settings, size: Self.iconSize,
                                       shape: iconShape, systemIsDark: systemIsDark, secondPhoto: secondFull)
        else { return }

        let previous = folderHasCustomIcon ? iconSnapshot(of: folderURL) : nil
        let icon = NSImage(cgImage: mixed, size: NSSize(width: Self.iconSize, height: Self.iconSize))
        isApplying = true
        Task {
            defer { isApplying = false }
            guard await replaceIcon(of: folderURL, with: icon, previous: previous) else {
                show(targetIsApp
                     ? "macOS didn't allow changing “\(folderURL.lastPathComponent)”. System apps can't be changed. For others, allow Icon Mixer in Privacy & Security > App Management."
                     : "Couldn't change the icon of “\(folderURL.lastPathComponent)”. Check that you have write access to it.",
                     isError: true)
                return
            }
            undo = Undo(folder: folderURL, previousIcon: previous)
            reloadFolderIcon()
            show(targetIsApp
                 ? "Applied to “\(folderURL.lastPathComponent)”. Quit and reopen it to update the Dock."
                 : "Applied to “\(folderURL.lastPathComponent)”.")
        }
    }

    func undoApply() {
        guard !isApplying, let undo else { return }
        let current = folderHasCustomIcon ? iconSnapshot(of: undo.folder) : nil
        isApplying = true
        Task {
            defer { isApplying = false }
            guard await replaceIcon(of: undo.folder, with: undo.previousIcon, previous: current) else {
                show("Couldn't restore the previous icon.", isError: true)
                return
            }
            self.undo = nil
            reloadFolderIcon()
            show("Restored the previous icon.")
        }
    }

    /// An existing icon is cleared first, with Finder refreshed in between, so every change
    /// reaches Finder as a folder gaining an icon rather than a swap it could keep cached.
    private func replaceIcon(of folder: URL, with icon: NSImage?, previous: NSImage?) async -> Bool {
        if previous != nil {
            guard NSWorkspace.shared.setIcon(nil, forFile: folder.path, options: []) else { return false }
            refreshFinder(folder)
            try? await Task.sleep(for: Self.finderSettleTime)
        }
        guard NSWorkspace.shared.setIcon(icon, forFile: folder.path, options: []) else {
            if let previous { NSWorkspace.shared.setIcon(previous, forFile: folder.path, options: []) }
            refreshFinder(folder)
            return false
        }
        refreshFinder(folder)
        return true
    }

    func removeCustomIcon() {
        guard let folderURL else { return }
        let previous = iconSnapshot(of: folderURL)
        guard NSWorkspace.shared.setIcon(nil, forFile: folderURL.path, options: []) else {
            show("Couldn't remove the custom icon.", isError: true)
            return
        }
        undo = Undo(folder: folderURL, previousIcon: previous)
        reloadFolderIcon()
        show("Removed the custom icon.")
        refreshFinder(folderURL)
    }

    /// Throws away the pending mix. Nothing on disk changes.
    func discard() {
        folderURL = nil
        targetIsApp = false
        appIcon = nil
        iconShape = .folder
        folderIcon = nil
        folderHasCustomIcon = false
        imageName = nil
        imageThumbnail = nil
        previewPhoto = nil
        fullPhoto = nil
        thumbnailPhoto = nil
        secondFull = nil
        secondPreview = nil
        secondThumbnail = nil
        secondImageName = nil
        secondImageThumbnail = nil
        preview = nil
        layerThumbnails = [:]
        undo = nil
        isAdjusting = false
        settings = MixSettings()
        clearMessage()
    }

    func resetAdjustments() {
        var fresh = MixSettings()
        fresh.style = settings.style
        fresh.frontColor = settings.frontColor
        fresh.finish = settings.finish
        fresh.finishStrength = settings.finishStrength
        fresh.finishTarget = settings.finishTarget
        fresh.glassTone = settings.glassTone
        fresh.glassColor = settings.glassColor
        fresh.back = settings.back
        fresh.backColor = settings.backColor
        fresh.panelShadow = settings.panelShadow
        settings = fresh
    }

    func choose(_ layer: FolderLayer) {
        layer.choose(in: &settings)
        // Its position sliders live in the Adjust panel.
        if layer == .differentPosition {
            isAdjusting = true
            adjustingLayer = .back
        }
    }

    // MARK: Helpers

    /// The app's own icon. A custom icon is skipped where possible, so mixes don't stack on old mixes.
    private func originalAppIcon(of app: URL) -> CGImage? {
        var image = NSWorkspace.shared.icon(forFile: app.path)
        if folderHasCustomIcon, let name = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let file = app.appendingPathComponent("Contents/Resources").appendingPathComponent(name)
            let path = file.pathExtension.isEmpty ? file.appendingPathExtension("icns") : file
            image = NSImage(contentsOf: path) ?? image
        }
        var rect = NSRect(x: 0, y: 0, width: Self.iconSize, height: Self.iconSize)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// The workspace icon reads from the folder when drawn, so undo needs its pixels copied out
    /// before the icon on disk changes.
    private func iconSnapshot(of folder: URL) -> NSImage? {
        var rect = NSRect(x: 0, y: 0, width: Self.iconSize, height: Self.iconSize)
        guard let image = NSWorkspace.shared.icon(forFile: folder.path)
            .cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let copy = CGContext(
                data: nil, width: Self.iconSize, height: Self.iconSize, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        copy.draw(image, in: CGRect(x: 0, y: 0, width: Self.iconSize, height: Self.iconSize))
        return copy.makeImage().map { NSImage(cgImage: $0, size: rect.size) }
    }

    /// Nudges Finder through the file system only. Don't script Finder's `update` command here:
    /// on macOS 26 running it on a folder deletes the folder's custom icon.
    private func refreshFinder(_ folder: URL) {
        NSWorkspace.shared.noteFileSystemChanged(folder.path)
        NSWorkspace.shared.noteFileSystemChanged(folder.deletingLastPathComponent().path)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: folder.path)
    }

    private func reloadFolderIcon() {
        guard let folderURL else { return }
        folderIcon = NSWorkspace.shared.icon(forFile: folderURL.path)
        folderHasCustomIcon = FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("Icon\r").path)
    }

    private func refreshPreview() {
        guard folderURL != nil, let photo = picture(previewPhoto), let baseFolder,
              let mixed = Mixer.render(folder: baseFolder, photo: photo, settings: settings, size: Self.previewSize,
                                       frontOpacity: isEditingBack ? Self.editingFrontOpacity : 1, shape: iconShape,
                                       systemIsDark: systemIsDark, secondPhoto: secondPreview)
        else {
            preview = nil
            layerThumbnails = [:]
            return
        }
        preview = NSImage(cgImage: mixed, size: NSSize(width: Self.previewSize, height: Self.previewSize))
        refreshThumbnails(folder: baseFolder)
    }

    private func refreshThumbnails(folder: CGImage) {
        guard let photo = picture(thumbnailPhoto) else { return }
        var thumbnails: [FolderLayer: NSImage] = [:]
        for layer in FolderLayer.allCases {
            if let image = Mixer.render(folder: folder, photo: photo,
                                        settings: layer.applied(to: settings), size: Self.thumbnailSize,
                                        shape: iconShape, systemIsDark: systemIsDark, secondPhoto: secondThumbnail) {
                thumbnails[layer] = NSImage(cgImage: image, size: NSSize(width: Self.thumbnailSize, height: Self.thumbnailSize))
            }
        }
        layerThumbnails = thumbnails
    }

    private func show(_ text: String, isError: Bool = false) {
        message = text
        messageIsError = isError
    }

    private func clearMessage() {
        message = nil
        messageIsError = false
    }
}
