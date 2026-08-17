import SwiftUI

/// Botó de play/pausa de la cronologia.
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
