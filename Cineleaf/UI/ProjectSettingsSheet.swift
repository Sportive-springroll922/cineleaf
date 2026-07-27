import CineleafCore
import SwiftUI

struct ProjectSettingsSheet: View {
    @EnvironmentObject private var state: EditorState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var preset: CanvasPreset
    @State private var frameRate: ProjectFrameRate

    init() {
        _name = State(initialValue: "")
        _preset = State(initialValue: .landscape16x9)
        _frameRate = State(initialValue: .fps30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("project.settings")
                .font(.title2.weight(.semibold))
            Form {
                TextField("project.name", text: $name)
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
                Button("action.apply") {
                    state.updateProjectSettings(name: name, preset: preset, frameRate: frameRate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            guard let project = state.project else { return }
            name = project.name
            preset = project.canvasPreset
            frameRate = project.frameRate
        }
    }
}
