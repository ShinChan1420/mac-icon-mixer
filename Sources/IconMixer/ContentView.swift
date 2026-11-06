import AppKit
import IconMixCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: MixerModel

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
    }

    // MARK: Left: what's being mixed

    private var sources: some View {
        VStack(spacing: Metric.gap) {
            SourceCard(title: "Folder or App", hint: "Drop a folder or app", symbol: "folder",
                       caption: model.targetURL?.lastPathComponent, image: model.targetIcon,
                       drop: { loadDrop($0, url: model.accept, data: model.accept(imageData:)) },
                       pick: pickFolder) {
                if model.targetHasCustomIcon {
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
                    if let tones = model.tonePreviews {
                        Divider().frame(height: 64)
                        TonePreview(title: "Light", image: tones.light, ground: Color(white: 0.93), ink: .black)
                        TonePreview(title: "Dark", image: tones.dark, ground: Color(white: 0.11), ink: .white)
                    }
                }
                .frame(height: 84, alignment: .bottom)
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
                .disabled((model.targetURL == nil && model.imageName == nil) || model.isApplying)
            Button("Adjust") { model.isAdjusting.toggle() }
                .systemGlassButton(prominent: model.isAdjusting)
                .disabled(!model.hasImage || model.targetURL == nil)
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
                    let available = model.isAvailable(layer)
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
