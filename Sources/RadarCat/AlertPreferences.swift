import Foundation
import Observation

/// Preferències dels avisos de pluja (BETA, opt-in): si estan actius i amb
/// quin radi. Instància compartida (`shared`) perquè ni la vista del popover
/// ni els Ajustos hagin de passar per `RadarStore` només per llegir o
/// escriure aquests dos valors - això permet que cada unitat compili sola
/// sense dependre de la implementació de `RadarStore`. `RadarStore` és qui
/// hi enganxa `onEnabledChange` al seu `init` per demanar permisos i
/// engegar/aturar la localització i les notificacions: `AlertPreferences`
/// en si mateix no demana cap permís, només guarda estat.
@MainActor
@Observable
final class AlertPreferences {
    static let shared = AlertPreferences()

    static let radiusOptions: [Double] = [5, 10, 20, 30]

    /// Cridada quan `alertsEnabled` canvia de valor (no en llegir-lo, ni en
    /// carregar el valor persistit a l'`init`): `true` quan l'usuari activa
    /// els avisos, `false` quan els desactiva.
    var onEnabledChange: ((Bool) -> Void)?

    /// Cridada quan `radiusKm` canvia de valor (mateixes precaucions que
    /// `onEnabledChange`: mai en carregar el valor persistit a l'`init`).
    /// Sense això, canviar el radi als Ajustos no afecta la severitat
    /// calculada al punt de l'usuari fins al pròxim cicle de refresc
    /// d'`RadarStore` (fins a 6 min) - amb el hook, `RadarStore` pot
    /// recalcular a l'instant amb el frame que ja té.
    var onRadiusChange: ((Double) -> Void)?

    /// Cridada quan `meteocatAlertsEnabled` canvia de valor - mateix patró
    /// exacte que `onEnabledChange`, per al banner d'avisos oficials de
    /// Meteocat (independent dels avisos de pluja per color de píxel).
    var onMeteocatEnabledChange: ((Bool) -> Void)?

    var alertsEnabled: Bool {
        didSet {
            guard oldValue != alertsEnabled else { return }
            UserDefaults.standard.set(alertsEnabled, forKey: Keys.alertsEnabled)
            onEnabledChange?(alertsEnabled)
        }
    }

    var radiusKm: Double {
        didSet {
            guard oldValue != radiusKm else { return }
            UserDefaults.standard.set(radiusKm, forKey: Keys.radiusKm)
            onRadiusChange?(radiusKm)
        }
    }

    /// Opt-in independent dels avisos de pluja: banner condicional al
    /// popover amb els avisos oficials de perill del Meteocat (calor, vent,
    /// pluja, neu...) per a la comarca de l'usuari - vegeu
    /// `docs/plans/avisos-meteocat.md`.
    var meteocatAlertsEnabled: Bool {
        didSet {
            guard oldValue != meteocatAlertsEnabled else { return }
            UserDefaults.standard.set(meteocatAlertsEnabled, forKey: Keys.meteocatAlertsEnabled)
            onMeteocatEnabledChange?(meteocatAlertsEnabled)
        }
    }

    private enum Keys {
        static let alertsEnabled = "com.pere.radarcat.alertsEnabled"
        static let radiusKm = "com.pere.radarcat.alertsRadiusKm"
        static let meteocatAlertsEnabled = "com.pere.radarcat.meteocatAlertsEnabled"
    }

    private init() {
        let defaults = UserDefaults.standard
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? false
        // Si el valor persistit no és una de les opcions vàlides (p.ex. ve
        // d'una versió futura que n'afegeix de noves i l'usuari torna
        // enrere), cau al valor per defecte en lloc de quedar-se amb un
        // radi que el `Picker` no podria seleccionar.
        let storedRadius = defaults.object(forKey: Keys.radiusKm) as? Double ?? 20
        radiusKm = Self.radiusOptions.contains(storedRadius) ? storedRadius : 20
        meteocatAlertsEnabled = defaults.object(forKey: Keys.meteocatAlertsEnabled) as? Bool ?? false
    }
}
