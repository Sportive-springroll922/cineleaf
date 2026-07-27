import AppKit
import CineleafCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("inspector.title")
                    .font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            if let clip = state.selectedClip {
                ClipInspector(clip: clip)
                    .id(clip.id)
            } else {
                ContentUnavailableView {
                    Label("inspector.empty.title", systemImage: "sidebar.right")
                } description: {
                    Text("inspector.empty.message")
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ClipInspector: View {
    @EnvironmentObject private var state: EditorState
    let clip: TimelineClip

    var body: some View {
        Form {
            Section("inspector.general") {
                TextField("inspector.name", text: binding(\.name))
                Toggle("inspector.enabled", isOn: binding(\.isEnabled))
                LabeledContent("inspector.start") {
                    TextField("inspector.start", value: startBinding, format: .number.precision(.fractionLength(2)))
                        .labelsHidden()
                        .frame(maxWidth: 90)
                }
                LabeledContent("inspector.duration") {
                    TextField("inspector.duration", value: durationBinding, format: .number.precision(.fractionLength(2)))
                        .labelsHidden()
                        .frame(maxWidth: 90)
                }
            }

            if clip.kind != .audio {
                Section("inspector.transform") {
                    LabeledContent("inspector.position_x") {
                        TextField("inspector.position_x", value: binding(\.transform.positionX), format: .number)
                            .labelsHidden()
                    }
                    LabeledContent("inspector.position_y") {
                        TextField("inspector.position_y", value: binding(\.transform.positionY), format: .number)
                            .labelsHidden()
                    }
                    LabeledContent("inspector.scale") {
                        Slider(value: binding(\.transform.scale), in: 0.05...5)
                    }
                    LabeledContent("inspector.rotation") {
                        TextField("inspector.rotation", value: binding(\.transform.rotationDegrees), format: .number)
                            .labelsHidden()
                    }
                    LabeledContent("inspector.opacity") {
                        Slider(value: binding(\.opacity), in: 0...1)
                    }
                    Picker("inspector.content_mode", selection: binding(\.transform.contentMode)) {
                        ForEach(ContentMode.allCases, id: \.self) { mode in
                            Text(mode.localizationKey).tag(mode)
                        }
                    }
                    DisclosureGroup("inspector.crop") {
                        cropSlider("inspector.crop.top", keyPath: \.transform.cropTop)
                        cropSlider("inspector.crop.leading", keyPath: \.transform.cropLeading)
                        cropSlider("inspector.crop.bottom", keyPath: \.transform.cropBottom)
                        cropSlider("inspector.crop.trailing", keyPath: \.transform.cropTrailing)
                    }
                    Button("inspector.transform.reset") {
                        state.updateClip(clip.id) { $0.transform = ClipTransform() }
                    }
                }
            }

            if clip.kind == .video {
                Section("inspector.video") {
                    Toggle("inspector.video_muted", isOn: binding(\.isVideoMuted))
                    fadeSlider("inspector.video_fade_in", keyPath: \.fades.videoIn)
                    fadeSlider("inspector.video_fade_out", keyPath: \.fades.videoOut)
                }
            }

            if clip.kind == .video || clip.kind == .audio {
                Section("inspector.audio") {
                    LabeledContent("inspector.volume") {
                        Slider(value: binding(\.audioVolume), in: 0...1)
                    }
                    fadeSlider("inspector.audio_fade_in", keyPath: \.fades.audioIn)
                    fadeSlider("inspector.audio_fade_out", keyPath: \.fades.audioOut)
                    if clip.kind == .video {
                        Button("audio.detach") { state.detachAudio() }
                    }
                }
            }

            if clip.kind == .text, clip.textStyle != nil {
                Section("inspector.text") {
                    TextField("text.content", text: textBinding(\.text), axis: .vertical)
                        .lineLimit(2...6)
                    Picker("text.font", selection: textBinding(\.fontName)) {
                        ForEach(NSFontManager.shared.availableFonts, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                    LabeledContent("text.size") {
                        TextField("text.size", value: textBinding(\.fontSize), format: .number)
                            .labelsHidden()
                    }
                    LabeledContent("text.weight") {
                        Slider(value: textBinding(\.fontWeight), in: -0.8...0.8)
                    }
                    Picker("text.alignment", selection: textBinding(\.alignment)) {
                        ForEach(TextAlignment.allCases, id: \.self) { alignment in
                            Text(alignment.localizationKey).tag(alignment)
                        }
                    }
                    ColorPicker("text.color", selection: colorBinding(\.foregroundHex), supportsOpacity: true)
                    ColorPicker("text.background", selection: colorBinding(\.backgroundHex), supportsOpacity: true)
                    ColorPicker("text.stroke_color", selection: colorBinding(\.strokeHex), supportsOpacity: true)
                    LabeledContent("text.stroke_width") {
                        Slider(value: textBinding(\.strokeWidth), in: 0...10)
                    }
                    LabeledContent("text.shadow") {
                        Slider(value: textBinding(\.shadowOpacity), in: 0...1)
                    }
                    Picker("text.animation", selection: textBinding(\.animation)) {
                        ForEach(TextAnimation.allCases, id: \.self) { animation in
                            Text(animation.localizationKey).tag(animation)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button("timeline.duplicate") { state.duplicateSelection() }
                    Spacer()
                    Button("timeline.delete", role: .destructive) { state.deleteSelection() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TimelineClip, Value>) -> Binding<Value> {
        Binding(
            get: { state.selectedClip?[keyPath: keyPath] ?? clip[keyPath: keyPath] },
            set: { value in state.updateClip(clip.id) { $0[keyPath: keyPath] = value } }
        )
    }

    private func textBinding<Value>(_ keyPath: WritableKeyPath<TextStyle, Value>) -> Binding<Value> {
        Binding(
            get: {
                (state.selectedClip?.textStyle ?? clip.textStyle)![keyPath: keyPath]
            },
            set: { value in
                state.updateClip(clip.id) { current in
                    current.textStyle?[keyPath: keyPath] = value
                }
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<TextStyle, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(cineleafHex: textBinding(keyPath).wrappedValue)) },
            set: { textBinding(keyPath).wrappedValue = NSColor($0).cineleafHex }
        )
    }

    private var startBinding: Binding<Double> {
        Binding(
            get: { state.selectedClip?.timelineStart.seconds ?? clip.timelineStart.seconds },
            set: { value in
                guard let trackID else { return }
                state.moveClip(
                    clip.id,
                    to: RationalTime(seconds: max(value, 0), preferredTimescale: 6_000),
                    trackID: trackID
                )
            }
        )
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { state.selectedClip?.duration.seconds ?? clip.duration.seconds },
            set: { value in
                state.updateClip(clip.id) {
                    $0.duration = RationalTime(seconds: max(value, 0.01), preferredTimescale: 6_000)
                }
            }
        )
    }

    private var trackID: UUID? {
        state.project?.timeline.tracks.first(where: { $0.clips.contains { $0.id == clip.id } })?.id
    }

    @ViewBuilder
    private func cropSlider(_ key: LocalizedStringKey, keyPath: WritableKeyPath<TimelineClip, Double>) -> some View {
        LabeledContent(key) {
            Slider(value: binding(keyPath), in: 0...0.49)
        }
    }

    @ViewBuilder
    private func fadeSlider(_ key: LocalizedStringKey, keyPath: WritableKeyPath<TimelineClip, RationalTime>) -> some View {
        LabeledContent(key) {
            Slider(
                value: Binding(
                    get: { (state.selectedClip?[keyPath: keyPath] ?? clip[keyPath: keyPath]).seconds },
                    set: { seconds in
                        state.updateClip(clip.id) {
                            $0[keyPath: keyPath] = RationalTime(seconds: seconds, preferredTimescale: 6_000)
                        }
                    }
                ),
                in: 0...max(clip.duration.seconds / 2, 0.001)
            )
        }
    }
}

private extension CineleafCore.ContentMode {
    var localizationKey: LocalizedStringKey {
        switch self {
        case .fit: "content_mode.fit"
        case .fill: "content_mode.fill"
        case .crop: "content_mode.crop"
        }
    }
}

private extension TextAlignment {
    var localizationKey: LocalizedStringKey {
        switch self {
        case .leading: "text.alignment.leading"
        case .center: "text.alignment.center"
        case .trailing: "text.alignment.trailing"
        }
    }
}

private extension TextAnimation {
    var localizationKey: LocalizedStringKey {
        switch self {
        case .none: "text.animation.none"
        case .fade: "text.animation.fade"
        case .slideUp: "text.animation.slide_up"
        }
    }
}

private extension NSColor {
    convenience init(cineleafHex: String) {
        let input = cineleafHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: input).scanHexInt64(&value)
        let alphaIncluded = input.count == 8
        self.init(
            srgbRed: CGFloat((value >> (alphaIncluded ? 24 : 16)) & 0xFF) / 255,
            green: CGFloat((value >> (alphaIncluded ? 16 : 8)) & 0xFF) / 255,
            blue: CGFloat((value >> (alphaIncluded ? 8 : 0)) & 0xFF) / 255,
            alpha: alphaIncluded ? CGFloat(value & 0xFF) / 255 : 1
        )
    }

    var cineleafHex: String {
        guard let color = usingColorSpace(.sRGB) else { return "#FFFFFFFF" }
        return String(
            format: "#%02X%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()),
            Int((color.alphaComponent * 255).rounded())
        )
    }
}
