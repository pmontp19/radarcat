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

    /// Bounding box de Catalunya en tile-coords (calibrat visualment: x[64..65.2],
    /// y[78.78..79.92]). y més gran = més al nord (dalt).
    static let catalunyaTileX = 64.0...65.2
    static let catalunyaTileY = 78.78...79.92

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 30
        cfg.httpMaximumConnectionsPerHost = 16
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: cfg)
    }

    /// Retall de Catalunya en coordenades display (origen dalt-esquerra, y avall),
    /// igual que el composite de referència en Python. Tile y gran = nord = dalt.
    static var catalunyaCrop: CGRect {
        let ts = CGFloat(RadarGrid.tileSize)
        let x0 = (CGFloat(catalunyaTileX.lowerBound) - 63) * ts
        let x1 = (CGFloat(catalunyaTileX.upperBound) - 63) * ts
        let yTop = (83 - CGFloat(catalunyaTileY.upperBound)) * ts
        let yBot = (83 - CGFloat(catalunyaTileY.lowerBound)) * ts
        return CGRect(x: x0, y: yTop, width: x1 - x0, height: yBot - yTop)
    }

    /// Carrega els tiles del mapa base (cachejat). Es dibuixen directament al
    /// context del frame per evitar el flip vertical de CGContext.draw(image:).
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

        // Passa el context a coordenades display (origen dalt-esquerra, y avall)
        // per coincidir píxel a píxel amb el composite de referència en Python.
        ctx.translateBy(x: 0, y: CGFloat(ch))
        ctx.scaleBy(x: 1, y: -1)

        // Dibuixa tiles (base + radar) en display coords, offset pel retall.
        let drawTile: (Int, Int, Data) -> Void = { x, y, data in
            guard let img = Self.makeCGImage(from: data) else { return }
            let dx = CGFloat((x - 63) * RadarGrid.tileSize) - crop.minX
            let dy = CGFloat((83 - y) * RadarGrid.tileSize) - crop.minY
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
