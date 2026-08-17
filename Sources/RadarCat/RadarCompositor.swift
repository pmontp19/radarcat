import Foundation
import CoreGraphics
import CoreImage
import ImageIO

/// Aparença amb què cal renderitzar un frame. En `.dark` es inverteix la
/// luminància de la capa de base però el radar es dibuixa sempre igual -
/// vegeu `compositeFrame`. `Hashable` perquè és la clau del cache de la capa
/// de base ja processada (`renderedBaseCache`, vegeu `compositeFrame`).
enum FrameAppearance: Hashable {
    case light, dark
}

/// Composa tiles de radar i de mapa base en una sola imatge, retallada al
/// bbox de Catalunya. Actor: serialitza la xarxa i la cache.
actor RadarCompositor {
    static let shared = RadarCompositor()

    private let session: URLSession
    private var baseTiles: [(x: Int, y: Int, data: Data)]?
    /// Capa de base ja composada i processada per aparença (llum inalterada,
    /// fosc amb `invertedForDarkAppearance` aplicat) - vegeu `compositeFrame`
    /// i `minGoodBaseTiles` sobre quan es pot cachejar de veritat.
    private var renderedBaseCache: [FrameAppearance: CGImage] = [:]
    private let cache = NSCache<NSString, FrameCache>()

    /// Nombre mínim de tiles de base que cal aconseguir per considerar la
    /// càrrega prou bona per cachejar-la (`baseTiles`) com a definitiva.
    /// Calculat com els tiles de `BaseGrid` que intersecten de veritat
    /// `catalunyaTileX`/`catalunyaTileY` (el retall final, no el marge que hi
    /// ha al voltant): x∈{127,128,129,130} (4, ja que 130.55 no arriba a
    /// cobrir el 131) × y∈{159,160,161} (3, ja que 161.95 no arriba a
    /// cobrir el 162) = 12. Per sota d'això el retall final tindria forats
    /// REALS dins l'àrea visible, no només marge de seguretat perdut - no val
    /// la pena cachejar-ho per sempre. `BaseGrid.xRange × BaseGrid.yRange`
    /// (fins a 42 tiles) inclou marge fora d'aquest retall, per això el
    /// llindar és molt més baix que el total demanat a `ensureBase`.
    private static let minGoodBaseTiles = 12

    /// Bounding box de Catalunya en tile-coords *de `BaseGrid`* (z=8, tile y
    /// creix cap al *nord* - vegeu `BaseGrid`). Aquest crop viu en l'espai de
    /// la base, no del radar: el radar (z=7, `RadarGrid`) es dibuixa escalat
    /// x2 sobre aquesta base (vegeu `compositeFrame`), no al revés. Per què
    /// z=8 (i no el z=7 que aquest crop usava abans, o el z=9 provat després)
    /// vegeu CLAUDE.md secció "Tile sources".
    ///
    /// Valors ajustats contra una mesura en píxels del contingut real
    /// (fronteres/etiquetes): el cos etiquetat de Catalunya (Vielha a les
    /// Terres de l'Ebre, Lleida a Girona) queda aproximadament entre tile-x
    /// 128.1...130.4 i tile-y 158.6...160.8 - estable (fronteres/noms no
    /// canvien), a diferència de l'eco de pluja, que sí pot sobresortir-ne
    /// (p.ex. tempestes al Pirineu/Vall d'Aran). El rang de sota hi afegeix
    /// marge per l'eco a banda i banda sense allunyar la càmera més del
    /// necessari - un primer intent més generós (127.6...130.5 /
    /// 158.8...162.5) deixava massa mar/muntanya buida, sobretot a l'oest.
    static let catalunyaTileX = 127.85...130.55
    static let catalunyaTileY = 159.4...161.95

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 30
        cfg.httpMaximumConnectionsPerHost = 16
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: cfg)
        // `RadarAnimator.build` només demana 10 frames per aparença cada
        // cicle (vegeu la doc allà); amb clau timestamp+aparença (`cacheKey`)
        // això vol dir com a màxim 20 entrades útils vives alhora (10 clars +
        // 10 foscos). Sense `countLimit` un `NSCache` no purga per compte,
        // només sota pressió de memòria del sistema - amb doble de claus des
        // que hi ha aparences, val la pena posar un límit explícit en lloc de
        // confiar només en això. Marge x2 (40) per si un canvi d'aparença amb
        // el popover obert deixa vives temporalment les 10 antigues i les 10
        // noves alhora.
        cache.countLimit = 40
    }

    /// Retall de Catalunya en coordenades natives de Core Graphics (origen
    /// baix-esquerra, y creixent cap amunt). A `BaseGrid` el tile y ja creix
    /// cap al nord, igual que la y nativa - a diferència de l'antic retall
    /// sobre `RadarGrid`, aquí NO cal cap "ancoratge"/inversió: la posició
    /// nativa d'un tile (x,y) és senzillament `(x - xRange.lowerBound) * ts`
    /// / `(y - yRange.lowerBound) * ts`.
    static var catalunyaCrop: CGRect {
        let ts = CGFloat(BaseGrid.tileSize)
        let x0 = (CGFloat(catalunyaTileX.lowerBound) - CGFloat(BaseGrid.xRange.lowerBound)) * ts
        let x1 = (CGFloat(catalunyaTileX.upperBound) - CGFloat(BaseGrid.xRange.lowerBound)) * ts
        let y0 = (CGFloat(catalunyaTileY.lowerBound) - CGFloat(BaseGrid.yRange.lowerBound)) * ts
        let y1 = (CGFloat(catalunyaTileY.upperBound) - CGFloat(BaseGrid.yRange.lowerBound)) * ts
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// `true` perquè la insígnia "meteo.cat" ve incrustada directament als
    /// píxels del tile `x=130, y=159` (z=8) de la base, no com a overlay
    /// HTML del giny (per això la veiem sense ni tan sols carregar el giny).
    /// Verificat baixant aquell tile amb `curl` i mirant-lo: la insígnia hi
    /// és, a la seva cantonada superior esquerra, dins la zona que
    /// `catalunyaTileX`/`catalunyaTileY` inclouen (cantonada sud-est del
    /// retall final - vegeu `attributionRectNormalized` per la posició
    /// exacta). Si mai es torna a canviar de zoom o de graella, reverificar-
    /// ho amb el mateix mètode - no assumir que hi continua sent.
    nonisolated static let baseIncludesAttribution = true

    /// Regió del frame ocupada per la insígnia "meteo.cat" dels tiles de
    /// base, en coordenades normalitzades (0...1, origen DALT-ESQUERRA, y
    /// avall - espai de SwiftUI, com `RadarFrameGeometry.normalized`). La
    /// insígnia (caixa blanca + tira d'icones de temps) es classifica com a
    /// eco de pluja per `RainDetector` si no s'exclou explícitament: el
    /// quadre groc del sol és RGB (241,204,54) -> to 48° (dins el rang
    /// "moderada" de `RainDetector`) i el verd del núvol és RGB (2,135,53)
    /// -> to 143° (també "moderada") - en un frame real, 70 de 94 mostres
    /// "humides" que `RainDetector` trobava venien d'aquí, no de pluja real.
    ///
    /// Mesurada llegint el PNG de depuració (z=8, aparença clara, 691x653px)
    /// amb un script (Python/Pillow) que cerca, dins el quadrant inferior
    /// dret, els píxels blancs purs (>250,>250,>250, el fons de la caixa),
    /// molt saturats (icones de colors) o molt foscos (text "meteo.cat") -
    /// contrastant amb el gris pla del mar del voltant. Bbox trobada:
    /// x∈[534,608], y∈[543,592] (retallada visualment amb una ampliació 4x
    /// per confirmar-la). Normalitzat: x∈[0.773,0.881], y∈[0.832,0.908].
    /// S'hi afegeix un marge de seguretat de 6px a cada costat (~0.009 en x,
    /// ~0.009 en y): x∈[0.764,0.890], y∈[0.822,0.917].
    nonisolated static let attributionRectNormalized: CGRect? = CGRect(
        x: 0.764, y: 0.822, width: 0.890 - 0.764, height: 0.917 - 0.822
    )

    /// Carrega els tiles del mapa base (`BaseGrid`; cachejat, un cop per
    /// procés - però NOMÉS si la càrrega arriba a `minGoodBaseTiles`, vegeu
    /// aquella constant). Abans, `if let baseTiles { return baseTiles }` era
    /// cert també quan `baseTiles` era `[]`: una primera arrencada sense
    /// xarxa deixava `baseTiles = []` cachejat per sempre i `compositeFrame`
    /// no tornava a ensenyar mapa mai més, ni quan tornava la connexió, fins
    /// a reiniciar l'app. Ara una càrrega per sota del llindar (buida o
    /// parcial) no es cacheja: es torna tal qual per aquesta crida (millor
    /// mostrar-la que res, si `compositeFrame` en pot fer alguna cosa), però
    /// la propera crida torna a intentar la descàrrega completa en lloc de
    /// quedar-se atrapada amb aquest resultat.
    private func ensureBase() async -> [(x: Int, y: Int, data: Data)] {
        if let baseTiles { return baseTiles }
        var tiles: [(x: Int, y: Int, data: Data)] = []
        for y in BaseGrid.yRange {
            for x in BaseGrid.xRange {
                let url = RadarAPI.fonsTileURL(z: BaseGrid.z, x: x, y: y)
                if let data = await fetch(url) { tiles.append((x, y, data)) }
            }
        }
        if tiles.count >= Self.minGoodBaseTiles {
            baseTiles = tiles
            // Tiles nous -> qualsevol capa ja processada per aparença que
            // hi hagués (no n'hi pot haver cap si açò és la primera vegada
            // que arribem al llindar, però sí si mai es torna a fer buit
            // `baseTiles` en el futur) ha quedat obsoleta.
            renderedBaseCache = [:]
        }
        return tiles
    }

    /// Clau de cache: timestamp *i* aparença, perquè un mateix instant es pot
    /// demanar en clar i en fosc (p.ex. si el sistema canvia d'aparença amb
    /// el popover obert) i són dues imatges diferents - vegeu `compositeFrame`.
    private static func cacheKey(timestamp: Date, appearance: FrameAppearance) -> NSString {
        let suffix = appearance == .dark ? "dark" : "light"
        return "\(timestamp.tilePathComponents)#\(suffix)" as NSString
    }

    /// Composa un frame de radar sobre el mapa base, retallat a Catalunya.
    /// En `.dark`, la capa de base es dibuixa amb la luminància invertida
    /// (vegeu `invertedForDarkAppearance`) i el radar es dibuixa SEMPRE tal
    /// qual a sobre, mai amb cap filtre: la classificació per to de
    /// `RainDetector` (vegeu aquell fitxer) depèn que els ecos conservin
    /// exactament el color de la llegenda de Meteocat, aparença fosca o no.
    func compositeFrame(timestamp: Date, appearance: FrameAppearance) async -> CGImage? {
        let key = Self.cacheKey(timestamp: timestamp, appearance: appearance)
        if let cached = cache.object(forKey: key) { return cached.image }

        let base = await ensureBase()
        guard !base.isEmpty else { return nil }
        let crop = Self.catalunyaCrop
        let cw = Int(crop.width.rounded()), ch = Int(crop.height.rounded())
        let baseTs = CGFloat(BaseGrid.tileSize)
        guard cw > 0, ch > 0 else { return nil }

        // La capa de base (tiles dibuixats + filtre d'aparença) NO depèn del
        // timestamp, només de l'aparença - i `RadarAnimator.build` en demana
        // 10 seguits per cicle de 6 min (vegeu la doc allà). Sense aquest
        // cache es tornaven a dibuixar els tiles de base i a passar tota la
        // cadena de CoreImage (desaturar + invertir + corba tonal, cara) 10
        // cops per un resultat idèntic cada vegada. Només es guarda quan
        // `baseTiles` ja és el cache "bo" i definitiu (`ensureBase`/
        // `minGoodBaseTiles`): si encara hi som per sota, cada crida pot
        // rebre un conjunt de tiles diferent (la xarxa reintentant-se), així
        // que cachejar aquest resultat parcial seria repetir el mateix error
        // que `ensureBase` corregeix per a `baseTiles`. `ensureBase` ja buida
        // aquest cache quan `baseTiles` es refà.
        let renderedBase: CGImage
        if let cached = renderedBaseCache[appearance] {
            renderedBase = cached
        } else {
            guard let baseCtx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }

            // Sense flip de CTM: el context es queda en coordenades natives
            // de Core Graphics (origen baix-esquerra, y creixent cap amunt).
            // `CGContext.draw` sempre col·loca la imatge relativa a la seva
            // pròpia cantonada inferior esquerra en la transformació VIGENT,
            // així que dibuixar sota un CTM invertit (y cap avall) renderitza
            // cada tile de cap per avall. Mantenir el CTM natiu, sense flip,
            // i calcular `dx`/`dy` en aquest mateix espai (vegeu
            // `catalunyaCrop`) ho evita del tot.
            let drawBaseTile: (Int, Int, Data) -> Void = { x, y, data in
                guard let img = Self.makeCGImage(from: data) else { return }
                let dx = CGFloat((x - BaseGrid.xRange.lowerBound) * BaseGrid.tileSize) - crop.minX
                let dy = CGFloat((y - BaseGrid.yRange.lowerBound) * BaseGrid.tileSize) - crop.minY
                baseCtx.draw(img, in: CGRect(x: dx, y: dy, width: baseTs, height: baseTs))
            }
            for t in base { drawBaseTile(t.x, t.y, t.data) }
            guard let baseImage = baseCtx.makeImage() else { return nil }

            // La capa de base es dibuixa en un context propi i es processa
            // (o no) ABANS de barrejar-la amb el radar, perquè el filtre
            // d'inversió mai ha de tocar els píxels del radar (vegeu el
            // comentari de dalt de tot de la funció).
            switch appearance {
            case .light:
                renderedBase = baseImage
            case .dark:
                renderedBase = Self.invertedForDarkAppearance(baseImage) ?? baseImage
            }

            if baseTiles != nil {
                renderedBaseCache[appearance] = renderedBase
            }
        }

        guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(renderedBase, in: CGRect(x: 0, y: 0, width: cw, height: ch))

        // El radar només existeix a z=7 (`RadarGrid`), un nivell de zoom per
        // sota del mapa base a z=8 (`BaseGrid`), així que cada tile de radar
        // cobreix exactament l'àrea de 4 tiles de base (nesting XYZ
        // estàndard: el tile de base (X,Y) és fill del tile de radar
        // (X/2, Y/2)). Es dibuixa cada tile de radar escalat x2, ancorat a
        // la seva posició filla (2x, 2y) en l'espai de coordenades de
        // `BaseGrid` - la imatge en si no necessita cap flip, només
        // l'ancoratge, perquè la y de `RadarGrid` creix cap al *sud* mentre
        // que la de `BaseGrid` creix cap al *nord* (confirmat empíricament,
        // vegeu el comentari de `BaseGrid`): escalar des de (2x, 2y) cobreix
        // aquell fill més (2x+1, 2y+1), cosa que fa caure correctament la
        // meitat nord del tile de radar sobre el fill nord de la base i la
        // meitat sud sobre el fill sud.
        let radarTs = baseTs * 2
        for y in RadarGrid.yRange {
            for x in RadarGrid.xRange {
                let url = RadarAPI.radarTileURL(timestamp: timestamp, z: RadarGrid.z, x: x, y: y)
                guard let data = await fetch(url), let img = Self.makeCGImage(from: data) else { continue }
                let dx = CGFloat((2 * x - BaseGrid.xRange.lowerBound) * BaseGrid.tileSize) - crop.minX
                let dy = CGFloat((2 * y - BaseGrid.yRange.lowerBound) * BaseGrid.tileSize) - crop.minY
                ctx.draw(img, in: CGRect(x: dx, y: dy, width: radarTs, height: radarTs))
            }
        }

        guard let out = ctx.makeImage() else { return nil }
        // A z=8 el retall surt a ~691x653px, gairebé exactament la mida a
        // què es mostra la targeta del mapa (~356pt -> ~712px en retina, un
        // 3% d'ampliació imperceptible) - no cal reescalar-lo (ni cap avall
        // ni cap amunt): vegeu el comentari a `BaseGrid` sobre per què z=9
        // (que sí obligava a triar entre reescalar o gastar 4x més memòria
        // en cache) es va provar i es va desfer.

        cache.setObject(FrameCache(image: out), forKey: key)
        #if DEBUG
        Self.savePNG(out, to: "/Users/pere/Desktop/radarcat_appframe.png")
        #endif
        return out
    }

    /// Classifica la pluja SENSE sortir de l'actor: el mostreig de píxels de
    /// `RainDetector` és feina de CPU que abans corria a `RadarStore`
    /// (`@MainActor`). `normalized` `nil` -> `here` surt `.none` sense
    /// cridar `maxSeverity`. `nil` si no hi ha frame (mateix contracte que
    /// `compositeFrame`).
    func classifyRain(
        timestamp: Date,
        appearance: FrameAppearance,
        aroundNormalized normalized: CGPoint?,
        radiusKm: Double
    ) async -> (overFrame: RainSeverity, here: RainSeverity)? {
        guard let cg = await compositeFrame(timestamp: timestamp, appearance: appearance) else { return nil }
        let overFrame = RainDetector.maxSeverityOverFrame(in: cg)
        let here = normalized.map { RainDetector.maxSeverity(in: cg, aroundNormalized: $0, radiusKm: radiusKm) } ?? .none
        return (overFrame, here)
    }

    /// `CIContext` és car de crear; un de sol reutilitzat entre frames n'hi
    /// ha prou (no té estat mutable propi de cara a nosaltres).
    private static let ciContext = CIContext()

    /// Inverteix la luminància de la capa de base per a l'aparença fosca
    /// (vegeu `compositeFrame` - mai s'aplica al frame amb el radar a
    /// sobre). Es desatura primer (`CIColorControls`, saturació 0) perquè
    /// l'únic element de color real d'aquesta capa - la insígnia
    /// "meteo.cat" - no acabi en un negatiu de tons complementaris cridaner.
    ///
    /// Una inversió pura deixaria el mar més clar que la terra (l'invers
    /// d'apagar-los del tot). La `CIToneCurve` que segueix comprimeix el mar
    /// cap avall i aixeca la terra perquè el relleu es torni a distingir,
    /// sense poder-ne capgirar l'ordre (una funció monòtona no ho permet):
    /// el mar surt sempre una mica més clar que la terra, per un marge molt
    /// més petit que sense corregir. Compromís conscient, no un descuit -
    /// vegeu `docs/dark-mode-tuning.md` per les mesures i el raonament
    /// complet darrere de cada punt de la corba.
    private static func invertedForDarkAppearance(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let desaturateFilter = CIFilter(name: "CIColorControls") else { return nil }
        desaturateFilter.setValue(input, forKey: kCIInputImageKey)
        desaturateFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let desaturated = desaturateFilter.outputImage,
              let invertFilter = CIFilter(name: "CIColorInvert")
        else { return nil }
        invertFilter.setValue(desaturated, forKey: kCIInputImageKey)
        guard let inverted = invertFilter.outputImage,
              let curveFilter = CIFilter(name: "CIToneCurve")
        else { return nil }
        curveFilter.setValue(inverted, forKey: kCIInputImageKey)
        // 5 punts (x=luminància original invertida, y=luminància final),
        // triats a partir dels percentils reals del frame invertit (mar
        // ~0.81, terra ~0.59, fronteres/etiquetes ~0.95-1.0) - vegeu
        // `docs/dark-mode-tuning.md` per com es van triar i mesurar.
        curveFilter.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
        curveFilter.setValue(CIVector(x: 0.35, y: 0.05), forKey: "inputPoint1")
        curveFilter.setValue(CIVector(x: 0.59, y: 0.20), forKey: "inputPoint2")
        curveFilter.setValue(CIVector(x: 0.81, y: 0.35), forKey: "inputPoint3")
        curveFilter.setValue(CIVector(x: 1.0, y: 0.88), forKey: "inputPoint4")
        guard let curved = curveFilter.outputImage else { return nil }
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return ciContext.createCGImage(curved, from: extent)
    }

    /// Debug: escriu un CGImage a PNG (per comparar amb la referència).
    static func savePNG(_ cg: CGImage, to path: String) {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }

    private func fetch(_ url: URL) async -> Data? {
        for attempt in 0..<2 {
            do {
                var req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                req.timeoutInterval = 12
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                    return data
                }
                if attempt == 1 { return nil }
            } catch {
                if attempt == 1 { return nil }
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return nil
    }

    // MARK: - Imatges

    static func makeCGImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

private final class FrameCache {
    let image: CGImage
    init(image: CGImage) { self.image = image }
}
