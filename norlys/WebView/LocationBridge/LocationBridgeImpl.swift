import CoreLocation

class LocationBridgeImpl: NSObject, LocationServicesBridge {
    private let locationManager: CLLocationManager
    private var lastLocation: CLLocation?
    private var watchContinuations: [Double: AsyncStream<CLLocation>.Continuation] = [:]
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func checkPermission() async throws {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            throw NSError(domain: "LocationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location permission denied"])
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }
    }
    
    func location(options: [String: Any]?) -> CLLocation? {
        return lastLocation
    }
    
    func startUpdatingLocation(id: Double, options: [String: Any]?) -> AsyncStream<CLLocation> {
        return AsyncStream { continuation in
            watchContinuations[id] = continuation
            locationManager.startUpdatingLocation()
            
            continuation.onTermination = { [weak self] _ in
                self?.stopUpdatingLocation(id: id)
            }
        }
    }
    
    func stopUpdatingLocation(id: Double) {
        watchContinuations.removeValue(forKey: id)
        if watchContinuations.isEmpty {
            locationManager.stopUpdatingLocation()
        }
    }
}

extension LocationBridgeImpl: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        
        for continuation in watchContinuations.values {
            continuation.yield(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }
} 