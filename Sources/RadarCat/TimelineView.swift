import SwiftUI

/// Cronologia: substitueix el `Slider` de pista blava plena i el comptador
/// "5/10" d'abans. Sense `Slider`: el scrub es fa arrossegant directament
/// sobre la pista contínua (`TimelineTrackView`, que en concentra tota la
/// lògica). Disposició en dues files (informació a dalt, pista a sota tot
/// l'ample), com el control de precipitació del Temps d'Apple - abans tot
/// vivia en una sola fila (play + pista + hora) i la fila de marques no
/// s'assemblava gens a aquest control natiu.
struct TimelineView: View {
    @Environment(RadarStore.self) private var store

    var body: some View {
        let animator = store.animator
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                PlayPauseButton(animator: animator)
                Spacer(minLength: 8)
                FrameTimestampLabel(animator: animator)
            }
            TimelineTrackView(animator: animator)
                // Un sol element combinat: `.accessibilityElement(children:
                // .ignore)` DESCARTA tot el contingut descendent de
                // `TimelineTrackView` de cara a VoiceOver (les etiquetes
                // "12:24"/"Ara" dels extrems de la pista INCLOSES - no
                // "s'ignoren els fills però es filtren cap amunt", com deia
                // una versió anterior d'aquest comentari; l'API realment vol
                // dir "no hi ha fills", punt). Per no perdre de tot la
                // referència de l'hora d'inici, el `accessibilityLabel`
                // l'incorpora com a text estàtic (s'anuncia un cop en
                // enfocar, no a cada canvi de valor); l'hora del frame
                // vigent i si és "ara" o "fa N minuts" viuen a
                // `accessibilityValue` (es torna a anunciar cada cop que
                // `frameAccessibilityValue` canviï, en ajustar amb
                // VoiceOver).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cronologia del radar, de \(earliestAbsoluteLabel(animator: animator)) a ara")
                .accessibilityValue(frameAccessibilityValue(animator: animator))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: animator.step(by: 1)
                    case .decrement: animator.step(by: -1)
                    @unknown default: break
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 11)
    }

    /// Hora real del primer frame, per al `accessibilityLabel` de la pista -
    /// mateixa font que `TimelineTrackView.earliestLabel` (privada allà),
    /// duplicada aquí perquè és una sola línia i no val la pena exposar-la
    /// només per aquest ús.
    private func earliestAbsoluteLabel(animator: RadarAnimator) -> String {
        animator.frames.first?.timestamp.hourMinuteLabel ?? "?"
    }

    private func frameAccessibilityValue(animator: RadarAnimator) -> String {
        guard let current = animator.currentTimestamp else { return "Sense dades" }
        guard let latest = animator.frames.last?.timestamp,
              animator.currentIndex < animator.frames.count - 1
        else { return "\(current.hourMinuteLabel), ara" }
        let minutes = max(0, Int(latest.timeIntervalSince(current) / 60))
        return "\(current.hourMinuteLabel), fa \(minutes) minuts"
    }
}
