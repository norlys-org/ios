//
//  WebViewController.swift
//  norlys
//
//  Created by Hugo Lageneste on 06/03/2025.
//

import UIKit
import WebKit

class WebViewController: UIViewController {
    
    // MARK: - Properties
    
    // The web view component that displays web content
    private var webView: WKWebView!
    
    // Spinning wheel that shows during page loading
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    // URL that will load when the app starts
    var initialURL: URL = URL(string: "https://norlys.live")!
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupActivityIndicator()
        loadWebsite()
        
        // Hides the top navigation bar completely
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Calculate frame that respects top safe area but extends to bottom edge
        if #available(iOS 11.0, *) {
            let topInset = view.safeAreaInsets.top
            let newFrame = CGRect(
                x: 0,
                y: topInset,
                width: view.bounds.width,
                height: view.bounds.height - topInset
            )
            webView.frame = newFrame
        } else {
            // Fallback for older iOS versions
            let statusBarHeight = UIApplication.shared.statusBarFrame.height
            let newFrame = CGRect(
                x: 0,
                y: statusBarHeight,
                width: view.bounds.width,
                height: view.bounds.height - statusBarHeight
            )
            webView.frame = newFrame
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupWebView() {
        // Create configuration for the web view
        let configuration = WKWebViewConfiguration()
        // Enable JavaScript support - required for modern websites and PWAs
        configuration.preferences.javaScriptEnabled = true
        // Enable service workers for PWA support
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Create the web view and set this class as its delegate
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // Set appropriate content insets to fix bottom content being hidden
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        view.addSubview(webView)
    }
    
    private func setupActivityIndicator() {
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        
        // Center the activity indicator in the middle of the screen
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - WebView Actions
    
    private func loadWebsite() {
        let request = URLRequest(url: initialURL)
        webView.load(request)
    }
    
    // Shows error messages to the user when page loading fails
    // The error typically comes from network issues or website problems
    private func showError(message: String) {
        let alertController = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        
        // The retry button reloads the page when tapped
        alertController.addAction(UIAlertAction(title: "Retry", style: .default, handler: { [weak self] _ in
            self?.webView.reload()
        }))
        present(alertController, animated: true)
    }
}

// MARK: - WKNavigationDelegate
// Handles web page loading events and errors

extension WebViewController: WKNavigationDelegate {
    
    // Called when a page starts loading - shows the spinner
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityIndicator.startAnimating()
    }
    
    // Called when a page finishes loading - hides the spinner
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }
    
    // Called when page loading fails - this is where errors come from
    // The error parameter contains details about what went wrong
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        
        // Check if the error is related to network connectivity
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain &&
           (nsError.code == NSURLErrorNotConnectedToInternet ||
            nsError.code == NSURLErrorNetworkConnectionLost) {
            showError(message: "No internet connection. Please check your network settings and try again.")
        } else {
            showError(message: "Failed to load page: \(error.localizedDescription)")
        }
    }
}

// MARK: - WKUIDelegate
// Handles JavaScript dialogs from the website (alerts, confirms, prompts)

extension WebViewController: WKUIDelegate {
    
    // Displays confirmation dialogs when the website uses JavaScript confirm()
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completionHandler(false)
        }))
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completionHandler(true)
        }))
        present(alertController, animated: true)
    }
    
}
