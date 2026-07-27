import Foundation

public struct TimelineIndex: Sendable {
    private struct IndexedClip: Sendable {
        var clip: TimelineClip
        var maximumEnd: RationalTime
    }

    private let clipsByTrack: [UUID: [IndexedClip]]

    public init(timeline: Timeline) {
        clipsByTrack = Dictionary(uniqueKeysWithValues: timeline.tracks.map { track in
            let ordered = track.clips.sorted {
                if $0.timelineStart == $1.timelineStart { return $0.id.uuidString < $1.id.uuidString }
                return $0.timelineStart < $1.timelineStart
            }
            var maximumEnd = RationalTime.zero
            let indexed = ordered.map { clip in
                maximumEnd = max(maximumEnd, clip.timelineEnd)
                return IndexedClip(clip: clip, maximumEnd: maximumEnd)
            }
            return (track.id, indexed)
        })
    }

    public func clips(in range: RationalTimeRange, trackID: UUID) -> [TimelineClip] {
        guard range.duration > .zero, let indexed = clipsByTrack[trackID], !indexed.isEmpty else { return [] }

        var lower = 0
        var upper = indexed.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if indexed[middle].maximumEnd <= range.start {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        var result: [TimelineClip] = []
        result.reserveCapacity(min(32, indexed.count - lower))
        for entry in indexed[lower...] {
            if entry.clip.timelineStart >= range.end { break }
            if entry.clip.timeRange.intersects(range) { result.append(entry.clip) }
        }
        return result
    }
}
