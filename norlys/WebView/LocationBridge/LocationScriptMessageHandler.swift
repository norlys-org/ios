import WebKit
import CoreLocation

class LocationScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private let locationBridge: LocationServicesBridge
    private weak var webView: WKWebView?
    
    init(locationBridge: LocationServicesBridge, webView: WKWebView) {
        self.locationBridge = locationBridge
        self.webView = webView
        super.init()
    }
    
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