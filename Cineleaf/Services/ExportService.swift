import AVFoundation
import Foundation
import CineleafCore

enum ExportError: Error {
    case cannotCreateSession
    case unsupportedOutputType
    case invalidDestination
    case insufficientDiskSpace
    case cancelled
    case failed(String)
    case outputValidationFailed
}

struct ExportResult: Sendable {
    var url: URL
    var duration: RationalTime
    var resolution: Resolution
    var hasVideo: Bool
    var hasAudio: Bool
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

actor AVExportService {
    private var currentSession: AVAssetExportSession?
    private let minimumFreeBytes: Int64 = 100 * 1_024 * 1_024

    func export(
        rendered: RenderedComposition,
        plan: ExportPlan,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportResult {
        guard destination.isFileURL else { throw ExportError.invalidDestination }
        let parent = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExportError.invalidDestination
        }
        let resourceValues = try parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = resourceValues.volumeAvailableCapacityForImportantUsage,
           available < minimumFreeBytes {
            throw ExportError.insufficientDiskSpace
        }

        let preset = presetName(for: plan)
        guard let session = AVAssetExportSession(asset: rendered.composition, presetName: preset) else {
            throw ExportError.cannotCreateSession
        }
        let fileType: AVFileType = plan.container == .mp4 ? .mp4 : .mov
        guard session.supportedFileTypes.contains(fileType) else { throw ExportError.unsupportedOutputType }
        if FileManager.default.fileExists(atPath: destination.path) {
            var existingIsDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: destination.path, isDirectory: &existingIsDirectory)
            guard !existingIsDirectory.boolValue else { throw ExportError.invalidDestination }
            try FileManager.default.removeItem(at: destination)
        }

        session.outputURL = destination
        session.outputFileType = fileType
        session.videoComposition = rendered.videoComposition
        session.audioMix = rendered.audioMix
        session.shouldOptimizeForNetworkUse = false
        if plan.quality != .high {
            let pixels = Double(plan.resolution.width * plan.resolution.height)
            let scale = max(pixels / Double(1920 * 1080), 0.25)
            let bitsPerSecond = (plan.quality == .compact ? 3_000_000.0 : 8_000_000.0) * scale
            session.fileLengthLimit = Int64((rendered.duration.seconds * (bitsPerSecond + 192_000)) / 8)
        }
        currentSession = session
        let sessionBox = ExportSessionBox(session)
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Cineleaf export"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            currentSession = nil
        }

        do {
            try await LocalDiagnostics.shared.measure("export") {
                try await Self.run(sessionBox: sessionBox, progress: progress)
            }
            let result = try await validate(url: destination, expected: plan)
            progress(1)
            return result
        } catch {
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            throw error
        }
    }

    func cancel() {
        currentSession?.cancelExport()
    }

    private static func run(
        sessionBox: ExportSessionBox,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let monitor = Task {
            while !Task.isCancelled {
                progress(Double(sessionBox.session.progress))
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { monitor.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sessionBox.session.exportAsynchronously {
                    switch sessionBox.session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: ExportError.cancelled)
                    case .failed:
                        continuation.resume(
                            throwing: ExportError.failed(sessionBox.session.error?.localizedDescription ?? "unknown")
                        )
                    default:
                        continuation.resume(throwing: ExportError.failed("unexpected export state"))
                    }
                }
            }
        } onCancel: {
            sessionBox.session.cancelExport()
        }
    }

    private func validate(url: URL, expected: ExportPlan) async throws -> ExportResult {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard duration.isNumeric, duration > .zero, let video = videoTracks.first else {
            throw ExportError.outputValidationFailed
        }
        let naturalSize = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let resolution = Resolution(width: Int(abs(rect.width).rounded()), height: Int(abs(rect.height).rounded()))
        guard resolution == expected.resolution else { throw ExportError.outputValidationFailed }
        return ExportResult(
            url: url,
            duration: RationalTime(duration),
            resolution: resolution,
            hasVideo: true,
            hasAudio: !audioTracks.isEmpty
        )
    }

    private func presetName(for plan: ExportPlan) -> String {
        if plan.codec == .hevc { return AVAssetExportPresetHEVCHighestQuality }
        switch max(plan.resolution.width, plan.resolution.height) {
        case ...1280: return AVAssetExportPreset1280x720
        case ...1920: return AVAssetExportPreset1920x1080
        case ...2560: return AVAssetExportPresetHighestQuality
        default: return AVAssetExportPreset3840x2160
        }
    }
}
