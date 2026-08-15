import Testing
import Foundation
@testable import RadarCat

/// Tolerant reading of the SMP `avisos` shape (`MeteocatAvisos.parseSnapshot`),
/// each covering a trap already fixed once in `ha-avisoscat`'s own
/// `models.py` and worth re-checking on this independent Swift port.
@Suite struct MeteocatAvisosModelTests {
    private func decode(_ json: String) -> [Any] {
        let data = Data(json.utf8)
        return (try? JSONSerialization.jsonObject(with: data) as? [Any]) ?? []
    }

    @Test func estatAsDictionaryReadsItsNomField() {
        let raw = decode("""
        [[{"estat":{"nom":"Obert","data":null},"meteor":{"nom":"Vent"},"avisos":[]}]]
        """)
        let episodis = MeteocatAvisos.parseSnapshot(raw)
        #expect(episodis.count == 1)
        #expect(episodis[0].estat == "Obert")
        #expect(episodis[0].isOpen == true)
    }

    @Test func estatAsPlainStringIsAlsoRead() {
        // The "temps violent" avis shape sends `estat` as a plain string
        // rather than `{"nom": ...}` - both must resolve to the same thing.
        let raw = decode("""
        [[{"estat":"Obert","meteor":{"nom":"Temps violent"},
           "avisos":[{"tipus":"Avís Vigilància per Temps Violent","estat":"Vigent","afectacions":[]}]}]]
        """)
        let episodis = MeteocatAvisos.parseSnapshot(raw)
        #expect(episodis[0].avisos[0].estat == "Vigent")
        #expect(episodis[0].avisos[0].isOpen == true)
    }

    @Test func unknownEstatLiteralCountsAsOpen() {
        // `"Ampliat"` was observed live on the real feed and is not one of
        // the known closure literals - it must read as open, not closed.
        let raw = decode("""
        [[{"estat":{"nom":"Ampliat"},"meteor":{"nom":"Vent"},"avisos":[]}]]
        """)
        #expect(MeteocatAvisos.parseSnapshot(raw)[0].isOpen == true)
    }

    @Test func closedEstatLiteralIsRecognisedByPrefix() {
        let raw = decode("""
        [[{"estat":{"nom":"Tancat"},"meteor":{"nom":"Vent"},"avisos":[]}]]
        """)
        #expect(MeteocatAvisos.parseSnapshot(raw)[0].isOpen == false)
    }

    @Test func nullAfectacionsReadsAsNoEntries() {
        let raw = decode("""
        [[{"estat":"Obert","meteor":{"nom":"Vent"},
           "avisos":[{"tipus":"Avís","estat":"Obert","evolucions":[
             {"dia":"2026-08-06T00:00Z","comentari":"","periodes":[
               {"nom":"12-18","afectacions":null}
             ]}
           ]}]}]]
        """)
        let episodis = MeteocatAvisos.parseSnapshot(raw)
        #expect(episodis[0].avisos[0].evolucions[0].periodes["12-18"] == [])
    }

    @Test func floatShapedNumbersConvertTolerantly() {
        // `perill`/`idComarca`/`nivell` arrive as `2.0`, not `2`.
        let raw = decode("""
        [[{"estat":"Obert","meteor":{"nom":"Vent"},
           "avisos":[{"tipus":"Avís","estat":"Obert","evolucions":[
             {"dia":"2026-08-06T00:00Z","comentari":"","periodes":[
               {"nom":"12-18","afectacions":[
                 {"idComarca":13.0,"perill":2.0,"nivell":1.0,"llindar":"x"}
               ]}
             ]}
           ]}]}]]
        """)
        let afectacio = MeteocatAvisos.parseSnapshot(raw)[0].avisos[0].evolucions[0].periodes["12-18"]![0]
        #expect(afectacio.idComarca == 13)
        #expect(afectacio.perill == 2)
        #expect(afectacio.nivell == 1)
    }

    @Test func tipusRecognisesTempsViolentByPrefix() {
        #expect(MeteocatAvisos.parseTipus("Avís Vigilància per Temps Violent") == .tempsViolent)
        #expect(MeteocatAvisos.parseTipus("Avís") == .avis)
        #expect(MeteocatAvisos.parseTipus("Avís Vigilància") == .vigilancia)
        #expect(MeteocatAvisos.parseTipus("Preavís") == .other)
    }

    @Test func nestedEpisodeListsAreFlattened() {
        // The captured payload nests episodes one level deeper, one sub-array
        // per forecast day: `[[day1…], [day2…], [day3…]]`.
        let raw = decode("""
        [[{"estat":"Obert","meteor":{"nom":"A"},"avisos":[]}],
         [{"estat":"Obert","meteor":{"nom":"B"},"avisos":[]}]]
        """)
        let episodis = MeteocatAvisos.parseSnapshot(raw)
        #expect(episodis.map(\.meteorNom) == ["A", "B"])
    }

    @Test func dangerCategoryMapsToOfficialTrafficLightBands() {
        #expect(MeteocatDangerCategory(perill: 0) == .cap)
        #expect(MeteocatDangerCategory(perill: 1) == .moderat)
        #expect(MeteocatDangerCategory(perill: 2) == .moderat)
        #expect(MeteocatDangerCategory(perill: 3) == .alt)
        #expect(MeteocatDangerCategory(perill: 4) == .alt)
        #expect(MeteocatDangerCategory(perill: 5) == .moltAlt)
        #expect(MeteocatDangerCategory(perill: 6) == .moltAlt)
    }
}
