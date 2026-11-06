import CoreGraphics
import Foundation

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

    /// Styles drawn on top of a glass finish, so they stay sharp.
    var sitsOnGlass: Bool { self == .sticker || self == .stamp }

    /// Styles trimmed to the front of the icon.
    var isClippedToFront: Bool { self == .fill || self == .tinted || self == .stamp }
}

/// Where the picture goes on an icon. Fractions of the icon, origin bottom-left.
public struct IconShape: Equatable, Sendable {
    public static let folder = IconShape(front: Mixer.frontPanel, body: Mixer.folderBody, followsOutline: false)

    public var front: CGRect
    public var body: CGRect
    /// True for icons with no front panel, such as apps: the picture is trimmed to the icon's own outline.
    public var followsOutline: Bool
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
    public var glassTone: GlassTone = .auto
    public var glassColor = MixColor(red: 0.2, green: 0.55, blue: 0.9)

    public init() {}
}

/// The layer a drag or pinch acts on.
public enum EditLayer: Sendable {
    case front, back
}

extension MixSettings {
    /// Clears position and photo adjustments on both layers, keeping the chosen look.
    public func withoutAdjustments() -> MixSettings {
        var fresh = MixSettings()
        fresh.style = style
        fresh.frontColor = frontColor
        fresh.finish = finish
        fresh.finishStrength = finishStrength
        fresh.finishTarget = finishTarget
        fresh.glassTone = glassTone
        fresh.glassColor = glassColor
        fresh.back = back
        fresh.backColor = backColor
        fresh.panelShadow = panelShadow
        return fresh
    }

    /// Puts a picture of its own on the second layer, centred and ready to adjust.
    public mutating func centerBackPicture() {
        back = .differentPosition
        backOffsetX = 0
        backOffsetY = 0
        backRotation = 0
        backZoom = 1
    }

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
