import SwiftUI
import AppKit
import Observation

/// Tema triat per l'usuari al menú "⋯" (Clar/Fosc/Sistema), persistit.
///
/// Aplica `NSApplication.shared.appearance` directament (AppKit), NO
/// `.preferredColorScheme` (es va provar primer i es va desfer): un cop
/// verificat en viu, forçar "Clar" amb `.preferredColorScheme` sobre
/// `MenuBarContentView` no canviava res de veritat - ni la capçalera
/// (`.thinMaterial`, que llegeix l'aparença REAL de l'`NSWindow`/`NSPanel`
/// que allotja el popover d'un `MenuBarExtra(.window)`, no l'entorn SwiftUI
/// declarat des de dins), ni res més enllà del que `@Environment(\.colorScheme)`
/// arriba a llegir per lògica pròpia. `NSApp.appearance` és la via AppKit
/// d'abans que existís `.preferredColorScheme`, i SÍ es propaga a
/// l'aparença efectiva de totes les finestres/panells de l'app (i, per
/// tant, també a `@Environment(\.colorScheme)`, que es resol a partir
/// d'aquesta aparença efectiva) - per això és l'única via que fa servir
/// aquesta classe, aplicada un cop a l'`init` (amb el valor persistit,
/// perquè un llançament amb "Fosc" ja arrenqui fosc) i cada cop que `mode`
/// canviï.
@MainActor
@Observable
final class AppearancePreference {
    static let shared = AppearancePreference()

    enum Mode: String, CaseIterable {
        case system, light, dark

        /// `nil` = "Sistema": no sobreescriu res, `NSApp.appearance` torna a
        /// `nil` i AppKit resol l'aparença real del sistema tot sol, tal com
        /// ja passava abans que existís aquesta preferència.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }

        var label: String {
            switch self {
            case .system: return "Sistema"
            case .light: return "Clar"
            case .dark: return "Fosc"
            }
        }
    }

    /// Cridada quan `mode` canvia de valor (mateix patró que
    /// `AlertPreferences.onEnabledChange`): `RadarStore` hi enganxa una
    /// clausura al seu `init` per recompondre els frames en la nova
    /// aparença. Necessari perquè el mapa reaccioni en calent: `NSApp
    /// .appearance` (vegeu `apply()`) SÍ actualitza la capçalera/materials a
    /// l'instant (AppKit els redibuixa amb l'aparença efectiva vigent en
    /// qualsevol redraw), però `@Environment(\.colorScheme)` d'una vista JA
    /// muntada no es reavalua només perquè un codi imperatiu de fora de
    /// SwiftUI toqui `NSApp.appearance` - `MenuBarContentView.onChange(of:
    /// colorScheme)` no arribava a disparar-se amb el popover ja obert
    /// (comprovat en viu: la capçalera canviava, el mapa no), per això cal
    /// aquest ganxo explícit en lloc de confiar-hi soles.
    var onModeChange: ((Mode) -> Void)?

    var mode: Mode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
            // `apply()` ABANS de `onModeChange`: si el nou mode és
            // `.system`, qui rep la crida necessita poder llegir l'aparença
            // REAL del sistema (`NSApplication.effectiveAppearance`), que
            // només és fiable un cop `NSApp.appearance` ja ha tornat a
            // `nil` - si `onModeChange` es cridés abans, encara veuria
            // l'aparença forçada anterior.
            apply()
            onModeChange?(mode)
        }
    }

    private enum Keys {
        static let mode = "com.pere.radarcat.appearanceMode"
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Keys.mode).flatMap(Mode.init(rawValue:))
        mode = stored ?? .system
        apply()
    }

    private func apply() {
        NSApplication.shared.appearance = mode.nsAppearance
    }
}
