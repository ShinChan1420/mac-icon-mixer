import AppKit
import IconMixCore
import SwiftUI
import UniformTypeIdentifiers

/// Spacing and corner sizes shared across the window, so everything lines up on one system.
private enum Metric {
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

struct ContentView: View {
    @Bindable var model: MixerModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sources
                .frame(width: Metric.sourceWidth)
            Divider()
            stage
            Divider()
            look
                .frame(width: Metric.lookWidth)
        }
        .frame(minWidth: 1140, minHeight: 700)
        .inspector(isPresented: $model.isAdjusting) {
            AdjustPanel(model: model)
                .inspectorColumnWidth(min: 260, ideal: 280, max: 320)
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in
            model.systemIsDark = scheme == .dark
        }
    }

    // MARK: Left: what's being mixed

    private var sources: some View {
        VStack(spacing: Metric.gap) {
            SourceCard(title: "Folder or App", hint: "Drop a folder or app", symbol: "folder",
                       caption: model.folderURL?.lastPathComponent, image: model.folderIcon,
                       drop: { loadDrop($0, url: model.accept, data: model.accept(imageData:)) },
                       pick: pickFolder) {
                if model.folderHasCustomIcon {
                    Button("Remove Custom Icon", action: model.removeCustomIcon)
                        .systemGlassButton()
                        .fixedSize()
                        .disabled(model.isApplying)
                }
            }
            SourceCard(title: "Image", hint: "Drop an image", symbol: "photo",
                       caption: model.imageName, image: model.imageThumbnail,
                       drop: { loadDrop($0, url: model.accept, data: model.accept(imageData:)) },
                       pick: pickImage) {
                // On an app, no image means a finish on its original icon. Folders always need a picture.
                if model.hasImage && model.targetIsApp {
                    Button("Remove Image", action: model.removeImage)
                        .systemGlassButton()
                        .fixedSize()
                }
            }
            SourceCard(title: "Second Image", hint: model.hasLayers ? "Optional, for the second layer" : "Not used on this look",
                       symbol: "square.2.layers.3d", caption: model.secondImageName, image: model.secondImageThumbnail,
                       isEnabled: model.hasLayers,
                       drop: { loadDrop($0, url: model.acceptSecond, data: model.acceptSecond(imageData:)) },
                       pick: pickSecondImage) {
                if model.secondImageName != nil {
                    Button("Remove", action: model.removeSecondImage)
                        .systemGlassButton()
                }
            }
        }
        .padding(Metric.edge)
    }

    // MARK: Centre: the icon

    private var stage: some View {
        VStack(spacing: 16) {
            if let preview = model.preview {
                DraggablePreview(image: preview, model: model)
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach([64.0, 32.0, 16.0], id: \.self) { side in
                        Image(nsImage: preview)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: side, height: side)
                    }
                }
            } else {
                Spacer()
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Add a folder or app to start")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            actionBar
        }
        .padding(Metric.edge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(model.messageIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }
            if model.canUndo {
                Button("Undo", action: model.undoApply)
                    .systemGlassButton()
                    .disabled(model.isApplying)
            }
            Spacer(minLength: 8)
            Button("Discard", role: .destructive, action: model.discard)
                .systemGlassButton()
                .disabled((model.folderURL == nil && model.imageName == nil) || model.isApplying)
            Button("Adjust") { model.isAdjusting.toggle() }
                .systemGlassButton(prominent: model.isAdjusting)
                .disabled(!model.hasImage || model.folderURL == nil)
            Button("Apply", action: model.apply)
                .systemGlassButton(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isReady || model.isApplying)
        }
        .controlSize(.large)
        .frame(height: 40)
    }

    // MARK: Right: how it looks

    private var look: some View {
        VStack(alignment: .leading, spacing: 22) {
            styleSection
            finishSection
            secondLayerSection
            Spacer(minLength: 0)
        }
        .padding(Metric.edge)
        .disabled(model.preview == nil)
    }

    /// One form row. Every control starts on the same line after the label and ends on the column's edge.
    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: Metric.labelWidth, alignment: .leading)
            control()
                .frame(maxWidth: .infinity)
        }
        .frame(height: Metric.rowHeight)
    }

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(height: Metric.rowHeight)
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Style") {
                Picker("Style", selection: frontStyle) {
                    ForEach(MixStyle.frontStyles) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fullWidthSegments()
            }
            row("Colour") {
                HStack(spacing: 8) {
                    Button { model.settings.frontColor = nil } label: {
                        Text("Reset").frame(maxWidth: .infinity)
                    }
                    .systemGlassButton()
                    .buttonSizingFlexible()
                    .frame(width: Metric.besideWellWidth)
                    .disabled(!model.settings.style.usesFrontColor || model.settings.frontColor == nil)
                    ColorPicker("Front colour", selection: frontColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: Metric.wellWidth)
                        .help("Front colour")
                        .disabled(!model.settings.style.usesFrontColor)
                }
            }
        }
        .disabled(!model.hasImage)
    }

    private var finishSection: some View {
        let hasFinish = model.settings.finish != .none
        return VStack(alignment: .leading, spacing: 10) {
            row("Finish") {
                Picker("Finish", selection: $model.settings.finish) {
                    ForEach(Finish.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fullWidthSegments()
            }
            row("Apply to") {
                if model.hasLayers {
                    Picker("Apply finish to", selection: $model.settings.finishTarget) {
                        ForEach(FinishTarget.allCases) { Text($0.title(object: model.objectName)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fullWidthSegments()
                    .help("Which part of the icon gets the finish")
                    .disabled(!hasFinish)
                } else {
                    Text(model.settings.style == .picture
                         ? "Needs a folder or app shape"
                         : "The whole \(model.objectName.lowercased())")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            row("Tone") {
                HStack(spacing: 8) {
                    Picker("Glass tone", selection: $model.settings.glassTone) {
                        ForEach(GlassTone.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .buttonSizingFlexible()
                    .frame(width: Metric.besideWellWidth)
                    .help("Auto matches your Light or Dark mode when you press Apply. A saved icon doesn't change later.")
                    .disabled(!hasFinish)
                    ColorPicker("Glass colour", selection: glassColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: Metric.wellWidth)
                        .help("Glass colour")
                        .disabled(!hasFinish || model.settings.glassTone != .custom)
                }
            }
            row("Strength") {
                Slider(value: $model.settings.finishStrength, in: 0...1)
                    .help("Blur and bending. At 0 the picture stays sharp and only the glass surface shows.")
                    .disabled(!hasFinish)
            }
        }
        .disabled(model.settings.style == .picture)
    }

    private var secondLayerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Second Layer") {
                if model.targetIsApp {
                    Text("Apps have one layer").font(.callout).foregroundStyle(.secondary)
                }
                ColorPicker("Second layer colour", selection: backColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: Metric.wellWidth)
                    .help("Plain colour")
                    .reservingSpace(visible: FolderLayer.plainColor.isSelected(in: model.settings))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(FolderLayer.allCases) { layer in
                    let available = (!model.targetIsApp || layer.worksOnApps) && (model.hasImage || layer == .original)
                    LayerTile(title: layer.title, image: model.layerThumbnails[layer],
                              isSelected: layer.isSelected(in: model.settings)) {
                        model.choose(layer)
                    }
                    .disabled(!available)
                    .opacity(available ? 1 : 0.35)
                }
            }
        }
    }

    // MARK: Bindings

    /// nil while Whole Cut or Picture Only is on, so no front style looks selected.
    private var frontStyle: Binding<MixStyle?> {
        Binding {
            model.settings.style.hasBackOptions ? model.settings.style : nil
        } set: { newValue in
            if let newValue { model.settings.style = newValue }
        }
    }

    private var backColor: Binding<Color> {
        colorBinding { model.settings.backColor } set: { model.settings.backColor = $0 }
    }

    private var glassColor: Binding<Color> {
        colorBinding { model.settings.glassColor } set: { model.settings.glassColor = $0 }
    }

    private var frontColor: Binding<Color> {
        colorBinding { model.settings.frontColor ?? .folderBlue } set: { model.settings.frontColor = $0 }
    }

    private func colorBinding(get: @escaping () -> MixColor, set: @escaping (MixColor) -> Void) -> Binding<Color> {
        Binding {
            let color = get()
            return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
        } set: { newValue in
            guard let color = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            set(MixColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent))
        }
    }

    // MARK: File pickers

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .applicationBundle]
        if panel.runModal() == .OK, let url = panel.url { model.accept(url) }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { model.accept(url) }
    }

    private func pickSecondImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { model.acceptSecond(url) }
    }
}

/// Reads dragged files or image data, handing each to the matching callback on the main actor.
@MainActor
private func loadDrop(_ providers: [NSItemProvider], url handleURL: @escaping @MainActor (URL) -> Void,
                      data handleData: @escaping @MainActor (Data) -> Void) -> Bool {
    var accepted = false
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in handleURL(url) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            accepted = true
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in handleData(data) }
            }
        }
    }
    return accepted
}

