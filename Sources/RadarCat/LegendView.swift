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
///
/// Construïts amb `Color(hue:saturation:brightness:)`, NO amb els colors amb
/// nom (`.blue`, `.cyan`, `.green`...) que hi havia abans: aquells són colors
/// DINÀMICS del sistema, amb un RGB diferent en clar i en fosc (p.ex.
/// `.systemYellow` és més clar/saturat en fosc que en clar) - `RadarCompositor
/// .compositeFrame` dibuixa el radar SEMPRE igual, sense cap filtre
/// d'aparença (vegeu el comentari allà), així que en fosc la llegenda amb
/// colors amb nom acabava mostrant un to lleugerament diferent del que hi ha
/// de veritat als píxels de l'eco. Un `Color(hue:...)` és un valor de color
/// fix, idèntic en totes dues aparences - igual que ho és el radar mateix.
/// Cada to escollit dins la mateixa banda que `RainDetector.severity(r:g:b:)`
/// hi classificaria (feble 170°...300°, moderada 45°...170°, forta
/// 345°...45°, calamarsa 300°...345°): la llegenda i el detector llegeixen el
/// mateix mapa de colors.
struct LegendView: View {
    private let barWidth: CGFloat = 96

    private let gradientColors: [Color] = [
        Color(hue: 232 / 360, saturation: 0.85, brightness: 0.95),   // blau - feble (inici)
        Color(hue: 190 / 360, saturation: 0.80, brightness: 0.85),   // cian - feble (fi)
        Color(hue: 130 / 360, saturation: 0.70, brightness: 0.75),   // verd - moderada (inici)
        Color(hue: 54 / 360, saturation: 0.90, brightness: 0.95),    // groc - moderada (fi)
        Color(hue: 30 / 360, saturation: 0.90, brightness: 0.95),    // taronja - forta (inici)
        Color(hue: 3 / 360, saturation: 0.85, brightness: 0.90),     // vermell - forta (fi)
        Color(hue: 312 / 360, saturation: 0.75, brightness: 0.95),   // magenta - calamarsa
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
