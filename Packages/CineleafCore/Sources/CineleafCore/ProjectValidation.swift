import Foundation

public enum ProjectValidationError: Error, Equatable, Sendable {
    case unsupportedFormatVersion(Int)
    case invalidCanvas
    case duplicateIdentifier(UUID)
    case invalidTime(UUID)
    case incompatibleTrack(UUID)
    case missingAsset(UUID)
    case missingText(UUID)
    case overlappingClips(UUID, UUID)
    case invalidOpacity(UUID)
    case invalidAudioVolume(UUID)
    case invalidTransform(UUID)
    case invalidFade(UUID)
    case invalidPlaybackRate(UUID)
    case invalidColorAdjustments(UUID)
    case invalidEffect(UUID)
    case invalidTransition(UUID)
    case invalidKeyframe(UUID)
    case invalidRole(UUID)
}

public enum ProjectValidator {
    public static func validate(_ project: CineleafProject) throws {
        guard project.formatVersion == CineleafProject.currentFormatVersion else {
            throw ProjectValidationError.unsupportedFormatVersion(project.formatVersion)
        }
        guard project.canvas.width > 0 && project.canvas.height > 0 else {
            throw ProjectValidationError.invalidCanvas
        }

        var identifiers = Set<UUID>()
        guard identifiers.insert(project.id).inserted else {
            throw ProjectValidationError.duplicateIdentifier(project.id)
        }
        let assetIDs = Set(project.assets.map(\.id))
        let assetsByID = Dictionary(uniqueKeysWithValues: project.assets.map { ($0.id, $0) })
        for asset in project.assets where !identifiers.insert(asset.id).inserted {
            throw ProjectValidationError.duplicateIdentifier(asset.id)
        }
        for marker in project.timeline.markers {
            guard identifiers.insert(marker.id).inserted else {
                throw ProjectValidationError.duplicateIdentifier(marker.id)
            }
            guard marker.time >= .zero else { throw ProjectValidationError.invalidTime(marker.id) }
        }

        for track in project.timeline.tracks {
            guard identifiers.insert(track.id).inserted else {
                throw ProjectValidationError.duplicateIdentifier(track.id)
            }

            let ordered = track.clips.sorted { $0.timelineStart < $1.timelineStart }
            for (index, clip) in ordered.enumerated() {
                guard identifiers.insert(clip.id).inserted else {
                    throw ProjectValidationError.duplicateIdentifier(clip.id)
                }
                guard clip.timelineStart >= .zero, clip.sourceStart >= .zero, clip.duration > .zero else {
                    throw ProjectValidationError.invalidTime(clip.id)
                }
                guard clip.playbackRate.isFinite, (0.25...4).contains(clip.playbackRate) else {
                    throw ProjectValidationError.invalidPlaybackRate(clip.id)
                }
                guard clip.kind.compatibleTrack == track.kind else {
                    throw ProjectValidationError.incompatibleTrack(clip.id)
                }
                if clip.kind == .text {
                    guard clip.textStyle != nil, clip.assetID == nil else {
                        throw ProjectValidationError.missingText(clip.id)
                    }
                } else if let assetID = clip.assetID {
                    guard assetIDs.contains(assetID) else {
                        throw ProjectValidationError.missingAsset(assetID)
                    }
                    if clip.kind != .image,
                       let sourceDuration = assetsByID[assetID]?.metadata.duration,
                       clip.sourceStart + scaled(clip.duration, by: clip.playbackRate) > sourceDuration {
                        throw ProjectValidationError.invalidTime(clip.id)
                    }
                } else {
                    throw ProjectValidationError.missingAsset(clip.id)
                }
                guard (0...1).contains(clip.opacity) else {
                    throw ProjectValidationError.invalidOpacity(clip.id)
                }
                guard (0...2).contains(clip.audioVolume) else {
                    throw ProjectValidationError.invalidAudioVolume(clip.id)
                }
                let transform = clip.transform
                guard transform.scale > 0,
                      [transform.positionX, transform.positionY, transform.scale, transform.rotationDegrees,
                       transform.cropTop, transform.cropLeading, transform.cropBottom, transform.cropTrailing]
                        .allSatisfy(\.isFinite),
                      [transform.cropTop, transform.cropLeading, transform.cropBottom, transform.cropTrailing]
                        .allSatisfy({ (0...1).contains($0) }) else {
                    throw ProjectValidationError.invalidTransform(clip.id)
                }
                let fades = [clip.fades.videoIn, clip.fades.videoOut, clip.fades.audioIn, clip.fades.audioOut]
                guard fades.allSatisfy({ $0 >= .zero && $0 <= clip.duration }),
                      clip.fades.videoIn + clip.fades.videoOut <= clip.duration,
                      clip.fades.audioIn + clip.fades.audioOut <= clip.duration else {
                    throw ProjectValidationError.invalidFade(clip.id)
                }
                let color = clip.colorAdjustments
                guard [color.exposure, color.contrast, color.saturation, color.temperature, color.tint,
                       color.highlights, color.shadows, color.sharpen, color.vignette].allSatisfy(\.isFinite),
                      (-4...4).contains(color.exposure), (0...4).contains(color.contrast),
                      (0...4).contains(color.saturation), (-1...1).contains(color.temperature),
                      (-1...1).contains(color.tint), (-1...1).contains(color.highlights),
                      (-1...1).contains(color.shadows), (0...1).contains(color.sharpen),
                      (0...1).contains(color.vignette) else {
                    throw ProjectValidationError.invalidColorAdjustments(clip.id)
                }
                var effectIDs = Set<UUID>()
                for effect in clip.effects {
                    guard effectIDs.insert(effect.id).inserted else {
                        throw ProjectValidationError.duplicateIdentifier(effect.id)
                    }
                    guard effect.amount.isFinite, (0...1).contains(effect.amount) else {
                        throw ProjectValidationError.invalidEffect(clip.id)
                    }
                }
                for transition in [clip.transitionIn, clip.transitionOut].compactMap({ $0 }) {
                    guard transition.duration > .zero, transition.duration <= clip.duration else {
                        throw ProjectValidationError.invalidTransition(clip.id)
                    }
                }
                guard validKeyframes(clip.keyframes, duration: clip.duration) else {
                    throw ProjectValidationError.invalidKeyframe(clip.id)
                }
                switch clip.role {
                case .standard: break
                case .subtitle where clip.kind == .text: break
                case .voiceover where clip.kind == .audio: break
                default: throw ProjectValidationError.invalidRole(clip.id)
                }
                if index > 0 {
                    let previous = ordered[index - 1]
                    if previous.timeRange.intersects(clip.timeRange) {
                        throw ProjectValidationError.overlappingClips(previous.id, clip.id)
                    }
                }
            }
        }
    }

    private static func scaled(_ time: RationalTime, by factor: Double) -> RationalTime {
        RationalTime(seconds: time.seconds * factor, preferredTimescale: 60_000)
    }

    private static func validKeyframes(_ keyframes: ClipKeyframes, duration: RationalTime) -> Bool {
        for property in KeyframedProperty.allCases {
            let frames = keyframes[property]
            guard frames.allSatisfy({ $0.time >= .zero && $0.time <= duration && $0.value.isFinite }) else {
                return false
            }
            guard zip(frames, frames.dropFirst()).allSatisfy({ pair in pair.0.time < pair.1.time }) else { return false }
            switch property {
            case .opacity where !frames.allSatisfy({ (0...1).contains($0.value) }): return false
            case .volume where !frames.allSatisfy({ (0...2).contains($0.value) }): return false
            case .scale where !frames.allSatisfy({ $0.value > 0 }): return false
            default: break
            }
        }
        return true
    }
}
