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

    /// The site's opening aurora, played natively over the web view until the page has drawn
    var introOverlay: IntroOverlayView?
    
    /// Hosts the web view navigates to itself; must match WKAppBoundDomains in Info.plist
    static let appBoundHosts: Set<String> = ["norlys.live", "www.norlys.live"]

    /// Initial URL to load in the web view
//    var initialURL: URL = URL(string: "http://192.168.1.9:3000")!
    var initialURL: URL = URL(string: "https://norlys.live")!
    
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
        setupIntroOverlay()
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

        // WKWebView only runs service workers for the domains listed under WKAppBoundDomains in
        // Info.plist, and only once navigation is held to them. That is what lets the site's
        // precache serve the app from disk; links elsewhere are handed to Safari instead
        // (see decidePolicyFor in WebViewControllerDelegates)
        configuration.limitsNavigationsToAppBoundDomains = true
        
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
        configuration.userContentController.add(self, name: "introReady")
        
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // A WKWebView paints white until the page's first frame, which shows through as a flash
        // between the launch screen and the site
        view.backgroundColor = .black
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = .black
        }

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
    
    /**
     * Covers the launch with the intro, which the page lifts by posting `introReady` once it has
     * drawn (see WKScriptMessageHandler), or the navigation delegate does if it never does.
     */
    private func setupIntroOverlay() {
        let overlay = IntroOverlayView()
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)
        introOverlay = overlay
    }

    /// Lifts the intro, if it is still up
    func dismissIntro() {
        introOverlay?.dismiss()
        introOverlay = nil
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
