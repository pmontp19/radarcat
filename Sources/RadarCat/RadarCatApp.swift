import SwiftUI

@main
struct RadarCatApp: App {
    @State private var store = RadarStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(store)
                // Només amplada fixa: l'alçada la determina el contingut,
                // no aquesta finestra. La targeta del mapa es dimensiona
                // explícitament dins `RadarStageView` (vegeu el comentari
                // allà sobre per què cal fer-ho a mà), així que aquí no cal
                // fixar ni recalcular cap alçada cada cop que es retoca el
                // retall.
                .frame(width: MenuBarContentView.stageWidth)
        } label: {
            // Tres estats, sense que el de pluja trepitgi el d'obsolet:
            // dades obsoletes primer (poc fiable, no val la pena destacar
            // pluja sobre dades velles), després plou-ara-mateix, i
            // finalment el normal jeràrquic de sempre. Amb els avisos de
            // pluja desactivats (opt-in, vegeu `AlertPreferences`) mai hi ha
            // ubicació ni, per tant, lectura de "plou aquí": la icona només
            // alterna entre normal i obsolet - es comprova
            // `AlertPreferences.shared.alertsEnabled` explícitament aquí en
            // lloc de confiar només que `isRainingHere` acabi sent `false`
            // per manca de coordenades.
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
            //
            // Pel mateix motiu, l'estat "obsolet" NO es pot distingir del
            // normal amb `.monochrome` vs `.hierarchical` sobre el mateix
            // glif `cloud.rain.fill` (com es feia abans d'aquest redisseny):
            // en "template mode" totes dues renderitzen idèntiques, deixant
            // l'estat obsolet invisible. Calia, doncs, un tercer glif amb
            // una silueta pròpia. Es tria "exclamationmark.icloud.fill" en
            // lloc de "cloud.rain" (contorn sense omplir) o
            // "cloud.slash.fill": el contorn sense omplir es confon amb la
            // seva pròpia versió omplerta a 16pt (la diferència és massa
            // subtil per llegir-se d'un cop d'ull), i "cloud.slash.fill"
            // suggereix "sense pluja/sense núvols" (un missatge fals: no és
            // que no plogui, és que no ens en refiem perquè les dades són
            // velles). L'exclamació dins d'un núvol, en canvi, aporta una
            // forma interior d'alt contrast que es manté llegible reduïda a
            // silueta i comunica "alguna cosa no rutlla amb aquesta dada",
            // que és exactament el que vol dir "obsolet".
            if store.isStale {
                Image(systemName: "exclamationmark.icloud.fill")
                    .accessibilityLabel("Dades del radar obsoletes")
            } else if AlertPreferences.shared.alertsEnabled && store.isRainingHere {
                Image(systemName: "umbrella.fill")
                    .accessibilityLabel("Plou a la teva ubicació")
            } else {
                Image(systemName: "cloud.rain.fill")
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityLabel("Radar de pluja de Catalunya")
            }
        }
        .menuBarExtraStyle(.window)

        // Escena nativa d'Ajustos: NOMÉS defineix la finestra (contingut,
        // mida, ⌘W per tancar-la) - no la fa abastable per si sola. En una
        // app `LSUIElement` amb només `MenuBarExtra` no hi ha barra de menú
        // principal que reculli `⌘,` globalment (limitació coneguda
        // d'AppKit/SwiftUI, FB10184971), així que qui obre aquesta finestra
        // de veritat és el `SettingsLink` que la unitat de la vista posa al
        // menú "⋯" del popover; `⌘,` només funciona mentre el popover té el
        // focus (la vista li posa `.keyboardShortcut(",")`), no com a
        // drecera global de l'app.
        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
