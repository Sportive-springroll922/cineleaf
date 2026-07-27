import Foundation

public enum CanvasPreset: String, Codable, CaseIterable, Sendable {
    case landscape16x9
    case vertical9x16
    case square1x1
    case portrait4x5

    public var resolution: Resolution {
        switch self {
        case .landscape16x9: Resolution(width: 1920, height: 1080)
        case .vertical9x16: Resolution(width: 1080, height: 1920)
        case .square1x1: Resolution(width: 1080, height: 1080)
        case .portrait4x5: Resolution(width: 1080, height: 1350)
        }
    }
}

public struct Resolution: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum ProjectFrameRate: String, Codable, CaseIterable, Sendable {
    case fps24
    case fps25
    case fps30
    case fps50
    case fps60

    public var value: RationalRate {
        switch self {
        case .fps24: RationalRate(numerator: 24)
        case .fps25: RationalRate(numerator: 25)
        case .fps30: RationalRate(numerator: 30)
        case .fps50: RationalRate(numerator: 50)
        case .fps60: RationalRate(numerator: 60)
        }
    }

    public var displayValue: Int { Int(value.numerator) }
}

public enum MediaKind: String, Codable, Sendable {
    case video
    case audio
    case image
}

public struct MediaMetadata: Codable, Hashable, Sendable {
    public var duration: RationalTime?
    public var resolution: Resolution?
    public var frameRate: RationalRate?
    public var fileType: String
    public var hasAudio: Bool
    public var fileSize: Int64

    public init(
        duration: RationalTime? = nil,
        resolution: Resolution? = nil,
        frameRate: RationalRate? = nil,
        fileType: String,
        hasAudio: Bool,
        fileSize: Int64
    ) {
        self.duration = duration
        self.resolution = resolution
        self.frameRate = frameRate
        self.fileType = fileType
        self.hasAudio = hasAudio
        self.fileSize = fileSize
    }
}

public struct MediaReference: Codable, Hashable, Sendable {
    public var lastKnownPath: String
    public var securityScopedBookmark: Data?
    public var sourceModificationDate: Date?

    public init(lastKnownPath: String, securityScopedBookmark: Data? = nil, sourceModificationDate: Date? = nil) {
        self.lastKnownPath = lastKnownPath
        self.securityScopedBookmark = securityScopedBookmark
        self.sourceModificationDate = sourceModificationDate
    }
}

public struct MediaAsset: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var kind: MediaKind
    public var reference: MediaReference
    public var metadata: MediaMetadata

    public init(
        id: UUID = UUID(),
        displayName: String,
        kind: MediaKind,
        reference: MediaReference,
        metadata: MediaMetadata
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.reference = reference
        self.metadata = metadata
    }
}

public enum TrackKind: String, Codable, Sendable {
    case video
    case audio
}

public enum ClipKind: String, Codable, Sendable {
    case video
    case audio
    case image
    case text

    public var compatibleTrack: TrackKind {
        self == .audio ? .audio : .video
    }
}

public enum ContentMode: String, Codable, CaseIterable, Sendable {
    case fit
    case fill
    case crop
}

public struct ClipTransform: Codable, Hashable, Sendable {
    public var positionX: Double
    public var positionY: Double
    public var scale: Double
    public var rotationDegrees: Double
    public var cropTop: Double
    public var cropLeading: Double
    public var cropBottom: Double
    public var cropTrailing: Double
    public var contentMode: ContentMode

    public init(
        positionX: Double = 0,
        positionY: Double = 0,
        scale: Double = 1,
        rotationDegrees: Double = 0,
        cropTop: Double = 0,
        cropLeading: Double = 0,
        cropBottom: Double = 0,
        cropTrailing: Double = 0,
        contentMode: ContentMode = .fit
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.cropTop = cropTop
        self.cropLeading = cropLeading
        self.cropBottom = cropBottom
        self.cropTrailing = cropTrailing
        self.contentMode = contentMode
    }
}

public enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

public enum TextAnimation: String, Codable, CaseIterable, Sendable {
    case none
    case fade
    case slideUp
}

public struct TextStyle: Codable, Hashable, Sendable {
    public var text: String
    public var fontName: String
    public var fontSize: Double
    public var fontWeight: Double
    public var alignment: TextAlignment
    public var foregroundHex: String
    public var backgroundHex: String
    public var strokeHex: String
    public var strokeWidth: Double
    public var shadowOpacity: Double
    public var animation: TextAnimation

    public init(
        text: String = "",
        fontName: String = ".AppleSystemUIFont",
        fontSize: Double = 64,
        fontWeight: Double = 0,
        alignment: TextAlignment = .center,
        foregroundHex: String = "#FFFFFFFF",
        backgroundHex: String = "#00000000",
        strokeHex: String = "#000000FF",
        strokeWidth: Double = 0,
        shadowOpacity: Double = 0,
        animation: TextAnimation = .none
    ) {
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.alignment = alignment
        self.foregroundHex = foregroundHex
        self.backgroundHex = backgroundHex
        self.strokeHex = strokeHex
        self.strokeWidth = strokeWidth
        self.shadowOpacity = shadowOpacity
        self.animation = animation
    }
}

public struct ClipFades: Codable, Hashable, Sendable {
    public var videoIn: RationalTime
    public var videoOut: RationalTime
    public var audioIn: RationalTime
    public var audioOut: RationalTime

