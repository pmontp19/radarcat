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

/// Detecta el nivell d'eco de pluja en un píxel concret del frame compositat.
enum RainDetector {
    /// `point` en coordenades natives (origen baix-esquerra, y amunt), com
    /// `GeoPosition.pixel` i `RadarCompositor.catalunyaCrop`.
    static func severity(in image: CGImage, at point: CGPoint) -> RainSeverity {
        guard let (r, g, b) = pixel(in: image, at: point) else { return .none }
        return severity(r: r, g: g, b: b)
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

    /// Llegeix el píxel directament del buffer del `CGImage` (creat per
    /// `RadarCompositor` com a RGBA de 8 bits/component, vegeu `compositeFrame`).
    private static func pixel(in image: CGImage, at point: CGPoint) -> (UInt8, UInt8, UInt8)? {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return nil }

        let x = Int(point.x)
        // El buffer és top-left/y-down; `point` ve en espai natiu (baix-
        // esquerra, y amunt) - cal invertir la y.
        let y = image.height - 1 - Int(point.y)
        guard x >= 0, x < image.width, y >= 0, y < image.height else { return nil }

        let bpp = image.bitsPerPixel / 8
        let offset = y * image.bytesPerRow + x * bpp
        guard offset + 2 < CFDataGetLength(data) else { return nil }
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}
