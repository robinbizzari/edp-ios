import Foundation
import CoreLocation

/// Position de l'iPhone, une seule fois et à la demande (bus du matin, météo).
/// Elle reste sur le téléphone : EDP ne l'envoie à personne.
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var oneShot: [(Result<CLLocation, Error>) -> Void] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // la ville suffit
    }

    /// Position actuelle, une seule fois.
    func currentPosition(_ done: @escaping (Result<CLLocation, Error>) -> Void) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            done(.failure(BridgeError("Localisation refusée : autorise-la dans Réglages › EDP › Position.")))
        case .notDetermined:
            oneShot.append(done)
            manager.requestWhenInUseAuthorization()   // la position sera demandée une fois la réponse reçue
        default:
            oneShot.append(done)
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined, !oneShot.isEmpty else { return }
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.requestLocation()
        } else {
            failOneShot(BridgeError("Localisation refusée : autorise-la dans Réglages › EDP › Position."))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, !oneShot.isEmpty else { return }
        let waiting = oneShot
        oneShot.removeAll()
        waiting.forEach { $0(.success(location)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        failOneShot(BridgeError("Position introuvable pour le moment. Réessaie dans un instant."))
    }

    private func failOneShot(_ error: Error) {
        let waiting = oneShot
        oneShot.removeAll()
        waiting.forEach { $0(.failure(error)) }
    }
}
