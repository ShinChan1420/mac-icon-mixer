import AppKit
import IconMixCore
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class MixerModel {
    private struct Undo {
        let target: URL
        /// nil means the target had its default icon before.
        let previousIcon: NSImage?
    }

    private static let previewSize = 512
    private static let thumbnailSize = 160
    private static let tonePreviewSize = 192
    private static let iconSize = 1024
    private static let editingFrontOpacity = 0.4

    private(set) var targetURL: URL?
    private(set) var targetIsApp = false
    private(set) var iconShape = IconShape.folder
    private(set) var targetIcon: NSImage?
    private(set) var targetHasCustomIcon = false
    private(set) var preview: NSImage?
    private(set) var layerThumbnails: [FolderLayer: NSImage] = [:]
    /// How the icon looks in each mode, shown while the tone is Auto.
    private(set) var tonePreviews: (light: NSImage, dark: NSImage)?
    private(set) var message: String?
    private(set) var messageIsError = false
    private(set) var isApplying = false

    var isAdjusting = false
    /// Which layer the Adjust panel is showing.
    var adjustingLayer = EditLayer.front
    /// Auto glass follows this, and icons applied with Auto are swapped to match.
    var systemIsDark = false {
        didSet {
            guard systemIsDark != oldValue else { return }
            refreshPreview()
            syncAutoIcons()
        }
    }
    /// While true the preview fades the front layer. Apply and the thumbnails ignore this.
    var isEditingBack = false {
        didSet { if isEditingBack != oldValue { refreshPreview() } }
    }
    var settings = MixSettings() {
        didSet { if settings != oldValue { refreshPreview() } }
    }

    private let store: IconStoring
    private let keeper: AutoIconKeeper
    private let finderSettleTime: Duration
    private let genericFolder: CGImage?
    private var appIcon: CGImage?
    private var image: LoadedImage?
    private var secondImage: LoadedImage?
    private var undo: Undo?

    init(store: IconStoring = SystemIconStore(), finderSettleTime: Duration = .milliseconds(400),
         autoIconFolder: URL = AutoIconKeeper.defaultFolder) {
        self.store = store
        self.keeper = AutoIconKeeper(store: store, folder: autoIconFolder, settleTime: finderSettleTime)
        self.finderSettleTime = finderSettleTime
        self.genericFolder = store.genericFolderIcon
    }

    // MARK: State for the views

    var imageName: String? { image?.name }
    var imageThumbnail: NSImage? { image?.displayImage }
    var secondImageName: String? { secondImage?.name }
    var secondImageThumbnail: NSImage? { secondImage?.displayImage }
    var hasImage: Bool { image != nil }
    /// True when the icon has a light and a dark version that follow the Mac's mode.
    var followsSystem: Bool {
        settings.glassTone == .auto && settings.finish != .none && settings.style != .picture
    }
    /// True while icons need swapping, so the app stays open with its window closed.
    var keepsIconsInSync: Bool { keeper.hasIcons }
    var canUndo: Bool { undo != nil }
    var objectName: String { targetIsApp ? "App" : "Folder" }
    /// True when the current look has separate layers.
    var hasLayers: Bool { !targetIsApp && settings.style.hasBackOptions }
    var secondLayerIsPicture: Bool { hasLayers && settings.canEditBack }
    var secondLayerHasContent: Bool { secondLayerIsPicture || (hasLayers && settings.back == .color) }
    /// An app can take a finish on its own icon with no image; everything else needs a picture.
    var isReady: Bool { targetURL != nil && (hasImage || (targetIsApp && settings.finish != .none)) }

    func isAvailable(_ layer: FolderLayer) -> Bool {
        (!targetIsApp || layer.worksOnApps) && (hasImage || layer == .original)
    }

    // MARK: Input

    /// Takes any dropped or picked file and fills the matching source, whichever card it landed on.
    func accept(_ dropped: URL) {
        let url = dropped.resolvingSymlinksInPath()
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
        let isApp = values?.contentType?.conforms(to: .applicationBundle) == true
        if values?.isDirectory == true, values?.isPackage != true || isApp {
            setTarget(url, isApp: isApp)
            return
        }
        guard values?.contentType?.conforms(to: .image) == true,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            show("“\(url.lastPathComponent)” isn't a folder, an app or an image.", isError: true)
            return
        }
        setImage(source, name: url.lastPathComponent)
    }

    func accept(imageData data: Data) {
        guard let source = imageSource(from: data) else { return }
        setImage(source, name: "Dropped image")
    }

    /// Fills the second layer with its own picture.
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
        guard let source = imageSource(from: data) else { return }
        setSecondImage(source, name: "Dropped image")
    }

    func removeImage() {
        image = nil
        var next = settings
        next.style = .fill
        commit(next)
    }

    func removeSecondImage() {
        secondImage = nil
        refreshPreview()
    }

    private func imageSource(from data: Data) -> CGImageSource? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            show("That drag didn't contain a readable image.", isError: true)
            return nil
        }
        return source
    }

    private func setTarget(_ url: URL, isApp: Bool) {
        targetURL = url
        undo = nil
        reloadTargetIcon()
        targetIsApp = isApp
        appIcon = isApp ? store.originalAppIcon(at: url, hasCustomIcon: targetHasCustomIcon) : nil
        iconShape = appIcon.map(Mixer.shape(ofIcon:)) ?? .folder
        clearMessage()

        var next = settings
        if isApp {
            next.back = .folder
            next.panelShadow = false
            adjustingLayer = .front
            if !hasImage { next.style = .fill }
        }
        commit(next)
    }

    private func setImage(_ source: CGImageSource, name: String) {
        guard let loaded = LoadedImage(source: source, name: name) else {
            show("Couldn't read “\(name)”.", isError: true)
            return
        }
        image = loaded
        clearMessage()
        var next = settings.withoutAdjustments()
        next.backColor = Mixer.averageColor(of: loaded.preview)
        commit(next)
    }

    private func setSecondImage(_ source: CGImageSource, name: String) {
        guard let loaded = LoadedImage(source: source, name: name) else {
            show("Couldn't read “\(name)”.", isError: true)
            return
        }
        secondImage = loaded
        clearMessage()
        var next = settings
        next.centerBackPicture()
        commit(next)
    }

    /// One redraw for a batch of changes, including when only the images changed.
    private func commit(_ next: MixSettings) {
        guard next != settings else {
            refreshPreview()
            return
        }
        settings = next
    }

    // MARK: Actions

    func apply() {
        guard !isApplying, isReady, let targetURL,
              let mixed = render(size: Self.iconSize, photo: \.full, settings: settings)
        else { return }

        let isApp = targetIsApp
        let isDark = systemIsDark
        let versions = followsSystem ? autoVersions() : nil
        let previous = targetHasCustomIcon ? store.snapshot(at: targetURL) : nil
        let icon = NSImage(cgImage: mixed, size: NSSize(width: Self.iconSize, height: Self.iconSize))
        let name = targetURL.lastPathComponent
        isApplying = true
        Task {
            defer { isApplying = false }
            guard await store.replaceIcon(at: targetURL, with: icon, previous: previous,
                                          settleTime: finderSettleTime) else {
                show(isApp
                     ? "macOS didn't allow changing “\(name)”. System apps can't be changed. For others, allow Icon Mixer in Privacy & Security > App Management."
                     : "Couldn't change the icon of “\(name)”. Check that you have write access to it.",
                     isError: true)
                return
            }
            undo = Undo(target: targetURL, previousIcon: previous)
            reloadTargetIcon()
            let applied = isApp ? "Applied to “\(name)”. Quit and reopen it to update the Dock." : "Applied to “\(name)”."
            show(applied)
            keepOrForget(targetURL, versions: versions, isDark: isDark, applied: applied)
        }
    }

    private func autoVersions() -> (light: CGImage, dark: CGImage)? {
        guard let light = render(size: Self.iconSize, photo: \.full, settings: settings, isDark: false),
              let dark = render(size: Self.iconSize, photo: \.full, settings: settings, isDark: true)
        else { return nil }
        return (light, dark)
    }

    private func keepOrForget(_ target: URL, versions: (light: CGImage, dark: CGImage)?, isDark: Bool, applied: String) {
        guard let versions else {
            keeper.remove(target)
            return
        }
        do {
            try keeper.keep(target, light: versions.light, dark: versions.dark, showsDark: isDark)
            show("\(applied) It follows Light and Dark while Icon Mixer is running.")
        } catch {
            show("\(applied) It can't follow Light and Dark: \(error.localizedDescription)", isError: true)
        }
    }

    /// Swaps kept icons to the current mode. Also runs at launch, in case the mode changed while the app was closed.
    func syncAutoIcons() {
        guard keeper.hasIcons else { return }
        let isDark = systemIsDark
        Task {
            await keeper.sync(isDark: isDark)
            reloadTargetIcon()
        }
    }

    func undoApply() {
        guard !isApplying, let undo else { return }
        let current = targetHasCustomIcon ? store.snapshot(at: undo.target) : nil
        isApplying = true
        Task {
            defer { isApplying = false }
            guard await store.replaceIcon(at: undo.target, with: undo.previousIcon, previous: current,
                                          settleTime: finderSettleTime) else {
                show("Couldn't restore the previous icon.", isError: true)
                return
            }
            keeper.remove(undo.target)
            self.undo = nil
            reloadTargetIcon()
            show("Restored the previous icon.")
        }
    }

    func removeCustomIcon() {
        guard let targetURL else { return }
        let previous = store.snapshot(at: targetURL)
        guard store.setIcon(nil, at: targetURL) else {
            show("Couldn't remove the custom icon.", isError: true)
            return
        }
        keeper.remove(targetURL)
        undo = Undo(target: targetURL, previousIcon: previous)
        reloadTargetIcon()
        show("Removed the custom icon.")
        store.refreshFinder(at: targetURL)
    }

    /// Throws away the pending mix. Nothing on disk changes.
    func discard() {
        targetURL = nil
        targetIsApp = false
        appIcon = nil
        iconShape = .folder
        targetIcon = nil
        targetHasCustomIcon = false
        image = nil
        secondImage = nil
        undo = nil
        isAdjusting = false
        clearMessage()
        commit(MixSettings())
    }

    func resetAdjustments() {
        settings = settings.withoutAdjustments()
    }

    func choose(_ layer: FolderLayer) {
        layer.choose(in: &settings)
        // Its position sliders live in the Adjust panel.
        guard layer == .differentPosition else { return }
        isAdjusting = true
        adjustingLayer = .back
    }

    // MARK: Rendering

    /// The icon the picture is mixed onto: the plain folder, or the chosen app's icon.
    private var baseIcon: CGImage? { targetIsApp ? appIcon : genericFolder }

    private func render(size: Int, photo: KeyPath<LoadedImage, CGImage>, settings: MixSettings,
                        frontOpacity: Double = 1, isDark: Bool? = nil) -> CGImage? {
        guard targetURL != nil, let baseIcon else { return nil }
        guard let picture = image?[keyPath: photo] ?? (targetIsApp ? Mixer.noPhoto : nil) else { return nil }
        return Mixer.render(icon: baseIcon, photo: picture, settings: settings, size: size,
                            frontOpacity: frontOpacity, shape: iconShape, systemIsDark: isDark ?? systemIsDark,
                            secondPhoto: secondImage?[keyPath: photo])
    }

    private func refreshPreview() {
        let frontOpacity = isEditingBack ? Self.editingFrontOpacity : 1
        guard let mixed = render(size: Self.previewSize, photo: \.preview, settings: settings,
                                 frontOpacity: frontOpacity) else {
            preview = nil
            layerThumbnails = [:]
            tonePreviews = nil
            return
        }
        preview = NSImage(cgImage: mixed, size: NSSize(width: Self.previewSize, height: Self.previewSize))
        refreshThumbnails()
        refreshTonePreviews()
    }

    private func refreshTonePreviews() {
        guard followsSystem,
              let light = render(size: Self.tonePreviewSize, photo: \.thumbnail, settings: settings, isDark: false),
              let dark = render(size: Self.tonePreviewSize, photo: \.thumbnail, settings: settings, isDark: true)
        else {
            tonePreviews = nil
            return
        }
        let size = NSSize(width: Self.tonePreviewSize, height: Self.tonePreviewSize)
        tonePreviews = (NSImage(cgImage: light, size: size), NSImage(cgImage: dark, size: size))
    }

    private func refreshThumbnails() {
        var thumbnails: [FolderLayer: NSImage] = [:]
        for layer in FolderLayer.allCases {
            guard let mixed = render(size: Self.thumbnailSize, photo: \.thumbnail,
                                     settings: layer.applied(to: settings)) else { continue }
            thumbnails[layer] = NSImage(cgImage: mixed, size: NSSize(width: Self.thumbnailSize, height: Self.thumbnailSize))
        }
        layerThumbnails = thumbnails
    }

    private func reloadTargetIcon() {
        guard let targetURL else { return }
        targetIcon = store.icon(at: targetURL)
        targetHasCustomIcon = store.hasCustomIcon(at: targetURL)
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
