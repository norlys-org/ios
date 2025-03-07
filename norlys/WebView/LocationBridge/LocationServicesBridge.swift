import CoreLocation

/**
 * LocationServicesBridge Protocol
 * 
 * Defines the interface for bridging location services between the web app and native iOS.
 * This protocol abstracts the location functionality to allow for different implementations
 * and easier testing.
 */
protocol LocationServicesBridge: AnyObject {
    /**
     * Checks and requests location permission from the user if needed.
     * Throws an error if permission is denied.
     */
    func checkPermission() async throws
    
    /**
     * Returns the last known location if available.
     * - Parameter options: Optional configuration options from the web geolocation API
     * - Returns: The last known location or nil if not available
     */
    func location(options: [String: Any]?) -> CLLocation?
    
    /**
     * Starts updating location and provides an async stream of location updates.
     * - Parameters:
     *   - id: Unique identifier for the location watch request
     *   - options: Optional configuration options from the web geolocation API
     * - Returns: An async stream of location updates
     */
    func startUpdatingLocation(id: Double, options: [String: Any]?) -> AsyncStream<CLLocation>
    
    /**
     * Stops updating location for the specified watch request.
     * - Parameter id: The identifier of the watch request to stop
     */
    func stopUpdatingLocation(id: Double)
} 