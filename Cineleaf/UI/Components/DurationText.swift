import Foundation
import CineleafCore

enum DurationText {
    static func string(_ time: RationalTime, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = time.seconds >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: max(time.seconds, 0)) ?? String(localized: "duration.zero")
    }
}
