import AppKit
import CineleafCore
import SwiftUI

struct TimelineScrollView: NSViewRepresentable {
    var project: CineleafProject
    var selectedClipIDs: Set<UUID>
    var pixelsPerSecond: Double
    var playhead: RationalTime
    var waveforms: [UUID: [Float]]
    var locale: Locale
    var onSelect: (UUID, Bool) -> Void
    var onMove: (UUID, RationalTime, UUID) -> Void
    var onTrimStart: (UUID, RationalTime) -> Void
    var onTrimEnd: (UUID, RationalTime) -> Void
    var onSeek: (RationalTime) -> Void
    var onSnap: (RationalTime, UUID) -> RationalTime
    var onDropAsset: (UUID, UUID?, RationalTime?) -> Void
    var onMuteTrack: (UUID, Bool) -> Void
    var onLockTrack: (UUID, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.setAccessibilityIdentifier("editor.timeline")
        let timeline = TimelineDrawingView()
        timeline.coordinator = context.coordinator
        scrollView.documentView = timeline
        context.coordinator.update(timeline)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let timeline = scrollView.documentView as? TimelineDrawingView else { return }
        context.coordinator.update(timeline)
    }

    final class Coordinator {
        var parent: TimelineScrollView

        init(parent: TimelineScrollView) { self.parent = parent }

        func update(_ view: TimelineDrawingView) {
            view.project = parent.project
            view.selectedClipIDs = parent.selectedClipIDs
            view.pixelsPerSecond = parent.pixelsPerSecond
            view.playhead = parent.playhead
            view.waveforms = parent.waveforms
            view.locale = parent.locale
            let durationWidth = max(parent.project.timeline.duration.seconds * parent.pixelsPerSecond, 800)
            view.frame = CGRect(
                x: 0,
                y: 0,
                width: TimelineDrawingView.headerWidth + CGFloat(durationWidth) + 240,
                height: TimelineDrawingView.rulerHeight
                    + CGFloat(max(parent.project.timeline.tracks.count, 1)) * TimelineDrawingView.trackHeight
            )
            view.needsDisplay = true
        }
    }
}

final class TimelineDrawingView: NSView {
    static let headerWidth: CGFloat = 108
    static let rulerHeight: CGFloat = 28
    static let trackHeight: CGFloat = 54
    weak var coordinator: TimelineScrollView.Coordinator?
    var project = CineleafProject(name: "")
    var selectedClipIDs: Set<UUID> = []
    var pixelsPerSecond = 80.0
    var playhead = RationalTime.zero
    var waveforms: [UUID: [Float]] = [:]
    var locale = Locale.autoupdatingCurrent

    private enum InteractionMode: Equatable {
        case move
        case trimStart
        case trimEnd
        case scrub
    }

    private struct Interaction {
        var mode: InteractionMode
        var clipID: UUID?
        var sourceTrackID: UUID?
        var targetTrackID: UUID?
        var mouseStart: CGPoint
        var originalStart: RationalTime
        var originalEnd: RationalTime
        var proposedStart: RationalTime
        var proposedEnd: RationalTime
    }

