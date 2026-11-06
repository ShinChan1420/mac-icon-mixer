import AppKit
import IconMixCore
import SwiftUI

/// The mixed icon. Dragging moves a layer and pinching zooms it; the strip above the
/// front panel controls the second layer, everywhere else controls the front picture.
struct DraggablePreview: View {
    let image: NSImage
    let model: MixerModel

    @State private var lastTranslation = CGSize.zero
    @State private var dragLayer: EditLayer?
    @State private var pinchLayer: EditLayer?
    @State private var pinchStartZoom = 1.0
    @State private var hoveredLayer: EditLayer?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let top = (geometry.size.height - side) / 2
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard model.settings.finish != .none else { return }
                    model.settings.toggleGlassTone(systemIsDark: model.systemIsDark)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hoveredLayer = layer(atY: point.y, top: top, side: side)
                    case .ended: hoveredLayer = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let target = dragLayer ?? layer(atY: value.startLocation.y, top: top, side: side)
                            dragLayer = target
                            if target == .back { model.isEditingBack = true }
                            let dx = value.translation.width - lastTranslation.width
                            let dy = value.translation.height - lastTranslation.height
                            lastTranslation = value.translation
                            model.settings.move(target, dx: dx / side, dy: -dy / side, shape: model.iconShape)
                        }
                        .onEnded { _ in
                            lastTranslation = .zero
                            dragLayer = nil
                            model.isEditingBack = pinchLayer == .back
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let target: EditLayer
                            if let pinchLayer {
                                target = pinchLayer
                            } else {
                                target = hoveredLayer ?? .front
                                pinchLayer = target
                                pinchStartZoom = model.settings.zoom(of: target)
                            }
                            if target == .back { model.isEditingBack = true }
                            model.settings.setZoom(pinchStartZoom * value.magnification, of: target)
                        }
                        .onEnded { _ in
                            pinchLayer = nil
                            model.isEditingBack = dragLayer == .back
                        }
                )
                .overlay(alignment: .top) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
        }
    }

    private var hint: String {
        let active = dragLayer ?? pinchLayer ?? hoveredLayer
        let tone = model.settings.finish == .none ? "" : " Click to switch light and dark."
        if active == .back { return "Second layer: drag to move, pinch to zoom.\(tone)" }
        if model.settings.canEditBack {
            return "Drag to move, pinch to zoom. Use the strip above the front for the second layer.\(tone)"
        }
        return "Drag to move, pinch to zoom.\(tone)"
    }

    private func layer(atY y: CGFloat, top: CGFloat, side: CGFloat) -> EditLayer {
        model.settings.layer(atUnitY: (y - top) / side)
    }
}
