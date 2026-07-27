import AVFoundation
import Foundation

enum ProxyMediaError: Error {
    case unsupported
    case exportFailed(String)
    case cancelled
}

private final class ProxyExportBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

actor ProxyMediaService {
    private let store: MediaDerivativeStore
    private var activeSession: AVAssetExportSession?

    init(store: MediaDerivativeStore = .shared) {
        self.store = store
    }

    func generate(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = [
            "proxy-540p", url.path, "\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)",
            "\(values.fileSize ?? 0)"
        ].joined(separator: "|")
        if let cached = try await store.cachedURL(for: key, extension: "mov") {
            progress(1)
            return cached
        }
        let output = try await store.temporaryURL(extension: "mov")
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality),
              session.supportedFileTypes.contains(.mov) else { throw ProxyMediaError.unsupported }
        session.outputURL = output
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false
        activeSession = session
        let box = ProxyExportBox(session)
        do {
            try await withTaskCancellationHandler {
                let monitor = Task {
                    while !Task.isCancelled {
                        progress(Double(box.session.progress))
                        try await Task.sleep(for: .milliseconds(100))
                    }
                }
                defer { monitor.cancel() }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    box.session.exportAsynchronously {
                        switch box.session.status {
                        case .completed: continuation.resume()
                        case .cancelled: continuation.resume(throwing: ProxyMediaError.cancelled)
                        case .failed:
                            continuation.resume(throwing: ProxyMediaError.exportFailed(
                                box.session.error?.localizedDescription ?? "unknown"
                            ))
                        default: continuation.resume(throwing: ProxyMediaError.exportFailed("unexpected export state"))
                        }
                    }
                }
            } onCancel: {
                box.session.cancelExport()
            }
            activeSession = nil
            progress(1)
            return try await store.commit(output, for: key, extension: "mov")
        } catch {
            activeSession = nil
            await store.discard(output)
            throw error
        }
    }

    func cancel() {
        activeSession?.cancelExport()
    }
}
