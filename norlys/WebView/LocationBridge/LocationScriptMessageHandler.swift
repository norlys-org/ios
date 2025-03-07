import WebKit
import CoreLocation

/**
 * LocationScriptMessageHandler
 * 
 * Handles JavaScript messages from the web app related to geolocation services.
 * This class acts as a bridge between the web geolocation API and native location services,
 * translating web API calls into native location requests and sending results back to the web app.
 */
class LocationScriptMessageHandler: NSObject, WKScriptMessageHandler {
    /// The bridge to native location services
    private let locationBridge: LocationServicesBridge
    
    /// Reference to the web view for sending JavaScript messages
    private weak var webView: WKWebView?
    
    init(locationBridge: LocationServicesBridge, webView: WKWebView) {
        self.locationBridge = locationBridge
        self.webView = webView
        super.init()
    }
    
    /**
     * Handles incoming JavaScript messages from the web app.
     * Processes different geolocation actions: getCurrentPosition, watchPosition, and clearWatch.
     */
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        
        switch action {
        case "getCurrentPosition":
            handleGetCurrentPosition(body)
        case "watchPosition":
            handleWatchPosition(body)
        case "clearWatch":
            if let watchId = body["watchId"] as? Double {
                locationBridge.stopUpdatingLocation(id: watchId)
            }
        default:
            break
        }
    }
    
    /**
     * Handles getCurrentPosition requests from the web app.
     * Attempts to return the last known location or starts location updates to get a new position.
     */
    private func handleGetCurrentPosition(_ body: [String: Any]) {
        Task {
            do {
                try await locationBridge.checkPermission()
                if let location = locationBridge.location(options: body["options"] as? [String: Any]) {
                    sendLocationUpdate(location: location, callbackId: body["callbackId"] as? String)
                } else {
                    let stream = locationBridge.startUpdatingLocation(id: -1, options: body["options"] as? [String: Any])
                    for await location in stream {
                        sendLocationUpdate(location: location, callbackId: body["callbackId"] as? String)
                        break
                    }
                }
            } catch {
                sendError(error: error, callbackId: body["callbackId"] as? String)
            }
        }
    }
    
    /**
     * Handles watchPosition requests from the web app.
     * Starts continuous location updates and sends them back to the web app.
     */
    private func handleWatchPosition(_ body: [String: Any]) {
        guard let watchId = body["watchId"] as? Double else { return }
        
        Task {
            do {
                try await locationBridge.checkPermission()
                let stream = locationBridge.startUpdatingLocation(id: watchId, options: body["options"] as? [String: Any])
                for await location in stream {
                    sendLocationUpdate(location: location, watchId: watchId)
                }
            } catch {
                sendError(error: error, watchId: watchId)
            }
        }
    }
    
    /**
     * Sends a location update back to the web app through JavaScript.
     * - Parameters:
     *   - location: The location to send
     *   - callbackId: Optional ID for getCurrentPosition callbacks
     *   - watchId: Optional ID for watchPosition callbacks
     */
    private func sendLocationUpdate(location: CLLocation, callbackId: String? = nil, watchId: Double? = nil) {
        let script = """
            (function() {
                var position = {
                    coords: {
                        latitude: \(location.coordinate.latitude),
                        longitude: \(location.coordinate.longitude),
                        accuracy: \(location.horizontalAccuracy),
                        altitude: \(location.altitude),
                        altitudeAccuracy: \(location.verticalAccuracy),
                        heading: \(location.course),
                        speed: \(location.speed)
                    },
                    timestamp: \(location.timestamp.timeIntervalSince1970 * 1000)
                };
                \(callbackId != nil ? "window._geolocationCallbacks['\(callbackId!)'].success(position);" : "")
                \(watchId != nil ? "window._geolocationWatchers['\(watchId!)'].success(position);" : "")
            })();
        """
        
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    /**
     * Sends an error back to the web app through JavaScript.
     * - Parameters:
     *   - error: The error to send
     *   - callbackId: Optional ID for getCurrentPosition callbacks
     *   - watchId: Optional ID for watchPosition callbacks
     */
    private func sendError(error: Error, callbackId: String? = nil, watchId: Double? = nil) {
        let script = """
            (function() {
                var error = {
                    code: 1,
                    message: "\(error.localizedDescription)"
                };
                \(callbackId != nil ? "window._geolocationCallbacks['\(callbackId!)'].error(error);" : "")
                \(watchId != nil ? "window._geolocationWatchers['\(watchId!)'].error(error);" : "")
            })();
        """
        
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
} 