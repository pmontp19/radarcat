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

    /// Interval entre frames "normals" del bucle.
    private let stepInterval: TimeInterval = 0.35
    /// Interval de retenció al frame més nou (l'últim de la seqüència) abans
    /// de reiniciar el bucle: sense aquesta pausa, en tornar a l'inici no hi
    /// ha manera de saber quin és l'estat "actual" enmig del moviment
    /// continu. Vegeu `scheduleNextAdvance`.
    private let holdInterval: TimeInterval = 0.9

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
    /// `appearance` no té valor per defecte a propòsit: qui construeix els
    /// frames ha de decidir explícitament si són per a aparença clara o
    /// fosca, no heretar-ho implícitament.
    func build(latest: Date, count: Int = 10, appearance: FrameAppearance) async {
        isBuilding = true
        buildProgress = 0
        lastBuildError = nil
        defer { isBuilding = false }

        let set = Self.frameSet(latest: latest, count: count)
        var built: [Frame] = []
        built.reserveCapacity(set.count)
        for (i, ts) in set.enumerated() {
            let cg = await compositor.compositeFrame(timestamp: ts, appearance: appearance)
            let img = cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            built.append(Frame(timestamp: ts, image: img))
            buildProgress = Double(i + 1) / Double(set.count)
        }
        // `pause()` abans d'assignar l'índex nou pel mateix motiu que a
        // `jumpToLatest()`: si ja s'estava reproduint (refresc en calent amb
        // el popover obert, cas freqüent cada ~6 min), `play()` tot sol no
        // faria res per `guard !isPlaying` i el timer en vol seguiria comptant
        // amb l'interval de la posició antiga, saltant-se el `holdInterval`
        // del frame nou just quan més compta.
        pause()
        frames = built
        currentIndex = max(0, built.count - 1)   // mostra l'últim frame
        if !built.isEmpty { play() }             // auto-reprodueix
    }

    func play() {
        guard !frames.isEmpty else { return }
        guard !isPlaying else { return }
        isPlaying = true
        scheduleNextAdvance()
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
        // No canvia si es reprodueix o no (contracte: `seek` no reprèn), però
        // si ja s'estava reproduint cal reprogramar: el timer en vol encara
        // porta l'interval calculat per a la posició d'abans del scrub.
        if isPlaying { scheduleNextAdvance() }
    }

    /// Navegació manual (dreceres ←/→): un frame amunt o avall, sense donar
    /// la volta als extrems. Passa a mans de l'usuari, per això atura la
    /// reproducció automàtica.
    func step(by delta: Int) {
        pause()
        guard !frames.isEmpty else { return }
        currentIndex = min(max(currentIndex + delta, 0), frames.count - 1)
    }

    /// Torna al frame més nou i reprèn la reproducció automàtica: útil per
    /// "desfer" una navegació manual sense haver de comptar frames. Sempre
    /// passa per `pause()` abans: si ja s'estava reproduint, `play()` tot
    /// sol no faria res (ja `isPlaying`) i el timer en curs quedaria amb
    /// l'interval calculat per a la posició antiga en lloc del `holdInterval`
    /// que pertoca ara que som al frame més nou.
    func jumpToLatest() {
        guard !frames.isEmpty else { return }
        pause()
        currentIndex = frames.count - 1
        play()
    }

    /// El bucle no fa servir un `Timer` `repeats: true` perquè cada frame
    /// necessita una durada diferent (el frame més nou es reté més temps,
    /// vegeu `holdInterval`). En comptes d'això, cada disparo programa el
    /// seu propi següent amb l'interval que toqui, i sempre invalida el
    /// timer anterior abans de crear-ne un: així mai queden dos timers vius
    /// ni se n'acumula cap.
    private func scheduleNextAdvance() {
        timer?.invalidate()
        let interval = frames.indices.contains(currentIndex) && currentIndex == frames.count - 1
            ? holdInterval
            : stepInterval
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fireAdvance() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fireAdvance() {
        guard isPlaying else { return }   // s'ha pausat mentre el timer era en vol
        guard !frames.isEmpty else { pause(); return }  // sense frames no hi ha res a reproduir
        advance()
        scheduleNextAdvance()
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        currentIndex = (currentIndex + 1) % frames.count
    }

    /// Conjunt de timestamps: `count` frames cada 6 min fins a `latest`, ascendent.
    static func frameSet(latest: Date, count: Int) -> [Date] {
        (0..<count).map { latest.addingTimeInterval(TimeInterval(-360 * $0)) }.reversed()
    }

    // `isolated deinit` (SE-0371): sense l'`isolated` explícit, el deinit
    // s'executa en un context no aïllat i no pot tocar `timer`, que és
    // main-actor. Amb `isolated` es garanteix que corre a l'actor principal.
    isolated deinit {
        timer?.invalidate()
    }
}
