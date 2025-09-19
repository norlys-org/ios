//
//  ContentView.swift
//  norlys
//
//  Created by Hugo Lageneste on 06/03/2025.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // Only set up window for iOS 12 and below
        if #available(iOS 13.0, *) {
            // Scene delegate will handle window setup
        } else {
            setupWindow()
        }
        return true
    }
    
    private func setupWindow() {
        window = UIWindow(frame: UIScreen.main.bounds)
        let webViewController = WebViewController()
        let navigationController = UINavigationController(rootViewController: webViewController)
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }
    
    // MARK: - 🔔 Push Notification Callbacks
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📲 APNs device token:", token)
        
        DispatchQueue.main.async {
            PushBridge.shared.webView?.evaluateJavaScript(
                "window.onPushTokenReceived && window.onPushTokenReceived('\(token)')"
            )
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        // forward payload to your web app if you want:
        completion()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications:", error.localizedDescription)
        
        let msg = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
        DispatchQueue.main.async {
            PushBridge.shared.webView?.evaluateJavaScript(
                "window.onPushError && window.onPushError('\(msg)')"
            )
        }
    }
    
    // MARK: - UISceneSession Lifecycle (iOS 13+)
    
    @available(iOS 13.0, *)
    func application(_ application: UIApplication, onfigurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        setupWindow(with: windowScene)
    }
    
    private func setupWindow(with windowScene: UIWindowScene) {
        window = UIWindow(windowScene: windowScene)
        let webViewController = WebViewController()
        let navigationController = UINavigationController(rootViewController: webViewController)
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }
}
