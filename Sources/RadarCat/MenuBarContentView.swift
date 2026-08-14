import SwiftUI
import AppKit

/// Contingut del popover: línia d'estat, targeta del mapa i cronologia -
/// sense capçalera d'app, sense `Divider()` ni peu. Aquest fitxer és només
/// composició; la implementació de cada peça viu al seu propi fitxer petit
/// (`StatusHeaderView`, `MoreActionsMenu`, `RadarStageView`,
/// `RadarStageStates`, `MapOverlays`, `LegendView`, `TimelineView`). Vegeu
/// `popover-redesign-spec.md` i `popover-ui-spec.md` pel contracte i les
/// mides exactes que segueixen totes elles.
struct MenuBarContentView: View {
    @Environment(RadarStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    /// Amplada del popover. `RadarCatApp` en depèn pel seu `.frame(width:)`
    /// - mantenir aquest nom i aquest valor exactes, és la frontera entre
    /// unitats.
    static let stageWidth: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            StatusHeaderView()
            RadarStageView()
            TimelineView()
        }
        .frame(width: Self.stageWidth)
        .background(hiddenStepShortcuts)
        // Aparença: es fixa un cop en aparèixer i cada cop que el sistema
        // canvia (mode fosc del Mac, no del popover) - `RadarStore` decideix
        // si cal recompondre els frames o no (vegeu `setAppearance`).
        .task { await store.setAppearance(colorScheme == .dark ? .dark : .light) }
        .onChange(of: colorScheme) { _, newValue in
            Task { await store.setAppearance(newValue == .dark ? .dark : .light) }
        }
    }

    /// Dreceres ←/→ (secció 5 de l'spec): a diferència de l'espai
    /// (play/pausa), que viu al botó real de `TimelineView`, no hi ha cap
    /// control visible "frame següent/anterior" al popover (el scrub de la
    /// cronologia és per arrossegar, no per fletxes) - calen botons
    /// invisibles per registrar la drecera igualment, el truc habitual de
    /// SwiftUI per a accions sense control propi.
    ///
    /// Mida zero (no només `opacity(0)`, que deixava el botó real allà
    /// ocupant 22x22pt de mentida) i `.focusable(false)`: amb "Accés total
    /// per teclat" activat a Configuració del Sistema, un botó normal - per
    /// invisible que sigui - entra igualment a l'ordre de tabulació, i
    /// l'usuari podia acabar-hi disparant `step(by:)` prement Tab sense cap
    /// pista de per què el frame acaba de canviar. `.focusable(false)` el
    /// treu d'aquest ordre; la drecera de teclat (`.keyboardShortcut`) hi
    /// segueix funcionant igual, no depèn del focus. S'amaguen també de
    /// VoiceOver: no són controls reals per navegar-hi, només ganxos de
    /// teclat.
    private var hiddenStepShortcuts: some View {
        HStack(spacing: 0) {
            Button("") { store.animator.step(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .focusable(false)
            Button("") { store.animator.step(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .focusable(false)
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Hora sense zero davant per hores d'un sol dígit ("8:12", no "08:12"):
/// `Date.shortLabel` (a `RadarAPI.swift`) hi afegeix dia i mes, massa llarg
/// per a la línia d'estat i el segell de la cronologia, on l'hora ja n'hi ha
/// prou de sola. Format fix "H:mm" (24h, sense AM/PM): ca_ES ja fa servir
/// aquest format i tota la interfície és en català.
extension Date {
    var hourMinuteLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "H:mm"
        return f.string(from: self)
    }
}
