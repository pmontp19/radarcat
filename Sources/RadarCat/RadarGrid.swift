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
/// que teníem a z=7.
///
/// S'HA PROVAT z=9 (doble resolució de partida) i s'ha descartat -
/// deliberadament, no per oblit: a z=9, Meteocat dibuixa les etiquetes a la
/// MATEIXA mida en píxels de tile que a z=8, així que cada etiqueta hi cobreix
/// la meitat de geografia. En encabir la mateixa àrea de Catalunya als
/// mateixos ~760px del popover, el text es redueix a la meitat en lloc de
/// sortir més nítid: mesurat sobre el frame renderitzat, "Barcelona"/
/// "Sabadell"/"Mataró" queien a ~5-6px d'alçada (il·legibles), i hi
/// apareixien moltes etiquetes noves que a aquesta mida només eren soroll.
/// z=9 no arregla la suavitat del text, la converteix en mida massa petita -
/// el problema original (etiquetes toves) no es soluciona pujant de zoom, es
/// soluciona no reescalant cap amunt el frame en la vista (vegeu el
/// comentari sobre resolució a `RadarCompositor.compositeFrame`). Si mai es
/// reconsidera pujar de zoom, cal verificar primer amb aquesta mateixa
/// mesura (alçada real en px de les etiquetes a la mida de pantalla
/// definitiva), no assumir que més resolució de tile == més nitidesa.
///
/// Cada tile de `RadarGrid` (z=7) correspon exactament a 4 tiles d'aquí
/// (nesting XYZ estàndard: fill/2 == pare), així que el radar es dibuixa
/// escalat x2 sobre aquesta base - veure `RadarCompositor`.
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
