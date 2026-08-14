import SwiftUI

/// Overlays flotants dins la targeta del mapa que depenen de geometria (punt
/// i anell d'ubicació) o d'un estat puntual (píndola d'obsolet, atribució de
/// respatller). La llegenda de colors viu a part, a `LegendView.swift`,
/// perquè és prou entitat pròpia per merèixer el seu fitxer. Vegeu
/// `popover-ui-spec.md` secció 2.

/// Blau de Maps: convenció pròpia dels mapes per al punt "on ets", deixat
/// deliberadament diferent del color d'accent del sistema (que aquí es fa
/// servir per a l'anell del radi i altres controls) - és l'altra excepció
/// explícita a "sense colors literals" de l'spec, vegeu `LegendView`.
private let mapsBlue = Color(red: 0, green: 0.478, blue: 1)

/// Punt "la meva ubicació" més, opcionalment, l'anell del radi d'avís i el
/// halo de "plou aquí". Tota la vista és purament decorativa de cara a
/// VoiceOver: l'estat de pluja i la ubicació ja els anuncia en text
/// `StatusHeaderView`, repetir-los aquí només afegiria soroll.
struct LocationOverlay: View {
    let normalized: CGPoint
    let cardSize: CGSize
    /// `nil` si els avisos no estan actius: sense radi configurat no hi ha
    /// anell a dibuixar (vegeu `RadarStageView`, que decideix aquest valor).
    let radiusKm: Double?
    let isRainingHere: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        let x = normalized.x * cardSize.width
        let y = normalized.y * cardSize.height
        ZStack {
            if let radiusKm {
                radiusRing(radiusKm: radiusKm, x: x, y: y)
            }
            if isRainingHere && !reduceMotion {
                haloEffect(x: x, y: y)
            }
            dot.position(x: x, y: y)
        }
        .accessibilityHidden(true)
    }

    private var dot: some View {
        ZStack {
            Circle().fill(.white).frame(width: 14, height: 14)
            Circle().fill(mapsBlue).frame(width: 10, height: 10)
        }
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
    }

    private func radiusRing(radiusKm: Double, x: CGFloat, y: CGFloat) -> some View {
        let radiusPx = radiusKm / RadarFrameGeometry.frameWidthKm * cardSize.width
        return ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1))
                .frame(width: radiusPx * 2, height: radiusPx * 2)
                .position(x: x, y: y)
            Text("\(Int(radiusKm)) km")
                .font(.system(size: 8))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .position(x: x, y: y + radiusPx + 8)
        }
    }

    /// Halo molt suau que respira al voltant del punt quan plou dins el
    /// radi. Repeteix cada 2,4s (prou lent per no distreure d'una icona que
    /// es veu contínuament) i es desactiva del tot amb reduir moviment -
    /// vegeu `popover-ui-spec.md` secció 5.
    private func haloEffect(x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(mapsBlue.opacity(pulsing ? 0 : 0.45))
            .frame(width: pulsing ? 34 : 10, height: pulsing ? 34 : 10)
            .position(x: x, y: y)
            .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false), value: pulsing)
            .onAppear { pulsing = true }
    }
}

/// Píndola "dades no fiables": únic senyal addicional (a banda de
/// l'atenuació del mapa que hi afegeix `RadarStageView`) que el que es veu
/// pot no reflectir la realitat. Viu amunt-dreta perquè no interfereixi amb
/// la llegenda (avall-dreta, vegeu `RadarStageView.legendStack`). El text ve
/// ja fet des de `RadarStageView` (`stalePillText`): pot ser "fa N min"
/// (obsolet per temps) o "sense connexió" (el darrer refresc ha fallat
/// encara que no faci prou estona com per ser obsolet) - aquesta vista no
/// necessita saber quin dels dos casos és.
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

/// Atribució de respatller pròpia: NOMÉS es fa servir si
/// `RadarCompositor.baseIncludesAttribution` és `false`. Avui és `true` (la
/// insígnia "meteo.cat" ja ve incrustada als tiles de base, vegeu aquell
/// fitxer), així que aquesta vista no es mostra mai en l'estat actual del
/// codi - es manté per si algun dia Meteocat canvia de font i cal tornar a
/// afegir l'atribució manualment, tal com demana el contracte.
struct AttributionLabel: View {
    var body: some View {
        Text("meteo.cat")
            .font(.system(size: 8.5))
            .foregroundStyle(.white.opacity(0.55))
            .shadow(color: .black.opacity(0.5), radius: 1)
    }
}
