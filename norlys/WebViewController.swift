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
    
    private var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var progressObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    
    // Configuration
    var initialURL: URL = URL(string: "https://norlys.live")!
    
    // UI Elements
    private lazy var refreshControl = UIRefreshControl()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupProgressView()
        setupRefreshControl()
        setupActivityIndicator()
        setupNavigationItems()
        loadWebsite()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
    }
    
    deinit {
        // Clean up KVO observers
        progressObserver?.invalidate()
        urlObserver?.invalidate()
    }
    
    // MARK: - Setup Methods
    
    private func setupWebView() {
        // Configure WKWebView
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.allowsInlineMediaPlayback = true
        
        // Create WKWebView
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)
        
        // Set up observers
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe loading progress
        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.updateProgress(value: Float(webView.estimatedProgress))
        }
        
        // Observe URL changes
        urlObserver = webView.observe(\.url, options: [.new]) { [weak self] _, change in
            if let url = change.newValue {
                self?.title = url?.host
            }
        }
    }
    
    private func setupProgressView() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        progressView.progress = 0.0
        progressView.alpha = 0.0
    }
    
    private func setupRefreshControl() {
        refreshControl.addTarget(self, action: #selector(refreshWebView(_:)), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)
    }
    
    private func setupActivityIndicator() {
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupNavigationItems() {
        // Back and forward buttons
        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(goBack))
        let forwardButton = UIBarButtonItem(image: UIImage(systemName: "chevron.forward"), style: .plain, target: self, action: #selector(goForward))
        let refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshPage))
        let homeButton = UIBarButtonItem(image: UIImage(systemName: "house"), style: .plain, target: self, action: #selector(goHome))
        
        navigationItem.leftBarButtonItems = [backButton, forwardButton]
        navigationItem.rightBarButtonItems = [refreshButton, homeButton]
        
        // Update state
        updateNavigationButtons()
    }
    
    // MARK: - WebView Actions
    
    private func loadWebsite() {
        let request = URLRequest(url: initialURL, cachePolicy: .returnCacheDataElseLoad)
        webView.load(request)
    }
    
    @objc private func refreshWebView(_ sender: UIRefreshControl) {
        webView.reload()
    }
    
    @objc private func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    @objc private func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    @objc private func refreshPage() {
        webView.reload()
    }
    
    @objc private func goHome() {
        let request = URLRequest(url: initialURL)
        webView.load(request)
    }
    
    // MARK: - Helper Methods
    
    private func updateProgress(value: Float) {
        progressView.progress = value
        
        if value >= 1.0 {
            UIView.animate(withDuration: 0.3, delay: 0.3, options: .curveEaseOut, animations: {
                self.progressView.alpha = 0.0
            }, completion: { _ in
                self.progressView.setProgress(0.0, animated: false)
            })
        } else if progressView.alpha == 0.0 {
            UIView.animate(withDuration: 0.3, options: .curveEaseIn, animations: {
                self.progressView.alpha = 1.0
            })
        }
    }
    
    private func updateNavigationButtons() {
        navigationItem.leftBarButtonItems?[0].isEnabled = webView.canGoBack
        navigationItem.leftBarButtonItems?[1].isEnabled = webView.canGoForward
    }
    
    private func showError(message: String) {
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

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityIndicator.startAnimating()
        updateNavigationButtons()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        title = webView.title ?? webView.url?.host
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
        updateNavigationButtons()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
        showError(message: "Failed to load page: \(error.localizedDescription)")
        updateNavigationButtons()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
        
        // Check for network connection issues
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain &&
           (nsError.code == NSURLErrorNotConnectedToInternet ||
            nsError.code == NSURLErrorNetworkConnectionLost) {
            showError(message: "No internet connection. Please check your network settings and try again.")
        } else {
            showError(message: "Failed to load page: \(error.localizedDescription)")
        }
        
        updateNavigationButtons()
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow most navigation within the app
        if let url = navigationAction.request.url {
            // Only handle external links that use schemes we can't handle
            if navigationAction.targetFrame == nil,
               let scheme = url.scheme?.lowercased(),
               !["http", "https", "file", "about"].contains(scheme) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
        }
        
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension WebViewController: WKUIDelegate {
    
    // Handle JavaScript alerts
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alertController = UIAlertController(title: webView.title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completionHandler()
        }))
        present(alertController, animated: true)
    }
    
    // Handle JavaScript confirm dialogs
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alertController = UIAlertController(title: webView.title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completionHandler(false)
        }))
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completionHandler(true)
        }))
        present(alertController, animated: true)
    }
    
    // Handle JavaScript text input dialogs
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alertController = UIAlertController(title: webView.title, message: prompt, preferredStyle: .alert)
        
        alertController.addTextField { textField in
            textField.text = defaultText
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completionHandler(nil)
        }))
        
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completionHandler(alertController.textFields?.first?.text)
        }))
        
        present(alertController, animated: true)
    }
}
