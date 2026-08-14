import Foundation
import UserNotifications

/// Notificació nativa quan comença a ploure a la ubicació de l'usuari.
///
/// Comprovat empíricament aquesta sessió: amb signatura ad-hoc (el mode
/// `SIGNING_MODE=adhoc` que fa servir `Scripts/compile_and_run.sh` per
/// iterar), `requestAuthorization` sempre falla amb "Notifications are not
/// allowed for this application" (UNErrorDomain codi 1) - independentment
/// de si l'app es llança via `open` (LaunchServices) o com a binari solt.
/// No té a veure amb LSUIElement ni amb el mètode de llançament: macOS
/// exigeix una identitat de signatura estable (Developer ID, no ad-hoc "-")
/// perquè `UserNotifications` autoritzi una app. Amb una signatura real
/// (`APP_IDENTITY` a `package_app.sh`) hauria de funcionar sense canvis
/// aquí. Verificar-ho en dev requereix, doncs, un build signat de veritat.
enum RainNotifier {
    /// Només s'ha de cridar des del flux d'activació explícita de l'usuari
    /// (`RadarStore.enableAlerts()`, en activar "Avisos de pluja" (BETA) als
    /// Ajustos) - mai en arrencar l'app. Els avisos són opt-in: macOS no ha
    /// de mostrar el diàleg de notificacions abans que l'usuari els demani.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyRainStarted() {
        let content = UNMutableNotificationContent()
        content.title = "Plou a la teva ubicació"
        content.body = "El radar detecta pluja ara mateix on ets."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "rain-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
