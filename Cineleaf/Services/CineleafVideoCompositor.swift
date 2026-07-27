import AVFoundation
import CineleafCore
import CoreImage
import CoreVideo

struct VideoClipRenderPlan: @unchecked Sendable {
    let trackID: CMPersistentTrackID
    let clip: TimelineClip
    let sourceSize: CGSize
    let preferredTransform: CGAffineTransform
    let canvas: Resolution
}

struct VideoTrackRenderPlan: @unchecked Sendable {
    let trackID: CMPersistentTrackID
    let clips: [VideoClipRenderPlan]
}

final class CineleafVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = true
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?
    let requiredSourceSampleDataTrackIDs: [NSNumber] = []
    let layerPlans: [VideoTrackRenderPlan]

    init(timeRange: CMTimeRange, layerPlans: [VideoTrackRenderPlan]) {
        self.timeRange = timeRange
        self.layerPlans = layerPlans
        requiredSourceTrackIDs = layerPlans.map { NSNumber(value: $0.trackID) as NSValue }
        super.init()
    }
}

final class CineleafVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
        kCVPixelBufferMetalCompatibilityKey as String: true
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
        kCVPixelBufferMetalCompatibilityKey as String: true
    ]

    private let renderQueue = DispatchQueue(label: "org.cineleaf.video-compositor", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "org.cineleaf.video-compositor.state")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var cancellationGeneration = 0

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let generation = stateQueue.sync { cancellationGeneration }
        renderQueue.async { [weak self] in
            guard let self else {
                request.finishCancelledRequest()
                return
            }
            guard self.stateQueue.sync(execute: { self.cancellationGeneration == generation }) else {
                request.finishCancelledRequest()
                return
            }
            do {
                let buffer = try self.render(request)
                request.finish(withComposedVideoFrame: buffer)
            } catch is CancellationError {
                request.finishCancelledRequest()
            } catch {
                request.finish(with: error)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        stateQueue.sync { cancellationGeneration += 1 }
    }

    private func render(_ request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        guard let instruction = request.videoCompositionInstruction as? CineleafVideoCompositionInstruction,
              let destination = request.renderContext.newPixelBuffer() else {
            throw CompositorError.invalidRequest
        }
        let renderSize = request.renderContext.size
        let renderBounds = CGRect(origin: .zero, size: renderSize)
        var result = CIImage(color: CIColor.black).cropped(to: renderBounds)
        let timelineTime = RationalTime(
            seconds: request.compositionTime.seconds,
            preferredTimescale: 60_000
        )

        for layer in instruction.layerPlans {
            guard let plan = activePlan(in: layer, at: timelineTime),
                  let sourceBuffer = request.sourceFrame(byTrackID: layer.trackID) else { continue }
            var image = CIImage(cvPixelBuffer: sourceBuffer)
            image = applyColorAndEffects(to: image, plan: plan, at: timelineTime)
            image = crop(image, using: plan.clip.transform)
            image = image.transformed(by: renderedTransform(plan: plan, at: timelineTime))
            image = applyTransitionCrop(to: image, plan: plan, at: timelineTime, renderBounds: renderBounds)
            let opacity = videoOpacity(plan: plan, at: timelineTime)
            if opacity < 1 {
                image = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
                ])
            }
            result = image.cropped(to: renderBounds).composited(over: result)
        }

        context.render(
            result.cropped(to: renderBounds),
            to: destination,
            bounds: renderBounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return destination
    }

    private func activePlan(in layer: VideoTrackRenderPlan, at time: RationalTime) -> VideoClipRenderPlan? {
        layer.clips.first { $0.clip.timeRange.contains(time) }
    }

    private func applyColorAndEffects(
        to source: CIImage,
        plan: VideoClipRenderPlan,
        at timelineTime: RationalTime
    ) -> CIImage {
        let adjustments = plan.clip.colorAdjustments
        let originalExtent = source.extent
        var image = source
        if adjustments.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: adjustments.exposure])
        }
        if adjustments.contrast != 1 || adjustments.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: adjustments.contrast,
                kCIInputSaturationKey: adjustments.saturation
            ])
        }
        if adjustments.temperature != 0 || adjustments.tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(
                    x: CGFloat(6_500 + adjustments.temperature * 3_000),
                    y: CGFloat(adjustments.tint * 150)
                ),
                "inputTargetNeutral": CIVector(x: 6_500, y: 0)
            ])
        }
        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": max(0, 1 + adjustments.highlights),
                "inputShadowAmount": adjustments.shadows
            ])
        }
        if adjustments.sharpen > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: adjustments.sharpen * 2
            ])
        }
        if adjustments.vignette > 0 {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: adjustments.vignette * 2,
                kCIInputRadiusKey: min(originalExtent.width, originalExtent.height) * 0.75
            ])
        }

        for effect in plan.clip.effects where effect.isEnabled && effect.amount > 0 {
            switch effect.kind {
            case .gaussianBlur:
                image = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: effect.amount * 30
                ]).cropped(to: originalExtent)
            case .sharpen:
                image = image.applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: effect.amount * 3
                ])
            case .vignette:
                image = image.applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: effect.amount * 2.5,
                    kCIInputRadiusKey: min(originalExtent.width, originalExtent.height) * 0.7
                ])
            case .monochrome:
                image = image.applyingFilter("CIColorMonochrome", parameters: [
                    kCIInputColorKey: CIColor(red: 0.78, green: 0.82, blue: 0.88),
                    kCIInputIntensityKey: effect.amount
                ])
            case .sepia:
                image = image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: effect.amount])
            case .bloom:
                image = image.clampedToExtent().applyingFilter("CIBloom", parameters: [
                    kCIInputIntensityKey: effect.amount,
                    kCIInputRadiusKey: effect.amount * 20
                ]).cropped(to: originalExtent)
            }
        }

        let localTime = timelineTime - plan.clip.timelineStart
        if let transition = plan.clip.transitionIn, transition.kind == .blur, localTime < transition.duration {
            let progress = max(0, min(localTime.seconds / transition.duration.seconds, 1))
            image = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: (1 - progress) * 35
            ]).cropped(to: originalExtent)
        }
        if let transition = plan.clip.transitionOut,
           transition.kind == .blur,
           localTime > plan.clip.duration - transition.duration {
            let progress = max(0, min((localTime - (plan.clip.duration - transition.duration)).seconds / transition.duration.seconds, 1))
            image = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: progress * 35
            ]).cropped(to: originalExtent)
        }
        return image
    }

    private func crop(_ image: CIImage, using transform: ClipTransform) -> CIImage {
        let extent = image.extent
        return image.cropped(to: CGRect(
            x: extent.minX + extent.width * CGFloat(transform.cropLeading),
            y: extent.minY + extent.height * CGFloat(transform.cropBottom),
            width: extent.width * CGFloat(max(0, 1 - transform.cropLeading - transform.cropTrailing)),
            height: extent.height * CGFloat(max(0, 1 - transform.cropTop - transform.cropBottom))
        ))
    }

    private func renderedTransform(plan: VideoClipRenderPlan, at timelineTime: RationalTime) -> CGAffineTransform {
        let clip = plan.clip
        let localTime = timelineTime - clip.timelineStart
        var transform = clip.transform
        transform.positionX = value(.positionX, clip: clip, at: localTime, fallback: transform.positionX)
        transform.positionY = value(.positionY, clip: clip, at: localTime, fallback: transform.positionY)
        transform.scale = value(.scale, clip: clip, at: localTime, fallback: transform.scale)
        transform.rotationDegrees = value(
            .rotationDegrees, clip: clip, at: localTime, fallback: transform.rotationDegrees
        )
        if let transition = clip.transitionIn, localTime < transition.duration {
            let progress = max(0, min(localTime.seconds / transition.duration.seconds, 1))
            if transition.kind == .slideLeft { transform.positionX += Double(plan.canvas.width) * (1 - progress) }
            if transition.kind == .slideRight { transform.positionX -= Double(plan.canvas.width) * (1 - progress) }
        }
        if let transition = clip.transitionOut, localTime > clip.duration - transition.duration {
            let progress = max(0, min((localTime - (clip.duration - transition.duration)).seconds / transition.duration.seconds, 1))
            if transition.kind == .slideLeft { transform.positionX -= Double(plan.canvas.width) * progress }
            if transition.kind == .slideRight { transform.positionX += Double(plan.canvas.width) * progress }
        }

        let transformedRect = CGRect(origin: .zero, size: plan.sourceSize).applying(plan.preferredTransform)
        var normalized = plan.preferredTransform
        normalized.tx -= transformedRect.minX
        normalized.ty -= transformedRect.minY
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let canvasSize = CGSize(width: CGFloat(plan.canvas.width), height: CGFloat(plan.canvas.height))
        let fit = min(canvasSize.width / displaySize.width, canvasSize.height / displaySize.height)
        let fill = max(canvasSize.width / displaySize.width, canvasSize.height / displaySize.height)
        let contentScale = transform.contentMode == .fit ? fit : fill
        let scale = contentScale * CGFloat(transform.scale)
        let scaled = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
        let base = normalized
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (canvasSize.width - scaled.width) / 2,
                y: (canvasSize.height - scaled.height) / 2
            ))
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let user = CGAffineTransform(translationX: -center.x, y: -center.y)
            .rotated(by: CGFloat(transform.rotationDegrees) * .pi / 180)
            .translatedBy(
                x: center.x + CGFloat(transform.positionX),
                y: center.y + CGFloat(transform.positionY)
            )
        return base.concatenating(user)
    }

    private func applyTransitionCrop(
        to image: CIImage,
        plan: VideoClipRenderPlan,
        at timelineTime: RationalTime,
        renderBounds: CGRect
    ) -> CIImage {
        let localTime = timelineTime - plan.clip.timelineStart
        var visible = renderBounds
        if let transition = plan.clip.transitionIn, transition.kind == .wipeLeft, localTime < transition.duration {
            let progress = max(0, min(localTime.seconds / transition.duration.seconds, 1))
            visible.size.width *= progress
        }
        if let transition = plan.clip.transitionOut,
           transition.kind == .wipeLeft,
           localTime > plan.clip.duration - transition.duration {
            let progress = max(0, min((localTime - (plan.clip.duration - transition.duration)).seconds / transition.duration.seconds, 1))
            visible.size.width *= 1 - progress
        }
        return image.cropped(to: visible)
    }

    private func videoOpacity(plan: VideoClipRenderPlan, at timelineTime: RationalTime) -> Double {
        let clip = plan.clip
        let time = timelineTime - clip.timelineStart
        var opacity = value(.opacity, clip: clip, at: time, fallback: clip.opacity)
        if clip.fades.videoIn > .zero, time < clip.fades.videoIn {
            opacity *= max(0, time.seconds / clip.fades.videoIn.seconds)
        }
        if clip.fades.videoOut > .zero, time > clip.duration - clip.fades.videoOut {
            opacity *= max(0, (clip.duration - time).seconds / clip.fades.videoOut.seconds)
        }
        if let transition = clip.transitionIn,
           [.crossDissolve, .fadeThroughBlack, .blur].contains(transition.kind),
           time < transition.duration {
            opacity *= max(0, time.seconds / transition.duration.seconds)
        }
        if let transition = clip.transitionOut,
           [.crossDissolve, .fadeThroughBlack, .blur].contains(transition.kind),
           time > clip.duration - transition.duration {
            opacity *= max(0, (clip.duration - time).seconds / transition.duration.seconds)
        }
        return min(max(opacity, 0), 1)
    }

    private func value(
        _ property: KeyframedProperty,
        clip: TimelineClip,
        at time: RationalTime,
        fallback: Double
    ) -> Double {
        KeyframeInterpolator.value(at: time, keyframes: clip.keyframes[property]) ?? fallback
    }
}

private enum CompositorError: Error {
    case invalidRequest
}
