import SwiftUI

/// Llegenda de colors del radar (Feble -> Forta -> Calamarsa), flotant
/// avall-dreta sobre la targeta del mapa (vegeu `RadarStageView`; abans era
/// avall-esquerra, però just allà és on sol haver-hi eco real a les Terres
/// de l'Ebre - la llegenda tapava el fenomen que ha d'explicar). Mida
/// encongida (116->96pt la barra, 7,5->7pt les etiquetes) perquè, ara que
/// també ha de compartir cantonada amb la insígnia "meteo.cat" dels tiles
/// (vegeu `RadarStageView.legendBottomInset`), no envaeixi terra. Colors
/// literals a propòsit: és una de les dues úniques excepcions a "sense
/// colors literals per a superfícies" de `popover-ui-spec.md` (l'altra és el
/// blau de Maps del punt d'ubicació, a `MapOverlays.swift`) perquè aquests
/// són la pròpia llegenda de colors de Meteocat, no un color de superfície
/// de la interfície.
struct LegendView: View {
    private let barWidth: CGFloat = 96

    private let gradientColors: [Color] = [
        .blue, .cyan, .green, .yellow, .orange, .red,
        Color(red: 1, green: 0, blue: 1),   // magenta - calamarsa
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                .frame(width: barWidth, height: 4)
                .clipShape(Capsule())
            HStack {
                Text("Feble")
                Spacer()
                Text("Forta")
                Spacer()
                Text("Calamarsa")
            }
            .frame(width: barWidth)
        }
        .font(.system(size: 7))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        // Una sola lectura per VoiceOver: la barra de degradat en si no
        // aporta res parlada, només les tres etiquetes en calen com a valor.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Llegenda d'intensitat de pluja: feble, forta, calamarsa")
    }
}
