import Testing
import CoreGraphics
@testable import RadarCat

/// `maxSeverityOverFrame`: el nivell més alt PRESENT a tot el frame, ignorant
/// soroll aïllat (recompte acumulat per nivell, vegeu el comentari de la
/// funció). Mides prou grans perquè els recomptes superin còmodament el
/// mínim absolut de 6 mostres vàlides que exigeix la funció.
@Suite struct MaxSeverityOverFrameTests {
    @Test func allGrayFrameHasNoEcho() {
        let image = TestImage.solid(width: 60, height: 60, rgb: (128, 128, 128))
        #expect(RainDetector.maxSeverityOverFrame(in: image) == .none)
    }

    @Test func fewIsolatedBluePixelsAreNoise() {
        let image = TestImage.make(width: 60, height: 60) { x, y in
            // Coordenades múltiples de 4 (alineades amb el pas de mostreig),
            // com a `oneOrTwoIsolatedPixelsAreNotSignificantRain` - perquè el
            // test comprovi el LLINDAR, no si la graella els troba per atzar.
            if (x, y) == (20, 20) || (x, y) == (24, 24) { return (0, 0, 255) }  // blau = feble
            return (128, 128, 128)
        }
        #expect(RainDetector.maxSeverityOverFrame(in: image) == .none)
    }

    @Test func largeBluePatchIsWeak() {
        let image = TestImage.make(width: 60, height: 60) { x, y in
            if (20...40).contains(x) && (20...40).contains(y) { return (0, 0, 255) }
            return (128, 128, 128)
        }
        #expect(RainDetector.maxSeverityOverFrame(in: image) == .weak)
    }

    @Test func largeGreenPatchIsModerate() {
        let image = TestImage.make(width: 60, height: 60) { x, y in
            if (20...40).contains(x) && (20...40).contains(y) { return (0, 255, 0) }
            return (128, 128, 128)
        }
        #expect(RainDetector.maxSeverityOverFrame(in: image) == .moderate)
    }

    @Test func largeMagentaPatchIsHail() {
        let image = TestImage.make(width: 60, height: 60) { x, y in
            if (20...40).contains(x) && (20...40).contains(y) { return (255, 0, 255) }
            return (128, 128, 128)
        }
        #expect(RainDetector.maxSeverityOverFrame(in: image) == .hail)
    }
}
