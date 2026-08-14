import SwiftUI

@main
struct RadarCatApp: App {
    @State private var store = RadarStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(store)
                // Només amplada fixa: `MenuBarContentView.radarStage` es
                // dimensiona ell mateix (amplada x aspecte real del retall,
                // `RadarCompositor.catalunyaCropAspectRatio`), així que
                // l'alçada de la finestra ja no cal fixar-la a mà (ni
                // recalcular-la cada cop que es retoca el retall).
                .frame(width: MenuBarContentView.stageWidth)
        } label: {
            if store.isStale {
                Image(systemName: "cloud.rain.fill")
                    .symbolRenderingMode(.monochrome)
            } else {
                Image(systemName: "cloud.rain.fill")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
