import SwiftUI

/// Píndola "dades no fiables": únic senyal addicional (a banda de
/// l'atenuació del mapa que hi afegeix `RadarStageOverlaysView`) que el que
/// es veu pot no reflectir la realitat. Viu amunt-dreta perquè no
/// interfereixi amb la llegenda (avall-dreta). El text ve ja fet des de
/// `RadarStageOverlaysView` (`stalePillText`): pot ser "fa N min" (obsolet
/// per temps) o "sense connexió" (el darrer refresc ha fallat encara que no
/// faci prou estona com per ser obsolet) - aquesta vista no necessita saber
/// quin dels dos casos és.
struct StalePillView: View {
    let text: String

    var body: some View {
        Text("⚠ \(text)")
            .font(.system(size: 9.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.5), lineWidth: 0.75))
            .accessibilityLabel("Dades no fiables: \(text)")
    }
}
