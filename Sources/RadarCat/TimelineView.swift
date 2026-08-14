import SwiftUI

/// Cronologia: substitueix el `Slider` de pista blava plena i el comptador
/// "5/10" d'abans. Sense `Slider`: el scrub es fa arrossegant directament
/// sobre la pista contínua (`TimelineTrackView`, que en concentra tota la
/// lògica). Disposició en dues files (informació a dalt, pista a sota tot
/// l'ample), com el control de precipitació del Temps d'Apple - abans tot
/// vivia en una sola fila (play + pista + hora) i la fila de marques no
/// s'assemblava al control natiu que demanava l'spec. Vegeu
/// `popover-ui-spec.md` secció 3.
struct TimelineView: View {
    @Environment(RadarStore.self) private var store

    var body: some View {
        let animator = store.animator
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                playPauseButton(animator: animator)
                Spacer(minLength: 8)
                frameTimestamp(animator: animator)
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

    private func playPauseButton(animator: RadarAnimator) -> some View {
        Button {
            animator.toggle()
        } label: {
            Image(systemName: animator.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .iconButtonChrome()
        }
        .buttonStyle(.plain)
        .disabled(animator.frames.count < 2)
        // L'espai és la drecera "oficial" de play/pausa (secció 5): viu
        // aquí, al botó real, a diferència de ←/→ que no tenen cap control
        // visible equivalent i es resolen amb botons amagats a
        // `MenuBarContentView`.
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(animator.isPlaying ? "Pausa" : "Reprodueix")
    }

    /// L'ÚNICA hora que reflecteix el frame en reproducció (mai etiquetada
    /// com a "darrera imatge", que és cosa de `StatusHeaderView`). Al frame
    /// més nou NOMÉS es mostra l'hora, sense segona línia: "Ara" ja hi surt
    /// a la pista de sota (`TimelineTrackView`) - repetir-lo aquí llegia com
    /// un duplicat ("11:18 / Ara" al costat d'"Ara"). El desplaçament
    /// relatiu ("−N min") només aporta res quan NO s'és al frame més nou.
    ///
    /// La segona línia SEMPRE ocupa el mateix espai, buida o no (text " "
    /// amb opacitat 0 en lloc de fer desaparèixer la línia sencera): abans,
    /// quan `relative` passava de buit a no-buit en arrossegar, aquest bloc
    /// canviava d'1 a 2 línies d'alçada i, com que vivia en una `HStack`
    /// amb el botó de play (alineació `.center` per defecte), tot plegat -
    /// botó inclòs - saltava amunt/avall a cada canvi. Reservar l'alçada
    /// sempre elimina el salt sense necessitat de fixar cap alineació
    /// explícita.
    private func frameTimestamp(animator: RadarAnimator) -> some View {
        let relative = frameRelativeLabel(animator: animator)
        return VStack(alignment: .trailing, spacing: 1) {
            Text(animator.currentTimestamp?.hourMinuteLabel ?? "—")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
            Text(relative.isEmpty ? " " : relative)
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(relative.isEmpty ? 0 : 1)
        }
        // El seu contingut ja forma part de `frameAccessibilityValue`, llegit
        // com a part de l'element combinat de la pista (vegeu més amunt) -
        // sense amagar-lo aquí, VoiceOver el llegiria dues vegades.
        .accessibilityHidden(true)
    }

    /// Buit al frame més nou (vegeu `frameTimestamp`): buit, no "Ara". Es
    /// calcula sobre els timestamps reals del frame actual i de l'últim, no
    /// sobre cap cadència assumida (com `TimelineTrackView.earliestLabel`).
    private func frameRelativeLabel(animator: RadarAnimator) -> String {
        guard let current = animator.currentTimestamp,
              let latest = animator.frames.last?.timestamp,
              animator.currentIndex < animator.frames.count - 1
        else { return "" }
        let minutes = max(0, Int(latest.timeIntervalSince(current) / 60))
        return "−\(minutes) min"
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
