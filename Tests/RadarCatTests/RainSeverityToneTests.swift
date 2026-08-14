import Testing
import CoreGraphics
@testable import RadarCat

/// Classificació per to (hue) dels colors de la llegenda de Meteocat, sobre
/// tessel·les uniformes de 20x20. Comprova `maxSeverityOverFrame` perquè
/// `severity(r:g:b:)` és privat - és l'única porta d'entrada des d'aquest
/// mòdul de tests que no depèn d'un radi ni d'un centre. Cal una imatge prou
/// gran (no 1x1): `maxSeverityOverFrame` exigeix un mínim absolut de 6
/// mostres vàlides abans de confiar en cap nivell (vegeu el seu comentari),
/// i amb el pas de mostreig de 4px una tessel·la massa petita mai l'arriba.
@Suite struct RainSeverityToneTests {
    @Test func classifiesLegendColorsByHue() {
        #expect(severityOfSolidColor((0, 0, 255)) == .weak)       // blau
        #expect(severityOfSolidColor((0, 255, 255)) == .weak)     // cian
        #expect(severityOfSolidColor((128, 0, 255)) == .weak)     // lila
        #expect(severityOfSolidColor((0, 255, 0)) == .moderate)   // verd
        #expect(severityOfSolidColor((255, 255, 0)) == .moderate) // groc
        #expect(severityOfSolidColor((255, 140, 0)) == .strong)   // taronja
        #expect(severityOfSolidColor((255, 0, 0)) == .strong)     // vermell
        #expect(severityOfSolidColor((255, 0, 255)) == .hail)     // magenta
    }

    @Test func grayTerrainIsNotAnEcho() {
        #expect(severityOfSolidColor((128, 128, 128)) == .none)
        #expect(severityOfSolidColor((60, 60, 60)) == .none)
        #expect(severityOfSolidColor((230, 230, 230)) == .none)
        // Gris "gairebé" gris (petita diferència entre canals, com deixaria
        // la interpolació d'una vora) tampoc ha de comptar com a eco - el
        // llindar de saturació (`delta > 30`) l'ha de descartar.
        #expect(severityOfSolidColor((140, 132, 128)) == .none)
    }
}

private func severityOfSolidColor(_ rgb: (UInt8, UInt8, UInt8)) -> RainSeverity {
    let image = TestImage.solid(width: 20, height: 20, rgb: rgb)
    return RainDetector.maxSeverityOverFrame(in: image)
}
