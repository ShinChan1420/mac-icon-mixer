import IconMixCore
import SwiftUI

struct AdjustPanel: View {
    @Bindable var model: MixerModel

    var body: some View {
        Form {
            Picker("Layer", selection: $model.adjustingLayer) {
                Text("First Layer").tag(EditLayer.front)
                Text("Second Layer").tag(EditLayer.back)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fullWidthSegments()

            switch model.adjustingLayer {
            case .front: firstLayer
            case .back: secondLayer
            }
            Button("Reset Adjustments", action: model.resetAdjustments)
                .systemGlassButton()
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var firstLayer: some View {
        Section("Placement") {
            slider("Zoom", $model.settings.zoom, MixSettings.frontZoomRange)
            slider("Horizontal", $model.settings.offsetX, -1...1)
            slider("Vertical", $model.settings.offsetY, -1...1)
            slider("Rotation", $model.settings.rotation, -180...180)
            slider("Opacity", $model.settings.opacity, 0...1)
        }
        Section("Photo") {
            slider("Brightness", $model.settings.brightness, -0.5...0.5)
            slider("Contrast", $model.settings.contrast, 0.5...1.5)
            slider("Saturation", $model.settings.saturation, 0...2)
        }
    }

    @ViewBuilder private var secondLayer: some View {
        if !model.secondLayerHasContent {
            Text(model.hasLayers
                 ? "Pick Plain Colour, Same Position or Different Position to adjust the second layer."
                 : "This look has a single layer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Placement") {
            Group {
                slider("Zoom", backPlacement(\.backZoom) { _ in 1 }, MixSettings.backZoomRange, editsBack: true)
                slider("Horizontal", backPlacement(\.backOffsetX) { $0.offsetX }, -1...1, editsBack: true)
                slider("Vertical", backPlacement(\.backOffsetY) { $0.offsetY }, -1...1, editsBack: true)
                slider("Rotation", backPlacement(\.backRotation) { $0.rotation }, -180...180, editsBack: true)
            }
            .disabled(!model.secondLayerIsPicture)
            slider("Opacity", $model.settings.backOpacity, 0...1, editsBack: true)
                .disabled(!model.secondLayerHasContent)
        }
        Section("Photo") {
            slider("Brightness", $model.settings.backBrightness, -0.5...0.5, editsBack: true)
            slider("Contrast", $model.settings.backContrast, 0.5...1.5, editsBack: true)
            slider("Saturation", $model.settings.backSaturation, 0...2, editsBack: true)
        }
        .disabled(!model.secondLayerIsPicture)
    }

    /// While the back follows the front it shows the front's value; moving a slider gives it its own.
    private func backPlacement(_ own: WritableKeyPath<MixSettings, Double>,
                               following: @escaping (MixSettings) -> Double) -> Binding<Double> {
        Binding {
            model.settings.back == .samePosition ? following(model.settings) : model.settings[keyPath: own]
        } set: { newValue in
            model.settings.detachBack()
            model.settings[keyPath: own] = newValue
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        editsBack: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range) { isEditing in
                if editsBack { model.isEditingBack = isEditing }
            }
            .labelsHidden()
        }
    }
}
