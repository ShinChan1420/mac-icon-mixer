import AppKit
import SwiftUI

/// One picture going into the mix. All three sources share this card.
struct SourceCard<Extra: View>: View {
    let title: String
    let hint: String
    let symbol: String
    let caption: String?
    let image: NSImage?
    var isEnabled = true
    let drop: ([NSItemProvider]) -> Bool
    let pick: () -> Void
    @ViewBuilder let extra: () -> Extra

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(caption ?? hint)
                .font(.callout)
                .foregroundStyle(caption == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Button(caption == nil ? "Choose…" : "Change…", action: pick)
                    .systemGlassButton()
                    .fixedSize()
                extra()
            }
            .controlSize(.small)
        }
        .padding(Metric.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Metric.cardCorner)
                .fill(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)))
            if isTargeted || caption == nil {
                RoundedRectangle(cornerRadius: Metric.cardCorner)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { isEnabled && drop($0) }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
