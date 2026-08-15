import Foundation

/// Data model and tolerant parser for the Meteocat SMP severe-weather feed,
/// scoped to what v1 needs (docs/plans/avisos-meteocat.md): only ordinary
/// `avis`/`vigilancia` warnings with normal per-comarca, per-band
/// affectations. `preavis` entries live under a separate top-level payload
/// key this parser never reads (`MeteocatAvisosParser` only extracts
/// `avisos`), and `temps_violent` emissions are recognised but skipped in
/// `MeteocatAvisosVigencia` - neither is out of caution, both are a
/// deliberate v1 descope.
///
/// Swift port of `ha-avisoscat`'s `models.py`, keeping its central rule: the
/// keyless `meteo.cat` payload is not a supported API, so every field here is
/// read with a tolerant default, never a forced cast that could crash on a
/// shape the source has never sent before.

/// One comarca affected within one 6-hour band.
struct MeteocatAfectacio: Equatable {
    let idComarca: Int
    let perill: Int   // 0-6
    let nivell: Int   // 1 = low threshold, 2 = high threshold
    let llindar: String
}

/// One forecast day of a warning, split into its time bands.
struct MeteocatEvolucio: Equatable {
    /// Day this entry applies to, read from the JSON `dia` field (a midnight
    /// timestamp). `nil` when unparseable - unlike `ha-avisoscat`'s
    /// `vigencia.py`, v1 does not derive a day for an entry missing one
    /// (that inference exists there for a multi-day outlook this v1 does not
    /// build); an evolution with no day simply never resolves as vigent.
    let dia: Date?
    let comentari: String
    /// Band name ("00-06", "06-12", "12-18", "18-00", exactly as the JSON
    /// keys them) to its affectations.
    let periodes: [String: [MeteocatAfectacio]]
}

/// Warning type, only as far as v1 needs to tell `temps_violent` apart (its
/// own two-hour-from-emission validity window, out of scope here) from
/// everything else.
enum MeteocatTipusAvis: Equatable {
    case avis
    case vigilancia
    case tempsViolent
    case other
}

/// One emission of a warning: its dates plus its per-day evolution.
struct MeteocatAvis: Equatable {
    let tipus: MeteocatTipusAvis
    let estat: String
    let dataInici: Date?
    let dataFi: Date?
    let evolucions: [MeteocatEvolucio]

    /// Whether this emission is not in an explicitly closed state. Mirrors
    /// `ha-avisoscat`'s trap #1: `estat` is never compared for equality
    /// against a single expected value (it was observed live as `"Ampliat"`,
    /// which is open), only checked against a short list of closure prefixes.
    var isOpen: Bool { !MeteocatAvisos.isClosed(estat) }
}

/// A meteor under warning, with its emissions.
struct MeteocatEpisodi: Equatable {
    let meteorNom: String
    let estat: String
    let avisos: [MeteocatAvis]

    var isOpen: Bool { !MeteocatAvisos.isClosed(estat) }
}

/// Official traffic-light category of the 0-6 danger grade
/// (docs/01-data-sources.md §1.4 in `ha-avisoscat`, verified there against
/// Meteocat's own JavaScript): 0 none, 1-2 moderate, 3-4 high, 5-6 very high.
enum MeteocatDangerCategory: Equatable {
    case cap, moderat, alt, moltAlt

    init(perill: Int) {
        switch perill {
        case ...0: self = .cap
        case 1...2: self = .moderat
        case 3...4: self = .alt
        default: self = .moltAlt
        }
    }
}

