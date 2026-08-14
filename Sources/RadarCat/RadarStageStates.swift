import SwiftUI

/// Estat de primera càrrega dins la targeta del mapa: un únic indicador
/// determinat (barra fina a la vora inferior) en lloc del doble `ProgressView`
/// que competia amb el de la capçalera abans d'aquest redisseny. Vegeu
/// `popover-ui-spec.md` secció 4 - el percentatge de progrés viu al subtítol
/// de `StatusHeaderView`, no aquí dins, ja que és el mateix element de text
/// que en l'estat normal mostra "Última imatge X".
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

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.08))
                Rectangle().fill(Color.accentColor)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 2)
    }
}

/// Estat d'error sense cap frame disponible (ni tan sols un d'antic per
/// mostrar atenuat) - típicament la primera connexió de l'app fallant. Si ja
/// hi havia un frame vell, la targeta el segueix mostrant atenuat en lloc
/// d'arribar aquí, vegeu `RadarStageView.content`.
struct RadarErrorState: View {
    /// Ja humanitzat en català (`store.errorMessage`): mai
    /// `error.localizedDescription`, vegeu el contracte.
    let message: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("No s'ha pogut connectar")
                .font(.system(size: 12, weight: .semibold))
            Text(message ?? "Comprova la connexió; ho tornarem a provar automàticament.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Torna-ho a provar", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
