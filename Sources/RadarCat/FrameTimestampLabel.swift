import SwiftUI

/// Hora del frame en reproducció, amb un desplaçament relatiu opcional a
/// sota. Extret de `TimelineView` perquè és un bloc amb la seva pròpia
/// lògica de layout, no un simple ajudant que hi encaixi inline.
///
/// L'ÚNICA hora que reflecteix el frame en reproducció (mai etiquetada com a
/// "darrera imatge", que és cosa de `StatusHeaderView`). Al frame més nou
/// NOMÉS es mostra l'hora, sense segona línia: "Ara" ja hi surt a la pista
/// de sota (`TimelineTrackView`) - repetir-lo aquí llegia com un duplicat
/// ("11:18 / Ara" al costat d'"Ara"). El desplaçament relatiu ("−N min")
/// només aporta res quan NO s'és al frame més nou.
///
/// La segona línia SEMPRE ocupa el mateix espai, buida o no (text " " amb
/// opacitat 0 en lloc de fer desaparèixer la línia sencera): abans, quan
/// `relative` passava de buit a no-buit en arrossegar, aquest bloc canviava
/// d'1 a 2 línies d'alçada i, com que vivia en una `HStack` amb el botó de
/// play (alineació `.center` per defecte), tot plegat - botó inclòs -
/// saltava amunt/avall a cada canvi. Reservar l'alçada sempre elimina el
/// salt sense necessitat de fixar cap alineació explícita.
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
