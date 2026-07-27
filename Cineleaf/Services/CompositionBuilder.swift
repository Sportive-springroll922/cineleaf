import AppKit
import AVFoundation
import CoreText
import QuartzCore
import CineleafCore

enum CompositionError: Error {
    case emptyTimeline
    case missingAsset(UUID)
    case missingVideoTrack(UUID)
    case missingAudioTrack(UUID)
    case cannotCreateCompositionTrack
    case unreadableImage(UUID)
}

final class RenderedComposition: @unchecked Sendable {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition?
    let audioMix: AVAudioMix?
    let duration: RationalTime
    let revision: Date

    init(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?,
        audioMix: AVAudioMix?,
        duration: RationalTime,
        revision: Date
    ) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.duration = duration
        self.revision = revision
    }
}

actor AVCompositionBuilder {
    private let accessManager: MediaAccessManager

    init(accessManager: MediaAccessManager) {
        self.accessManager = accessManager
    }

    func build(project: CineleafProject) async throws -> RenderedComposition {
        try ProjectValidator.validate(project)
        guard project.timeline.duration > .zero else { throw CompositionError.emptyTimeline }
        return try await LocalDiagnostics.shared.measure("composition_rebuild") {
            try await self.buildComposition(project: project)
        }
    }

    private func buildComposition(project: CineleafProject) async throws -> RenderedComposition {
        let composition = AVMutableComposition()
        let assets = Dictionary(uniqueKeysWithValues: project.assets.map { ($0.id, $0) })
        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        var overlayClips: [(TimelineClip, MediaAsset?)] = []

        for track in project.timeline.tracks {
            try Task.checkCancellation()
            let enabled = track.clips.filter(\.isEnabled)
            if track.kind == .video {
                let videoClips = enabled.filter { $0.kind == .video }
                if !videoClips.isEmpty {
                    guard let destination = composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else { throw CompositionError.cannotCreateCompositionTrack }
                    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: destination)
                    for clip in videoClips where !clip.isVideoMuted {
                        guard let assetID = clip.assetID, let media = assets[assetID] else {
                            throw CompositionError.missingAsset(clip.assetID ?? clip.id)
                        }
                        let url = try await accessManager.resolve(media.reference)
                        let sourceAsset = AVURLAsset(url: url)
                        guard let source = try await sourceAsset.loadTracks(withMediaType: .video).first else {
                            throw CompositionError.missingVideoTrack(media.id)
                        }
                        try destination.insertTimeRange(
                            CMTimeRange(start: clip.sourceStart.cmTime, duration: clip.duration.cmTime),
                            of: source,
                            at: clip.timelineStart.cmTime
                        )
                        let naturalSize = try await source.load(.naturalSize)
                        let preferred = try await source.load(.preferredTransform)
                        configure(layer: layer, clip: clip, sourceSize: naturalSize, preferred: preferred, canvas: project.canvas)
                    }
                    layerInstructions.append(layer)
                }

                overlayClips += enabled.compactMap { clip in
                    guard clip.kind == .text || clip.kind == .image else { return nil }
                    return (clip, clip.assetID.flatMap { assets[$0] })
                }
            }

            let audioClips = enabled.filter { $0.kind == .audio || ($0.kind == .video && $0.audioVolume > 0) }
            if !audioClips.isEmpty {
                guard let destination = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw CompositionError.cannotCreateCompositionTrack }
                let parameters = AVMutableAudioMixInputParameters(track: destination)
                for clip in audioClips {
                    guard let assetID = clip.assetID, let media = assets[assetID] else {
                        throw CompositionError.missingAsset(clip.assetID ?? clip.id)
                    }
                    let url = try await accessManager.resolve(media.reference)
                    let sourceAsset = AVURLAsset(url: url)
                    guard let source = try await sourceAsset.loadTracks(withMediaType: .audio).first else {
                        if clip.kind == .video { continue }
                        throw CompositionError.missingAudioTrack(media.id)
                    }
                    try destination.insertTimeRange(
                        CMTimeRange(start: clip.sourceStart.cmTime, duration: clip.duration.cmTime),
                        of: source,
                        at: clip.timelineStart.cmTime
                    )
                    configure(parameters: parameters, clip: clip, trackMuted: track.isMuted)
                }
                audioParameters.append(parameters)
            }
        }

        let audioMix: AVMutableAudioMix? = audioParameters.isEmpty ? nil : {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioParameters
            return mix
        }()

        let videoComposition: AVMutableVideoComposition?
        if !layerInstructions.isEmpty {
            let mutable = AVMutableVideoComposition()
            mutable.renderSize = CGSize(width: CGFloat(project.canvas.width), height: CGFloat(project.canvas.height))
            mutable.frameDuration = project.frameRate.value.frameDuration.cmTime
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: project.timeline.duration.cmTime)
            instruction.layerInstructions = Array(layerInstructions.reversed())
            instruction.backgroundColor = NSColor.black.cgColor
            mutable.instructions = [instruction]
            if !overlayClips.isEmpty {
                mutable.animationTool = try await animationTool(
                    overlays: overlayClips,
                    canvas: project.canvas,
                    duration: project.timeline.duration
                )
            }
            videoComposition = mutable
        } else {
            videoComposition = nil
        }

        return RenderedComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            duration: project.timeline.duration,
            revision: project.modifiedAt
        )
    }

    private func configure(
        layer: AVMutableVideoCompositionLayerInstruction,
        clip: TimelineClip,
        sourceSize: CGSize,
        preferred: CGAffineTransform,
        canvas: Resolution
    ) {
        let transformedRect = CGRect(origin: .zero, size: sourceSize).applying(preferred)
        var normalized = preferred
        normalized.tx -= transformedRect.minX
        normalized.ty -= transformedRect.minY
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let canvasSize = CGSize(width: CGFloat(canvas.width), height: CGFloat(canvas.height))
        let fitScale = min(canvasSize.width / displaySize.width, canvasSize.height / displaySize.height)
        let fillScale = max(canvasSize.width / displaySize.width, canvasSize.height / displaySize.height)
        let contentScale = clip.transform.contentMode == .fit ? fitScale : fillScale
        let scale = contentScale * CGFloat(clip.transform.scale)
        let scaled = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
        var result = normalized
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (canvasSize.width - scaled.width) / 2,
                y: (canvasSize.height - scaled.height) / 2
            ))
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let userTransform = CGAffineTransform(translationX: -center.x, y: -center.y)
            .rotated(by: CGFloat(clip.transform.rotationDegrees) * .pi / 180)
            .translatedBy(
                x: center.x + CGFloat(clip.transform.positionX),
                y: center.y + CGFloat(clip.transform.positionY)
            )
        result = result.concatenating(userTransform)

        let start = clip.timelineStart.cmTime
        let end = clip.timelineEnd.cmTime
        layer.setTransform(result, at: start)
        let crop = CGRect(
            x: sourceSize.width * CGFloat(clip.transform.cropLeading),
            y: sourceSize.height * CGFloat(clip.transform.cropTop),
            width: sourceSize.width * CGFloat(max(0, 1 - clip.transform.cropLeading - clip.transform.cropTrailing)),
            height: sourceSize.height * CGFloat(max(0, 1 - clip.transform.cropTop - clip.transform.cropBottom))
        )
        layer.setCropRectangle(crop, at: start)
        layer.setOpacity(0, at: end)
        if clip.fades.videoIn > .zero {
            layer.setOpacityRamp(
                fromStartOpacity: 0,
                toEndOpacity: Float(clip.opacity),
                timeRange: CMTimeRange(start: start, duration: clip.fades.videoIn.cmTime)
            )
        } else {
            layer.setOpacity(Float(clip.opacity), at: start)
        }
        if clip.fades.videoOut > .zero {
            layer.setOpacityRamp(
                fromStartOpacity: Float(clip.opacity),
                toEndOpacity: 0,
                timeRange: CMTimeRange(start: end - clip.fades.videoOut.cmTime, duration: clip.fades.videoOut.cmTime)
            )
        }
    }

    private func configure(
        parameters: AVMutableAudioMixInputParameters,
        clip: TimelineClip,
        trackMuted: Bool
    ) {
        let volume = trackMuted ? Float(0) : Float(min(clip.audioVolume, 1))
        let start = clip.timelineStart.cmTime
        let end = clip.timelineEnd.cmTime
        if clip.fades.audioIn > .zero {
            parameters.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: volume,
                timeRange: CMTimeRange(start: start, duration: clip.fades.audioIn.cmTime)
            )
        } else {
            parameters.setVolume(volume, at: start)
        }
        if clip.fades.audioOut > .zero {
            parameters.setVolumeRamp(
                fromStartVolume: volume,
                toEndVolume: 0,
                timeRange: CMTimeRange(start: end - clip.fades.audioOut.cmTime, duration: clip.fades.audioOut.cmTime)
            )
        }
        parameters.setVolume(0, at: end)
    }

    private func animationTool(
        overlays: [(TimelineClip, MediaAsset?)],
        canvas: Resolution,
        duration: RationalTime
    ) async throws -> AVVideoCompositionCoreAnimationTool {
        let frame = CGRect(x: 0, y: 0, width: CGFloat(canvas.width), height: CGFloat(canvas.height))
        let parent = CALayer()
        parent.frame = frame
        parent.isGeometryFlipped = true
        let background = CALayer()
        background.frame = frame
        background.backgroundColor = NSColor.black.cgColor
        parent.addSublayer(background)
        let video = CALayer()
        video.frame = frame
        parent.addSublayer(video)

        for (clip, asset) in overlays {
            try Task.checkCancellation()
            switch clip.kind {
            case .image:
                guard let asset else { throw CompositionError.missingAsset(clip.assetID ?? clip.id) }
                let url = try await accessManager.resolve(asset.reference)
                guard let image = NSImage(contentsOf: url),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw CompositionError.unreadableImage(asset.id)
                }
                let layer = CALayer()
                layer.contents = cgImage
                layer.contentsGravity = clip.transform.contentMode == .fill ? .resizeAspectFill : .resizeAspect
                configureOverlay(layer, clip: clip, frame: frame)
                parent.addSublayer(layer)
            case .text:
                guard let style = clip.textStyle else { continue }
                let layer = CATextLayer()
                layer.contentsScale = 2
                let font = NSFont(name: style.fontName, size: CGFloat(style.fontSize))
                    ?? NSFont.systemFont(
                        ofSize: CGFloat(style.fontSize),
                        weight: NSFont.Weight(rawValue: CGFloat(style.fontWeight))
                    )
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(CGFloat(style.shadowOpacity))
                shadow.shadowBlurRadius = style.shadowOpacity > 0 ? 8 : 0
                shadow.shadowOffset = NSSize(width: 0, height: 2)
                layer.string = NSAttributedString(string: style.text, attributes: [
                    .font: font,
                    .foregroundColor: NSColor(hex: style.foregroundHex),
                    .strokeColor: NSColor(hex: style.strokeHex),
                    .strokeWidth: -style.strokeWidth,
                    .shadow: shadow
                ])
                layer.alignmentMode = style.alignment.caAlignment
                layer.isWrapped = true
                layer.backgroundColor = NSColor(hex: style.backgroundHex).cgColor
                configureOverlay(layer, clip: clip, frame: frame)
                parent.addSublayer(layer)
            default:
                break
            }
        }
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)
    }

    private func configureOverlay(_ layer: CALayer, clip: TimelineClip, frame: CGRect) {
        layer.frame = frame
        layer.opacity = 0
        let center = CGPoint(
            x: frame.midX + CGFloat(clip.transform.positionX),
            y: frame.midY + CGFloat(clip.transform.positionY)
        )
        layer.position = center
        layer.setAffineTransform(
            CGAffineTransform(
                scaleX: CGFloat(clip.transform.scale),
                y: CGFloat(clip.transform.scale)
            )
                .rotated(by: CGFloat(clip.transform.rotationDegrees) * .pi / 180)
        )
        let fadeIn = max(clip.fades.videoIn.seconds, clip.textStyle?.animation == .fade ? 0.25 : 0)
        let fadeOut = max(clip.fades.videoOut.seconds, clip.textStyle?.animation == .fade ? 0.25 : 0)
        let duration = max(clip.duration.seconds, 0.001)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, clip.opacity, clip.opacity, 0]
        animation.keyTimes = [
            0,
            NSNumber(value: min(fadeIn / duration, 0.49)),
            NSNumber(value: max(1 - fadeOut / duration, 0.51)),
            1
        ]
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + clip.timelineStart.seconds
        animation.duration = duration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "cineleaf.visibility")

        if clip.textStyle?.animation == .slideUp {
            let slide = CABasicAnimation(keyPath: "position.y")
            slide.fromValue = center.y + 48
            slide.toValue = center.y
            slide.beginTime = animation.beginTime
            slide.duration = min(0.35, duration)
            slide.fillMode = .both
            slide.isRemovedOnCompletion = false
            layer.add(slide, forKey: "cineleaf.slide")
        }
    }
}

private extension CineleafCore.TextAlignment {
    var caAlignment: CATextLayerAlignmentMode {
        switch self {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: value)
        var bits: UInt64 = 0
        scanner.scanHexInt64(&bits)
        let hasAlpha = value.count == 8
        let red = CGFloat((bits >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((bits >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((bits >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(bits & 0xFF) / 255 : 1
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
