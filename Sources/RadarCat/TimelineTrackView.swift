import SwiftUI

/// Pista de la cronologia: una única capsula contínua (fons tènue + tram
/// "reproduït" en color d'accent) amb un mànec rodó a la posició actual, en
/// lloc de la fila de marques individuals d'abans. Aquest és el patró
/// d'Apple per a un control de temps sobre un mapa (vegeu el control de
/// precipitació del giny "Radar" del Temps a iOS/macOS: pista contínua +
/// mànec + etiquetes d'hora reals sota la pista, mai un comptador relatiu
/// tipo "N de 10") - la fila de marques anterior no s'hi assemblava gens i,
/// combinada amb el text de `TimelineView.frameTimestamp` apareixent/
/// desapareixent segons el frame, produïa un salt visible cada cop que
/// l'usuari arrossegava cap a "ara" o cap enrere.
struct TimelineTrackView: View {
    let animator: RadarAnimator

    private let trackHeight: CGFloat = 3
    private let knobDiameter: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width
                let midY = geo.size.height / 2
                let x = knobX(width: w)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: w, height: trackHeight)
                        .position(x: w / 2, y: midY)
                    // Tram "reproduït": des de l'inici fins al mànec, com el
                    // groc/blau ple del control d'Apple - `max(trackHeight,
                    // x)` perquè al primer frame (x=0) la capsula igualment
                    // hi tingui una mica d'ample, no un segment invisible.
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(trackHeight, x), height: trackHeight)
                        .position(x: max(trackHeight, x) / 2, y: midY)
                    Circle()
                        .fill(.white)
                        .frame(width: knobDiameter, height: knobDiameter)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        .position(x: x, y: midY)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    // `minimumDistance: 0` fa que un simple clic ja compti
                    // com a "arrossegament" d'amplitud zero: així una sola
                    // gesture cobreix "clicables i arrossegables" sense
                    // necessitar un `Slider`.
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in scrub(to: value.location.x, width: w) }
                )
            }
            .frame(height: 15)
            HStack {
                Text(earliestLabel)
                Spacer()
                // "Ara" en negreta/color primari, com Apple ressalta "Now"
                // enfront de la resta d'hores de la pista: és l'extrem que
                // importa més, no un extrem qualsevol.
                Text("Ara")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 8.5))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Posició en X del mànec: fracció `currentIndex / (frames.count - 1)`
    /// de l'amplada disponible - el primer frame cau exactament a x=0, el
    /// darrer exactament a `width`. `scrub` fa la inversa exacta d'aquesta
    /// mateixa fórmula, així que clicar allà on ja hi ha el mànec no el mou.
    private func knobX(width: CGFloat) -> CGFloat {
        guard animator.frames.count > 1 else { return 0 }
        let fraction = CGFloat(animator.currentIndex) / CGFloat(animator.frames.count - 1)
        return fraction * width
    }

    private func scrub(to x: CGFloat, width: CGFloat) {
        guard animator.frames.count > 1, width > 0 else { return }
        let fraction = min(max(x / width, 0), 1)
        let index = Int((fraction * CGFloat(animator.frames.count - 1)).rounded())
        animator.seek(to: index)
        animator.pause()
    }

    /// Etiqueta de l'extrem esquerre: l'hora real del primer frame ("11:24"),
    /// no un delta relatiu ("−54 min") com abans - Apple mostra hores
    /// absolutes sota la pista ("9p 12a 3a…"), no comptadors relatius, i
    /// `Date.hourMinuteLabel` (definida a `MenuBarContentView.swift`) ja és
    /// el mateix format que fa servir `TimelineView.frameTimestamp` per al
    /// frame actual - una sola convenció d'hora a tota la cronologia.
    private var earliestLabel: String {
        animator.frames.first?.timestamp.hourMinuteLabel ?? ""
    }
}
