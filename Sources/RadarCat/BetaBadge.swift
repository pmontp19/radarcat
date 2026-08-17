import SwiftUI

/// Etiqueta "BETA": els avisos es basen en una heurística de color de píxel
/// sobre els tiles de radar (vegeu `RainDetector`), no en dades certificades,
/// i encara no s'han validat prou àmpliament per treure-la.
struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}
