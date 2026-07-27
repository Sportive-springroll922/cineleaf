import CineleafCore
import Foundation
import Speech

enum TranscriptionError: Error {
    case authorizationDenied
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case recognitionFailed
    case noSpeechDetected
}

actor OnDeviceTranscriptionService {
    private var activeTask: SFSpeechRecognitionTask?

    func transcribe(url: URL, locale: Locale = .current) async throws -> [SubtitleCue] {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else { throw TranscriptionError.authorizationDenied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceRecognitionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let tokens = try await withTaskCancellationHandler {
            try await recognize(recognizer: recognizer, request: request)
        } onCancel: {
            Task { await self.cancel() }
        }
        let cues = AutomaticCaptionBuilder.cues(from: tokens)
        guard !cues.isEmpty else { throw TranscriptionError.noSpeechDetected }
        return cues
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    private func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> [TranscriptToken] {
        let gate = RecognitionGate()
        defer { activeTask = nil }
        return try await withCheckedThrowingContinuation { continuation in
            activeTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    gate.resume(continuation, with: .failure(error))
                    return
                }
                guard let result, result.isFinal else { return }
                let tokens = result.bestTranscription.segments.map { segment in
                    TranscriptToken(
                        text: segment.substring,
                        start: RationalTime(seconds: segment.timestamp, preferredTimescale: 1_000),
                        duration: RationalTime(seconds: max(segment.duration, 0.01), preferredTimescale: 1_000)
                    )
                }
                gate.resume(continuation, with: tokens.isEmpty ? .failure(TranscriptionError.noSpeechDetected) : .success(tokens))
            }
        }
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}

private final class RecognitionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume<T>(_ continuation: CheckedContinuation<T, Error>, with result: Result<T, Error>) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume(with: result)
    }
}
