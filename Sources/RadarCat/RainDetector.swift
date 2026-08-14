import Foundation
import CoreGraphics

/// Nivell de l'eco de radar en un píxel, seguint la llegenda de colors del
/// giny de Meteocat: blau/lila = Feble, verd/groc = Moderada, taronja/vermell
/// = Forta, magenta = Calamarsa. Aproximat pel to (hue) del píxel - no cal
/// exactitud, només prou consistència per triar un llindar d'alarma.
enum RainSeverity: Int, Comparable {
    case none, weak, moderate, strong, hail
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Detecta el nivell d'eco de pluja en un frame compositat: el pitjor cas
/// dins un disc de diversos km centrat en un punt (`maxSeverity`, per a
/// l'alerta de proximitat - un únic píxel de pantalla equival a uns quants
/// km sobre el terreny a aquesta escala, i la xifra exacta depèn de la
/// resolució real del frame i de `RadarFrameGeometry.frameWidthKm`, mai fixa
/// - massa fi, en qualsevol cas, per avisar "abans" que la pluja arribi), o bé
/// el pitjor cas a TOT el frame (`maxSeverityOverFrame`, per a la línia
/// d'estat sense ubicació - "Pluja activa a Catalunya" ha de correspondre's
/// amb el que l'usuari veu al mapa, no només amb un llindar binari `>=
/// .moderate`: un eco feble ben visible a les Terres de l'Ebre amb la línia
/// dient "sense pluja" és una contradicció flagrant per a qui l'està
/// mirant). `hasSignificantRain` es defineix EN TERMES de
/// `maxSeverityOverFrame` (`>= .moderate`) perquè no hi hagi dues lògiques de
/// llindar independents que puguin arribar a conclusions diferents.
///
/// Totes dues funcions descarten qualsevol mostra dins
/// `RadarCompositor.attributionRectNormalized`: els tiles de base porten la
/// insígnia "meteo.cat" incrustada (decisió de producte, es queda com a
/// atribució de la font), i els seus colors (groc del sol, verd del logotip)
/// cauen dins els mateixos rangs de to que un eco real - sense excloure-la,
/// és una font de fals positiu CONSTANT (no soroll intermitent que la
/// histèresi de `RainAlertTracker` pugui filtrar).
enum RainDetector {
    /// Severitat màxima dins un disc de radi `radiusKm` centrat a `center`.
    /// `center` és normalitzat (0...1, origen DALT-ESQUERRA, y avall - espai
    /// SwiftUI, com `RadarFrameGeometry.normalized`). La mida real en píxels
    /// es llegeix sempre de `image.width`/`image.height`, mai se suposa des
    /// de fora (la mida del frame pot canviar independentment).
    ///
    /// Mostreig: no cal precisió de píxel - l'objectiu és "hi ha pluja
    /// significativa en algun punt d'aquest radi", no un mapa exacte - i
    /// això es crida un cop per cicle de refresc (6 min) per cada usuari amb
    /// avisos actius, així que el nombre de mostres ha d'estar acotat.
    /// S'usen 6 anells concèntrics (més el centre) amb un nombre de mostres
    /// creixent per anell (els anells exteriors tenen més perímetre a
    /// cobrir, però es limita a un màxim de 24 per anell): en el pitjor cas
    /// són ~111 mostres en total, molt per sota del límit de "poques
    /// centenes". Surt d'hora si ja s'ha trobat el pitjor cas possible
    /// (`.hail`), ja que cap mostra addicional el pot superar.
    ///
    /// Robustesa a vores mig grises/mig de color (el frame es reescala amb
    /// interpolació en algun punt de la cadena): cada mostra es classifica
    /// independentment amb `severity(r:g:b:)`, que ja descarta els tons poc
    /// saturats com a "sense eco" - una mostra concreta pot caure just a la
    /// vora i sortir `.none`, però com que es prenen desenes de mostres pel
    /// disc, n'hi ha prou que unes poques caiguin de ple dins l'eco.
    static func maxSeverity(in image: CGImage, aroundNormalized center: CGPoint, radiusKm: Double) -> RainSeverity {
        guard let buffer = PixelBuffer(image) else { return .none }
        let cx = Double(center.x) * Double(image.width)
        let cy = Double(center.y) * Double(image.height)
        let exclude = attributionRectPx(for: image)

        var worst = sample(buffer, x: cx, y: cy, excluding: exclude)
        if worst == .hail { return worst }

        // Radi en km -> fracció de l'amplada del frame -> píxels d'AQUESTA
        // imatge concreta (mai una mida fixa, vegeu el comentari de dalt).
        let radiusPx = (radiusKm / RadarFrameGeometry.frameWidthKm) * Double(image.width)
        guard radiusPx > 0 else { return worst }

        let rings = 6
        for ring in 1...rings {
            let r = radiusPx * Double(ring) / Double(rings)
            let samplesOnRing = min(24, max(8, ring * 6))
            for s in 0..<samplesOnRing {
                let angle = 2 * Double.pi * Double(s) / Double(samplesOnRing)
                let sev = sample(buffer, x: cx + r * cos(angle), y: cy + r * sin(angle), excluding: exclude)
                if sev > worst {
                    worst = sev
                    if worst == .hail { return worst }
                }
            }
        }
        return worst
    }

