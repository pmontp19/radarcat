import Testing
import Foundation
@testable import RadarCat

/// `ComarcaResolver` reads the bundled `Resources/comarques.json` (generated
/// by `Scripts/generate_comarques_geometry.py`) and resolves a coordinate by
/// even-odd ray casting. The two real-city checkpoints mirror the ones the
/// generation script self-verifies before writing that file.
@Suite struct ComarcaResolverTests {
    @Test func barcelonaResolvesToBarcelones() {
        let comarca = ComarcaResolver.comarca(at: 41.3851, lon: 2.1734)
        #expect(comarca?.idComarca == 13)
        #expect(comarca?.nom == "Barcelonès")
    }

    @Test func vicResolvesToOsona() {
        let comarca = ComarcaResolver.comarca(at: 41.9301, lon: 2.2545)
        #expect(comarca?.idComarca == 24)
        #expect(comarca?.nom == "Osona")
    }

    @Test func pointOutsideCataloniaResolvesToNil() {
        // Fraga (Aragó), just across the border from the Segrià/Llitera line.
        #expect(ComarcaResolver.comarca(at: 41.5222, lon: 0.3502) == nil)
    }

    @Test func bundledTableHasTheFortyThreeLandComarques() {
        #expect(ComarcaResolver.comarques.count == 43)
        #expect(ComarcaResolver.comarques.allSatisfy { $0.idComarca >= 1 && $0.idComarca <= 43 })
    }

    /// A ring with a hole excludes a point sitting inside that hole, exactly
    /// like `ha-avisoscat`'s `_point_in_polygon` even-odd rule: a point
    /// crosses the outer ring and the hole once each (even = outside), not
    /// only the outer ring (odd = inside). Synthetic geometry, independent of
    /// the real comarques data: a 10x10 degree square with a 2x2 hole at its
    /// centre.
    @Test func evenOddRuleExcludesAHole() {
        let outer: [[Double]] = [[0, 0], [0, 10], [10, 10], [10, 0], [0, 0]]
        let hole: [[Double]] = [[4, 4], [4, 6], [6, 6], [6, 4], [4, 4]]
        let comarca = Comarca(idComarca: 999, nom: "Synthetic", rings: [outer, hole])

        // Inside the outer ring but outside the hole: should resolve inside.
        #expect(pointInSynthetic(comarca, lat: 1, lon: 1) == true)
        // Inside the hole: should resolve outside.
        #expect(pointInSynthetic(comarca, lat: 5, lon: 5) == false)
        // Outside the outer ring entirely.
        #expect(pointInSynthetic(comarca, lat: 20, lon: 20) == false)
    }

    /// `ComarcaResolver.comarca(at:)` only searches the bundled table, so the
    /// synthetic comarca above is tested through the same even-odd logic via
    /// a temporary single-comarca lookup rather than by injecting it into the
    /// shared static table.
    private func pointInSynthetic(_ comarca: Comarca, lat: Double, lon: Double) -> Bool {
        ComarcaResolver.comarca(at: lat, lon: lon, in: [comarca]) != nil
    }
}
