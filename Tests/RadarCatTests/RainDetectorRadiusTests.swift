import Testing
import CoreGraphics
@testable import RadarCat

/// `maxSeverity`: un radi petit no ha d'arribar a un eco llunyà, un de gran sí.
@Suite struct MaxSeverityRadiusTests {
    @Test func smallRadiusMissesFarEcho_bigRadiusCatchesIt() {
        let width = 200, height = 200
        let cx = width / 2, cy = height / 2
        let offsetPx = 70
        let echo = (x: cx + offsetPx, y: cy)

        // Tot el frame és gris de terreny (sense eco) excepte un únic píxel
        // vermell (forta) a `offsetPx` píxels a la dreta del centre.
        let image = TestImage.make(width: width, height: height) { x, y in
            if x == echo.x && y == echo.y { return (255, 0, 0) }
            return (128, 128, 128)
        }
        let center = CGPoint(x: 0.5, y: 0.5)

        // Es converteix l'offset en píxels a km amb la MATEIXA fórmula que
        // fa servir `maxSeverity` (radiusKm / frameWidthKm * amplada), en
        // lloc d'un valor de km fix, perquè el test no depengui del valor
        // concret que triï `RadarFrameGeometry.frameWidthKm` (unitat en
        // paral·lel) - es comprova la relació geomètrica, no un número
        // absolut de km.
        let kmPerPixel = RadarFrameGeometry.frameWidthKm / Double(width)
        // radiusPx = offsetPx - 20: l'anell més extern (l'únic que pot
        // arribar-hi) queda sempre curt, per construcció, sense importar
        // l'arrodoniment del mostreig.
        let smallRadiusKm = Double(offsetPx - 20) * kmPerPixel
        // radiusPx = offsetPx exacte: l'anell més extern, a angle 0, cau
        // exactament sobre l'eco (mateix eix x que el centre).
        let bigRadiusKm = Double(offsetPx) * kmPerPixel

        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: smallRadiusKm) == .none)
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: bigRadiusKm) == .strong)
    }

    // `y = 0.5` és un punt fix de qualsevol inversió vertical (1 - 0.5 =
    // 0.5): un test que només hi col·loqui el centre no distingiria un
    // `cy = center.y * height` correcte d'un `cy = (1 - center.y) * height`
    // invertit. Aquests dos casos posen `center.y` prop de 0 i prop d'1
    // (lluny del punt fix) amb l'eco exactament a la posició que la fórmula
    // CORRECTA hauria de mostrejar primer (el propi centre) - un mirall
    // vertical el buscaria a l'altra punta del frame i el test fallaria.
    // És el mateix tipus de bug (mirall vertical) que aquest projecte ja va
    // patir un cop a `RadarCompositor` - vegeu CLAUDE.md.
    @Test func detectsEchoNearNorthEdge_notFooledByVerticalFlip() {
        let width = 200, height = 200
        let normY = 0.05
        let echoY = Int((normY * Double(height)).rounded())
        let image = TestImage.make(width: width, height: height) { x, y in
            if x == width / 2 && y == echoY { return (255, 0, 0) }
            return (128, 128, 128)
        }
        let center = CGPoint(x: 0.5, y: normY)
        let kmPerPixel = RadarFrameGeometry.frameWidthKm / Double(width)
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: 5 * kmPerPixel) == .strong)
    }

    @Test func detectsEchoNearSouthEdge_notFooledByVerticalFlip() {
        let width = 200, height = 200
        let normY = 0.95
        let echoY = Int((normY * Double(height)).rounded())
        let image = TestImage.make(width: width, height: height) { x, y in
            if x == width / 2 && y == echoY { return (255, 0, 0) }
            return (128, 128, 128)
        }
        let center = CGPoint(x: 0.5, y: normY)
        let kmPerPixel = RadarFrameGeometry.frameWidthKm / Double(width)
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: 5 * kmPerPixel) == .strong)
    }

    @Test func zeroRadiusOnlyChecksCenter() {
        let width = 100, height = 100
        let image = TestImage.make(width: width, height: height) { x, y in
            if x == 50 && y == 50 { return (255, 0, 0) }   // el propi centre
            if x == 51 && y == 50 { return (0, 255, 0) }   // a 1px, no hauria de comptar
            return (128, 128, 128)
        }
        let center = CGPoint(x: 0.5, y: 0.5)
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: 0) == .strong)
    }

    @Test func negativeRadiusOnlyChecksCenter() {
        let width = 100, height = 100
        let image = TestImage.make(width: width, height: height) { x, y in
            if x == 50 && y == 50 { return (128, 128, 128) }   // centre sec
            if x == 51 && y == 50 { return (255, 0, 0) }       // eco fort a tocar, fora d'abast
            return (128, 128, 128)
        }
        let center = CGPoint(x: 0.5, y: 0.5)
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: -5) == .none)
    }

    @Test func centerOutsideUnitRangeDoesNotCrashAndStillFindsEchoWithinReach() {
        let width = 100, height = 100
        let image = TestImage.make(width: width, height: height) { x, y in
            if x == 5 && y == 50 { return (255, 0, 0) }
            return (128, 128, 128)
        }
        let center = CGPoint(x: -0.1, y: 0.5)   // cx = -10: fora del frame
        let kmPerPixel = RadarFrameGeometry.frameWidthKm / Double(width)
        // radiusPx = 15: l'anell més extern, a angle 0, cau exactament a
        // x = -10 + 15 = 5, on és l'eco.
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: 15 * kmPerPixel) == .strong)
    }

    @Test func radiusCoveringWholeFrameDoesNotCrash() {
        let width = 50, height = 50
        let image = TestImage.make(width: width, height: height) { x, y in
            if x == 25 && y == 25 { return (0, 255, 0) }
            return (128, 128, 128)
        }
        let center = CGPoint(x: 0.5, y: 0.5)
        let kmPerPixel = RadarFrameGeometry.frameWidthKm / Double(width)
        let hugeRadiusKm = 1_000 * kmPerPixel   // molt més gran que el frame sencer
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: hugeRadiusKm) == .moderate)
    }

    @Test func oneByOneImageDoesNotCrash() {
        let image = TestImage.solid(width: 1, height: 1, rgb: (0, 255, 0))
        let center = CGPoint(x: 0.5, y: 0.5)
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: 5) == .moderate)
    }

    @Test func echoAtSquareCornerOutsideCircleIsNotDetected() {
        let width = 200, height = 200
        let cx = 100, cy = 100
        let radiusPx = 40
        // Cantonada del quadrat circumscrit al disc de radi `radiusPx`:
        // distància des del centre = radiusPx * sqrt(2) ≈ 56.6, ben fora del
        // disc encara que hi càpiga dins la caixa que l'envolta - prova que
        // el mostreig és per anells (mai supera `radiusPx`), no una graella
        // quadrada.
        let cornerX = cx + radiusPx, cornerY = cy + radiusPx
        let image = TestImage.make(width: width, height: height) { x, y in
            if x == cornerX && y == cornerY { return (255, 0, 0) }
            return (128, 128, 128)
        }
        let center = CGPoint(x: 0.5, y: 0.5)
        let kmPerPixel = RadarFrameGeometry.frameWidthKm / Double(width)
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: Double(radiusPx) * kmPerPixel) == .none)
    }
}

