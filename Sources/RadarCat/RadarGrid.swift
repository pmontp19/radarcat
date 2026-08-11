import Foundation
import CoreGraphics

/// Graella fixa de cobertura del radar de Catalunya a zoom 7.
/// Empíricament: x ∈ [63..68], y ∈ [78..83] (6×6 tiles de 256px).
enum RadarGrid {
    static let z = 7
    static let xRange = 63...68
    static let yRange = 78...83
    static let tileSize = 256

    static var cols: Int { xRange.count }
    static var rows: Int { yRange.count }
    static var pixelWidth: Int { cols * tileSize }
    static var pixelHeight: Int { rows * tileSize }
}
