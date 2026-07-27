import CineleafCore
import SwiftUI

struct NewProjectSheet: View {
    @EnvironmentObject private var state: EditorState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var preset = CanvasPreset.landscape16x9
    @State private var frameRate = ProjectFrameRate.fps30

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("project.new")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("newProject.title")
            Form {
                TextField("project.name", text: $name)
                    .accessibilityIdentifier("newProject.name")
                Picker("project.canvas", selection: $preset) {
                    ForEach(CanvasPreset.allCases, id: \.self) { value in
                        Text(value.localizationKey).tag(value)
                    }
                }
                Picker("project.frame_rate", selection: $frameRate) {
                    ForEach(ProjectFrameRate.allCases, id: \.self) { value in
                        Text("\(value.displayValue) fps").tag(value)
                    }
                }
            }
            HStack {
                Spacer()
                Button("action.cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("action.create") {
                    state.newProject(name: name, preset: preset, frameRate: frameRate)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("newProject.create")
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

extension CanvasPreset {
    var localizationKey: LocalizedStringKey {
        switch self {
        case .landscape16x9: "canvas.landscape"
        case .vertical9x16: "canvas.vertical"
        case .square1x1: "canvas.square"
        case .portrait4x5: "canvas.portrait"
        }
    }
}