/// `hasSignificantRain`: cap eco, un de gran, i soroll aïllat.
@Suite struct HasSignificantRainTests {
    @Test func allGrayFrameHasNoSignificantRain() {
        let image = TestImage.solid(width: 60, height: 60, rgb: (128, 128, 128))
        #expect(RainDetector.hasSignificantRain(in: image) == false)
    }

    @Test func largeGreenPatchIsSignificantRain() {
        let image = TestImage.make(width: 60, height: 60) { x, y in
            if (20...40).contains(x) && (20...40).contains(y) { return (0, 255, 0) }
            return (128, 128, 128)
        }
        #expect(RainDetector.hasSignificantRain(in: image) == true)
    }

    @Test func oneOrTwoIsolatedPixelsAreNotSignificantRain() {
        let image = TestImage.make(width: 60, height: 60) { x, y in
            // Coordenades múltiples de 4 (alineades amb el pas de mostreig
            // de `hasSignificantRain`) a posta, perquè el test comprovi el
            // LLINDAR de mostres i no depengui de si la graella de mostreig
            // troba o no aquests dos píxels concrets per pura sort.
            if (x, y) == (20, 20) || (x, y) == (24, 24) { return (0, 255, 0) }
            return (128, 128, 128)
        }
        #expect(RainDetector.hasSignificantRain(in: image) == false)
    }

    @Test func oneByOneImageDoesNotCrash() {
        // Una sola mostra mai supera el mínim absolut (6): no pot demostrar
        // "pluja significativa" per si sola.
        let image = TestImage.solid(width: 1, height: 1, rgb: (0, 255, 0))
        #expect(RainDetector.hasSignificantRain(in: image) == false)
    }
}
