import CoreGraphics
import Foundation

/// Utilitat de test: construeix un `CGImage` petit escrivint els bytes RGBA
/// directament (mateix format que produeix `RadarCompositor.compositeFrame`:
/// 8 bits/component, `premultipliedLast`), en lloc de dibuixar-lo amb un
/// `CGContext`. Així s'evita qualsevol confusió amb el sistema de
/// coordenades de DIBUIX de Core Graphics (origen baix-esquerra): la
/// clausura `pixel` rep directament fila/columna del buffer (0,0 = cantonada
/// SUPERIOR esquerra, y avall), el mateix espai en què `RainDetector` llegeix
/// el buffer intern.
enum TestImage {
    static func make(width: Int, height: Int, pixel: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                let offset = (y * width + x) * 4
                bytes[offset] = r
                bytes[offset + 1] = g
                bytes[offset + 2] = b
                bytes[offset + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    static func solid(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) -> CGImage {
        make(width: width, height: height) { _, _ in rgb }
    }
}
