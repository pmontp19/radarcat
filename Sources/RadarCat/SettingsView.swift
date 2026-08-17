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
