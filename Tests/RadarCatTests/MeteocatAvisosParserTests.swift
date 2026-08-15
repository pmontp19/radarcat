import Testing
import Foundation
@testable import RadarCat

/// `MeteocatAvisosParser` extracts the `avisos` JSON array out of a
/// `Meteocat.avisosSMP({...})` call embedded in an HTML page. Each test here
/// pins one of the failure modes `ha-avisoscat`'s own `parser.py` documents
/// (see that file's doc comment) on this independent Swift port.
@Suite struct MeteocatAvisosParserTests {
    @Test func extractsAPlainAvisosArray() throws {
        let html = """
        <html><script>
        Meteocat.avisosSMP({dom:'x', opcions:{avisos:false}, avisos: [[{"id":1}]]});
        </script></html>
        """
        let result = try MeteocatAvisosParser.extractAvisos(fromHTML: html)
        #expect(result.count == 1)
        let day = result[0] as? [Any]
        #expect(day?.count == 1)
    }

    @Test func bracketsInsideACommentTextDoNotConfuseTheArrayEnd() throws {
        // A real `comentari` can read "ratxes de vent [rafegues]" - the `]`
        // inside that string must not be read as closing the array early.
        let html = """
        <script>
        Meteocat.avisosSMP({avisos: [[{"comentari":"ratxes de vent [rafegues] fortes","perill":2}]]});
        </script>
        """
        let result = try MeteocatAvisosParser.extractAvisos(fromHTML: html)
        let day = result[0] as? [Any]
        let episode = day?[0] as? [String: Any]
        #expect(episode?["comentari"] as? String == "ratxes de vent [rafegues] fortes")
    }

    @Test func nestedAvisosKeyInsideAnEpisodeIsNotMistakenForTheTopLevelOne() throws {
        // Every episode object in the real payload carries its own `avisos`
        // sub-key (the emissions of that episode) - only the top-level one
        // (depth 2 from the call's `(`) is the array this parser wants.
        let html = """
        <script>
        Meteocat.avisosSMP({avisos: [[{"meteor":{"nom":"Vent"},"avisos":[{"tipus":"Avís"}]}]]});
        </script>
        """
        let result = try MeteocatAvisosParser.extractAvisos(fromHTML: html)
        let day = result[0] as? [Any]
        #expect(day?.count == 1)
        let episode = day?[0] as? [String: Any]
        #expect((episode?["avisos"] as? [Any])?.count == 1)
    }

    @Test func decoyAvisosKeyInsideOpcionsIsIgnored() throws {
        // `opcions.avisos` is a boolean flag the widget config carries, not
        // the payload; it must never be picked up as the real key.
        let html = """
        <script>
        Meteocat.avisosSMP({opcions:{llistaAvisos:false,avisos:true}, avisos: [[{"id":2}]]});
        </script>
        """
        let result = try MeteocatAvisosParser.extractAvisos(fromHTML: html)
        let day = result[0] as? [Any]
        let episode = day?[0] as? [String: Any]
        #expect(episode?["id"] as? Int == 2)
    }

    @Test func picksTheRichestCandidateAmongMultipleCalls() throws {
        // The real homepage renders the call twice: a 1-day visor and a
        // richer 3-day widget. The richer one must win, ties go to the
        // first.
        let html = """
        <script>
        Meteocat.avisosSMP({avisos: [[{"id":1}]]});
        </script>
        <script>
        Meteocat.avisosSMP({avisos: [[{"id":1}],[{"id":2}],[{"id":3}]]});
        </script>
        """
        let result = try MeteocatAvisosParser.extractAvisos(fromHTML: html)
        #expect(result.count == 3)
    }

    @Test func aQuietDayWithNoOpenEpisodeIsNotAnError() throws {
        // `[[]]` carries zero entries once the one level of nesting is seen
        // through, exactly as empty as a bare `[]` - `pickRichest` collapses
        // a candidate with nothing in it to `[]` either way (mirrors
        // `ha-avisoscat`'s `_pick_richest`), so this must not throw and must
        // not be mistaken for `[[]]` (one empty day).
        let html = """
        <script>Meteocat.avisosSMP({avisos: [[]]});</script>
        """
        let result = try MeteocatAvisosParser.extractAvisos(fromHTML: html)
        #expect(result.isEmpty == true)
        #expect(MeteocatAvisos.parseSnapshot(result).isEmpty == true)
    }

    @Test func noCallMarkerAtAllThrows() {
        #expect(throws: MeteocatParseError.self) {
            try MeteocatAvisosParser.extractAvisos(fromHTML: "<html><body>nothing here</body></html>")
        }
    }

    @Test func callWithNoAvisosKeyThrows() {
        let html = "<script>Meteocat.avisosSMP({dom:'x'});</script>"
        #expect(throws: MeteocatParseError.self) {
            try MeteocatAvisosParser.extractAvisos(fromHTML: html)
        }
    }

    /// End-to-end sanity check against a real captured page: same shape
    /// `ha-avisoscat`'s own `parser.py` extracts from the same file
    /// (docs/captures/smp-page-choice-2026-08-06.md describes the sky that
    /// day: a temps-violent nowcast plus rain warnings across 36 comarques).
    @Test func realCapturedPageYieldsSixEpisodes() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/smp_page_sample.html")
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let raw = try MeteocatAvisosParser.extractAvisos(fromHTML: html)
        let episodis = MeteocatAvisos.parseSnapshot(raw)
        #expect(episodis.count == 6)
        #expect(episodis.contains { $0.meteorNom == "Temps violent" })
    }
}
