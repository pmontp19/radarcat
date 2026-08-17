import SwiftUI

/// Estat de primera càrrega dins la targeta del mapa: un únic indicador
/// determinat (barra fina a la vora inferior) en lloc del doble `ProgressView`
/// que competia amb el de la capçalera abans d'aquest redisseny. El
/// percentatge de progrés viu al subtítol de `StatusHeaderView`, no aquí
/// dins, ja que és el mateix element de text que en l'estat normal mostra
/// "Última imatge X".
struct RadarLoadingState: View {
    let progress: Double

    var body: some View {
        ZStack {
            // Una antena, no cap glif de núvol/pluja: encara no tenim cap
            // frame compositat, així que qualsevol icona meteorològica
            // (fins i tot un núvol "neutre") insinuaria una lectura que
            // encara no existeix. L'antena diu només "rebent dades", sense
            // afirmar res sobre el temps - el mateix criteri que
            // `RadarCatApp` ja aplica en triar els glifs de la barra de menú
            // (un glif ha de dir la veritat, no la millor aproximació).
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 22))
                .foregroundStyle(.secondary.opacity(0.5))
            VStack {
                Spacer()
                progressBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Sense `GeometryReader`: un `Rectangle` sense mida pròpia ja omple
    /// l'ample disponible, així que `.scaleEffect(x:anchor:.leading)` sobre
    /// el rectangle d'accent basta per retallar-lo a la fracció `progress`
    /// sense necessitat de llegir cap `geo.size.width`.
    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.08))
            Rectangle()
                .fill(Color.accentColor)
                .scaleEffect(x: progress, anchor: .leading)
        }
        .frame(height: 2)
    }
}
