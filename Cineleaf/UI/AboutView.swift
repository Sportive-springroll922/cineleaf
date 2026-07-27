import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Cineleaf")
                .font(.title.weight(.semibold))
            Text("about.version \(version) \(build)")
                .foregroundStyle(.secondary)
            Text("about.description")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Text("about.license")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Link("about.github", destination: URL(string: "https://github.com/luucabg/cineleaf")!)
                Link("about.third_party", destination: URL(string: "https://github.com/luucabg/cineleaf/blob/main/THIRD_PARTY_NOTICES.md")!)
            }
            Text("about.copyright")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 440)
    }
}
