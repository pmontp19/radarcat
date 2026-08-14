import Foundation

/// Debouncer de l'alarma de pluja: decideix quan cal notificar i quan es pot
/// tornar a "armar" per a una futura notificació, evitant avisos en cadena
/// quan el color al punt exacte de l'usuari oscil·la al voltant d'un llindar.
/// Tres proteccions, cadascuna per un motiu de soroll diferent:
///
/// - Llindar de severitat (`.moderate` en amunt, no `.weak`): un traç blau/
///   lila fluix just al píxel de l'usuari no val la pena una alarma - vegeu
///   `RainSeverity`.
/// - Histèresi de cicles secs (`dryCyclesToClear`): per tornar a "sec" (i
///   per tant poder re-armar una alarma futura) cal veure uns quants cicles
///   de refresc seguits per sota del llindar, no només un - evita que un
///   ruixat que oscil·la al voltant del llindar generi diverses
///   notificacions en pocs minuts.
/// - Període de silenci mínim (`minNotificationGap`): xarxa de seguretat
///   final i independent de l'anterior - encara que l'estat torni
///   legítimament de sec a plovent abans d'hora, no renotifica si l'última
///   notificació és massa recent.
struct RainAlertTracker {
    enum State: Equatable {
        case dry
        /// `consecutiveDryCycles` compta cicles seguits per sota del
        /// llindar vistos MENTRE encara es considera "plovent" - només en
        /// arribar a `dryCyclesToClear` es torna a `.dry`.
        case raining(consecutiveDryCycles: Int)
    }

    private(set) var state: State = .dry
    private var lastNotifiedAt: Date?

    /// ~3 cicles de refresc (cadència de 6 min, vegeu `RadarStore`) = uns
    /// 18 min per sota del llindar abans de considerar que ha aclarit.
    private let dryCyclesToClear = 3
    /// Silenci mínim entre notificacions encara que l'estat oscil·li.
    private let minNotificationGap: TimeInterval = 30 * 60

    var isRaining: Bool {
        if case .raining = state { return true }
        return false
    }

    /// Actualitza l'estat amb la severitat d'aquest cicle (`.none` si no hi
    /// ha lectura vàlida - sense ubicació, fora de Catalunya, o sense
    /// frame - es tracta igual que un píxel sec, subjecte a la mateixa
    /// histèresi). Retorna `true` si cal disparar una notificació ara.
    mutating func update(severity: RainSeverity, now: Date = Date()) -> Bool {
        let isWet = severity >= .moderate
        var justStartedRaining = false

        switch state {
        case .dry:
            if isWet {
                state = .raining(consecutiveDryCycles: 0)
                justStartedRaining = true
            }
        case .raining(let dryCount):
            if isWet {
                state = .raining(consecutiveDryCycles: 0)
            } else {
                let next = dryCount + 1
                state = next >= dryCyclesToClear ? .dry : .raining(consecutiveDryCycles: next)
            }
        }

        guard justStartedRaining else { return false }
        if let last = lastNotifiedAt, now.timeIntervalSince(last) < minNotificationGap {
            return false   // dins el període de silenci: l'estat ja ha canviat, però no renotifiquem
        }
        lastNotifiedAt = now
        return true
    }
}
