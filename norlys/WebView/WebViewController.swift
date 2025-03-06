import UIKit
import WebKit

class WebViewController: UIViewController {
    // MARK: - Properties
    private var webView: WKWebView!
    let loadingView = UIView()
    var initialURL: URL = URL(string: "http://localhost:3000")!
    
    // MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupLoadingView()
        loadWebsite()
        
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        // Inject JavaScript to identify as iOS app
        let script = """
            window.isIOSApp = true;
        """
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(userScript)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if #available(iOS 11.0, *) {
            let topInset = view.safeAreaInsets.top
//            let bottomInset = view.safeAreaInsets.bottom
            let newFrame = CGRect(
                x: 0,
                y: 0,
                width: view.bounds.width,
                height: view.bounds.height
            )
            webView.frame = newFrame
        } else {
            // let statusBarHeight = UIApplication.shared.statusBarFrame.height
            let newFrame = CGRect(
                x: 0,
                y: 0,
                width: view.bounds.width,
                height: view.bounds.height
            )
            webView.frame = newFrame
        }
        
        addVariableBlurToTop()
    }
    
    // MARK: - Setup Methods
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Add message handler
        configuration.userContentController.add(self, name: "nativeApp")
        
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
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

// MARK: - WKScriptMessageHandler
extension WebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let messageBody = message.body as? [String: Any] else { return }
        
        // Example function that does nothing but logs
        if messageBody["action"] as? String == "exampleFunction" {
            print("Example function called from web")
            
            // Send response back to web
            let response = """
                window.dispatchEvent(new CustomEvent('nativeResponse', {
                    detail: {
                        action: 'exampleFunction',
                        status: 'success'
                    }
                }));
            """
            webView.evaluateJavaScript(response, completionHandler: nil)
        }
    }
} 
