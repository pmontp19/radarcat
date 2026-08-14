import Foundation
import CoreLocation
import Observation

/// Gestiona la localització de l'usuari (When-In-Use) per al punt al mapa i
/// l'alerta de pluja. Inert en crear-se a propòsit: no demana permís ni
/// engega actualitzacions fins que algú crida `requestPermissionAndStart()`
/// explícitament - els avisos de pluja són opt-in (vegeu `AlertPreferences`)
/// i macOS no ha de preguntar per la ubicació abans que l'usuari els activi.
/// Si es denega o l'ubicació no arriba mai, `coordinate` es queda a `nil`
/// per sempre i tant el punt com l'alerta simplement no s'activen - sense
/// cap altre efecte advers.
@MainActor
@Observable
final class LocationProvider: NSObject {
    private(set) var coordinate: CLLocationCoordinate2D?

    /// Cridada cada cop que `coordinate` s'actualitza de veritat (mai a
    /// `stop()`, que el buida). Necessari perquè `CLLocationManager` no dona
    /// mai una posició de manera síncrona: en activar els avisos,
    /// `coordinate` és `nil` just després de `requestPermissionAndStart()`,
    /// i sense aquest avís `RadarStore` no sabria quan ha arribat el primer
    /// fix per recalcular severitat/municipi a l'instant - es quedaria
    /// esperant el pròxim cicle de refresc (fins a 6 min) tot i que el punt
    /// ja apareix al mapa (Observation sí que el propaga).
    var onCoordinateChange: ((CLLocationCoordinate2D) -> Void)?

    /// `true` si l'usuari ha denegat (o té restringit) el permís d'ubicació.
    /// Es calcula ja a l'`init` (llegir `authorizationStatus` és passiu, no
    /// dispara cap diàleg) perquè els Ajustos puguin oferir un botó cap a
    /// Configuració del Sistema encara que l'usuari no hagi tornat a activar
    /// els avisos aquesta sessió.
    private(set) var authorizationDenied = false

    private let manager = CLLocationManager()
    /// `true` un cop s'ha demanat l'activació explícita: sense això,
    /// `locationManagerDidChangeAuthorization` (que CoreLocation pot cridar
    /// pel seu compte, p.ex. en arrencar amb un permís ja concedit d'una
    /// sessió anterior) no ha d'engegar actualitzacions soles.
    private var started = false

    override init() {
        super.init()
        manager.delegate = self
        // A escala de tot Catalunya no cal precisió de metres, només
        // situar el punt raonablement dins el mapa.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        updateAuthorizationDenied()
    }

    /// Únic punt d'entrada del flux d'activació (`RadarStore.enableAlerts`,
    /// via `AlertPreferences.onEnabledChange`): demana permís si cal i
    /// comença a actualitzar la posició. Cridar-ho de nou (p.ex. permís ja
    /// concedit) és inofensiu.
    func requestPermissionAndStart() {
        started = true
        manager.requestWhenInUseAuthorization()
        startIfAuthorized()
    }

    /// Contrari d'activar: para les actualitzacions i buida `coordinate`
    /// perquè la vista deixi de mostrar el punt (el permís de sistema no
    /// es toca - això és cosa de l'usuari a Configuració del Sistema).
    func stop() {
        started = false
        manager.stopUpdatingLocation()
        coordinate = nil
    }

    private func startIfAuthorized() {
        updateAuthorizationDenied()
        guard started else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    private func updateAuthorizationDenied() {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            authorizationDenied = true
        default:
            authorizationDenied = false
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    // Els mètodes del delegate els pot cridar CoreLocation des de qualsevol
    // fil: es marquen `nonisolated` i es salta a MainActor per tocar l'estat
    // observable, en lloc de confiar que el delegate quedi aïllat sol.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.startIfAuthorized() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Simètric al guard `started` de `startIfAuthorized()`: sense això,
        // una actualització que ja estava en vol quan es crida `stop()`
        // arriba igualment aquí i torna a omplir `coordinate` just després
        // d'haver-lo buidat, fent reaparèixer el punt amb els avisos
        // desactivats.
        Task { @MainActor in
            guard self.started else { return }
            self.coordinate = loc.coordinate
            self.onCoordinateChange?(loc.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silenciós: sense senyal o permís denegat, simplement no hi ha punt.
    }
}
