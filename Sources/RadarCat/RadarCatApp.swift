import SwiftUI

@main
struct RadarCatApp: App {
    @State private var store = RadarStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(store)
                // El radar ara inclou les Terres de l'Ebre (RadarCompositor),
                // que fa la imatge notablement més "alta" (~0.78:1 en comptes
                // de ~1.19:1) - alçada augmentada perquè l'escenari no quedi
                // amb bandes buides als costats (scaledToFit encaixant per
                // amplada en comptes d'alçada).
                .frame(width: 380, height: 620)
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
