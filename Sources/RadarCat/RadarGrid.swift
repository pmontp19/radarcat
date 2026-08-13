import Foundation
import CoreGraphics

/// Graella de tiles de radar (Meteocat no serveix radar a cap altre zoom).
/// Empíricament: z=7, x ∈ [63..68], y ∈ [78..83] (6×6 tiles de 256px); alguns
/// d'aquests índexs cauen fora de la cobertura real i tornen 404 (ignorats
/// silenciosament per `RadarCompositor.fetch`), es mantenen per marge.
/// Tile y creix cap al *sud* en aquesta graella (veure `RadarCompositor`).
enum RadarGrid {
    static let z = 7
    static let xRange = 63...68
    static let yRange = 78...83
    static let tileSize = 256
}

/// Graella del mapa base. A diferència del radar, Meteocat sí serveix el
/// mapa base ("fons/GoogleMapsCompatible") a z=8, i aquesta graella *és* una
/// projecció contínua real (a diferència de la de z=7 - veure CLAUDE.md):
/// conté les Terres de l'Ebre, sense la vora negra ni el fragment despenjat
/// que teníem a z=7. Cada tile de `RadarGrid` (z=7) correspon exactament a
/// 4 tiles d'aquí (nesting XYZ estàndard: fill/2 == pare), així que el radar
/// es dibuixa escalat x2 sobre aquesta base - veure `RadarCompositor`.
///
/// Important: en aquesta graella el tile y creix cap al *nord* (el contrari
/// de `RadarGrid`), confirmat renderitzant el widget real de Meteocat
/// (`ginys/mapaRadar`) en un navegador i comparant l'ordre de fetch dels
/// tiles amb la posició del contingut en pantalla.
enum BaseGrid {
    static let z = 8
    static let xRange = 126...132
    static let yRange = 157...162
    static let tileSize = 256
}
