import SwiftUI

/// Targeta del mapa: el frame compositat (o l'estat que toqui: primera
/// càrrega, error, o mapa atenuat si les dades són obsoletes) més tots els
/// overlays flotants (llegenda, atribució condicional, punt d'ubicació,
/// píndola d'obsolet) - vegeu `RadarStageContentView`/`RadarStageOverlaysView`.
struct RadarStageView: View {
    @Environment(RadarStore.self) private var store

    /// Mida de la targeta, calculada A MÀ a partir de `MenuBarContentView
    /// .stageWidth` i de l'aspecte real del frame (`RadarFrameGeometry
    /// .aspectRatio`) - MAI amb `GeometryReader` + `.aspectRatio(.fit)`, tot
    /// i que sembli la manera "neta" de fer-ho.
    ///
    /// És una trampa ja coneguda d'aquest projecte, no una hipòtesi: es va
    /// provar exactament aquesta combinació en aquest mateix redisseny i,
    /// llançant l'app real, la targeta col·lapsava a 0pt d'alçada.
    /// `GeometryReader` no té cap mida intrínseca pròpia (accepta el que se
    /// li ofereix); dins d'un `VStack` que viu en un `MenuBarExtra` - que
    /// NOMÉS fixa l'AMPLADA del popover, vegeu `RadarCatApp` i
    /// `MenuBarContentView.stageWidth`, mai l'alçada de la finestra - aquesta
    /// combinació no té cap mida "natural" a la qual encaixar-se i es resol
    /// de manera degenerada. La versió d'aquest fitxer anterior a aquest
    /// redisseny ja ho documentava amb un comentari llarg just per aquest
    /// motiu (`git show HEAD:Sources/RadarCat/MenuBarContentView.swift`,
    /// funció `radarStage`) - una instrucció d'aquest mateix redisseny el va
    /// contradir sense voler-ho. Calcular-ho amb aritmètica senzilla és més
    /// verbós, però determinista: si mai es torna a "simplificar" cap a
    /// `GeometryReader`, torna a passar el mateix.
    static let cardWidth: CGFloat = MenuBarContentView.stageWidth - 24   // 12pt de canal a banda i banda
    static let cardHeight: CGFloat = cardWidth / RadarFrameGeometry.aspectRatio

    var body: some View {
        let cardSize = CGSize(width: Self.cardWidth, height: Self.cardHeight)
        ZStack {
            // Fons semàntic, mai `Color.black.opacity(...)` (inexistent
            // en mode fosc): és el que es veu mentre no hi ha imatge.
            Color(nsColor: .controlBackgroundColor)
            RadarStageContentView(animator: store.animator, errorMessage: store.errorMessage) {
                Task { await store.refresh() }
            }
            RadarStageOverlaysView(cardSize: cardSize)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
    }
}
