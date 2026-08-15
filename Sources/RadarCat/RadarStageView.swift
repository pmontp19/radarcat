import SwiftUI

/// Targeta del mapa: el frame compositat (o l'estat que toqui: primera
/// càrrega, error, o mapa atenuat si les dades són obsoletes) més tots els
/// overlays flotants (llegenda, atribució condicional, punt d'ubicació,
/// píndola d'obsolet). Vegeu `popover-ui-spec.md` secció 2 i 4.
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
        let animator = store.animator
        let cardSize = CGSize(width: Self.cardWidth, height: Self.cardHeight)
        ZStack {
            // Fons semàntic, mai `Color.black.opacity(...)` (inexistent
            // en mode fosc): és el que es veu mentre no hi ha imatge.
            Color(nsColor: .controlBackgroundColor)
            content(animator: animator)
            overlays(animator: animator, cardSize: cardSize)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func content(animator: RadarAnimator) -> some View {
        if let image = animator.currentImage {
            Image(nsImage: image)
                .resizable()
                // `.high`, no `.medium`: a 356pt (712px en retina) contra un
                // frame natiu d'uns 691px hi ha una ampliació d'un ~3% i, amb
                // text petit al mapa (noms de municipi), es nota la
                // diferència de qualitat d'interpolació.
                .interpolation(.high)
                .scaledToFill()
        } else if animator.isBuilding {
            RadarLoadingState(progress: animator.buildProgress)
        } else {
            RadarErrorState(message: store.errorMessage) {
                Task { await store.refresh() }
            }
        }
    }

    /// Els overlays només tenen sentit si hi ha mapa a sota: als estats de
    /// primera càrrega/error sense frame no es dibuixa cap (ni llegenda ni
    /// punt), tal com descriu la secció 4 de l'spec.
    @ViewBuilder
    private func overlays(animator: RadarAnimator, cardSize: CGSize) -> some View {
        if animator.currentImage != nil {
            if showStaleTreatment {
                Color.black.opacity(0.28)
            }
            legendStack
                .padding(.trailing, 7)
                .padding(.bottom, legendBottomInset(cardSize: cardSize))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            if let normalized = store.locationNormalized {
                LocationOverlay(
                    normalized: normalized,
                    cardSize: cardSize,
                    radiusKm: AlertPreferences.shared.alertsEnabled ? AlertPreferences.shared.radiusKm : nil,
                    isRainingHere: store.isRainingHere
                )
            }
            if showStaleTreatment {
                StalePillView(text: stalePillText)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            if let warning = store.currentMeteocatWarning {
                // Dalt-esquerra, no dalt-dreta com `StalePillView`, perquè no
                // hi col·lideixi quan totes dues condicions coincideixen.
                MeteocatWarningBannerView(warning: warning, comarcaNom: meteocatComarcaNom)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Nom de la comarca resolta per a l'avís de Meteocat vigent, `nil` en
    /// les mateixes condicions que `store.currentMeteocatWarning` és `nil`.
    private var meteocatComarcaNom: String? {
        guard let id = store.userComarcaId else { return nil }
        return ComarcaResolver.comarques.first { $0.idComarca == id }?.nom
    }

    /// Llegenda i, si cal, atribució pròpia, apilades verticalment (la
    /// llegenda a sobre) i totes dues ancorades a baix-dreta - vegeu
    /// `legendBottomInset` per què la posició vertical no és un simple inset
    /// fix.
    private var legendStack: some View {
        VStack(alignment: .trailing, spacing: 4) {
            LegendView()
            if !RadarCompositor.baseIncludesAttribution {
                AttributionLabel()
            }
        }
    }

    /// La llegenda viu a baix-DRETA (abans era baix-esquerra i tapava
    /// literalment l'eco de les Terres de l'Ebre, que és on sol haver-hi
    /// activitat real - baix-dreta d'aquest retall és sistemàticament mar
    /// obert). Però la insígnia "meteo.cat" (`RadarCompositor
    /// .attributionRectNormalized`) ja ocupa píxels REALS de la imatge just
    /// en aquesta mateixa cantonada - no és un overlay de SwiftUI que
    /// puguem apartar, així que la llegenda necessita un marge inferior
    /// extra (no el mateix inset de 7pt de les altres cantonades) perquè
    /// quedi per damunt seu en lloc de fondre-s'hi a sobre. Quan aquell
    /// rectangle és `nil` (la base no porta insígnia incrustada - avui no
    /// és el cas, vegeu `baseIncludesAttribution`) no hi ha res a evitar i
    /// n'hi ha prou amb l'inset habitual.
    private func legendBottomInset(cardSize: CGSize) -> CGFloat {
        guard let badge = RadarCompositor.attributionRectNormalized else { return 7 }
        return (1 - badge.minY) * cardSize.height + 4   // +4: una mica d'aire per damunt de la insígnia
    }

    /// Un frame es tracta com a "no fiable" (mapa atenuat + píndola) no
    /// només si `isStale` (llindar de temps de 12-20 min), sinó també si el
    /// darrer refresc ha fallat ja mateix (`store.errorMessage != nil`):
    /// sense això, una connexió caiguda just després d'un refresc bo no
    /// donava cap senyal visual fins al cap de minuts - vegeu
    /// `StatusHeaderView.hasErrorWithFrame`, el mateix raonament.
    private var showStaleTreatment: Bool {
        store.animator.currentImage != nil && (store.isStale || store.errorMessage != nil)
    }

    private var stalePillText: String {
        store.isStale ? "fa \(staleMinutesAgo) min" : "sense connexió"
    }

    private var staleMinutesAgo: Int {
        guard let latest = store.latestTimestamp else { return 0 }
        return max(0, Int(Date().timeIntervalSince(latest) / 60))
    }
}
