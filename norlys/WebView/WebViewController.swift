import UIKit
import WebKit
import CoreLocation
import AVFoundation
import UserNotifications

/**
 * WebViewController
 *
 * Main view controller that handles the web view functionality of the app.
 * It manages the WKWebView, handles JavaScript bridge communication, and provides
 * native functionality to the web app through various bridges (console, location).
 */
class WebViewController: UIViewController {
    // MARK: - Properties
    
    /// The main web view that displays web content
    var webView: WKWebView!
    
    /// Loading view displayed while web content is being loaded
    let loadingView = UIView()
    
    /// Initial URL to load in the web view
    var initialURL: URL = URL(string: "http://192.168.1.9:3000")!
//    var initialURL: URL = URL(string: "https://ny.norlys.live")!
    
    /// Bridge for handling location services
    private let locationBridge: LocationServicesBridge
    
    /// Handler for location-related JavaScript messages
    private var locationHandler: LocationScriptMessageHandler?
    
    // MARK: - Initialization
    
    init() {
        self.locationBridge = LocationBridgeImpl()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        self.locationBridge = LocationBridgeImpl()
        super.init(coder: coder)
    }
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupLoadingView()
        loadWebsite()
        
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
    }
    
    // MARK: - Setup Methods
    
    /**
     * Sets up the WKWebView with required configuration and JavaScript bridges.
     * Initializes console and location bridges for communication between web and native.
     */
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            configuration.preferences.javaScriptEnabled = true
        }
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        let isIOSFlagJS = "window.isIOSApp = true;"
        let isIOSFlagScript = WKUserScript(
            source: isIOSFlagJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(isIOSFlagScript)
        
        // Load JavaScript bridge files from bundle
        if let consoleBridgePath = Bundle.main.path(forResource: "console-bridge", ofType: "js"),
           let consoleBridgeScript = try? String(contentsOfFile: consoleBridgePath, encoding: .utf8),
           let geolocationBridgePath = Bundle.main.path(forResource: "geolocation-bridge", ofType: "js"),
           let geolocationBridgeScript = try? String(contentsOfFile: geolocationBridgePath, encoding: .utf8) {
            
            let consoleScript = WKUserScript(source: consoleBridgeScript,
                                           injectionTime: .atDocumentStart,
                                           forMainFrameOnly: false)
            
            let geolocationScript = WKUserScript(source: geolocationBridgeScript,
                                               injectionTime: .atDocumentStart,
                                               forMainFrameOnly: true)
            
            configuration.userContentController.addUserScript(consoleScript)
            configuration.userContentController.addUserScript(geolocationScript)
            print("Console bridge loaded successfully")
        } else {
            print("Failed to load JavaScript bridge files from bundle")
        }
        
        configuration.userContentController.add(self, name: "console")
        configuration.userContentController.add(self, name: "requestPush")
        
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        // Setup location handler
        locationHandler = LocationScriptMessageHandler(locationBridge: locationBridge, webView: webView)
        configuration.userContentController.add(locationHandler!, name: "location")
        
        view.addSubview(webView)

        // save reference for AppDelegate to send token back
        PushBridge.shared.webView = webView
    }
    
    /**
     * Sets up the loading view that is displayed while web content is being loaded.
     */
    private func setupLoadingView() {
        loadingView.backgroundColor = .black
        loadingView.frame = view.bounds
        loadingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(loadingView)
        view.bringSubviewToFront(loadingView)
    }
    
    // MARK: - WebView Actions
    
    /**
     * Loads the initial website in the web view.
     */
    private func loadWebsite() {
        let request = URLRequest(url: initialURL)
        webView.load(request)
    }
    
    /**
     * Displays an error alert with an option to retry loading the page.
     * - Parameter message: The error message to display
     */
    func showError(message: String) {
        let alertController = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        alertController.addAction(UIAlertAction(title: "Retry", style: .default, handler: { [weak self] _ in
            self?.webView.reload()
        }))
        present(alertController, animated: true)
    }
}

// MARK: - Push Bridge holder
final class PushBridge {
    static let shared = PushBridge()
    weak var webView: WKWebView?
}
