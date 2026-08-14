import Testing
import Foundation
@testable import RadarCat

/// Les tres proteccions de `RainAlertTracker` (vegeu els comentaris del propi
/// tipus): llindar de severitat, histèresi de cicles secs, i període de
/// silenci mínim. Els valors 3 cicles / 30 min són els documentats a
/// `RainAlertTracker` en el moment d'escriure aquest test - si es retoquen
/// allà, cal retocar-los aquí també.
@Suite struct RainAlertTrackerTests {
    @Test func firstRainNotifies() {
        var tracker = RainAlertTracker()
        #expect(tracker.update(severity: .moderate, now: Date()) == true)
        #expect(tracker.isRaining == true)
    }

    @Test func oscillatingBelowThresholdDoesNotReNotify() {
        var tracker = RainAlertTracker()
        let t0 = Date()
        #expect(tracker.update(severity: .moderate, now: t0) == true)

        // Un sol cicle per sota del llindar (< dryCyclesToClear = 3): no
        // torna a "sec", per tant continua "plovent" i no dispara res de nou.
        #expect(tracker.update(severity: .weak, now: t0.addingTimeInterval(360)) == false)
        #expect(tracker.isRaining == true)

        // Torna a pujar abans d'arribar mai a "sec": tampoc renotifica.
        #expect(tracker.update(severity: .strong, now: t0.addingTimeInterval(720)) == false)
        #expect(tracker.isRaining == true)
    }

    @Test func needsConsecutiveDryCyclesToClear() {
        var tracker = RainAlertTracker()
        let t0 = Date()
        _ = tracker.update(severity: .moderate, now: t0)

        // dryCyclesToClear = 3: calen 3 cicles secs SEGUITS, no només un.
        #expect(tracker.update(severity: .none, now: t0.addingTimeInterval(360)) == false)
        #expect(tracker.isRaining == true)
        #expect(tracker.update(severity: .none, now: t0.addingTimeInterval(720)) == false)
        #expect(tracker.isRaining == true)
        // 3r cicle sec seguit: aclareix (però "ha parat de ploure" no és un
        // esdeveniment que es notifiqui, per això `update` retorna `false`).
        #expect(tracker.update(severity: .none, now: t0.addingTimeInterval(1_080)) == false)
        #expect(tracker.isRaining == false)
    }

    @Test func minNotificationGapIsRespectedThenLifted() {
        var tracker = RainAlertTracker()
        let t0 = Date()
        #expect(tracker.update(severity: .moderate, now: t0) == true)

        // Aclareix del tot (3 cicles secs) perquè es pugui tornar a "armar".
        _ = tracker.update(severity: .none, now: t0.addingTimeInterval(360))
        _ = tracker.update(severity: .none, now: t0.addingTimeInterval(720))
        #expect(tracker.update(severity: .none, now: t0.addingTimeInterval(1_080)) == false)
        #expect(tracker.isRaining == false)

        // Torna a ploure 20 min després de l'última notificació (t0): dins
        // el període de silenci de 30 min - l'estat SÍ canvia (isRaining
        // torna a true) però `update` no renotifica.
        let soon = t0.addingTimeInterval(1_200)
        #expect(tracker.update(severity: .moderate, now: soon) == false)
        #expect(tracker.isRaining == true)

        // Aclareix un altre cop i, passats els 30 min de silenci des de
        // l'última notificació REAL (t0, no `soon` - `soon` no en va disparar
        // cap), un nou episodi de pluja SÍ notifica.
        _ = tracker.update(severity: .none, now: soon.addingTimeInterval(360))
        _ = tracker.update(severity: .none, now: soon.addingTimeInterval(720))
        _ = tracker.update(severity: .none, now: soon.addingTimeInterval(1_080))
        let later = t0.addingTimeInterval(1_800 + 60)
        #expect(tracker.update(severity: .moderate, now: later) == true)
    }
}
