import WebKit

// MARK: - WKNavigationDelegate
extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingView.isHidden = false
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingView.isHidden = true
    }
    
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
}

// MARK: - WKUIDelegate
extension WebViewController: WKUIDelegate {
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