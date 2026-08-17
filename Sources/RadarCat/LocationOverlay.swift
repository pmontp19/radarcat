import SwiftUI

/// Blau de Maps: convenció pròpia dels mapes per al punt "on ets", deixat
/// deliberadament diferent del color d'accent del sistema (que aquí es fa
/// servir per a l'anell del radi i altres controls) - és l'altra excepció
/// explícita al conveni del projecte de "sense colors literals", vegeu
/// `LegendView`.
private let mapsBlue = Color(red: 0, green: 0.478, blue: 1)

/// Punt "la meva ubicació" més, opcionalment, l'anell del radi d'avís i el
/// halo de "plou aquí". Tota la vista és purament decorativa de cara a
/// VoiceOver: l'estat de pluja i la ubicació ja els anuncia en text
/// `StatusHeaderView`, repetir-los aquí només afegiria soroll.
struct LocationOverlay: View {
    let normalized: CGPoint
    let cardSize: CGSize
    /// `nil` si els avisos no estan actius: sense radi configurat no hi ha
    /// anell a dibuixar (vegeu `RadarStageOverlaysView`, que decideix aquest
    /// valor).
    let radiusKm: Double?
    let isRainingHere: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        let x = normalized.x * cardSize.width
        let y = normalized.y * cardSize.height
        ZStack {
            if let radiusKm {
                RadiusRingView(radiusKm: radiusKm, x: x, y: y, cardSize: cardSize)
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

    /// Halo molt suau que respira al voltant del punt quan plou dins el
    /// radi. Repeteix cada 2,4s (prou lent per no distreure d'una icona que
    /// es veu contínuament) i es desactiva del tot amb reduir moviment.
    private func haloEffect(x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(mapsBlue.opacity(pulsing ? 0 : 0.45))
            .frame(width: pulsing ? 34 : 10, height: pulsing ? 34 : 10)
            .position(x: x, y: y)
            .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false), value: pulsing)
            .onAppear { pulsing = true }
    }
}
