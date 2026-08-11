import Foundation
import AppKit
import Observation

/// Reprodueix els frames composats de l'última hora. Observable per la vista.
@MainActor
@Observable
final class RadarAnimator {
    struct Frame {
        let timestamp: Date
        var image: NSImage?
    }

    private(set) var frames: [Frame] = []
    private(set) var currentIndex = 0
    private(set) var isBuilding = false
    private(set) var buildProgress: Double = 0
    private(set) var lastBuildError: String?

    var isPlaying = false
    var speed: TimeInterval = 0.45   // segons per frame
    private var timer: Timer?
    private let compositor = RadarCompositor.shared

    var currentImage: NSImage? {
        guard frames.indices.contains(currentIndex) else { return nil }
        return frames[currentIndex].image
    }
    var currentTimestamp: Date? {
        guard frames.indices.contains(currentIndex) else { return nil }
        return frames[currentIndex].timestamp
    }
    var isEmpty: Bool { frames.isEmpty }

    /// Composa `count` frames acabant a `latest` (cadència de 6 min).
    func build(latest: Date, count: Int = 10) async {
        isBuilding = true
        buildProgress = 0
        lastBuildError = nil
        defer { isBuilding = false }

        let set = Self.frameSet(latest: latest, count: count)
        var built: [Frame] = []
        built.reserveCapacity(set.count)
        for (i, ts) in set.enumerated() {
            let cg = await compositor.compositeFrame(timestamp: ts)
            let img = cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            built.append(Frame(timestamp: ts, image: img))
            buildProgress = Double(i + 1) / Double(set.count)
        }
        frames = built
        currentIndex = max(0, built.count - 1)   // mostra l'últim frame
        if !built.isEmpty { play() }             // auto-reprodueix
    }

    func play() {
        guard !frames.isEmpty else { return }
        guard !isPlaying else { return }
        isPlaying = true
        timer?.invalidate()
        let t = Timer(timeInterval: speed, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(to index: Int) {
        guard frames.indices.contains(index) else { return }
        currentIndex = index
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        currentIndex = (currentIndex + 1) % frames.count
    }

    /// Conjunt de timestamps: `count` frames cada 6 min fins a `latest`, ascendent.
    static func frameSet(latest: Date, count: Int) -> [Date] {
        (0..<count).map { latest.addingTimeInterval(TimeInterval(-360 * $0)) }.reversed()
    }
}
