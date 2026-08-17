import SwiftUI

/// Anell del radi d'avís al voltant del punt d'ubicació, amb l'etiqueta de
/// distància a sota.
struct RadiusRingView: View {
    let radiusKm: Double
    let x: CGFloat
    let y: CGFloat
    let cardSize: CGSize

    var body: some View {
        let radiusPx = radiusKm / RadarFrameGeometry.frameWidthKm * cardSize.width
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1))
                .frame(width: radiusPx * 2, height: radiusPx * 2)
                .position(x: x, y: y)
            Text("\(Int(radiusKm)) km")
                .font(.system(size: 8))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .position(x: x, y: y + radiusPx + 8)
        }
    }
}
