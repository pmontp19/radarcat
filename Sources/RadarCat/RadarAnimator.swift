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
            let img = makeImage(await compositor.compositeFrame(timestamp: ts, appearance: appearance))
            built.append(Frame(timestamp: ts, image: img))
            buildProgress = Double(i + 1) / Double(set.count)
        }
        // `pause()` abans d'assignar l'índex nou pel mateix motiu que a
        // `jumpToLatest()`: si ja s'estava reproduint (refresc en calent amb
        // el popover obert, cas freqüent cada ~6 min), `play()` tot sol no
        // faria res per `guard !isPlaying` i el timer en vol seguiria comptant
        // amb l'interval de la posició antiga, saltant-se el `holdInterval`
        // del frame nou just quan més compta.
        //
        // Sempre salta al frame més nou i reprèn - a diferència de
        // `recolor` (vegeu allà), que preserva `currentIndex` i només
        // reprèn si l'usuari no ha tocat res. NO és una inconsistència
        // per corregir: aquí hi ha dades noves de veritat (un refresc real
        // de Meteocat), i "ara" ha canviat de debò - val la pena saltar-hi.
        // Un canvi de tema no aporta cap dada nova, només la mateixa
        // informació renderitzada diferent - per això `recolor` es queda on
        // l'usuari estava mirant.
        pause()
        frames = built
        currentIndex = max(0, built.count - 1)   // mostra l'últim frame
        if !built.isEmpty { play() }             // auto-reprodueix
    }

    /// Recompon els frames JA existents (mateixos timestamps) en una aparença
    /// nova - a diferència de `build`, no hi ha dades noves, així que
    /// `currentIndex` NO canvia. El frame VIST es recompon PRIMER i se
    /// substitueix a l'instant, la resta en segon pla: abans,
    /// `setAppearance` cridava `build` sencer i els deu frames trigaven a
    /// canviar plegats (~10 composicions de CPU seguides), visible com un
    /// canvi de tema que es queda penjat un moment.
    ///
    /// `currentIndex` es rellegeix a CADA volta, no un cop sol a l'inici:
    /// `TimelineTrackView.scrub` crida `seek(to:)` directament mentre
    /// aquesta funció encara corre en segon pla, així que cal prioritzar
    /// sempre l'índex vigent perquè el frame on l'usuari acaba de saltar no
    /// es quedi amb l'aparença antiga. Per la mateixa raó només es reprèn la
    /// reproducció al final si `currentIndex` no ha canviat des de l'inici -
    /// si l'usuari ha arrossegat mentrestant, ja ha triat on vol mirar
    /// (mateix contracte que `seek`, que tampoc reprèn tot sol).
    ///
    /// Cada composició es substitueix NOMÉS si `compositeFrame` ha tornat
    /// una imatge de veritat: una fallada transitòria mai esborra un frame
    /// que ja anava bé.
    func recolor(appearance: FrameAppearance) async {
        guard !frames.isEmpty else { return }
        let wasPlaying = isPlaying
        let startIndex = currentIndex
        // `pauseInternal`, NO el `pause()` públic: aquell marca
        // `interruptedPlaybackControl` (vegeu la propietat), i si el
        // marquéssim aquí per la nostra pròpia pausa inicial, la condició
        // de sota mai distingiria "l'usuari ha tocat algun control mentre
        // recolorien" de "hem estat nosaltres pausant per començar".
        pauseInternal()
        interruptedPlaybackControl = false

        var processed = Set<Int>()
        while processed.count < frames.count {
            let idx: Int
            if frames.indices.contains(currentIndex), !processed.contains(currentIndex) {
                idx = currentIndex
            } else if let next = frames.indices.first(where: { !processed.contains($0) }) {
                idx = next
            } else {
                break   // invariant del bucle diu que això no passa mai
            }
            processed.insert(idx)
            let ts = frames[idx].timestamp
            if let img = makeImage(await compositor.compositeFrame(timestamp: ts, appearance: appearance)) {
                frames[idx].image = img
            }
        }

        // Reprèn NOMÉS si (1) reproduïa abans de començar, (2) `currentIndex`
        // no ha canviat, i (3) cap control real de reproducció s'ha tocat
        // mentrestant - (2) sol no basta: prémer pausa sense arrossegar no
        // canvia `currentIndex` però igualment vol dir "no reprenguis".
        if wasPlaying && currentIndex == startIndex && !interruptedPlaybackControl { play() }
    }

    /// `true` si `play()`/`pause()` (i, doncs, `toggle()`/`step(by:)`/
    /// `jumpToLatest()`, que hi passen per sota) s'han cridat des de FORA
    /// de `recolor` mentre aquesta encara s'executava en segon pla - vegeu
    /// el comentari allà. `recolor` la reinicia a `false` just després de
    /// la seva pròpia pausa inicial (via `pauseInternal`, que NO la marca).
    private var interruptedPlaybackControl = false

    /// `cg` -> `NSImage` conservant la mida real en punts = píxels natius
    /// (mateixa convenció que fa servir tot el pipeline, vegeu
    /// `RadarStageView.content`). Únic lloc que fa aquesta conversió -
    /// `build` i `recolor` hi passen totes dues, en lloc de repetir-la
    /// (abans hi havia tres còpies literals d'aquesta mateixa línia en
    /// aquest fitxer, ja divergides entre elles en el tractament d'errors).
    private func makeImage(_ cg: CGImage?) -> NSImage? {
        cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    func play() {
        interruptedPlaybackControl = true
        guard !frames.isEmpty else { return }
        guard !isPlaying else { return }
        isPlaying = true
        scheduleNextAdvance()
    }

    func pause() {
        interruptedPlaybackControl = true
        pauseInternal()
    }

    /// Feina real de `pause()`, sense marcar `interruptedPlaybackControl` -
    /// `recolor` hi passa per aturar la reproducció ell mateix sense que
    /// això compti com "l'usuari ha tocat un control".
    private func pauseInternal() {
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
        // El timer viu a `RunLoop.main`: ja corre al main thread, per això
        // `assumeIsolated` i no un `Task` nou a cada tick.
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireAdvance() }
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