    private var interaction: Interaction?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "timeline.accessibility"))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.string])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let visible = visibleRect
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: visible).fill()
        drawRuler(in: visible)
        for (index, track) in project.timeline.tracks.enumerated() {
            drawTrack(track, index: index, visible: visible)
        }
        drawPlayhead(visible: visible)
        drawPinnedHeaders(visible: visible)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let coordinator else { return }
        if handleTrackControl(at: point, coordinator: coordinator) { return }
        if let hit = hitClip(at: point) {
            coordinator.parent.onSelect(hit.clip.id, event.modifierFlags.contains(.command))
            let rect = clipRect(hit.clip, trackIndex: hit.trackIndex)
            let edge: CGFloat = 7
            let mode: InteractionMode
            if abs(point.x - rect.minX) <= edge { mode = .trimStart }
            else if abs(point.x - rect.maxX) <= edge { mode = .trimEnd }
            else { mode = .move }
            interaction = Interaction(
                mode: mode,
                clipID: hit.clip.id,
                sourceTrackID: project.timeline.tracks[hit.trackIndex].id,
                targetTrackID: project.timeline.tracks[hit.trackIndex].id,
                mouseStart: point,
                originalStart: hit.clip.timelineStart,
                originalEnd: hit.clip.timelineEnd,
                proposedStart: hit.clip.timelineStart,
                proposedEnd: hit.clip.timelineEnd
            )
        } else {
            let time = time(at: point.x)
            interaction = Interaction(
                mode: .scrub,
                mouseStart: point,
                originalStart: time,
                originalEnd: time,
                proposedStart: time,
                proposedEnd: time
            )
            coordinator.parent.onSeek(time)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var interaction, let coordinator else { return }
        let point = convert(event.locationInWindow, from: nil)
        if interaction.mode == .scrub {
            coordinator.parent.onSeek(time(at: point.x))
            return
        }
        guard let clipID = interaction.clipID else { return }
        let delta = RationalTime(
            seconds: Double(point.x - interaction.mouseStart.x) / pixelsPerSecond,
            preferredTimescale: 6_000
        )
        switch interaction.mode {
        case .move:
            interaction.proposedStart = coordinator.parent.onSnap(
                max(interaction.originalStart + delta, .zero),
                clipID
            )
            if let track = track(at: point), clip(id: clipID)?.kind.compatibleTrack == track.kind, !track.isLocked {
                interaction.targetTrackID = track.id
            }
        case .trimStart:
            interaction.proposedStart = coordinator.parent.onSnap(
                max(interaction.originalStart + delta, .zero),
                clipID
            )
        case .trimEnd:
            interaction.proposedEnd = coordinator.parent.onSnap(
                max(interaction.originalEnd + delta, interaction.originalStart),
                clipID
            )
        case .scrub:
            break
        }
        self.interaction = interaction
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let interaction, let coordinator else { self.interaction = nil; return }
        defer { self.interaction = nil; needsDisplay = true }
        guard let clipID = interaction.clipID else { return }
        switch interaction.mode {
        case .move:
            guard let target = interaction.targetTrackID else { return }
            coordinator.parent.onMove(clipID, interaction.proposedStart, target)
        case .trimStart:
            coordinator.parent.onTrimStart(clipID, interaction.proposedStart)
        case .trimEnd:
            coordinator.parent.onTrimEnd(clipID, interaction.proposedEnd)
        case .scrub:
            break
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        assetID(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let id = assetID(from: sender), let coordinator else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        coordinator.parent.onDropAsset(id, track(at: point)?.id, time(at: point.x))
        return true
    }

    private func drawRuler(in visible: CGRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(rect: CGRect(x: visible.minX, y: 0, width: visible.width, height: Self.rulerHeight)).fill()
        let minimumSpacing: CGFloat = 72
        let rawStep = minimumSpacing / pixelsPerSecond
        let candidates = [1.0, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let step = candidates.first(where: { $0 >= rawStep }) ?? 600
        let firstSecond = max(floor((Double(visible.minX - Self.headerWidth) / pixelsPerSecond) / step) * step, 0)
        var second = firstSecond
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        while xPosition(second) <= visible.maxX {
            let x = xPosition(second)
            NSColor.separatorColor.setStroke()
            let line = NSBezierPath()
            line.move(to: CGPoint(x: x, y: Self.rulerHeight - 7))
            line.line(to: CGPoint(x: x, y: Self.rulerHeight))
            line.stroke()
            let label = DurationText.string(RationalTime(seconds: second), locale: locale)
            label.draw(at: CGPoint(x: x + 3, y: 6), withAttributes: attributes)
            second += step
        }
    }

    private func drawTrack(_ track: TimelineTrack, index: Int, visible: CGRect) {
        let y = Self.rulerHeight + CGFloat(index) * Self.trackHeight
        let row = CGRect(x: visible.minX, y: y, width: visible.width, height: Self.trackHeight)
        (index.isMultiple(of: 2) ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor)
            .withAlphaComponent(0.72).setFill()
        NSBezierPath(rect: row).fill()
        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: CGPoint(x: visible.minX, y: row.maxY - 0.5))
        separator.line(to: CGPoint(x: visible.maxX, y: row.maxY - 0.5))
        separator.stroke()

        let preload = visible.insetBy(dx: -200, dy: 0)
        for clip in track.clips {
            var displayed = clip
            if let interaction, interaction.clipID == clip.id {
                switch interaction.mode {
                case .move:
                    guard interaction.targetTrackID == track.id else { continue }
                    displayed.timelineStart = interaction.proposedStart
                case .trimStart:
                    let delta = interaction.proposedStart - displayed.timelineStart
                    displayed.timelineStart = interaction.proposedStart
                    displayed.duration = max(displayed.duration - delta, RationalTime(value: 1, timescale: 6_000))
                case .trimEnd:
                    displayed.duration = max(
                        interaction.proposedEnd - displayed.timelineStart,
                        RationalTime(value: 1, timescale: 6_000)
                    )
                case .scrub:
                    break
                }
            }
            let rect = clipRect(displayed, trackIndex: index)
            guard rect.intersects(preload) else { continue }
            drawClip(displayed, rect: rect)
        }
        if let interaction,
           interaction.mode == .move,
           interaction.targetTrackID == track.id,
           interaction.sourceTrackID != track.id,
           let clipID = interaction.clipID,
           var moving = clip(id: clipID) {
            moving.timelineStart = interaction.proposedStart
            let rect = clipRect(moving, trackIndex: index)
            if rect.intersects(preload) { drawClip(moving, rect: rect) }
        }
    }

    private func drawClip(_ clip: TimelineClip, rect: CGRect) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        clipColor(clip).withAlphaComponent(clip.isEnabled ? 0.82 : 0.35).setFill()
        shape.fill()
        if selectedClipIDs.contains(clip.id) {
            NSColor.controlAccentColor.setStroke()
            shape.lineWidth = 3
            shape.stroke()
            NSColor.white.withAlphaComponent(0.8).setFill()
            NSBezierPath(rect: CGRect(x: rect.minX + 3, y: rect.minY + 5, width: 3, height: rect.height - 10)).fill()
            NSBezierPath(rect: CGRect(x: rect.maxX - 6, y: rect.minY + 5, width: 3, height: rect.height - 10)).fill()
        }

        let textRect = rect.insetBy(dx: 8, dy: 5)
        clip.name.draw(in: textRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: truncatingParagraphStyle
        ])
        if let assetID = clip.assetID, let peaks = waveforms[assetID], !peaks.isEmpty {
            drawWaveform(peaks, in: rect.insetBy(dx: 5, dy: 16))
        }
    }

    private func drawWaveform(_ peaks: [Float], in rect: CGRect) {
        guard rect.width > 2, rect.height > 2 else { return }
        NSColor.white.withAlphaComponent(0.42).setStroke()
        let path = NSBezierPath()
        let columns = max(Int(rect.width), 1)
        for column in 0..<columns {
            let index = min(column * peaks.count / columns, peaks.count - 1)
            let height = CGFloat(peaks[index]) * rect.height
            let x = rect.minX + CGFloat(column)
            path.move(to: CGPoint(x: x, y: rect.midY - height / 2))
            path.line(to: CGPoint(x: x, y: rect.midY + height / 2))
        }
        path.stroke()
    }

    private func drawPlayhead(visible: CGRect) {
        let x = xPosition(playhead.seconds)
        guard x >= visible.minX, x <= visible.maxX else { return }
        NSColor.systemRed.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.move(to: CGPoint(x: x, y: 0))
        path.line(to: CGPoint(x: x, y: bounds.maxY))
        path.stroke()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: CGRect(x: x - 4, y: Self.rulerHeight - 6, width: 8, height: 8)).fill()
    }

    private func drawPinnedHeaders(visible: CGRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(rect: CGRect(x: visible.minX, y: 0, width: Self.headerWidth, height: visible.height)).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath()
        border.move(to: CGPoint(x: visible.minX + Self.headerWidth - 0.5, y: 0))
        border.line(to: CGPoint(x: visible.minX + Self.headerWidth - 0.5, y: visible.maxY))
        border.stroke()
        for (index, track) in project.timeline.tracks.enumerated() {
            let y = Self.rulerHeight + CGFloat(index) * Self.trackHeight
            track.name.draw(at: CGPoint(x: visible.minX + 9, y: y + 18), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ])
            drawSymbol(track.isMuted ? "speaker.slash.fill" : "speaker.wave.2", at: visible.minX + 60, y: y + 18)
            drawSymbol(track.isLocked ? "lock.fill" : "lock.open", at: visible.minX + 84, y: y + 18)
        }
    }

    private func drawSymbol(_ name: String, at x: CGFloat, y: CGFloat) {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.draw(
            in: CGRect(x: x, y: y, width: 14, height: 14)
        )
    }

    private func handleTrackControl(at point: CGPoint, coordinator: TimelineScrollView.Coordinator) -> Bool {
        let pinnedX = visibleRect.minX
        guard point.x >= pinnedX, point.x <= pinnedX + Self.headerWidth,
              let track = track(at: point) else { return false }
        if point.x >= pinnedX + 55, point.x < pinnedX + 80 {
            coordinator.parent.onMuteTrack(track.id, !track.isMuted)
            return true
        }
        if point.x >= pinnedX + 80 {
            coordinator.parent.onLockTrack(track.id, !track.isLocked)
            return true
        }
        return false
    }

    private func hitClip(at point: CGPoint) -> (clip: TimelineClip, trackIndex: Int)? {
        guard let index = trackIndex(at: point) else { return nil }
        for clip in project.timeline.tracks[index].clips.reversed() where clipRect(clip, trackIndex: index).contains(point) {
            return (clip, index)
        }
        return nil
    }

    private func clip(id: UUID) -> TimelineClip? {
        project.timeline.tracks.flatMap(\.clips).first { $0.id == id }
    }

    private func clipRect(_ clip: TimelineClip, trackIndex: Int) -> CGRect {
        CGRect(
            x: xPosition(clip.timelineStart.seconds) + 2,
            y: Self.rulerHeight + CGFloat(trackIndex) * Self.trackHeight + 5,
            width: max(clip.duration.seconds * pixelsPerSecond - 4, 8),
            height: Self.trackHeight - 10
        )
    }

    private func trackIndex(at point: CGPoint) -> Int? {
        let index = Int((point.y - Self.rulerHeight) / Self.trackHeight)
        return project.timeline.tracks.indices.contains(index) ? index : nil
    }

    private func track(at point: CGPoint) -> TimelineTrack? {
        trackIndex(at: point).map { project.timeline.tracks[$0] }
    }

    private func time(at x: CGFloat) -> RationalTime {
        RationalTime(seconds: max(Double(x - Self.headerWidth) / pixelsPerSecond, 0), preferredTimescale: 6_000)
    }

    private func xPosition(_ seconds: Double) -> CGFloat {
        Self.headerWidth + CGFloat(seconds * pixelsPerSecond)
    }

    private func assetID(from sender: NSDraggingInfo) -> UUID? {
        sender.draggingPasteboard.string(forType: .string).flatMap(UUID.init(uuidString:))
    }

    private var truncatingParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private func clipColor(_ clip: TimelineClip) -> NSColor {
        switch clip.kind {
        case .video: NSColor.systemTeal
        case .audio: NSColor.systemIndigo
        case .image: NSColor.systemGreen
        case .text: NSColor.systemOrange
        }
    }
}
