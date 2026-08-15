import Testing
import Foundation
@testable import RadarCat

/// `MeteocatAvisosVigencia.avisVigent` decides *when* a warning applies, by
/// crossing its band against the clock - the same consequence
/// `ha-avisoscat`'s `vigencia.py` is built on: a warning starts and stops
/// without the source changing at all.
@Suite struct MeteocatAvisosVigenciaTests {
    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return f
    }()

    private func date(_ raw: String) -> Date {
        Self.utcFormatter.date(from: raw)!
    }

    private func episodi(
        meteorNom: String = "Vent",
        estat: String = "Obert",
        avisTipus: MeteocatTipusAvis = .avis,
        avisEstat: String = "Obert",
        dataInici: Date? = nil,
        dataFi: Date? = nil,
        dia: Date?,
        periode: String,
        afectacions: [MeteocatAfectacio]
    ) -> MeteocatEpisodi {
        let evolucio = MeteocatEvolucio(dia: dia, comentari: "test", periodes: [periode: afectacions])
        let avis = MeteocatAvis(
            tipus: avisTipus, estat: avisEstat, dataInici: dataInici, dataFi: dataFi, evolucions: [evolucio]
        )
        return MeteocatEpisodi(meteorNom: meteorNom, estat: estat, avisos: [avis])
    }

    @Test func warningIsVigentWithinItsBand() {
        let dia = date("2026-08-06T00:00Z")
        let episodis = [
            episodi(dia: dia, periode: "12-18", afectacions: [
                MeteocatAfectacio(idComarca: 13, perill: 2, nivell: 1, llindar: "x"),
            ]),
        ]
        let warning = MeteocatAvisosVigencia.avisVigent(
            episodis: episodis, idComarca: 13, now: date("2026-08-06T14:00Z")
        )
        #expect(warning?.perill == 2)
        #expect(warning?.category == .moderat)
    }

    @Test func warningIsNotVigentBeforeOrAfterItsBand() {
        let dia = date("2026-08-06T00:00Z")
        let episodis = [
            episodi(dia: dia, periode: "12-18", afectacions: [
                MeteocatAfectacio(idComarca: 13, perill: 2, nivell: 1, llindar: "x"),
            ]),
        ]
        #expect(MeteocatAvisosVigencia.avisVigent(
            episodis: episodis, idComarca: 13, now: date("2026-08-06T10:00Z")
        ) == nil)
        #expect(MeteocatAvisosVigencia.avisVigent(
            episodis: episodis, idComarca: 13, now: date("2026-08-06T19:00Z")
        ) == nil)
    }

    @Test func dataFiClipsTheBandEarlier() {
        // A warning ending mid-band stops applying at its own end, not the
        // band's end: `18-00` would otherwise cover until midnight.
        let dia = date("2026-08-06T00:00Z")
        let episodis = [
            episodi(
                dataFi: date("2026-08-06T20:00Z"),
                dia: dia, periode: "18-00",
                afectacions: [MeteocatAfectacio(idComarca: 13, perill: 3, nivell: 1, llindar: "x")]
            ),
        ]
        #expect(MeteocatAvisosVigencia.avisVigent(
            episodis: episodis, idComarca: 13, now: date("2026-08-06T19:00Z")
        ) != nil)
        #expect(MeteocatAvisosVigencia.avisVigent(
            episodis: episodis, idComarca: 13, now: date("2026-08-06T21:00Z")
        ) == nil)
    }

    @Test func tempsViolentEmissionsAreSkippedEvenIfTheirWindowWouldBeVigent() {
        let dia = date("2026-08-06T00:00Z")
        let episodis = [
            episodi(
                avisTipus: .tempsViolent,
                dia: dia, periode: "12-18",
                afectacions: [MeteocatAfectacio(idComarca: 13, perill: 6, nivell: 2, llindar: "x")]
            ),
        ]
        #expect(MeteocatAvisosVigencia.avisVigent(
            episodis: episodis, idComarca: 13, now: date("2026-08-06T14:00Z")
        ) == nil)
    }

    @Test func closedEpisodesAndEmissionsAreSkipped() {
        let dia = date("2026-08-06T00:00Z")
        let closedEpisode = episodi(
            estat: "Tancat",
            dia: dia, periode: "12-18",
            afectacions: [MeteocatAfectacio(idComarca: 13, perill: 4, nivell: 1, llindar: "x")]
        )
        let closedAvis = episodi(
            avisEstat: "Finalitzat",
            dia: dia, periode: "12-18",
            afectacions: [MeteocatAfectacio(idComarca: 13, perill: 4, nivell: 1, llindar: "x")]
        )
        #expect(MeteocatAvisosVigencia.avisVigent(
            episodis: [closedEpisode, closedAvis], idComarca: 13, now: date("2026-08-06T14:00Z")
        ) == nil)
    }

    @Test func evolutionWithNoUsableDayNeverResolvesAsVigent() {
        let episodis = [
            episodi(dia: nil, periode: "12-18", afectacions: [
                MeteocatAfectacio(idComarca: 13, perill: 2, nivell: 1, llindar: "x"),
            ]),
        ]
        #expect(MeteocatAvisosVigencia.avisVigent(
            episodis: episodis, idComarca: 13, now: date("2026-08-06T14:00Z")
        ) == nil)
    }

    @Test func mostSevereAffectationWinsAcrossMultipleWarnings() {
        let dia = date("2026-08-06T00:00Z")
        let weak = episodi(
            meteorNom: "Vent", dia: dia, periode: "12-18",
            afectacions: [MeteocatAfectacio(idComarca: 13, perill: 1, nivell: 1, llindar: "x")]
        )
        let strong = episodi(
            meteorNom: "Pluja", dia: dia, periode: "12-18",
            afectacions: [MeteocatAfectacio(idComarca: 13, perill: 5, nivell: 2, llindar: "y")]
        )
        let warning = MeteocatAvisosVigencia.avisVigent(
            episodis: [weak, strong], idComarca: 13, now: date("2026-08-06T14:00Z")
        )
        #expect(warning?.meteorNom == "Pluja")
        #expect(warning?.perill == 5)
        #expect(warning?.category == .moltAlt)
    }

    @Test func onlyTheRequestedComarcaMatches() {
        let dia = date("2026-08-06T00:00Z")
        let episodis = [
            episodi(dia: dia, periode: "12-18", afectacions: [
                MeteocatAfectacio(idComarca: 13, perill: 3, nivell: 1, llindar: "x"),
            ]),
        ]
        #expect(MeteocatAvisosVigencia.avisVigent(
            episodis: episodis, idComarca: 24, now: date("2026-08-06T14:00Z")
        ) == nil)
    }
}
