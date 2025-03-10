@preconcurrency
import WebKit

// MARK: - WKNavigationDelegate

/**
 * WKNavigationDelegate implementation for WebViewController
 * Handles web view navigation events, loading states, and errors.
 */
extension WebViewController: WKNavigationDelegate {
    /**
     * Called when the web view begins loading a new page.
     * Shows the loading view to indicate content is being loaded.
     */
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingView.isHidden = false
    }
    
    /**
     * Called when the web view finishes loading a page.
     * Hides the loading view to show the loaded content.
     */
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingView.isHidden = true
    }
    
    /**
     * Called when the web view fails to load a page.
     * Shows an appropriate error message based on the error type.
     */
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingView.isHidden = true
        
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain &&
           (nsError.code == NSURLErrorNotConnectedToInternet ||
            nsError.code == NSURLErrorNetworkConnectionLost) {
            showError(message: "No internet connection. Please check your network settings and try again.")
        } else {
            showError(message: "Failed to load page: \(error.localizedDescription)")
        }
    }
    
    /**
     * Called when the web view needs to decide whether to allow navigation to proceed.
     * Currently allows all navigation requests.
     */
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
    
    /**
     * Called when the web view encounters an error during navigation.
     * Shows the error message to the user.
     */
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(message: error.localizedDescription)
    }
}

// MARK: - WKUIDelegate

/**
 * WKUIDelegate implementation for WebViewController
 * Handles UI-related web view interactions like JavaScript alerts and media capture permissions.
 */
extension WebViewController: WKUIDelegate {
    /**
     * Called when the web page wants to show a JavaScript confirm dialog.
     * Presents a native iOS alert controller with OK and Cancel options.
     */
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
    
    /**
     * Called when the web page requests media capture permission.
     * Currently grants all media capture requests automatically.
     */
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}

// MARK: - WKScriptMessageHandler

/**
 * WKScriptMessageHandler implementation for WebViewController
 * Handles messages sent from JavaScript to native code, specifically console logging.
 */
extension WebViewController: WKScriptMessageHandler {
    /**
     * Called when a message is received from JavaScript.
     * Currently handles console messages (log, error, warn, info) and formats them for native output.
     */
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "console",
           let body = message.body as? [String: Any] {
            let type = body["type"] as? String ?? "log"
            let messages = body["message"] as? [String] ?? []
            let messageString = messages.joined(separator: " ")
            
            switch type {
            case "error":
                print("🔴 [WebView Error]:", messageString)
            case "warn":
                print("🟡 [WebView Warning]:", messageString)
            case "info":
                print("🔵 [WebView Info]:", messageString)
            default:
                print("⚪️ [WebView Log]:", messageString)
            }
        }
    }
}
