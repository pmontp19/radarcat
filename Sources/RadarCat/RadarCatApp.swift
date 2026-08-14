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
            // Tres estats, sense que el de pluja trepitgi el d'obsolet:
            // dades obsoletes primer (poc fiable, no val la pena destacar
            // pluja sobre dades velles), després plou-ara-mateix, i
            // finalment el normal jeràrquic de sempre.
            //
            // La distinció de "plou" es fa canviant de glif (cloud.rain.fill
            // -> umbrella.fill) i no de color/tint: comprovat empíricament
            // aquesta mateixa sessió que `MenuBarExtra` força l'ítem de la
            // barra de menú a renderitzar-se com a "template" (silueta d'un
            // sol to) sigui quin sigui el `symbolRenderingMode`
            // (.multicolor inclòs) o fins i tot `.renderingMode(.original)`
            // amb formes/colors propis (un `Circle().fill(.red)` tampoc hi
            // sortia vermell) - AppKit ignora el color real de la imatge en
            // aquest context. Un glif diferent, en canvi, sí es veu prou
            // clar a mida d'icona de barra de menú.
            if store.isStale {
                Image(systemName: "cloud.rain.fill")
                    .symbolRenderingMode(.monochrome)
            } else if store.isRainingHere {
                Image(systemName: "umbrella.fill")
            } else {
                Image(systemName: "cloud.rain.fill")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
