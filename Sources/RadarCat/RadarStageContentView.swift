import SwiftUI

/// Contingut principal de la targeta del mapa: el frame compositat, o
/// l'estat que toqui mentre no n'hi ha cap (primera càrrega o error).
/// Extret de `RadarStageView` perquè és una decisió multi-branca amb
/// paràmetres propis, no un simple ajudant que hi encaixi inline.
struct RadarStageContentView: View {
    let animator: RadarAnimator
    /// Ja humanitzat en català (`store.errorMessage`): mai
    /// `error.localizedDescription`, vegeu el contracte a `RadarStore`.
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
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
            RadarErrorState(message: errorMessage, retry: onRetry)
        }
    }
}
