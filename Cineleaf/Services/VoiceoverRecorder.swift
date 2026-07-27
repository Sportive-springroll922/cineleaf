import AVFAudio
import AVFoundation
import Foundation

enum VoiceoverError: Error {
    case permissionDenied
    case cannotPrepare
    case cannotRecord
    case notRecording
}

@MainActor
final class VoiceoverRecorder {
    private var recorder: AVAudioRecorder?

    var isRecording: Bool { recorder?.isRecording == true }

    func start() async throws {
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else { throw VoiceoverError.permissionDenied }
        let directory = try recordingsDirectory()
        let url = directory.appendingPathComponent("Voiceover-\(UUID().uuidString)").appendingPathExtension("m4a")
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else { throw VoiceoverError.cannotPrepare }
        guard recorder.record() else { throw VoiceoverError.cannotRecord }
        self.recorder = recorder
    }

    func stop() throws -> URL {
        guard let recorder, recorder.isRecording else { throw VoiceoverError.notRecording }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        return url
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        _ = recorder.deleteRecording()
        self.recorder = nil
    }

    private func recordingsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Cineleaf", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
