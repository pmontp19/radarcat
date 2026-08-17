import SwiftUI

/// Hora del frame en reproducció (mai "darrera imatge", que és cosa de
/// `StatusHeaderView`), amb un desplaçament relatiu ("−N min") a sota, buit
/// al frame més nou ("Ara" ja hi surt a la pista de sota).
///
/// La segona línia SEMPRE ocupa el mateix espai (text " " amb opacitat 0 en
/// lloc de fer-la desaparèixer): si no, l'`HStack` amb el botó de play
/// saltava d'alçada a cada canvi.
struct FrameTimestampLabel: View {
    let animator: RadarAnimator

    var body: some View {
        let relative = frameRelativeLabel
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
        // com a part de l'element combinat de la pista a `TimelineView` -
        // sense amagar-lo aquí, VoiceOver el llegiria dues vegades.
        .accessibilityHidden(true)
    }

    /// Buit al frame més nou (vegeu el comentari de dalt): buit, no "Ara".
    /// Es calcula sobre els timestamps reals del frame actual i de l'últim,
    /// no sobre cap cadència assumida (com `TimelineTrackView.earliestLabel`).
    private var frameRelativeLabel: String {
        guard let current = animator.currentTimestamp,
              let latest = animator.frames.last?.timestamp,
              animator.currentIndex < animator.frames.count - 1
        else { return "" }
        let minutes = max(0, Int(latest.timeIntervalSince(current) / 60))
        return "−\(minutes) min"
    }
}
