import SwiftUI

/// Atribució de respatller pròpia: NOMÉS es fa servir si
/// `RadarCompositor.baseIncludesAttribution` és `false`. Avui és `true` (la
/// insígnia "meteo.cat" ja ve incrustada als tiles de base, vegeu aquell
/// fitxer), així que aquesta vista no es mostra mai en l'estat actual del
/// codi - es manté per si algun dia Meteocat canvia de font i cal tornar a
/// afegir l'atribució manualment, tal com demana el contracte.
struct AttributionLabel: View {
    var body: some View {
        Text("meteo.cat")
            .font(.system(size: 8.5))
            .foregroundStyle(.white.opacity(0.55))
            .shadow(color: .black.opacity(0.5), radius: 1)
    }
}
