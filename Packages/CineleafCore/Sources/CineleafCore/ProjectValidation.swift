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
                       clip.sourceStart + clip.duration > sourceDuration {
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
                if index > 0 {
                    let previous = ordered[index - 1]
                    if previous.timeRange.intersects(clip.timeRange) {
                        throw ProjectValidationError.overlappingClips(previous.id, clip.id)
                    }
                }
            }
        }
    }
}
