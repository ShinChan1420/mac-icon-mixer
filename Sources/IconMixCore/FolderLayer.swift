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
        guard self == .shadow else {
            select(in: &settings)
            return
        }
        let turnOn = !isSelected(in: settings)
        leaveWholeImageStyles(&settings)
        settings.panelShadow = turnOn
    }

    /// The settings to show on this option's thumbnail.
    public func applied(to settings: MixSettings) -> MixSettings {
        var result = settings
        guard self == .shadow else {
            select(in: &result)
            return result
        }
        leaveWholeImageStyles(&result)
        result.panelShadow = true
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
