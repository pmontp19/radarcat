import SwiftUI

/// Overlays flotants sobre el frame compositat: llegenda, atribució
/// condicional, punt d'ubicació, tractament d'"obsolet". Només es dibuixen
/// si ja hi ha mapa a sota.
struct RadarStageOverlaysView: View {
    @Environment(RadarStore.self) private var store
    let cardSize: CGSize

    var body: some View {
        if store.animator.currentImage != nil {
            if showStaleTreatment {
                Color.black.opacity(0.28)
            }
            legendStack
                .padding(.trailing, 7)
                .padding(.bottom, legendBottomInset)
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
        }
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
    private var legendBottomInset: CGFloat {
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
