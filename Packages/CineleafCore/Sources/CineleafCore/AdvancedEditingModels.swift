import Foundation

public enum ClipRole: String, Codable, CaseIterable, Sendable {
    case standard
    case subtitle
    case voiceover
}

public struct ColorAdjustments: Codable, Hashable, Sendable {
    public var exposure: Double
    public var contrast: Double
    public var saturation: Double
    public var temperature: Double
    public var tint: Double
    public var highlights: Double
    public var shadows: Double
    public var sharpen: Double
    public var vignette: Double

    public init(
        exposure: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        temperature: Double = 0,
        tint: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        sharpen: Double = 0,
        vignette: Double = 0
    ) {
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.tint = tint
        self.highlights = highlights
        self.shadows = shadows
        self.sharpen = sharpen
        self.vignette = vignette
    }

    public static let neutral = ColorAdjustments()
}

public enum VideoEffectKind: String, Codable, CaseIterable, Sendable {
    case gaussianBlur
    case sharpen
    case vignette
    case monochrome
    case sepia
    case bloom
}

public struct VideoEffect: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: VideoEffectKind
    public var isEnabled: Bool
    public var amount: Double

    public init(id: UUID = UUID(), kind: VideoEffectKind, isEnabled: Bool = true, amount: Double = 0.5) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.amount = amount
    }
}

public enum TransitionKind: String, Codable, CaseIterable, Sendable {
    case crossDissolve
    case fadeThroughBlack
    case slideLeft
    case slideRight
    case wipeLeft
    case blur
}

public struct ClipTransition: Codable, Hashable, Sendable {
    public var kind: TransitionKind
    public var duration: RationalTime

    public init(kind: TransitionKind, duration: RationalTime = RationalTime(value: 1, timescale: 2)) {
        self.kind = kind
        self.duration = duration
    }
}

public enum TransitionEdge: String, Codable, Sendable {
    case `in`
    case out
}

public enum KeyframedProperty: String, Codable, CaseIterable, Sendable {
    case positionX
    case positionY
    case scale
    case rotationDegrees
    case opacity
    case volume
}

public struct ClipKeyframes: Codable, Hashable, Sendable {
    public var positionX: [ScalarKeyframe]
    public var positionY: [ScalarKeyframe]
    public var scale: [ScalarKeyframe]
    public var rotationDegrees: [ScalarKeyframe]
    public var opacity: [ScalarKeyframe]
    public var volume: [ScalarKeyframe]

    public init(
        positionX: [ScalarKeyframe] = [],
        positionY: [ScalarKeyframe] = [],
        scale: [ScalarKeyframe] = [],
        rotationDegrees: [ScalarKeyframe] = [],
        opacity: [ScalarKeyframe] = [],
        volume: [ScalarKeyframe] = []
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.opacity = opacity
        self.volume = volume
    }

    public subscript(property: KeyframedProperty) -> [ScalarKeyframe] {
        get {
            switch property {
            case .positionX: positionX
            case .positionY: positionY
            case .scale: scale
            case .rotationDegrees: rotationDegrees
            case .opacity: opacity
            case .volume: volume
            }
        }
        set {
            switch property {
            case .positionX: positionX = newValue
            case .positionY: positionY = newValue
            case .scale: scale = newValue
            case .rotationDegrees: rotationDegrees = newValue
            case .opacity: opacity = newValue
            case .volume: volume = newValue
            }
        }
    }
}

public struct TimelineMarker: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var time: RationalTime
    public var name: String
    public var colorHex: String

    public init(id: UUID = UUID(), time: RationalTime, name: String = "Marker", colorHex: String = "#F7C948FF") {
        self.id = id
        self.time = time
        self.name = name
        self.colorHex = colorHex
    }
}

public enum SubtitleFormat: String, Codable, CaseIterable, Sendable {
    case srt
    case webVTT
}

public struct SubtitleCue: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var start: RationalTime
    public var duration: RationalTime
    public var text: String

    public init(id: UUID = UUID(), start: RationalTime, duration: RationalTime, text: String) {
        self.id = id
        self.start = start
        self.duration = duration
        self.text = text
    }
}
