import Foundation

/// The single most severe Meteocat warning applying to a comarca right now -
/// enough to drive a banner and its detail popover.
struct MeteocatCurrentWarning: Equatable {
    let meteorNom: String
    let category: MeteocatDangerCategory
    let perill: Int
    let llindar: String
    let comentari: String
    /// Instant this warning stops being vigent (the 6-hour band's own end,
    /// clipped by the avis' `dataFi`) - not shown anywhere yet in v1, kept
    /// for `MeteocatAlertDetailView` and any future re-check logic.
    let vigentFins: Date
}

/// Warning validity: what applies to a comarca *right now*. Swift port of the
/// "in force" half of `ha-avisoscat`'s `vigencia.py`, scoped down to v1
/// (docs/plans/avisos-meteocat.md): no announced/outlook horizons, no
/// multi-day derivation for an evolution with an unparseable `dia` (that
/// exists there to serve a 3-day outlook grid this v1 does not build), and
/// `temps_violent` emissions are skipped outright rather than projected with
/// their own two-hour window.
///
/// The consequence this module exists to handle is unchanged from
/// `ha-avisoscat`: **a warning starts and stops without the source changing
/// at all** - a warning whose only affected band is `12-18` becomes live at
/// 12:00 UTC even though the payload has not moved. That is why this
/// recompute must stay network-free and safe to call on every location
/// update, not only on a fetch cycle.
enum MeteocatAvisosVigencia {
    /// The four 6-hour UTC bands, keyed exactly as the JSON keys them (the
    /// last one is `"18-00"`, not `"18-24"`) - half-open hour ranges, so
    /// `18-00` covers 18:00 up to but not including the next midnight.
    private static let bandes: [(nom: String, hores: Range<Int>)] = [
        ("00-06", 0..<6), ("06-12", 6..<12), ("12-18", 12..<18), ("18-00", 18..<24),
    ]

    /// Half-open hour range of a band name; `nil` when it is unusable. Known
    /// names are a plain lookup; anything else is parsed as `HH-HH`, so the
    /// `"18-24"` spelling some documentation uses still resolves to the same
    /// range as the `"18-00"` the JSON actually sends.
    private static func horesDeLaBanda(_ nom: String) -> Range<Int>? {
        if let known = bandes.first(where: { $0.nom == nom })?.hores { return known }
        let parts = nom.split(separator: "-")
        guard parts.count == 2, let start = Int(parts[0]), var end = Int(parts[1]) else { return nil }
        if start > 0 && end == 0 { end = 24 }
        guard start >= 0, start < end, end <= 24 else { return nil }
        return start..<end
    }

    /// Half-open UTC interval of an hour range on a given day.
    private static func bounds(day: Date, hores: Range<Int>) -> (start: Date, end: Date) {
        let midnight = Calendar.utc.startOfDay(for: day)
        return (
            midnight.addingTimeInterval(TimeInterval(hores.lowerBound) * 3600),
            midnight.addingTimeInterval(TimeInterval(hores.upperBound) * 3600)
        )
    }

    /// The most severe warning applying to `idComarca` at `now`, `nil` if
    /// nothing does. Every open episode/emission is walked (an unrecognised
    /// `estat` counts as open, same trap as `ha-avisoscat`'s `models.py`);
    /// `temps_violent` emissions are skipped, not projected, which is the one
    /// deliberate exclusion beyond what "in force" alone would already leave
    /// out.
    static func avisVigent(episodis: [MeteocatEpisodi], idComarca: Int, now: Date) -> MeteocatCurrentWarning? {
        var best: MeteocatCurrentWarning?
        for episodi in episodis where episodi.isOpen {
            for avis in episodi.avisos where avis.isOpen && avis.tipus != .tempsViolent {
                for evolucio in avis.evolucions {
                    // v1 does not derive a day for an evolution missing one
                    // (see the type's doc comment): it simply never resolves
                    // as vigent.
                    guard let dia = evolucio.dia else { continue }
                    for (bandaNom, afectacions) in evolucio.periodes {
                        guard let hores = horesDeLaBanda(bandaNom) else { continue }
                        var (inici, fi) = bounds(day: dia, hores: hores)
                        // Clipped by the avis' own start/end: a warning
                        // ending mid-band stops applying at its end, not the
                        // band's end.
                        if let dataInici = avis.dataInici { inici = max(inici, dataInici) }
                        if let dataFi = avis.dataFi { fi = min(fi, dataFi) }
                        guard inici < fi, now >= inici, now < fi else { continue }
                        for afectacio in afectacions where afectacio.idComarca == idComarca {
                            if best == nil || afectacio.perill > best!.perill {
                                best = MeteocatCurrentWarning(
                                    meteorNom: episodi.meteorNom,
                                    category: MeteocatDangerCategory(perill: afectacio.perill),
                                    perill: afectacio.perill,
                                    llindar: afectacio.llindar,
                                    comentari: evolucio.comentari,
                                    vigentFins: fi
                                )
                            }
                        }
                    }
                }
            }
        }
        return best
    }
}

private extension Calendar {
    /// A calendar fixed to UTC, so band boundaries never drift with the
    /// system's local time zone - the whole point of this module is
    /// computing bands in UTC regardless of where the machine thinks it is.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
