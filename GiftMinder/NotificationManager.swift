//
//  NotificationManager.swift
//  GiftMinder
//
//  Created by David Johnson on 2/19/26.
//

import Foundation
import SwiftUI
internal import Combine

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var selectedContactId: UUID?
    @Published var shouldNavigateToContactDetail = false
    @Published var selectedNetworkEventId: String?
    @Published var shouldNavigateToNetworkEvent = false
    
    override init() {
        super.init()
    }
    
    /// Handle notification response and extract contact ID for navigation
    func handleNotificationResponse(_ userInfo: [AnyHashable: Any]) {
        if let eventId = userInfo["eventId"] as? String,
           !eventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async {
                self.selectedNetworkEventId = eventId
                self.shouldNavigateToNetworkEvent = true
            }
            return
        }

        // Extract contact ID from notification payload
        if let contactIdString = userInfo["contactId"] as? String,
           let contactId = UUID(uuidString: contactIdString) {
            DispatchQueue.main.async {
                self.selectedContactId = contactId
                self.shouldNavigateToContactDetail = true
            }
        }
    }
    
    /// Reset navigation state
    func resetNavigation() {
        resetContactNavigation()
        resetEventNavigation()
    }

    func resetContactNavigation() {
        selectedContactId = nil
        shouldNavigateToContactDetail = false
    }

    func resetEventNavigation() {
        selectedNetworkEventId = nil
        shouldNavigateToNetworkEvent = false
    }
}

