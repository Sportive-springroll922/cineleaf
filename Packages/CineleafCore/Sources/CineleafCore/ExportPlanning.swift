import Foundation

public enum ExportConfigurationError: Error, Equatable, Sendable {
    case emptyFilename
    case emptyTimeline
    case invalidCanvas
}

public struct ExportPlan: Equatable, Sendable {
    public var filename: String
    public var resolution: Resolution
    public var frameRate: RationalRate
    public var codec: ExportCodec
    public var container: ExportContainer
    public var quality: ExportQuality

    public init(filename: String, project: CineleafProject, preferences: ExportPreferences? = nil) throws {
        let sanitized = FilenameSanitizer.sanitize(filename, fallback: "")
        guard !sanitized.isEmpty else { throw ExportConfigurationError.emptyFilename }
        guard project.timeline.duration > .zero else { throw ExportConfigurationError.emptyTimeline }
        guard project.canvas.width > 0 && project.canvas.height > 0 else {
            throw ExportConfigurationError.invalidCanvas
        }
        let preferences = preferences ?? project.exportPreferences
        self.filename = sanitized
        self.resolution = Self.outputResolution(canvas: project.canvas, longEdge: preferences.resolution.longEdge)
        self.frameRate = preferences.frameRate.value
        self.codec = preferences.codec
        self.container = preferences.container
        self.quality = preferences.quality
    }

    private static func outputResolution(canvas: Resolution, longEdge: Int) -> Resolution {
        let widthIsLong = canvas.width >= canvas.height
        let ratio = Double(canvas.width) / Double(canvas.height)
        let rawWidth = widthIsLong ? Double(longEdge) : Double(longEdge) * ratio
        let rawHeight = widthIsLong ? Double(longEdge) / ratio : Double(longEdge)
        return Resolution(width: even(rawWidth), height: even(rawHeight))
    }

    private static func even(_ value: Double) -> Int {
        let rounded = max(Int(value.rounded()), 2)
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
    }
}

