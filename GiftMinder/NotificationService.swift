//
//  NotificationService.swift
//  GiftMinder
//
//  Created by David Johnson on 2/19/26.
//

import Foundation
import FirebaseMessaging
import FirebaseAuth
import FirebaseFunctions
import UIKit

class NotificationService: NSObject, MessagingDelegate {
    static let shared = NotificationService()
    private let functions = Functions.functions()
    
    override init() {
        super.init()
    }
    
    // Set up FCM and handle token updates
    func setupFCMToken() {
        Messaging.messaging().delegate = self
        
        // Get current token
        Messaging.messaging().token { [weak self] token, error in
            if let error = error {
                print("Error fetching FCM token: \(error)")
                return
            }
            
            guard let token = token else {
                print("FCM token is nil")
                return
            }
            
            print("FCM Token obtained: \(token.prefix(20))...")
            self?.updateFCMTokenInCloud(token)
        }
    }
    
    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM token refreshed: \(token.prefix(20))...")
        updateFCMTokenInCloud(token)
    }
    
    // MARK: - Private Methods
    
    private func updateFCMTokenInCloud(_ token: String) {
        // Ensure user is authenticated
        guard let userId = Auth.auth().currentUser?.uid else {
            print("User not authenticated, FCM token not saved")
            return
        }
        
        print("Updating FCM token for user: \(userId)")
        
        functions.httpsCallable("updateFcmToken").call(["fcmToken": token]) { [weak self] result, error in
            if let error = error as NSError? {
                if error.code == FunctionsErrorCode.unauthenticated.rawValue {
                    print("User is unauthenticated")
                } else {
                    print("Error updating FCM token: \(error.localizedDescription)")
                }
                return
            }
            
            print("FCM token updated successfully in Firestore")
        }
    }
    
    // Update user notification preferences
    func updateNotificationPreferences(
        enableNotifications: Bool,
        daysInAdvance: Int,
        forumNotificationsEnabled: Bool,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        guard Auth.auth().currentUser != nil else {
            completion(false, NSError(domain: "NotificationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        functions.httpsCallable("updateNotificationPreferences").call([
            "enableNotifications": enableNotifications,
            "daysInAdvance": daysInAdvance,
            "forumUpdatesEnabled": forumNotificationsEnabled
        ]) { result, error in
            if let error = error {
                print("Error updating notification preferences: \(error)")
                completion(false, error)
                return
            }
            
            print("Notification preferences updated successfully")
            
            // Save to local UserDefaults as backup
            UserDefaults.standard.set(enableNotifications, forKey: "enableNotifications")
            UserDefaults.standard.set(daysInAdvance, forKey: "daysInAdvance")
            UserDefaults.standard.set(forumNotificationsEnabled, forKey: "forumNotificationsEnabled")
            
            completion(true, nil)
        }
    }
    
    // Check if notifications are enabled
    func areNotificationsEnabled() async -> Bool {
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }
    
    // Request notification permissions if not already granted
    func requestNotificationPermissions(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permissions: \(error)")
            }
            
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                completion(granted)
            }
        }
    }
}
