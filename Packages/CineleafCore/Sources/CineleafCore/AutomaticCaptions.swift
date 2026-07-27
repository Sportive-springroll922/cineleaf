import Foundation

public struct TranscriptToken: Codable, Hashable, Sendable {
    public var text: String
    public var start: RationalTime
    public var duration: RationalTime

    public init(text: String, start: RationalTime, duration: RationalTime) {
        self.text = text
        self.start = start
        self.duration = duration
    }
}

public enum AutomaticCaptionBuilder {
    public static func cues(
        from tokens: [TranscriptToken],
        maximumCharacters: Int = 42,
        maximumDuration: Double = 4
    ) -> [SubtitleCue] {
        guard maximumCharacters > 0, maximumDuration > 0 else { return [] }
        let ordered = tokens.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        var result: [SubtitleCue] = []
        var group: [TranscriptToken] = []

        func flush() {
            guard let first = group.first, let last = group.last else { return }
            let text = group.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
            result.append(SubtitleCue(start: first.start, duration: last.start + last.duration - first.start, text: text))
            group.removeAll(keepingCapacity: true)
        }

        for token in ordered {
            let candidateCount = group.map(\.text).reduce(0) { $0 + $1.count } + max(group.count, 1) + token.text.count
            let candidateDuration = group.first.map { (token.start + token.duration - $0.start).seconds } ?? token.duration.seconds
            if !group.isEmpty, candidateCount > maximumCharacters || candidateDuration > maximumDuration { flush() }
            group.append(token)
            if token.text.last.map({ ".!?".contains($0) }) == true { flush() }
        }
        flush()
        return result
    }
}
