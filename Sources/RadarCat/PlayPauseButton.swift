import SwiftUI

/// Botó de play/pausa de la cronologia. Extret de `TimelineView` perquè és
/// un control amb la seva pròpia lògica de modificadors/accessibilitat, no
/// un simple ajudant que hi encaixi inline.
struct PlayPauseButton: View {
    let animator: RadarAnimator

    var body: some View {
        Button {
            animator.toggle()
        } label: {
            Image(systemName: animator.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .iconButtonChrome()
        }
        .buttonStyle(.plain)
        .disabled(animator.frames.count < 2)
        // L'espai és la drecera "oficial" de play/pausa: viu aquí, al botó
        // real, a diferència de ←/→ que no tenen cap control visible
        // equivalent i es resolen amb botons amagats a `MenuBarContentView`.
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(animator.isPlaying ? "Pausa" : "Reprodueix")
    }
}
