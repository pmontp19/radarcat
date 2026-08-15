import SwiftUI
import AppKit

/// Finestra d'Ajustos nativa (`⌘,` / `SettingsLink` des del menú "⋯" del
/// popover). Contingut mínim a propòsit: només els avisos de pluja (BETA,
/// opt-in) i el seu radi - cap opció d'"Obrir a l'inici", que necessitaria
/// `SMAppService` i queda fora d'abast d'aquesta unitat.
struct SettingsView: View {
    @Environment(RadarStore.self) private var store
    @Bindable private var prefs = AlertPreferences.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.alertsEnabled) {
                    HStack(spacing: 6) {
                        Text("Avisos de pluja")
                        BetaBadge()
                    }
                }

                Picker("Radi de l'avís", selection: $prefs.radiusKm) {
                    ForEach(AlertPreferences.radiusOptions, id: \.self) { km in
                        Text("\(Int(km)) km").tag(km)
                    }
                }
                .disabled(!prefs.alertsEnabled)

                if prefs.alertsEnabled && store.location.authorizationDenied {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("L'accés a la ubicació està denegat: els avisos no poden saber on ets.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Obre Configuració del Sistema…") {
                            openLocationPrivacySettings()
                        }
                    }
                }
            } footer: {
                Text(
                    "Avisa amb una notificació quan el radar detecti pluja a prop teu. " +
                    "Necessita accés a la ubicació (per situar-te) i a les notificacions " +
                    "(per avisar-te) - macOS els demanarà en activar aquesta opció."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                // Sense `BetaBadge`, a diferència dels avisos de pluja: són
                // dades oficials directes de Meteocat, no una heurística de
                // color de píxel encara no validada àmpliament.
                Toggle("Avisos de Meteocat", isOn: $prefs.meteocatAlertsEnabled)

                if prefs.meteocatAlertsEnabled && store.location.authorizationDenied {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("L'accés a la ubicació està denegat: els avisos no poden saber a quina comarca ets.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Obre Configuració del Sistema…") {
                            openLocationPrivacySettings()
                        }
                    }
                }
            } footer: {
                Text(
                    "Mostra un avís quan hi hagi un avís oficial de perill vigent a la teva " +
                    "comarca (calor, vent, pluja, neu...). Necessita accés a la ubicació per " +
                    "situar la comarca - macOS el demanarà en activar aquesta opció."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 360)
    }

    private func openLocationPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Etiqueta "BETA": els avisos es basen en una heurística de color de píxel
/// sobre els tiles de radar (vegeu `RainDetector`), no en dades certificades,
/// i encara no s'han validat prou àmpliament per treure-la.
private struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}
