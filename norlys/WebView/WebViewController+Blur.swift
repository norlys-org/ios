import UIKit
import WebKit

extension WebViewController {
    func addVariableBlurToTop() {
        guard #available(iOS 13.0, *) else { return }
        
        var blurHeight: CGFloat = 0
        if #available(iOS 11.0, *) {
            blurHeight = view.safeAreaInsets.top
        } else {
            blurHeight = UIApplication.shared.statusBarFrame.height
        }
        
        guard blurHeight > 0 else { return }
        
        view.subviews.forEach { subview in
            if subview is VariableBlurUIView {
                subview.removeFromSuperview()
            }
        }
        
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
        
        view.addSubview(blurView)
        view.bringSubviewToFront(blurView)
        
        if let activityIndicator = view.subviews.first(where: { $0 is UIActivityIndicatorView }) {
            view.bringSubviewToFront(activityIndicator)
        }
        
        print("Added blur view with height: \(blurHeight)")
    }
} 