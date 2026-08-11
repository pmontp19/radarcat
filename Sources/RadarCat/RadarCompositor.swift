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

    /// Bounding box de Catalunya en tile-coords. Standard XYZ slippy-map
    /// convention: tile y increases *southward* (bigger y = more south),
    /// confirmed empirically against the Meteocat tile server (tile y=78
    /// shows terrain only near its north edge with blank space beyond, tile
    /// y=83 is blank open sea south of Catalonia).
    ///
    /// These values were tuned by eye against the composited output
    /// (`/Users/pere/Desktop/radarcat_appframe.png`), not derived from a
    /// formula, because the tile source itself has irregularities that a
    /// formula can't see:
    /// - Almost the entire labelled Catalonia map (Vielha to Tarragona,
    ///   Lleida to Girona) lives inside the single tile (x=64, y=80); its
    ///   north edge (~y=78.9) and south edge (~y=79.97) are the real limits
    ///   of useful, continuous coverage.
    /// - Tile y=81 has a genuine ~23px black border baked into its top edge
    ///   (verified on the raw tile), so the crop's south bound stays just
    ///   above y=80.0 to avoid showing that border as a stray black line.
    /// - Tile y=79 contains an unrelated, disconnected fragment (a "Tortosa"
    ///   label next to the meteo.cat logo over open sea) that does not
    ///   connect geographically to what's south of it in tile y=80 - most
    ///   likely leftover branding/placeholder content for tiles outside the
    ///   widget's real coverage, not a real northward continuation. Reaching
    ///   into it to try to pick up a labelled Tortosa reintroduces exactly
    ///   the kind of dead/nonsensical content this pass is trying to remove,
    ///   so Tortosa is left out rather than stitched in from there.
    /// The window below favours Vielha/Val d'Aran (north) and Girona's coast
    /// (east) with comfortable margins, and Tarragona with a small but real
    /// margin (rather than clipped, as it is in the Python reference) at the
    /// south, landing on roughly a 1.18:1 aspect close to the popover's own
    /// image area (see `MenuBarContentView.radarStage`, ~380x320pt).
    static let catalunyaTileX = 63.9...65.1
    static let catalunyaTileY = 78.95...79.97

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 30
        cfg.httpMaximumConnectionsPerHost = 16
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: cfg)
    }

    /// Retall de Catalunya en coordenades natives de Core Graphics (origen
    /// baix-esquerra, y creixent cap amunt). Com que el tile y creix cap al
    /// sud, es converteix a "files des de baix" amb `RadarGrid.yRange.upperBound - y`
    /// perquè un y de tile més gran (més al sud) doni una y nativa més petita.
    static var catalunyaCrop: CGRect {
        let ts = CGFloat(RadarGrid.tileSize)
        let yAnchor = CGFloat(RadarGrid.yRange.upperBound)
        let x0 = (CGFloat(catalunyaTileX.lowerBound) - 63) * ts
        let x1 = (CGFloat(catalunyaTileX.upperBound) - 63) * ts
        let yMin = (yAnchor - CGFloat(catalunyaTileY.upperBound)) * ts   // south edge
        let yMax = (yAnchor - CGFloat(catalunyaTileY.lowerBound)) * ts   // north edge
        return CGRect(x: x0, y: yMin, width: x1 - x0, height: yMax - yMin)
    }

    /// Carrega els tiles del mapa base (cachejat), un cop per procés.
    private func ensureBase() async -> [(x: Int, y: Int, data: Data)] {
        if let baseTiles { return baseTiles }
        var tiles: [(x: Int, y: Int, data: Data)] = []
        for y in RadarGrid.yRange {
            for x in RadarGrid.xRange {
                let url = RadarAPI.fonsTileURL(z: RadarGrid.z, x: x, y: y)
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
        let ts = CGFloat(RadarGrid.tileSize)
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
        let drawTile: (Int, Int, Data) -> Void = { x, y, data in
            guard let img = Self.makeCGImage(from: data) else { return }
            let dx = CGFloat((x - 63) * RadarGrid.tileSize) - crop.minX
            let dy = CGFloat((RadarGrid.yRange.upperBound - y) * RadarGrid.tileSize) - crop.minY
            ctx.draw(img, in: CGRect(x: dx, y: dy, width: ts, height: ts))
        }
        for t in base { drawTile(t.x, t.y, t.data) }
        for y in RadarGrid.yRange {
            for x in RadarGrid.xRange {
                let url = RadarAPI.radarTileURL(timestamp: timestamp, z: RadarGrid.z, x: x, y: y)
                guard let data = await fetch(url) else { continue }
                drawTile(x, y, data)
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