    /// Severitat màxima present a TOT el frame, ignorant la insígnia i el
    /// soroll aïllat. `.none` només si de debò no hi ha eco significatiu.
    ///
    /// Mateix mostreig que abans feia servir `hasSignificantRain` (pas de 4
    /// píxels - als ecos de radar, escala molt més gran que 4px, no se'ls
    /// escapa cap taca real, i és prou barat per cridar-se cada cicle de
    /// refresc) i el mateix llindar anti-soroll (proporcional a les mostres
    /// VÀLIDES, és a dir sense comptar les descartades per
    /// `attributionRectNormalized`, amb un mínim absolut de 6 perquè en
    /// frames petits una fracció microscòpica no quedi arrodonida a zero),
    /// però aplicat de manera ACUMULATIVA per nivell: es compta, de
    /// `.hail` cap avall, quantes mostres vàlides són "aquest nivell o
    /// pitjor", i es retorna el primer (més alt) nivell el recompte
    /// acumulat del qual arriba al llindar. Acumular en lloc de comptar
    /// cada nivell tot sol resol dos problemes de cop:
    /// - Un artefacte de vora o un únic píxel de compressió classificat per
    ///   atzar com `.hail` no fa que tot el frame "s'ensumi" calamarsa: el
    ///   recompte de NOMÉS `.hail` no arriba al llindar, i cau al nivell
    ///   real de sota.
    /// - Un eco real sol tenir una zona central més forta envoltada de tons
    ///   més febles, no un bloc uniforme d'un sol color: uns quants píxels
    ///   de cada nivell (moderat + fort + calamarsa) que, comptats cada un
    ///   tot sol, no arriben al llindar, sí que hi arriben comptats junts
    ///   ("moderat o pitjor").
    static func maxSeverityOverFrame(in image: CGImage) -> RainSeverity {
        guard let buffer = PixelBuffer(image) else { return .none }
        let exclude = attributionRectPx(for: image)
        let step = 4
        var validSamples = 0
        // Recompte EXACTE per nivell (índex = `RainSeverity.rawValue`);
        // `exactCounts[.none.rawValue]` no s'usa mai per decidir res.
        var exactCounts = [Int](repeating: 0, count: 5)

        var y = 0
        while y < image.height {
            var x = 0
            while x < image.width {
                defer { x += step }
                if let exclude, exclude.contains(CGPoint(x: Double(x), y: Double(y))) { continue }
                validSamples += 1
                if let (r, g, b) = buffer.rgb(x: x, y: y) {
                    exactCounts[severity(r: r, g: g, b: b).rawValue] += 1
                }
            }
            y += step
        }

        let threshold = max(6, Int((Double(validSamples) * 0.003).rounded(.up)))
        var cumulative = 0
        for level in stride(from: RainSeverity.hail.rawValue, through: RainSeverity.weak.rawValue, by: -1) {
            cumulative += exactCounts[level]
            if cumulative >= threshold { return RainSeverity(rawValue: level)! }
        }
        return .none
    }

