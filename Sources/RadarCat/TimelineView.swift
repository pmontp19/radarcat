import SwiftUI

/// Cronologia: substitueix el `Slider` de pista blava plena i el comptador
/// "5/10" d'abans. Sense `Slider`: el scrub es fa arrossegant directament
/// sobre la fila de marques (`TimelineTrackView`, que en concentra tota la
/// lògica). Vegeu `popover-ui-spec.md` secció 3.
struct TimelineView: View {
    @Environment(RadarStore.self) private var store

    var body: some View {
        let animator = store.animator
        HStack(spacing: 9) {
            playPauseButton(animator: animator)
            HStack(spacing: 9) {
                TimelineTrackView(animator: animator)
                frameTimestamp(animator: animator)
            }
            // Un sol element combinat: la pista de marques, les etiquetes
            // dels extrems i el segell de l'hora expliquen tots la mateixa
            // cosa (quin frame es veu ara) - agrupar-los evita que VoiceOver
            // ho repeteixi tres cops.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cronologia del radar")
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
    /// a la dreta de la fila d'etiquetes de la pista (`TimelineTrackView`) -
    /// repetir-lo aquí llegia com un duplicat ("11:18 / Ara" al costat
    /// d'"Ara"). El desplaçament relatiu ("−N min") només aporta res quan NO
    /// s'és al frame més nou.
    private func frameTimestamp(animator: RadarAnimator) -> some View {
        let relative = frameRelativeLabel(animator: animator)
        return VStack(alignment: .trailing, spacing: 1) {
            Text(animator.currentTimestamp?.hourMinuteLabel ?? "—")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
            if !relative.isEmpty {
                Text(relative)
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
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

    private func frameAccessibilityValue(animator: RadarAnimator) -> String {
        guard let current = animator.currentTimestamp else { return "Sense dades" }
        guard let latest = animator.frames.last?.timestamp,
              animator.currentIndex < animator.frames.count - 1
        else { return "\(current.hourMinuteLabel), ara" }
        let minutes = max(0, Int(latest.timeIntervalSince(current) / 60))
        return "\(current.hourMinuteLabel), fa \(minutes) minuts"
    }
}
