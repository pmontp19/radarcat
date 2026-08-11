import SwiftUI

@main
struct RadarCatApp: App {
    @State private var store = RadarStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(store)
                .frame(width: 380, height: 460)
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
