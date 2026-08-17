import SwiftUI
import AppKit

/// Menú "⋯": totes les accions que abans vivien disperses (peu amb enllaç a
/// meteo.cat, botó "Surt" solt) o que directament eren inabastables (Ajustos
/// - vegeu el comentari a `RadarCatApp` sobre per què el `SettingsLink`
/// d'aquí és l'únic camí real cap a aquella finestra en una app
/// `LSUIElement`). També substitueix el botó de refresc manual solt de la
/// capçalera antiga.
struct MoreActionsMenu: View {
    @Environment(RadarStore.self) private var store
    /// `@Bindable` sobre el singleton (com ja fa `SettingsView`): permet un
    /// `Binding` DIRECTE a `alertsEnabled`. Es va provar un binding manual
    /// que cridava `store.enableAlerts()/disableAlerts()` des del `set` i
    /// vam descobrir-hi un bug real: res assignava mai `alertsEnabled` de
    /// debò, així que la marca de verificació no es movia mai (encara que
    /// `enableAlerts()` demanés permisos igualment) i el submenú "Radi"
    /// quedava atenuat per sempre. Qui demana permisos és `RadarStore`, que
    /// hi enganxa `AlertPreferences.onEnabledChange` al seu `init` - un
    /// binding directe aquí ja ho activa tot sol, sense duplicar-ho.
    @Bindable private var prefs = AlertPreferences.shared
    /// Mateix patró `@Bindable` sobre un singleton `@Observable`, aplicat al
    /// tema (vegeu `AppearancePreference`) - el mateix que ja fan `prefs`
    /// aquí i `SettingsView` per `AlertPreferences.shared`.
    @Bindable private var appearancePref = AppearancePreference.shared

    var body: some View {
        Menu {
            Button("Refresca") { Task { await store.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isRefreshing)

            Menu("Tema: \(appearancePref.mode.label)") {
                ForEach(AppearancePreference.Mode.allCases, id: \.self) { mode in
                    Button {
                        appearancePref.mode = mode
                    } label: {
                        if appearancePref.mode == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            }

            Divider()

            Toggle(isOn: $prefs.alertsEnabled) {
                // "BETA" com a text apart (no una insígnia separada): un
                // `Menu` d'AppKit no permet compondre mides de font/badges
                // dins una mateixa etiqueta, així que el text pla "Avisos de
                // pluja  BETA" és l'aproximació natural.
                Text("Avisos de pluja  BETA")
            }
            Menu("Radi: \(Int(prefs.radiusKm)) km") {
                ForEach(AlertPreferences.radiusOptions, id: \.self) { km in
                    Button {
                        prefs.radiusKm = km
                    } label: {
                        if prefs.radiusKm == km {
                            Label("\(Int(km)) km", systemImage: "checkmark")
                        } else {
                            Text("\(Int(km)) km")
                        }
                    }
                }
            }
            .disabled(!prefs.alertsEnabled)

            Divider()

            Link("Obre meteo.cat", destination: RadarAPI.meteoCatURL)
            SettingsLink { Text("Ajustos…") }
                .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Surt de RadarCat") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .iconButtonChrome()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Més accions")
    }
}
