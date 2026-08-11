import Foundation
import Observation

/// Endpoint i constants del servei de radar de Meteocat (giny públic).
enum RadarAPI {
    static let metadataURL = URL(string:
        "https://static-m.meteo.cat/ginys/referencia/tiles/dates-tiles-CAPPI_0m.json")!
    static let ginyURL = URL(string:
        "https://static-m.meteo.cat/ginys/mapaRadar?language=ca")!
    static let meteoCatURL = URL(string: "https://www.meteo.cat")!

    /// Base dels tiles de radar.
    static let radarTilesBase = "https://static-m.meteo.cat/tiles/radar"
    /// Base dels tiles de mapa de fons.
    static let fonsTilesBase = "https://static-m.meteo.cat/tiles/fons/GoogleMapsCompatible"

    /// Construeix la URL d'un tile de radar per a un timestamp i coordenades.
    /// Format: {base}/{YYYY}/{MM}/{DD}/{HH}/{mm}/{zz}/000/000/{xxx}/000/000/{yyy}.png
    static func radarTileURL(timestamp: Date, z: Int, x: Int, y: Int) -> URL {
        let comps = timestamp.tilePathComponents
        let zs = String(format: "%02d", z)
        let xs = String(format: "%03d", x)
        let ys = String(format: "%03d", y)
        return URL(string: "\(radarTilesBase)/\(comps)/\(zs)/000/000/\(xs)/000/000/\(ys).png")!
    }

    /// Construeix la URL d'un tile de fons (mapa base).
    static func fonsTileURL(z: Int, x: Int, y: Int) -> URL {
        let zs = String(format: "%02d", z)
        let xs = String(format: "%03d", x)
        let ys = String(format: "%03d", y)
        return URL(string: "\(fonsTilesBase)/\(zs)/000/000/\(xs)/000/000/\(ys).png")!
    }
}

extension Date {
    /// Components pel path de tiles en hora UTC: "yyyy/MM/dd/HH/mm".
    var tilePathComponents: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy/MM/dd/HH/mm"
        return f.string(from: self)
    }

    /// Etiqueta llegible (hora local): "06/08 16:54".
    var shortLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: self)
    }
}

struct RadarMeta: Decodable {
    let dataUltimaImatge: String
    let dataSistema: String

    var ultimaImatgeDate: Date? { RadarMeta.parse(dataUltimaImatge) }
    var sistemaDate: Date? { RadarMeta.parse(dataSistema) }

    /// "08/06/2026 14:54Z" -> Date en UTC.
    static func parse(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MM/dd/yyyy HH:mm'Z'"
        return f.date(from: raw)
    }
}
