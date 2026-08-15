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

/// Graella del mapa base, z=8: a diferència de z=7 és una projecció contínua
/// real (conté les Terres de l'Ebre) i el seu tile y creix cap al *nord*, el
/// contrari de `RadarGrid`. Cada tile de `RadarGrid` (z=7) correspon
/// exactament a 4 tiles d'aquí (nesting XYZ estàndard: fill/2 == pare), així
/// que el radar es dibuixa escalat x2 sobre aquesta base - veure
/// `RadarCompositor`. Per què z=8 i no z=9 (provat i descartat: mateixes
/// etiquetes en px, geografia doble = text a mitges) i com es va confirmar
/// la direcció de la y, vegeu CLAUDE.md secció "Tile sources".
enum BaseGrid {
    static let z = 8
    static let xRange = 126...132
    static let yRange = 157...162
    static let tileSize = 256
}
