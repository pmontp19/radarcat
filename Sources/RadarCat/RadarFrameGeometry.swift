import Foundation
import CoreGraphics

/// Posició dins un frame compositat, independent del zoom dels tiles que
/// facin servir `RadarCompositor`/`BaseGrid` per construir-lo. Aquesta és la
/// frontera de coordenades que la resta de l'app fa servir (vista, detector
/// de pluja): tothom hi programa en normalitzat i mai en índexs de tile, així
/// que un futur canvi de zoom (com el de z=8 a z=9 fet en aquesta mateixa
/// unitat) no toca cap altre fitxer.
enum RadarFrameGeometry {
    /// Posició normalitzada (0...1, origen DALT-ESQUERRA, y avall - espai de
    /// SwiftUI) d'un lat/lon dins el frame compositat. `nil` si el punt cau
    /// fora del retall (p.ex. l'usuari és fora de Catalunya) - en aquest cas
    /// no hi ha res raonable a mostrar, ni clavat a una vora ni enlloc.
    ///
    /// Projecció Web Mercator estàndard sobre `BaseGrid`, moguda aquí des de
    /// l'antic `GeoPosition.pixel` (que ara hi delega): ja verificada
    /// empíricament contra 7 ciutats catalanes conegudes - les seves
    /// posicions relatives al mapa renderitzat hi encaixaven exactament. NO
    /// es re-deriva, només s'adapta al zoom vigent de `BaseGrid` (llegit
    /// dinàmicament, no clavat a z=8) i es normalitza a 0...1.
    static func normalized(lat: Double, lon: Double) -> CGPoint? {
        let z = BaseGrid.z
        let n = pow(2.0, Double(z))
        let xyzX = (lon + 180) / 360 * n
        let latRad = lat * .pi / 180
        let xyzY = (1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n
        let baseGridX = xyzX
        let baseGridY = n - xyzY   // BaseGrid: tile y creix cap al nord, l'invers de XYZ estàndard

        let ts = Double(BaseGrid.tileSize)
        let crop = RadarCompositor.catalunyaCrop
        // Píxel natiu del retall (origen baix-esquerra, y amunt), pas
        // intermedi abans de normalitzar.
        let px = (baseGridX - Double(BaseGrid.xRange.lowerBound)) * ts - Double(crop.minX)
        let py = (baseGridY - Double(BaseGrid.yRange.lowerBound)) * ts - Double(crop.minY)

        guard px >= 0, px <= Double(crop.width), py >= 0, py <= Double(crop.height) else {
            return nil
        }

        let nx = px / Double(crop.width)
        // El retall és natiu (baix-esquerra, y amunt); el contracte demana
        // l'espai de SwiftUI (dalt-esquerra, y avall) - cal invertir l'eix.
        let ny = 1 - py / Double(crop.height)
        return CGPoint(x: nx, y: ny)
    }

    /// Amplada del frame en km, per convertir un radi en km a fracció
    /// horitzontal del frame (`radiusKm / frameWidthKm`).
    ///
    /// Resolució estàndard de Web Mercator (metres/píxel a nivell de tile)
    /// avaluada a la latitud del centre del retall (~41,7°N, el centre
    /// aproximat de `RadarCompositor.catalunyaTileY`):
    /// `156543.03 / 2^z * cos(lat)`. No és exacta arreu del retall (Mercator
    /// distorsiona més com més al nord/sud del centre), però per a un disc
    /// de pocs desenes de km dins Catalunya l'error és menyspreable.
    static var frameWidthKm: Double {
        let centerLatDeg = 41.7
        let metersPerPixel = 156_543.03 / pow(2.0, Double(BaseGrid.z)) * cos(centerLatDeg * .pi / 180)
        let widthPx = Double(RadarCompositor.catalunyaCrop.width)
        return metersPerPixel * widthPx / 1000
    }

    /// Aspecte (amplada/alçada) del frame compositat. `RadarCompositor` NO
    /// reescala el frame final (vegeu el comentari a `compositeFrame` sobre
    /// per què el retall ja surt a la mida de la targeta i per què es va
    /// revocar el pas a z=9, que sí hauria obligat a triar entre reescalar
    /// o gastar 4x més memòria en cache): calcular-ho sobre `catalunyaCrop`
    /// dona directament l'aspecte real del frame que es mostra.
    static var aspectRatio: CGFloat {
        let crop = RadarCompositor.catalunyaCrop
        return crop.width / crop.height
    }
}
