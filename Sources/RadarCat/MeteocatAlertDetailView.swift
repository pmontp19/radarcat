import SwiftUI

/// Detall d'un avís de Meteocat en clicar `MeteocatWarningBannerView` -
/// popover senzill (docs/plans/avisos-meteocat.md): meteor, categoria
/// (color+text), comarca, vigència, comentari. Només l'avís més sever de la
/// comarca (`RadarStore.currentMeteocatWarning`), no la llista completa
/// d'avisos vigents - ampliable més endavant, fora d'abast d'aquesta v1.
struct MeteocatAlertDetailView: View {
    let warning: MeteocatCurrentWarning
    let comarcaNom: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(warning.category.color).frame(width: 10, height: 10)
                Text(warning.meteorNom)
                    .font(.system(size: 13, weight: .semibold))
            }

            if let comarcaNom {
                Label(comarcaNom, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !warning.llindar.isEmpty {
                Text(warning.llindar)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Vigent fins a \(warning.vigentFins.shortLabel)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            if !warning.comentari.isEmpty {
                Divider()
                // `comentari` és text extern no fiable (Meteocat pot
                // canviar-lo sense avís, i mai s'ha de tractar com HTML/
                // markdown): sempre com a `Text` pla, mateixa precaució que
                // `ha-avisoscat` aplica a `comentari`/`llindar`/`meteor_nom`.
                Text(warning.comentari)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
    }
}
