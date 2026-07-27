import Foundation

public enum SubtitleError: Error, Equatable, Sendable {
    case invalidCue(Int)
    case invalidTimestamp(String)
    case noCues
}

public enum SubtitleParser {
    public static func parse(_ contents: String, format: SubtitleFormat) throws -> [SubtitleCue] {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SubtitleError.noCues }

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        for (blockIndex, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n")
            if format == .webVTT, blockIndex == 0, lines.first?.hasPrefix("WEBVTT") == true { continue }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timingParts = lines[timingIndex].components(separatedBy: "-->")
            guard timingParts.count == 2 else { throw SubtitleError.invalidCue(blockIndex + 1) }
            let start = try timestamp(String(timingParts[0]))
            let endToken = timingParts[1].split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            let end = try timestamp(endToken)
            let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard end > start, !text.isEmpty else { throw SubtitleError.invalidCue(blockIndex + 1) }
            cues.append(SubtitleCue(start: start, duration: end - start, text: text))
        }
        guard !cues.isEmpty else { throw SubtitleError.noCues }
        return cues.sorted { $0.start < $1.start }
    }

    public static func serialize(_ cues: [SubtitleCue], format: SubtitleFormat) -> String {
        let header = format == .webVTT ? "WEBVTT\n\n" : ""
        let separator = format == .srt ? "," : "."
        let body = cues.sorted { $0.start < $1.start }.enumerated().map { index, cue in
            let timing = "\(formatted(cue.start, separator: separator)) --> \(formatted(cue.start + cue.duration, separator: separator))"
            return format == .srt ? "\(index + 1)\n\(timing)\n\(cue.text)" : "\(timing)\n\(cue.text)"
        }.joined(separator: "\n\n")
        return header + body + (body.isEmpty ? "" : "\n")
    }

    private static func timestamp(_ raw: String) throws -> RationalTime {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let components = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3,
              let seconds = Double(components.last ?? "") else {
            throw SubtitleError.invalidTimestamp(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let minutesIndex = components.count - 2
        guard let minutes = Double(components[minutesIndex]) else {
            throw SubtitleError.invalidTimestamp(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let hours: Double
        if components.count == 3, let parsedHours = Double(components[0]) {
            hours = parsedHours
        } else if components.count == 2 {
            hours = 0
        } else {
            throw SubtitleError.invalidTimestamp(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard hours >= 0, minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else {
            throw SubtitleError.invalidTimestamp(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return RationalTime(seconds: hours * 3_600 + minutes * 60 + seconds, preferredTimescale: 1_000)
    }

    private static func formatted(_ time: RationalTime, separator: String) -> String {
        let milliseconds = max(Int64((time.seconds * 1_000).rounded()), 0)
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let seconds = (milliseconds / 1_000) % 60
        let fraction = milliseconds % 1_000
        return String(format: "%02lld:%02lld:%02lld%@%03lld", hours, minutes, seconds, separator, fraction)
    }
}
