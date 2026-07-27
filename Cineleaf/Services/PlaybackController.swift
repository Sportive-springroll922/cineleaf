import AVFoundation
import Combine
import CineleafCore

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime = RationalTime.zero
    @Published private(set) var duration = RationalTime.zero
    private var periodicObserver: Any?

    init() {
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = RationalTime(time)
            self.isPlaying = self.player.rate != 0
        }
    }

    deinit {
        if let periodicObserver { player.removeTimeObserver(periodicObserver) }
    }

    func load(_ rendered: RenderedComposition) {
        let item = AVPlayerItem(asset: rendered.composition)
        item.videoComposition = rendered.videoComposition
        item.audioMix = rendered.audioMix
        player.replaceCurrentItem(with: item)
        duration = rendered.duration
        currentTime = .zero
        isPlaying = false
    }

    func togglePlayback() {
        if player.rate == 0 {
            if currentTime >= duration { seek(to: .zero) }
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func seek(to time: RationalTime) {
        let target = time.clamped(to: .zero...max(duration, .zero))
        player.seek(to: target.cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = .zero
        duration = .zero
    }
}
