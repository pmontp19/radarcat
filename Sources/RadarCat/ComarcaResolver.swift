import Foundation

/// One of the 43 land comarques the SMP payload can name, with its ring
/// geometry pre-decoded at dev time by
/// `Scripts/generate_comarques_geometry.py` (see that script for how to
/// regenerate `Resources/comarques.json` if Meteocat ever touches the
/// administrative boundaries). No maritime zones: RadarCat always runs on
/// land, so the 12 sea zones `ha-avisoscat` also tracks would be dead weight
/// here.
struct Comarca: Decodable, Equatable {
    let idComarca: Int
    let nom: String
    /// Closed rings of `[lat, lon]` pairs. Polygon/hole grouping from the
    /// source TopoJSON is not preserved - every ring of a comarca is tested
    /// together under one even-odd parity check, which gives the same answer
    /// as testing each polygon separately as long as a comarca's own rings
    /// never overlap (true for real administrative boundaries) - see the
    /// generation script's docstring.
    let rings: [[[Double]]]
}

/// Resolves a coordinate into the comarca id the SMP feed keys its
/// affectations by. Swift port of `ha-avisoscat`'s
/// `comarques.comarca_at`/`_point_in_polygon` ray casting, run over geometry
/// that is bundled instead of downloaded: unlike the config flow this mirrors,
/// RadarCat resolves a comarca on every location update (docs/plans/
/// avisos-meteocat.md), so fetching and decoding a TopoJSON at runtime would
/// be repeated, needless work for data that essentially never changes.
enum ComarcaResolver {
    static let comarques: [Comarca] = loadComarques()

    private static func loadComarques() -> [Comarca] {
        guard let url = Bundle.module.url(forResource: "comarques", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Comarca].self, from: data)
        else {
            // Never crashes the app over a packaging mistake: a caller simply
            // never resolves a comarca, exactly like a coordinate outside
            // Catalonia - the Meteocat banner just never appears.
            return []
        }
        return decoded
    }

    /// The comarca containing `(lat, lon)`, `nil` if the point falls outside
    /// every known comarca (outside Catalonia, or over the sea - this table
    /// has no maritime zones).
    static func comarca(at lat: Double, lon: Double) -> Comarca? {
        comarca(at: lat, lon: lon, in: comarques)
    }

    /// Same lookup over an explicit table rather than the bundled one - only
    /// exists so tests can exercise the ray-casting rule (e.g. a hole) on
    /// synthetic geometry without touching the shared static table.
    static func comarca(at lat: Double, lon: Double, in table: [Comarca]) -> Comarca? {
        table.first { pointInComarca(lat: lat, lon: lon, comarca: $0) }
    }

    /// Even-odd ray casting over every ring of the comarca at once, so a
    /// point inside a hole reads as outside (crosses the outer ring and the
    /// hole, an even number of times) exactly like `ha-avisoscat`'s
    /// `_point_in_polygon`.
    private static func pointInComarca(lat: Double, lon: Double, comarca: Comarca) -> Bool {
        var inside = false
        for ring in comarca.rings {
            guard ring.count >= 3 else { continue }
            var previous = ring[ring.count - 1]
            for point in ring {
                let (lat1, lon1) = (previous[0], previous[1])
                let (lat2, lon2) = (point[0], point[1])
                if (lat1 > lat) != (lat2 > lat) {
                    let crossingLon = lon1 + (lat - lat1) * (lon2 - lon1) / (lat2 - lat1)
                    if lon < crossingLon {
                        inside.toggle()
                    }
                }
                previous = point
            }
        }
        return inside
    }
}
