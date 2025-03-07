import UIKit
import WebKit

/**
 * WebViewController Blur Extension
 * 
 * Adds variable blur effect functionality to the WebViewController.
 * The blur effect is applied to the top of the view to create a smooth transition
 * between the status bar and the web content.
 */
extension WebViewController {
    /**
     * Adds a variable blur effect to the top of the view.
     * The blur intensity gradually decreases from top to bottom, creating a smooth transition.
     * The blur height is determined by the safe area insets or status bar height.
     */
    func addVariableBlurToTop() {
        guard #available(iOS 13.0, *) else { return }
        
        var blurHeight: CGFloat = 0
        if #available(iOS 11.0, *) {
            blurHeight = view.safeAreaInsets.top
        } else {
            blurHeight = UIApplication.shared.statusBarFrame.height
        }
        
        guard blurHeight > 0 else { return }
        
        // Remove any existing blur views
        view.subviews.forEach { subview in
            if subview is VariableBlurUIView {
                subview.removeFromSuperview()
            }
        }
        
        // Create and configure the blur view
        let blurView = VariableBlurUIView(
            maxBlurRadius: 10,
            direction: .blurredTopClearBottom,
            startOffset: -0.1
        )
        
        blurView.frame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: blurHeight
        )
        
        blurView.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        
        // Add the blur view and ensure it's above the web view
        view.addSubview(blurView)
        view.bringSubviewToFront(blurView)
        
        // Keep any activity indicator above the blur view
        if let activityIndicator = view.subviews.first(where: { $0 is UIActivityIndicatorView }) {
            view.bringSubviewToFront(activityIndicator)
        }
        
        print("Added blur view with height: \(blurHeight)")
    }
} 