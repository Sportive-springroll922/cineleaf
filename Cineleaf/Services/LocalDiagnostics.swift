import Foundation
import os

struct DiagnosticEvent: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let category: String
    let milliseconds: Double
}

actor LocalDiagnostics {
    static let shared = LocalDiagnostics()
    private let logger = Logger(subsystem: "org.cineleaf.Cineleaf", category: "performance")
    private var events: [DiagnosticEvent] = []
    private let eventLimit = 100

    func measure<T: Sendable>(
        _ category: String,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let value = try await operation()
        let elapsed = start.duration(to: clock.now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        logger.debug("\(category, privacy: .public) completed in \(milliseconds, privacy: .public) ms")
        events.append(DiagnosticEvent(date: Date(), category: category, milliseconds: milliseconds))
        if events.count > eventLimit { events.removeFirst(events.count - eventLimit) }
        return value
    }

    func recentEvents() -> [DiagnosticEvent] { events.reversed() }
}