    public init(
        videoIn: RationalTime = .zero,
        videoOut: RationalTime = .zero,
        audioIn: RationalTime = .zero,
        audioOut: RationalTime = .zero
    ) {
        self.videoIn = videoIn
        self.videoOut = videoOut
        self.audioIn = audioIn
        self.audioOut = audioOut
    }
}

public struct TimelineClip: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ClipKind
    public var assetID: UUID?
    public var timelineStart: RationalTime
    public var duration: RationalTime
    public var sourceStart: RationalTime
    public var transform: ClipTransform
    public var opacity: Double
    public var isEnabled: Bool
    public var isVideoMuted: Bool
    public var audioVolume: Double
    public var fades: ClipFades
    public var textStyle: TextStyle?
    public var playbackRate: Double
    public var isReversed: Bool
    public var groupID: UUID?
    public var linkGroupID: UUID?
    public var role: ClipRole
    public var colorAdjustments: ColorAdjustments
    public var effects: [VideoEffect]
    public var transitionIn: ClipTransition?
    public var transitionOut: ClipTransition?
    public var keyframes: ClipKeyframes

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ClipKind,
        assetID: UUID? = nil,
        timelineStart: RationalTime,
        duration: RationalTime,
        sourceStart: RationalTime = .zero,
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1,
        isEnabled: Bool = true,
        isVideoMuted: Bool = false,
        audioVolume: Double = 1,
        fades: ClipFades = ClipFades(),
        textStyle: TextStyle? = nil,
        playbackRate: Double = 1,
        isReversed: Bool = false,
        groupID: UUID? = nil,
        linkGroupID: UUID? = nil,
        role: ClipRole = .standard,
        colorAdjustments: ColorAdjustments = .neutral,
        effects: [VideoEffect] = [],
        transitionIn: ClipTransition? = nil,
        transitionOut: ClipTransition? = nil,
        keyframes: ClipKeyframes = ClipKeyframes()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.assetID = assetID
        self.timelineStart = timelineStart
        self.duration = duration
        self.sourceStart = sourceStart
        self.transform = transform
        self.opacity = opacity
        self.isEnabled = isEnabled
        self.isVideoMuted = isVideoMuted
        self.audioVolume = audioVolume
        self.fades = fades
        self.textStyle = textStyle
        self.playbackRate = playbackRate
        self.isReversed = isReversed
        self.groupID = groupID
        self.linkGroupID = linkGroupID
        self.role = role
        self.colorAdjustments = colorAdjustments
        self.effects = effects
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
        self.keyframes = keyframes
    }

    public var timeRange: RationalTimeRange {
        RationalTimeRange(start: timelineStart, duration: duration)
    }

    public var timelineEnd: RationalTime { timelineStart + duration }
}

public struct TimelineTrack: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: TrackKind
    public var isMuted: Bool
    public var isLocked: Bool
    public var clips: [TimelineClip]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: TrackKind,
        isMuted: Bool = false,
        isLocked: Bool = false,
        clips: [TimelineClip] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.clips = clips
    }
}

public struct Timeline: Codable, Hashable, Sendable {
    public var tracks: [TimelineTrack]
    public var markers: [TimelineMarker]

    public init(tracks: [TimelineTrack] = [], markers: [TimelineMarker] = []) {
        self.tracks = tracks
        self.markers = markers
    }

    public var duration: RationalTime {
        tracks.flatMap(\.clips).map(\.timelineEnd).max() ?? .zero
    }
}

public enum ExportCodec: String, Codable, CaseIterable, Sendable {
    case h264
    case hevc
}

public enum ExportContainer: String, Codable, CaseIterable, Sendable {
    case mp4
    case mov
}

public enum ExportQuality: String, Codable, CaseIterable, Sendable {
    case compact
    case balanced
    case high
}

public enum ExportResolutionPreset: String, Codable, CaseIterable, Sendable {
    case p720
    case p1080
    case p1440
    case p2160

    public var longEdge: Int {
        switch self {
        case .p720: 1280
        case .p1080: 1920
        case .p1440: 2560
        case .p2160: 3840
        }
    }
}

public struct ExportPreferences: Codable, Hashable, Sendable {
    public var resolution: ExportResolutionPreset
    public var frameRate: ProjectFrameRate
    public var quality: ExportQuality
    public var codec: ExportCodec
    public var container: ExportContainer

    public init(
        resolution: ExportResolutionPreset = .p1080,
        frameRate: ProjectFrameRate = .fps30,
        quality: ExportQuality = .balanced,
        codec: ExportCodec = .h264,
        container: ExportContainer = .mp4
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.quality = quality
        self.codec = codec
        self.container = container
    }
}

public struct CineleafProject: Identifiable, Codable, Hashable, Sendable {
    public static let currentFormatVersion = 2

    public var formatVersion: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var canvas: Resolution
    public var canvasPreset: CanvasPreset
    public var frameRate: ProjectFrameRate
    public var assets: [MediaAsset]
    public var timeline: Timeline
    public var exportPreferences: ExportPreferences

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        canvasPreset: CanvasPreset = .landscape16x9,
        frameRate: ProjectFrameRate = .fps30,
        assets: [MediaAsset] = [],
        timeline: Timeline? = nil,
        exportPreferences: ExportPreferences? = nil
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.canvasPreset = canvasPreset
        self.canvas = canvasPreset.resolution
        self.frameRate = frameRate
        self.assets = assets
        self.timeline = timeline ?? Timeline(tracks: [
            TimelineTrack(name: "V1", kind: .video),
            TimelineTrack(name: "A1", kind: .audio)
        ])
        self.exportPreferences = exportPreferences ?? ExportPreferences(frameRate: frameRate)
    }
}
