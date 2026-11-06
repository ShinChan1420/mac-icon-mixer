import AppKit
import SwiftUI

struct LayerTile: View {
    let title: String
    let image: NSImage?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().interpolation(.high)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 46, height: 46)
                Text(title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 26, alignment: .top)
            }
            .padding(.top, 6)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(isHovered ? 0.18 : 0.1),
                        in: RoundedRectangle(cornerRadius: Metric.tileCorner))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.tileCorner)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: isHovered && isEnabled && !reduceMotion ? -1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// The icon on a light or dark ground, as it will look in that mode.
struct TonePreview: View {
    let title: String
    let image: NSImage
    let ground: Color
    let ink: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 60, height: 60)
            Text(title)
                .font(.caption2)
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(ground, in: RoundedRectangle(cornerRadius: Metric.tileCorner))
    }
}
