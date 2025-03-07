import UIKit
import WebKit
import CoreLocation

class WebViewController: UIViewController {
    // MARK: - Properties
    var webView: WKWebView!
    let loadingView = UIView()
    var initialURL: URL = URL(string: "http://10.0.0.27:3001")!
    private let locationBridge: LocationServicesBridge
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
        addVariableBlurToTop()
    }
    
    // MARK: - Setup Methods
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Add console.log bridge
        let consoleScript = WKUserScript(source: """
            function captureLog(type, args) {
                window.webkit.messageHandlers.console.postMessage({
                    type: type,
                    message: Array.from(args).map(arg => {
                        try {
                            return typeof arg === 'object' ? JSON.stringify(arg) : String(arg);
                        } catch (e) {
                            return String(arg);
                        }
                    })
                });
            }
            
            console._log = console.log;
            console._error = console.error;
            console._warn = console.warn;
            console._info = console.info;
            
            console.log = function() { captureLog('log', arguments); console._log.apply(console, arguments); }
            console.error = function() { captureLog('error', arguments); console._error.apply(console, arguments); }
            console.warn = function() { captureLog('warn', arguments); console._warn.apply(console, arguments); }
            console.info = function() { captureLog('info', arguments); console._info.apply(console, arguments); }
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        
        // Add geolocation bridge
        let geolocationScript = WKUserScript(source: """
            (function() {
                window._geolocationCallbacks = {};
                window._geolocationWatchers = {};
                let watchId = 0;
                
                navigator.geolocation.getCurrentPosition = function(success, error, options) {
                    const callbackId = Date.now().toString();
                    window._geolocationCallbacks[callbackId] = { success, error };
                    window.webkit.messageHandlers.location.postMessage({
                        action: 'getCurrentPosition',
                        callbackId: callbackId,
                        options: options
                    });
                };
                
                navigator.geolocation.watchPosition = function(success, error, options) {
                    watchId++;
                    window._geolocationWatchers[watchId] = { success, error };
                    window.webkit.messageHandlers.location.postMessage({
                        action: 'watchPosition',
                        watchId: watchId,
                        options: options
                    });
                    return watchId;
                };
                
                navigator.geolocation.clearWatch = function(id) {
                    delete window._geolocationWatchers[id];
                    window.webkit.messageHandlers.location.postMessage({
                        action: 'clearWatch',
                        watchId: id
                    });
                };
            })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        
        configuration.userContentController.addUserScript(consoleScript)
        configuration.userContentController.addUserScript(geolocationScript)
        configuration.userContentController.add(self, name: "console")
        
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        // Setup location handler
        locationHandler = LocationScriptMessageHandler(locationBridge: locationBridge, webView: webView)
        configuration.userContentController.add(locationHandler!, name: "location")
        
        view.addSubview(webView)
    }
    
    private func setupLoadingView() {
        loadingView.backgroundColor = .black
        loadingView.frame = view.bounds
        loadingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(loadingView)
        view.bringSubviewToFront(loadingView)
    }
    
    // MARK: - WebView Actions
    private func loadWebsite() {
        let request = URLRequest(url: initialURL)
        webView.load(request)
    }
    
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
