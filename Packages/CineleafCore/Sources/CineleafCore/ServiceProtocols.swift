import Foundation

public struct ThumbnailRequest: Hashable, Sendable {
    public var assetID: UUID
    public var time: RationalTime
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(assetID: UUID, time: RationalTime, pixelWidth: Int, pixelHeight: Int) {
        self.assetID = assetID
        self.time = time
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct WaveformRequest: Hashable, Sendable {
    public var assetID: UUID
    public var sampleCount: Int

    public init(assetID: UUID, sampleCount: Int) {
        self.assetID = assetID
        self.sampleCount = sampleCount
    }
}

public protocol MediaInspecting: Sendable {
    associatedtype Inspection: Sendable
    func inspect(url: URL) async throws -> Inspection
}

public protocol ThumbnailGenerating: Sendable {
    associatedtype Image: Sendable
    func thumbnail(for request: ThumbnailRequest, url: URL) async throws -> Image
    func cancel(assetID: UUID) async
}

public protocol WaveformGenerating: Sendable {
    func waveform(for request: WaveformRequest, url: URL) async throws -> [Float]
    func cancel(assetID: UUID) async
}

public protocol ProjectExporting: Sendable {
    associatedtype Progress: AsyncSequence & Sendable where Progress.Element == Double
    func export(project: CineleafProject, to url: URL) async throws -> Progress
    func cancel() async
}
