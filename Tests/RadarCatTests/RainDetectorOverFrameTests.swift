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

    /// Regressió del bug real que va motivar el pas a components connexos
    /// (vegeu el comentari de `maxSeverityOverFrame`): moltes taques dobles
    /// disperses arreu del frame, cap d'elles a prop de cap altra (separades
    /// per 3 passos de graella = 12px, molt més que la distància 8-connectada
    /// d'1 pas), simulant l'eco feble i escampat d'un dia pràcticament sec.
    /// Amb la lògica ACUMULATIVA anterior, el recompte total (10 mostres)
    /// hauria superat el llindar (6) i hauria tornat `.weak` fals; amb
    /// components connexos cap clúster individual (mida 1) hi arriba.
    @Test func manyScatteredIsolatedBluePixelsAreNotSignificantRain() {
        let scatteredGridPoints: Set<[Int]> = [
            [0, 0], [0, 3], [0, 6], [0, 9],
            [3, 0], [3, 3], [3, 6], [3, 9],
            [6, 0], [6, 3],
        ]
        let image = TestImage.make(width: 60, height: 60) { x, y in
            guard x % 4 == 0, y % 4 == 0, scatteredGridPoints.contains([y / 4, x / 4]) else {
                return (128, 128, 128)
            }
            return (0, 0, 255)   // blau = feble
        }
        #expect(RainDetector.maxSeverityOverFrame(in: image) == .none)
    }

    /// Regressió al REVÉS de l'anterior: tres cèl·lules de pluja REALS i
    /// separades (mida de clúster 4 cadascuna - per sobre de
    /// `minClusterSize`, no soroll puntual), cap prou grossa tota sola per
    /// arribar al llindar del frame, però que plegades SÍ ho són. Una
    /// primera versió d'aquesta funció només mirava el clúster més gran
    /// (no la suma dels que qualifiquen) i hauria tornat `.none` aquí -
    /// exactament tan equivocat en sentit contrari com el bug de dalt.
    @Test func multipleSeparateGenuineClustersSumToSignificantRain() {
        let image = TestImage.make(width: 200, height: 200) { x, y in
            if (20...24).contains(x) && (20...24).contains(y) { return (0, 0, 255) }
            if (100...104).contains(x) && (100...104).contains(y) { return (0, 0, 255) }
            if (60...64).contains(x) && (150...154).contains(y) { return (0, 0, 255) }
            return (128, 128, 128)
        }
        #expect(RainDetector.maxSeverityOverFrame(in: image) == .weak)
    }
}
