import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Spacing and corner sizes shared across the window, so everything lines up on one system.
enum Metric {
    static let edge: CGFloat = 20
    static let gap: CGFloat = 12
    static let sourceWidth: CGFloat = 304
    static let lookWidth: CGFloat = 348
    static let labelWidth: CGFloat = 64
    static let rowHeight: CGFloat = 26
    static let wellWidth: CGFloat = 48
    /// The control beside a colour well: the row's width, less the label, the well and their gaps.
    static let besideWellWidth: CGFloat = lookWidth - edge * 2 - labelWidth - wellWidth - 16
    static let cardCorner: CGFloat = 12
    static let tileCorner: CGFloat = 10
}

/// Reads dragged files or image data, handing each to the matching callback on the main actor.
@MainActor
func loadDrop(_ providers: [NSItemProvider], url handleURL: @escaping @MainActor (URL) -> Void,
                      data handleData: @escaping @MainActor (Data) -> Void) -> Bool {
    var accepted = false
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in handleURL(url) }
            }
            continue
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
        accepted = true
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in handleData(data) }
        }
    }
    return accepted
}

extension View {
    /// Lets a button or menu fill the width it's given.
    @ViewBuilder func buttonSizingFlexible() -> some View {
        if #available(macOS 26, *) {
            buttonSizing(.flexible)
        } else {
            self
        }
    }

    /// Stretches a segmented control to its column, so it ends on the same edge as the rest.
    @ViewBuilder func fullWidthSegments() -> some View {
        if #available(macOS 26, *) {
            buttonSizing(.flexible).frame(maxWidth: .infinity)
        } else {
            frame(maxWidth: .infinity)
        }
    }

    /// Apple's Liquid Glass button styles on macOS 26, and the matching classic styles before it.
    @ViewBuilder func systemGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Hides a control but keeps its space, so showing it never moves anything around it.
    func reservingSpace(visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .disabled(!visible)
            .accessibilityHidden(!visible)
    }
}
