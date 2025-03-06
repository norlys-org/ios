import UIKit
import WebKit

class WebViewController: UIViewController {
    // MARK: - Properties
    private var webView: WKWebView!
    let loadingView = UIView()
    var initialURL: URL = URL(string: "https://norlys.live")!
    
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
        
        if #available(iOS 11.0, *) {
            // let topInset = view.safeAreaInsets.top
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