/// Tolerant reading of the SMP `avisos` array (already decoded from JSON into
/// `[String: Any]`/`[Any]` by `JSONSerialization`, itself already extracted
/// from the page's inline script by `MeteocatAvisosParser`).
enum MeteocatAvisos {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return f
    }()

    // Closure literals actually known. Deliberately short: an unrecognised
    // `estat` counts as open, same reasoning as `ha-avisoscat`'s
    // `_CLOSED_ESTAT_PREFIXES`.
    private static let closedEstatPrefixes = [
        "tancat", "tancada", "finalitzat", "finalitzada",
        "anullat", "anullada", "cancellat", "cancellada",
        "caducat", "caducada", "expirat", "expirada",
    ]

    private static let tempsViolentPrefixes = [
        "avis vigilancia per temps violent", "avis vigilancia temps violent", "avis temps violent",
    ]
    private static let vigilanciaPrefixes = ["avis vigilancia", "avis d'observacio", "avis observacio"]

    /// Casefold, fold Catalan diacritics and collapse whitespace - only what
    /// `estat`/`tipus` literals need to match reliably; `comentari`,
    /// `meteor_nom` and `llindar` are untrusted external text and are never
    /// normalised or matched, only displayed.
    static func normalize(_ value: String) -> String {
        let folded = value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "ca"))
            .replacingOccurrences(of: "·", with: "")
            .lowercased()
        return folded.split(separator: " ").joined(separator: " ")
    }

    static func isClosed(_ estat: String) -> Bool {
        let normalized = normalize(estat)
        guard !normalized.isEmpty else { return false }
        return closedEstatPrefixes.contains { normalized.hasPrefix($0) }
    }

    static func parseTipus(_ raw: String) -> MeteocatTipusAvis {
        let normalized = normalize(raw)
        if tempsViolentPrefixes.contains(where: { normalized.hasPrefix($0) }) { return .tempsViolent }
        if vigilanciaPrefixes.contains(where: { normalized.hasPrefix($0) }) { return .vigilancia }
        if normalized.hasPrefix("avis") { return .avis }
        return .other
    }

    private static func asInt(_ value: Any?, default def: Int = 0) -> Int {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let d = Double(s) { return Int(d) }
        return def
    }

    private static func asString(_ value: Any?, default def: String = "") -> String {
        (value as? String) ?? def
    }

    private static func asList(_ value: Any?) -> [Any] {
        (value as? [Any]) ?? []
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let raw = value as? String, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return dateFormatter.date(from: raw)
    }

    /// Read a status, which arrives either as a plain string or as
    /// `{"nom": ..., ...}`.
    private static func parseEstat(_ value: Any?) -> String {
        if let dict = value as? [String: Any] { return asString(dict["nom"]) }
        return asString(value)
    }

    private static func parseAfectacio(_ raw: Any) -> MeteocatAfectacio? {
        guard let dict = raw as? [String: Any] else { return nil }
        return MeteocatAfectacio(
            idComarca: asInt(dict["idComarca"]),
            perill: asInt(dict["perill"]),
            nivell: asInt(dict["nivell"], default: 1),
            llindar: asString(dict["llindar"])
        )
    }

    private static func parsePeriodes(_ raw: Any?) -> [String: [MeteocatAfectacio]] {
        var result: [String: [MeteocatAfectacio]] = [:]
        for entry in asList(raw) {
            guard let dict = entry as? [String: Any],
                  let nom = dict["nom"] as? String, !nom.isEmpty
            else { continue }
            // `afectacions` arrives as `null`, not `[]`, on a band with
            // nothing in it - `asList` already reads that as no entries.
            let afectacions = asList(dict["afectacions"]).compactMap(parseAfectacio)
            result[nom, default: []].append(contentsOf: afectacions)
        }
        return result
    }

    private static func parseEvolucio(_ raw: Any) -> MeteocatEvolucio? {
        guard let dict = raw as? [String: Any] else { return nil }
        return MeteocatEvolucio(
            dia: parseDate(dict["dia"]),
            comentari: asString(dict["comentari"]),
            periodes: parsePeriodes(dict["periodes"])
        )
    }

    private static func parseAvis(_ raw: Any) -> MeteocatAvis? {
        guard let dict = raw as? [String: Any] else { return nil }
        return MeteocatAvis(
            tipus: parseTipus(asString(dict["tipus"])),
            estat: parseEstat(dict["estat"]),
            dataInici: parseDate(dict["dataInici"]),
            dataFi: parseDate(dict["dataFi"]),
            evolucions: asList(dict["evolucions"]).compactMap(parseEvolucio)
        )
    }

    private static func parseEpisodi(_ raw: Any) -> MeteocatEpisodi? {
        guard let dict = raw as? [String: Any] else { return nil }
        let meteorDict = dict["meteor"] as? [String: Any]
        return MeteocatEpisodi(
            meteorNom: asString(meteorDict?["nom"]),
            estat: parseEstat(dict["estat"]),
            avisos: asList(dict["avisos"]).compactMap(parseAvis)
        )
    }

    /// The captured payload nests episodes one level deeper (`[[{...}]]`, one
    /// sub-array per forecast day), so a list of lists is flattened rather
    /// than parsed as a list of malformed episodes.
    private static func flatten(_ raw: [Any]) -> [Any] {
        var items: [Any] = []
        for entry in raw {
            if let list = entry as? [Any] {
                items.append(contentsOf: list)
            } else {
                items.append(entry)
            }
        }
        return items
    }

    /// Turn the decoded `avisos` JSON array into typed episodes. Never
    /// throws: malformed input in, an empty (or partial) result out - one bad
    /// episode must not discard the healthy ones beside it.
    static func parseSnapshot(_ episodisRaw: [Any]) -> [MeteocatEpisodi] {
        flatten(episodisRaw).compactMap(parseEpisodi)
    }
}
