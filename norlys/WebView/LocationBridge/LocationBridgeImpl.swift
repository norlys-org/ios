import CoreLocation

/**
 * LocationBridgeImpl
 * 
 * Implementation of the LocationServicesBridge protocol that provides location services
 * using iOS CoreLocation framework. This class manages the location manager and handles
 * the communication between the web geolocation API and native location services.
 */
class LocationBridgeImpl: NSObject, LocationServicesBridge {
    /// The Core Location manager used to access device location services
    private let locationManager: CLLocationManager
    
    /// Stores the most recent location update
    private var lastLocation: CLLocation?
    
    /// Dictionary of active location watch requests and their continuations
    private var watchContinuations: [Double: AsyncStream<CLLocation>.Continuation] = [:]
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // MARK: - LocationServicesBridge Implementation
    
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

// MARK: - CLLocationManagerDelegate

extension LocationBridgeImpl: CLLocationManagerDelegate {
    /**
     * Called when new location data is available.
     * Updates the last known location and notifies all active watch requests.
     */
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        
        for continuation in watchContinuations.values {
            continuation.yield(location)
        }
    }
    
    /**
     * Called when a location error occurs.
     * Logs the error for debugging purposes.
     */
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Error: \(error.localizedDescription)")
    }
    
    /**
     * Called when location authorization status changes.
     * Starts updating location if authorized.
     */
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }
} 