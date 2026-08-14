import Foundation
import CoreGraphics

/// Converteix lat/lon a una posició de píxel dins `RadarCompositor.catalunyaCrop`.
/// Projecció Web Mercator estàndard sobre `BaseGrid` (z=8), verificada
/// empíricament aquesta mateixa sessió contra 7 ciutats catalanes conegudes -
/// les seves posicions relatives al mapa renderitzat hi van encaixar
/// exactament. No cal re-derivar-la ni qüestionar-la.
enum GeoPosition {
    /// Píxel en coordenades natives del retall (origen baix-esquerra, y
    /// amunt, com `RadarCompositor.catalunyaCrop`), o `nil` si el punt cau
    /// fora del retall (p.ex. l'usuari és fora de Catalunya) - en aquest cas
    /// no hi ha res raonable a mostrar, ni clavat a una vora ni enlloc.
    static func pixel(lat: Double, lon: Double) -> CGPoint? {
        let z = BaseGrid.z
        let n = pow(2.0, Double(z))
        let xyzX = (lon + 180) / 360 * n
        let latRad = lat * .pi / 180
        let xyzY = (1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n
        let baseGridX = xyzX
        let baseGridY = n - xyzY   // BaseGrid: tile y creix cap al nord, l'invers de XYZ estàndard

        let ts = Double(BaseGrid.tileSize)
        let crop = RadarCompositor.catalunyaCrop
        let px = (baseGridX - Double(BaseGrid.xRange.lowerBound)) * ts - Double(crop.minX)
        let py = (baseGridY - Double(BaseGrid.yRange.lowerBound)) * ts - Double(crop.minY)

        guard px >= 0, px <= Double(crop.width), py >= 0, py <= Double(crop.height) else {
            return nil
        }
        return CGPoint(x: px, y: py)
    }
}