private extension View {
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

/// One picture going into the mix. All three sources share this card.
private struct SourceCard<Extra: View>: View {
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

private struct LayerTile: View {
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

/// The mixed icon. Dragging moves a layer and pinching zooms it; the strip above the
/// front panel controls the second layer, everywhere else controls the front picture.
private struct DraggablePreview: View {
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

private struct AdjustPanel: View {
    @Bindable var model: MixerModel

    private var settings: MixSettings { model.settings }
    private var hasSecondLayer: Bool { settings.style.hasBackOptions && !model.targetIsApp }
    private var backIsPicture: Bool { hasSecondLayer && settings.canEditBack }
    private var backHasContent: Bool { backIsPicture || (hasSecondLayer && settings.back == .color) }

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
        if !backHasContent {
            Text(hasSecondLayer
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
            .disabled(!backIsPicture)
            slider("Opacity", $model.settings.backOpacity, 0...1, editsBack: true)
                .disabled(!backHasContent)
        }
        Section("Photo") {
            slider("Brightness", $model.settings.backBrightness, -0.5...0.5, editsBack: true)
            slider("Contrast", $model.settings.backContrast, 0.5...1.5, editsBack: true)
            slider("Saturation", $model.settings.backSaturation, 0...2, editsBack: true)
        }
        .disabled(!backIsPicture)
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
