import Foundation
import CoreGraphics
import ImageIO

/// Composa tiles de radar i de mapa base en una sola imatge, retallada al
/// bbox de Catalunya. Actor: serialitza la xarxa i la cache.
actor RadarCompositor {
    static let shared = RadarCompositor()

    private let session: URLSession
    private var baseTiles: [(x: Int, y: Int, data: Data)]?
    private let cache = NSCache<NSString, FrameCache>()

    /// Bounding box de Catalunya en tile-coords *de `BaseGrid`* (z=8, tile y
    /// creix cap al *nord* - vegeu `BaseGrid`). Aquest crop viu en l'espai de
    /// la base, no del radar: el radar (z=7, `RadarGrid`) es dibuixa escalat
    /// x2 sobre aquesta base (vegeu `compositeFrame`), no al revés.
    ///
    /// Abans això retallava directament els tiles de radar/base de z=7, que
    /// van resultar ser una imatge pre-tallada no estàndard sense les Terres
    /// de l'Ebre (amb una vora negra baixada del tile y=81 i un fragment de
    /// "Tortosa" despenjat sobre mar al tile y=79 - vegeu el git log
    /// d'aquest fitxer per aquella versió i el raonament complet). Es va
    /// descobrir baixant el widget real de Meteocat (`ginys/mapaRadar`) en
    /// un navegador: el seu mapa base fa servir z=8, una projecció contínua
    /// real que sí conté les Terres de l'Ebre de manera coherent amb la
    /// resta del mapa (Tortosa apareix just al sud de Tarragona, sense cap
    /// tall ni fragment despenjat). El radar de Meteocat només existeix a
    /// z=7, per això es continua fent servir `RadarGrid` per baixar-lo,
    /// escalant-lo x2 per encaixar amb aquesta base de z=8.
    ///
    /// Valors ajustats contra una mesura en píxels del contingut real
    /// (fronteres/etiquetes) sobre aquesta graella de z=8: el cos etiquetat
    /// de Catalunya (Vielha a les Terres de l'Ebre, Lleida a Girona) queda
    /// aproximadament entre tile-x 128.1...130.4 i tile-y 158.6...160.8 -
    /// això és estable (fronteres/noms no canvien), a diferència de l'eco de
    /// pluja, que sí pot sobresortir-ne (p.ex. tempestes al Pirineu/Vall
    /// d'Aran, just al nord del límit administratiu). El rang de sota hi
    /// afegeix marge per l'eco de pluja a banda i banda sense allunyar la
    /// càmera més del necessari - un primer intent més generós (127.6...
    /// 130.5 / 158.8...162.5) deixava massa mar/muntanya buida, sobretot a
    /// l'oest.
    static let catalunyaTileX = 127.85...130.55
    static let catalunyaTileY = 159.4...161.95

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 30
        cfg.httpMaximumConnectionsPerHost = 16
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: cfg)
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

    /// Aspecte (amplada/alçada) del frame compositat. `MenuBarContentView`
    /// hi ajusta l'escenari del radar (`.aspectRatio`) en lloc de dependre
    /// d'una alçada de finestra calculada a mà - això evitava, per
    /// construcció, quedar-se curt o llarg i deixar bandes buides a dalt/baix
    /// cada cop que `catalunyaTileX`/`catalunyaTileY` es retoquen. Nonisolated
    /// perquè és static i pur (sense estat de l'actor), consultable des de
    /// la vista sense `await`.
    nonisolated static var catalunyaCropAspectRatio: CGFloat {
        let crop = catalunyaCrop
        return crop.width / crop.height
    }

    /// Carrega els tiles del mapa base (z=8, `BaseGrid`; cachejat, un cop per procés).
    private func ensureBase() async -> [(x: Int, y: Int, data: Data)] {
        if let baseTiles { return baseTiles }
        var tiles: [(x: Int, y: Int, data: Data)] = []
        for y in BaseGrid.yRange {
            for x in BaseGrid.xRange {
                let url = RadarAPI.fonsTileURL(z: BaseGrid.z, x: x, y: y)
                if let data = await fetch(url) { tiles.append((x, y, data)) }
            }
        }
        baseTiles = tiles
        return tiles
    }

    /// Composa un frame de radar sobre el mapa base, retallat a Catalunya.
    func compositeFrame(timestamp: Date) async -> CGImage? {
        let key = timestamp.tilePathComponents as NSString
        if let cached = cache.object(forKey: key) { return cached.image }

        let base = await ensureBase()
        guard !base.isEmpty else { return nil }
        let crop = Self.catalunyaCrop
        let cw = Int(crop.width.rounded()), ch = Int(crop.height.rounded())
        let baseTs = CGFloat(BaseGrid.tileSize)
        guard cw > 0, ch > 0,
              let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // No CTM flip here: the context stays in native Core Graphics
        // coordinates (origin bottom-left, y increasing upward). CGContext.draw
        // always places an image relative to its own bottom-left corner in the
        // CURRENT transform, so drawing under a y-flipped CTM renders every
        // tile upside down. Keeping the native, unflipped CTM and computing
        // `dx`/`dy` below in that same native space (see `catalunyaCrop`)
        // avoids that entirely.
        let drawBaseTile: (Int, Int, Data) -> Void = { x, y, data in
            guard let img = Self.makeCGImage(from: data) else { return }
            let dx = CGFloat((x - BaseGrid.xRange.lowerBound) * BaseGrid.tileSize) - crop.minX
            let dy = CGFloat((y - BaseGrid.yRange.lowerBound) * BaseGrid.tileSize) - crop.minY
            ctx.draw(img, in: CGRect(x: dx, y: dy, width: baseTs, height: baseTs))
        }
        for t in base { drawBaseTile(t.x, t.y, t.data) }

        // Radar only exists at z=7 (RadarGrid), one zoom level below the
        // base map's z=8 (BaseGrid), so each radar tile covers exactly the
        // area of 4 base tiles (standard XYZ nesting: base tile (X,Y) is a
        // child of radar tile (X/2, Y/2)). Draw each radar tile scaled x2,
        // anchored at its (2x, 2y) child position in BaseGrid's coordinate
        // space - the image itself needs no flip, only its anchor point
        // does, because RadarGrid's y increases *southward* while
        // BaseGrid's increases *northward* (confirmed empirically, see
        // BaseGrid's doc comment): scaling up from (2x, 2y) covers that
        // child plus (2x+1, 2y+1), which correctly lands the radar tile's
        // own north half over the base's north child and south half over
        // the south child.
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
        cache.setObject(FrameCache(image: out), forKey: key)
        Self.savePNG(out, to: "/Users/pere/Desktop/radarcat_appframe.png")
        return out
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
            try? await Task.sleep(nanoseconds: 150_000_000)
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
