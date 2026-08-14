import Testing
import CoreGraphics
@testable import RadarCat

/// Regressió del defecte crític trobat en revisió: la insígnia "meteo.cat"
/// incrustada als tiles de base (groc del sol, verd del núvol) es
/// classificava com a eco de pluja real perquè els seus colors cauen dins
/// els mateixos rangs de to que `severity(r:g:b:)` fa servir per a
/// ".moderate" - vegeu `RadarCompositor.attributionRectNormalized` i el
/// comentari de capçalera de `RainDetector`. Aquests tests construeixen un
/// frame gairebé sec amb colors saturats NOMÉS dins el requadre de la
/// insígnia i comproven que cap dels dos detectors "l'ensuma".
@Suite struct RainDetectorAttributionTests {
    @Test func hasSignificantRainIgnoresAttributionBadge() throws {
        let rect = try #require(RadarCompositor.attributionRectNormalized)
        let width = 300, height = 300
        let badge = pixelRect(rect, width: width, height: height)

        let image = TestImage.make(width: width, height: height) { x, y in
            guard badge.contains(CGPoint(x: Double(x), y: Double(y))) else {
                return (128, 128, 128)   // resta del frame: sec de veritat
            }
            // Alterna els dos colors reals de la insígnia (sol groc / núvol
            // verd, vegeu el comentari de `attributionRectNormalized`), tots
            // dos ".moderate" si no s'exclouen.
            return x % 2 == 0 ? (241, 204, 54) : (2, 135, 53)
        }

        #expect(RainDetector.hasSignificantRain(in: image) == false)
        #expect(RainDetector.maxSeverityOverFrame(in: image) == .none)
    }

    @Test func maxSeverityIgnoresAttributionBadgeEvenCenteredOnIt() throws {
        let rect = try #require(RadarCompositor.attributionRectNormalized)
        let width = 300, height = 300
        let badge = pixelRect(rect, width: width, height: height)

        let image = TestImage.make(width: width, height: height) { x, y in
            badge.contains(CGPoint(x: Double(x), y: Double(y))) ? (241, 204, 54) : (128, 128, 128)
        }

        // Centrat al mig del requadre de la insígnia, amb un radi que el
        // cobreix sencer: sense l'exclusió seria un `.moderate` garantit.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let kmPerPixel = RadarFrameGeometry.frameWidthKm / Double(width)
        let radiusKm = Double(max(badge.width, badge.height)) * kmPerPixel
        #expect(RainDetector.maxSeverity(in: image, aroundNormalized: center, radiusKm: radiusKm) == .none)
    }
}

/// Converteix un rectangle normalitzat (0...1, dalt-esquerra, y avall) a
/// píxels d'una imatge concreta - la mateixa conversió que fa `RainDetector`
/// interanment, replicada aquí perquè el test construeix la imatge de test.
private func pixelRect(_ rect: CGRect, width: Int, height: Int) -> CGRect {
    CGRect(
        x: rect.minX * Double(width), y: rect.minY * Double(height),
        width: rect.width * Double(width), height: rect.height * Double(height)
    )
}