    /// `true` si hi ha un eco significatiu (>= `.moderate`) en algun lloc del
    /// frame - per a la línia d'estat "Pluja activa a Catalunya" quan
    /// l'usuari no té avisos actius (i per tant no hi ha `center` on mirar).
    /// Definida en termes de `maxSeverityOverFrame` (vegeu el comentari
    /// d'aquella funció): no hi ha una segona lògica de llindar aquí.
    static func hasSignificantRain(in image: CGImage) -> Bool {
        maxSeverityOverFrame(in: image) >= .moderate
    }

    /// Classifica per to (hue): primer descarta grisos (terra/fronteres),
    /// després reparteix el cercle de tons en 4 franges seguint l'ordre de
    /// la llegenda de Meteocat (que NO és un escombrat continu del cercle de
    /// tons - per això "Feble" (blau/lila) i "Calamarsa" (magenta) són
    /// franges veïnes tot i representar intensitats oposades).
    private static func severity(r: UInt8, g: UInt8, b: UInt8) -> RainSeverity {
        let (rd, gd, bd) = (Double(r), Double(g), Double(b))
        let maxC = max(rd, gd, bd), minC = min(rd, gd, bd)
        let delta = maxC - minC
        guard delta > 30 else { return .none }   // gris: sense eco

        var hue: Double
        if maxC == rd {
            hue = 60 * (((gd - bd) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxC == gd {
            hue = 60 * ((bd - rd) / delta + 2)
        } else {
            hue = 60 * ((rd - gd) / delta + 4)
        }
        if hue < 0 { hue += 360 }

        switch hue {
        case 45..<170: return .moderate   // verd/groc
        case 170..<300: return .weak      // cian/blau/lila
        case 300..<345: return .hail      // magenta/rosa
        default: return .strong           // vermell/taronja (345...360 i 0..<45)
        }
    }

    /// Mostra un punt de `buffer` en el seu propi espai (top-left, y avall -
    /// sense flip, vegeu `PixelBuffer`), arrodonint al píxel més proper.
    /// Fora de rang (el disc pot sobresortir del frame a prop de les vores) o
    /// dins `excludeRect` (la insígnia, vegeu `attributionRectPx`) retorna
    /// `.none`, que mai guanya el màxim - simplement no aporta res.
    private static func sample(_ buffer: PixelBuffer, x: Double, y: Double, excluding excludeRect: CGRect?) -> RainSeverity {
        let px = Int(x.rounded()), py = Int(y.rounded())
        if let excludeRect, excludeRect.contains(CGPoint(x: Double(px), y: Double(py))) { return .none }
        guard let (r, g, b) = buffer.rgb(x: px, y: py) else { return .none }
        return severity(r: r, g: g, b: b)
    }

    /// Converteix `RadarCompositor.attributionRectNormalized` (0...1,
    /// dalt-esquerra, y avall - mateix espai que `center`) a píxels
    /// d'AQUESTA imatge concreta, un cop per crida. `nil` si el mapa base
    /// vigent no porta insígnia (llavors no es descarta res).
    private static func attributionRectPx(for image: CGImage) -> CGRect? {
        guard let rect = RadarCompositor.attributionRectNormalized else { return nil }
        let w = Double(image.width), h = Double(image.height)
        return CGRect(x: rect.minX * w, y: rect.minY * h, width: rect.width * w, height: rect.height * h)
    }
}

/// Vista de només lectura sobre el buffer RGBA d'un `CGImage`, en l'espai
/// propi del buffer (top-left, y avall - el mateix que `CGImageSource`
/// produeix, sense cap flip). Es construeix un cop per crida a
/// `maxSeverity`/`hasSignificantRain` i es reutilitza per a totes les
/// mostres, evitant repetir `dataProvider?.data` per cada píxel mostrejat.
private struct PixelBuffer {
    private let bytes: UnsafePointer<UInt8>
    private let retainedData: CFData   // manté viu el buffer mentre `bytes` s'usa
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    private let bpp: Int

    init?(_ image: CGImage) {
        guard let provider = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(provider)
        else { return nil }
        self.retainedData = provider
        self.bytes = ptr
        self.width = image.width
        self.height = image.height
        self.bytesPerRow = image.bytesPerRow
        self.bpp = image.bitsPerPixel / 8
    }

    func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8)? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = y * bytesPerRow + x * bpp
        guard offset + 2 < CFDataGetLength(retainedData) else { return nil }
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}
