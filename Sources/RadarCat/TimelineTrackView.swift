import SwiftUI

/// Pista de marques de la cronologia (una per frame) + les etiquetes dels
/// seus extrems ("−54 min"/"Ara"). Extret de `TimelineView` perquè aquell
/// fitxer no passi de les ~150 línies i perquè el scrub (que és tota la
/// lògica no trivial d'aquesta peça) quedi aïllat en un sol lloc.
struct TimelineTrackView: View {
    let animator: RadarAnimator

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(animator.frames.indices, id: \.self) { i in
                        tickMark(index: i, current: animator.currentIndex)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    // `minimumDistance: 0` fa que un simple clic ja compti
                    // com a "arrossegament" d'amplitud zero: així una sola
                    // gesture cobreix "clicables i arrossegables" sense
                    // necessitar un `Slider`.
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in scrub(to: value.location.x, width: geo.size.width) }
                )
            }
            .frame(height: 15)
            HStack {
                Text(earliestLabel)
                Spacer()
                Text("Ara")
            }
            .font(.system(size: 8.5))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tickMark(index: Int, current: Int) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(index == current ? Color.accentColor : Color.primary.opacity(index < current ? 0.30 : 0.16))
            .frame(width: 2, height: index == current ? 15 : 8)
    }

    private func scrub(to x: CGFloat, width: CGFloat) {
        guard !animator.frames.isEmpty, width > 0 else { return }
        let clampedX = min(max(x, 0), width)
        let index = min(animator.frames.count - 1, Int(clampedX / width * CGFloat(animator.frames.count)))
        animator.seek(to: index)
        animator.pause()
    }

    /// Etiqueta de l'extrem esquerre ("−54 min"): la diferència real entre
    /// el primer i l'últim frame, no `cadència × (nombre de frames − 1)` -
    /// cap constant de cadència a mantenir sincronitzada amb
    /// `RadarAnimator`/`RadarStore`. Si mai canvia la cadència real, aquesta
    /// etiqueta ja la reflecteix sola.
    private var earliestLabel: String {
        guard let first = animator.frames.first?.timestamp,
              let last = animator.frames.last?.timestamp
        else { return "" }
        let minutes = max(0, Int(last.timeIntervalSince(first) / 60))
        return "−\(minutes) min"
    }
}
