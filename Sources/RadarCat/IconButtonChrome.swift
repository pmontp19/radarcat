import SwiftUI

/// Aparença compartida dels botons quadrats d'icona del popover: el "⋯" de
/// `MoreActionsMenu` i el play/pausa de `TimelineView` són, segons l'spec,
/// el mateix element visual (22x22pt, cantonada 5pt, farciment que es marca
/// una mica en hover) - abans hi havia dues còpies literals d'aquestes
/// mides, un lloc únic evita que es desincronitzin si es retoquen.
private struct IconButtonChrome: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .frame(width: 22, height: 22)
            .background(
                Color.primary.opacity(isHovering ? 0.10 : 0.06),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .onHover { isHovering = $0 }
    }
}

extension View {
    func iconButtonChrome() -> some View { modifier(IconButtonChrome()) }
}
