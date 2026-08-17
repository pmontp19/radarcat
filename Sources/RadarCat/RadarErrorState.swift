import SwiftUI

/// Estat d'error sense cap frame disponible (ni tan sols un d'antic per
/// mostrar atenuat) - típicament la primera connexió de l'app fallant. Si ja
/// hi havia un frame vell, la targeta el segueix mostrant atenuat en lloc
/// d'arribar aquí, vegeu `RadarStageContentView`.
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
