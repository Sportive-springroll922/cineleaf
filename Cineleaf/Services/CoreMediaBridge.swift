import CoreMedia
import CineleafCore

extension RationalTime {
    var cmTime: CMTime {
        CMTime(value: value, timescale: timescale)
    }

    init(_ time: CMTime) {
        if time.isNumeric, time.timescale > 0 {
            self.init(value: time.value, timescale: time.timescale)
        } else {
            self = .zero
        }
    }
}

extension RationalTimeRange {
    var cmTimeRange: CMTimeRange {
        CMTimeRange(start: start.cmTime, duration: duration.cmTime)
    }
}
