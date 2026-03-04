//
//  GiftMinderApp.swift
//  GiftMinder
//
//  Created by David Johnson on 11/7/25.
//

import SwiftUI
import FirebaseCore
import UserNotifications
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        AuthUserSyncService.shared.start()
        
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Set up FCM
        Messaging.messaging().delegate = NotificationService.shared
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        
        // Handle notification tap when app is launched
        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            NotificationManager.shared.handleNotificationResponse(notification)
        }
        
        return true
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle remote notification in background
        completionHandler(.newData)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        NotificationManager.shared.handleNotificationResponse(userInfo)
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        NotificationManager.shared.handleNotificationResponse(userInfo)
        completionHandler()
    }
}

@main
struct GiftMinderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("themeMode") private var themeModeRaw: String = ThemeMode.system.rawValue
    @AppStorage("authState") private var authStateRaw: String = AuthState.unauthenticated.rawValue
    @StateObject private var notificationManager = NotificationManager.shared

    private var themeMode: ThemeMode {
        ThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var authState: AuthState {
        AuthState(rawValue: authStateRaw) ?? .unauthenticated
    }

    @State private var showSplash: Bool = true
    @State private var animateEntrance: Bool = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView(onComplete: {
                        // Hide splash and trigger entrance animation for main UI
                        withAnimation(.easeOut(duration: 0.45)) {
                            showSplash = false
                        }
                        // slight delay so ContentView appears and can animate
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            animateEntrance = true
                        }
                    })
                    .preferredColorScheme(themeMode.colorScheme)
                    .ignoresSafeArea()
                } else if authState == .unauthenticated {
                    LoginView()
                        .preferredColorScheme(themeMode.colorScheme)
                        .ignoresSafeArea()
                } else {
                    ContentView(animateEntrance: $animateEntrance)
                        .environmentObject(notificationManager)
                        .preferredColorScheme(themeMode.colorScheme)
                        .ignoresSafeArea()
                }
            }
            // Ensure app background fills the window but avoid drawing under the bottom tab bar
            .background(BrandedDottedBackground().ignoresSafeArea(edges: .top))
        }
    }
}
