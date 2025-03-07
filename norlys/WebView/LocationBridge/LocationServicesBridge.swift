import CoreLocation

protocol LocationServicesBridge: AnyObject {
    func checkPermission() async throws
    func location(options: [String: Any]?) -> CLLocation?
    func startUpdatingLocation(id: Double, options: [String: Any]?) -> AsyncStream<CLLocation>
    func stopUpdatingLocation(id: Double)
} 