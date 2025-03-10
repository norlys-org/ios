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
    
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Request authorization immediately if not determined
        if locationManager.authorizationStatus == .notDetermined {
            print("Requesting location authorization on init")
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    // MARK: - LocationServicesBridge Implementation
    
    func checkPermission() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            switch locationManager.authorizationStatus {
            case .notDetermined:
                print("Location permission not determined, requesting authorization...")
                // Store the continuation to be resolved when authorization status changes
                self.authorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
                
            case .restricted, .denied:
                print("Location permission denied or restricted")
                continuation.resume(throwing: NSError(domain: "LocationError", code: 1, 
                    userInfo: [NSLocalizedDescriptionKey: "Location permission denied"]))
                
            case .authorizedWhenInUse, .authorizedAlways:
                print("Location permission granted")
                continuation.resume()
                
            @unknown default:
                print("Unknown location authorization status")
                continuation.resume(throwing: NSError(domain: "LocationError", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown authorization status"]))
            }
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
        print("Received location update: \(location.coordinate)")
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
        // Notify all active watch requests of the error
        for continuation in watchContinuations.values {
            continuation.finish()
        }
        watchContinuations.removeAll()
    }
    
    /**
     * Called when location authorization status changes.
     * Starts updating location if authorized.
     */
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("Location authorization status changed to: \(manager.authorizationStatus.rawValue)")
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location permission granted, starting updates")
            locationManager.startUpdatingLocation()
            authorizationContinuation?.resume()
            
        case .denied, .restricted:
            print("Location permission denied or restricted")
            let error = NSError(domain: "LocationError", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Location permission denied"])
            authorizationContinuation?.resume(throwing: error)
            
        case .notDetermined:
            print("Location permission still not determined")
            
        @unknown default:
            print("Unknown location authorization status")
            let error = NSError(domain: "LocationError", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown authorization status"])
            authorizationContinuation?.resume(throwing: error)
        }
        
        authorizationContinuation = nil
    }
} 