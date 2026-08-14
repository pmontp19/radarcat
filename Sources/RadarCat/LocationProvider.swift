import Foundation
import CoreLocation
import Observation

/// Gestiona la localització de l'usuari (When-In-Use) per al punt al mapa i
/// l'alerta de pluja. Demana permís en crear-se; si es denega o l'ubicació
/// no arriba mai, `coordinate` es queda a `nil` per sempre i tant el punt
/// com l'alerta simplement no s'activen - sense cap altre efecte advers.
@MainActor
@Observable
final class LocationProvider: NSObject {
    private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // A escala de tot Catalunya no cal precisió de metres, només
        // situar el punt raonablement dins el mapa.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
        startIfAuthorized()
    }

    private func startIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
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
        Task { @MainActor in self.coordinate = loc.coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silenciós: sense senyal o permís denegat, simplement no hi ha punt.
    }
}
