# GiftMinder Push Notifications Setup

This guide explains how to set up push notifications for upcoming contact events (birthdays, anniversaries, and custom dates), plus network event invites and organizer updates.

## Overview

The notification system works by:
1. **iOS App** - Requests notification permissions and handles receiving notifications
2. **Firebase Cloud Functions** - Periodically checks for upcoming events and sends notifications
3. **Apple Push Notification Service (APNs)** - Delivers notifications to devices
4. **Firestore** - Stores contact data and tracks notification sending

For Event Network notifications, Firestore triggers on `networkEvents/{eventId}` send:
- `network_event_invite` when a new event is created
- `network_event_update` when organizer details change
- `network_event_invite_response` when an invitee accepts/maybe/declines
- payload key: `eventId` (used by iOS to deep-link into Event detail)

## Part 1: iOS App Setup (Already Done ✓)

The iOS app has been configured to:
- Request user notification permissions on first launch
- Handle notification tap events and navigate to the contact's profile
- Extract contact ID from notification payload for deep linking

## Part 2: Firebase Configuration

### 1. Set Up APNs Certificate

1. Go to [Apple Developer](https://developer.apple.com/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Certificates** and create a new **Apple Push Notification service (APNs)** SSL Certificate
4. Download the certificate and open in Keychain Access
5. Export the certificate as `.p8` file (or use the new key format)
6. Go to **Firebase Console** → Your Project → **Project Settings** → **Cloud Messaging**
7. Under APNs Certificates, upload your certificate

### 2. Add APNs Key in Firebase

1. In Apple Developer, go to **Keys**
2. Create a new key with **Apple Push Notifications service (APNs)** capability
3. Download the `.p8` file
4. In Firebase Console → **Cloud Messaging** → **APNs Authentication Key**
5. Upload the key and enter your Team ID, Key ID, and Bundle ID

## Part 3: Firebase Cloud Functions Setup

### 1. Initialize Cloud Functions Project

```bash
# Install Firebase CLI if not already installed
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize functions in your Firebase project directory
firebase init functions
# Choose TypeScript when prompted
```

### 2. Create the Notification Function

Replace the contents of `functions/src/index.ts` with:

```typescript
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

interface Contact {
  id: string;
  name: string;
  dateOfBirth: admin.firestore.Timestamp;
  isBirthYearKnown: boolean;
  hasBirthday: boolean;
  anniversaryDate?: admin.firestore.Timestamp;
  isAnniversaryYearKnown: boolean;
  customEvents?: Array<{
    id: string;
    title: string;
    date: admin.firestore.Timestamp;
    isYearKnown: boolean;
  }>;
}

interface User {
  id: string;
  fcmToken?: string;
  notificationPreferences?: {
    enableNotifications: boolean;
    daysInAdvance: number; // e.g., 1, 7, 30
  };
}

// Scheduled function to check for upcoming events daily
export const checkUpcomingEventsDaily = functions.pubsub
  .schedule("0 8 * * *") // Run daily at 8 AM UTC
  .timeZone("UTC")
  .onRun(async (context) => {
    console.log("Starting daily event check...");

    try {
      // Fetch all users
      const usersSnapshot = await db.collection("users").get();

      for (const userDoc of usersSnapshot.docs) {
        const user = userDoc.data() as User;

        // Skip if user has notifications disabled or no FCM token
        if (
          !user.fcmToken ||
          user.notificationPreferences?.enableNotifications === false
        ) {
          continue;
        }

        // Fetch user's contacts
        const contactsSnapshot = await db
          .collection("users")
          .doc(userDoc.id)
          .collection("contacts")
          .get();

        const upcomingEvents: Array<{
          contact: any;
          eventType: string;
          eventDate: Date;
          daysUntil: number;
        }> = [];

        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const daysInAdvance = user.notificationPreferences?.daysInAdvance || 1;

        for (const contactDoc of contactsSnapshot.docs) {
          const contact = contactDoc.data() as Contact;

          // Check birthday
          if (contact.hasBirthday && contact.dateOfBirth) {
            const birthDate = contact.dateOfBirth.toDate();
            const daysUntilBirthday = getDaysUntilEvent(birthDate, today);

            if (
              daysUntilBirthday === daysInAdvance ||
              (daysInAdvance > 1 &&
                daysUntilBirthday > 0 &&
                daysUntilBirthday <= daysInAdvance)
            ) {
              upcomingEvents.push({
                contact,
                eventType: "birthday",
                eventDate: birthDate,
                daysUntil: daysUntilBirthday,
              });
            }
          }

          // Check anniversary
          if (contact.anniversaryDate) {
            const annDate = contact.anniversaryDate.toDate();
            const daysUntilAnniversary = getDaysUntilEvent(annDate, today);

            if (
              daysUntilAnniversary === daysInAdvance ||
              (daysInAdvance > 1 &&
                daysUntilAnniversary > 0 &&
                daysUntilAnniversary <= daysInAdvance)
            ) {
              upcomingEvents.push({
                contact,
                eventType: "anniversary",
                eventDate: annDate,
                daysUntil: daysUntilAnniversary,
              });
            }
          }

          // Check custom events
          if (contact.customEvents && contact.customEvents.length > 0) {
            for (const event of contact.customEvents) {
              const eventDate = event.date.toDate();
              const daysUntilEvent = getDaysUntilEvent(eventDate, today);

              if (
                daysUntilEvent === daysInAdvance ||
                (daysInAdvance > 1 &&
                  daysUntilEvent > 0 &&
                  daysUntilEvent <= daysInAdvance)
              ) {
                upcomingEvents.push({
                  contact,
                  eventType: event.title,
                  eventDate,
                  daysUntil: daysUntilEvent,
                });
              }
            }
          }
        }

        // Send notifications for upcoming events
        for (const event of upcomingEvents) {
          await sendEventNotification(
            user.fcmToken,
            event.contact,
            event.eventType,
            event.daysUntil
          );
        }
      }

      console.log("Event check completed successfully");
      return null;
    } catch (error) {
      console.error("Error in checkUpcomingEventsDaily:", error);
      throw error;
    }
  });

// Send notification for a specific event
async function sendEventNotification(
  fcmToken: string,
  contact: Contact,
  eventType: string,
  daysUntil: number
): Promise<void> {
  let title = "";
  let body = "";

  if (daysUntil === 0) {
    title = `${contact.name}'s ${eventType === "birthday" ? "Birthday" : eventType} is Today! 🎉`;
    body = "Tap to view their profile and find the perfect gift";
  } else if (daysUntil === 1) {
    title = `${contact.name}'s ${eventType === "birthday" ? "Birthday" : eventType} is Tomorrow!`;
    body = "Tap to view their profile and find the perfect gift";
  } else {
    title = `${contact.name}'s ${eventType === "birthday" ? "Birthday" : eventType} is in ${daysUntil} days`;
    body = "Tap to view their profile and find the perfect gift";
  }

  const message: admin.messaging.Message = {
    token: fcmToken,
    notification: {
      title,
      body,
    },
    data: {
      contactId: contact.id,
      eventType,
    },
    apns: {
      payload: {
        aps: {
          alert: {
            title,
            body,
          },
          sound: "default",
          badge: 1,
        },
      },
    },
  };

  try {
    await messaging.send(message);
    console.log(`Notification sent to user for ${contact.name}`);
  } catch (error) {
    console.error(
      `Failed to send notification for ${contact.name}:`,
      error
    );
  }
}

// Calculate days until event (handling year wraparound)
function getDaysUntilEvent(eventDate: Date, today: Date): number {
  const currentYear = today.getFullYear();

  // Create next occurrence of the event
  let nextOccurrence = new Date(
    currentYear,
    eventDate.getMonth(),
    eventDate.getDate()
  );

  // If the event has already passed this year, check next year
  if (nextOccurrence < today) {
    nextOccurrence = new Date(
      currentYear + 1,
      eventDate.getMonth(),
      eventDate.getDate()
    );
  }

  const timeDiff = nextOccurrence.getTime() - today.getTime();
  const daysDiff = Math.ceil(timeDiff / (1000 * 60 * 60 * 24));

  return daysDiff;
}

// API endpoint to store/update FCM token
export const updateFcmToken = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { fcmToken } = data;
    const uid = context.auth.uid;

    await db.collection("users").doc(uid).update({
      fcmToken,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  }
);

// API endpoint to update notification preferences
export const updateNotificationPreferences = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { enableNotifications, daysInAdvance } = data;
    const uid = context.auth.uid;

    await db.collection("users").doc(uid).update({
      notificationPreferences: {
        enableNotifications,
        daysInAdvance,
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  }
);
```

### 3. Configure Firestore Rules

Update your `firestore.rules` to allow users to manage their notification settings:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth.uid == uid;
      match /contacts/{contactId} {
        allow read, write: if request.auth.uid == uid;
      }
    }
  }
}
```

### 4. Deploy Cloud Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

### 5. Event Network Trigger Notes

If you use the provided `functions/src/index.ts` in this workspace, event pushes are already included:

- Trigger: `onNetworkEventCreated`
  - Sends invite push notifications to invitees and attendees (excluding organizer)
- Trigger: `onNetworkEventUpdated`
  - Sends update push notifications when title/time/location/theme/details/visibility/invite list changes
- User resolution:
  - Invite handles resolve through `usernames/{handle} -> uid`
  - FCM token read from `users/{uid}.fcmToken`
  - Honors `users/{uid}.notificationPreferences.enableNotifications === false`

## Part 3: iOS App Integration for FCM Token

Add this to `ProductAPI.swift` or create a new `NotificationService.swift`:

```swift
import FirebaseMessaging
import FirebaseAuth
import FirebaseFunctions

class NotificationService {
    static let shared = NotificationService()
    private let functions = Functions.functions()
    
    func setupFCMToken() {
        Messaging.messaging().token { token, error in
            if let error = error {
                print("Error fetching FCM token: \(error)")
                return
            }
            
            guard let token = token else { return }
            print("FCM Token: \(token)")
            
            // Store token in Firestore
            self.updateFCMToken(token)
        }
        
        // Listen for token refresh
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tokenRefreshed),
            name: NSNotification.Name.MessagingTokenRefreshed,
            object: nil
        )
    }
    
    @objc private func tokenRefreshed() {
        Messaging.messaging().token { token, error in
            guard let token = token else { return }
            self.updateFCMToken(token)
        }
    }
    
    private func updateFCMToken(_ token: String) {
        functions.httpsCallable("updateFcmToken").call(["fcmToken": token]) { result, error in
            if let error = error {
                print("Error updating FCM token: \(error)")
                return
            }
            print("FCM token updated successfully")
        }
    }
    
    func updateNotificationPreferences(
        enableNotifications: Bool,
        daysInAdvance: Int
    ) {
        functions.httpsCallable("updateNotificationPreferences").call([
            "enableNotifications": enableNotifications,
            "daysInAdvance": daysInAdvance
        ]) { result, error in
            if let error = error {
                print("Error updating preferences: \(error)")
                return
            }
            print("Notification preferences updated")
        }
    }
}
```

## Part 4: Initialize in iOS App

Update `GiftMinderApp.swift` to initialize FCM:

```swift
import FirebaseMessaging

// In AppDelegate.application(_:didFinishLaunchingWithOptions:)
Messaging.messaging().delegate = self  // Add to AppDelegate

// In GiftMinderApp or after user authenticates
NotificationService.shared.setupFCMToken()
```

## Part 5: Add Notification Settings to Settings Page

In your settings UI, expand the **Enable Event Notifications** area so users understand what it does and what to do if iOS permission is off.

### Recommended UX behavior

1. Show a short explanation under the notifications header (birthdays, anniversaries, and custom dates).
2. Keep the main toggle: **Enable Event Notifications**.
3. When enabled:
  - Show a timing picker (`Same day`, `1 day before`, `7 days before`, `15 days before`, `30 days before`, `Custom...`).
  - If `Custom...` is selected, show a numeric text field so users can type any number of days.
   - Use `.menu` picker style for better compatibility on smaller iPhones.
4. Detect current iOS notification permission status:
   - `.notDetermined`: show button **Allow Notifications** (request permission).
   - `.denied`: show button **Open iPhone Settings**.
5. Sync every setting change to Firebase via `NotificationService.updateNotificationPreferences(...)`.

### Example SwiftUI implementation

```swift
import UserNotifications

@AppStorage("enableNotifications") private var enableNotifications: Bool = true
@AppStorage("daysInAdvance") private var daysInAdvance: Int = 1
@State private var selectedDaysInAdvanceOption: Int = 1
@State private var customDaysInput: String = ""
@FocusState private var isCustomDaysFieldFocused: Bool
@State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

private let presetDays = [0, 1, 7, 15, 30]

private var customDaysValue: Int? {
  guard let value = Int(customDaysInput), value >= 0 else { return nil }
  return value
}

private var permissionMessage: String {
  switch authorizationStatus {
  case .authorized, .provisional, .ephemeral:
    return "Event reminders are enabled on this device."
  case .notDetermined:
    return "Allow notifications to receive event reminders."
  case .denied:
    return "Notifications are turned off in iPhone Settings."
  @unknown default:
    return "Notification permission status is unavailable."
  }
}

var body: some View {
  Section(header: Text("Notifications")) {
    Text("Get reminders for birthdays, anniversaries, and custom dates.")
      .font(.caption)
      .foregroundColor(.secondary)

    Toggle("Enable Event Notifications", isOn: $enableNotifications)
      .onChange(of: enableNotifications) { _ in
        updateNotificationPreferences()
        refreshAuthorizationStatus()
      }

    if enableNotifications {
      Picker("Notify me", selection: $selectedDaysInAdvanceOption) {
        Text("Same day").tag(0)
        Text("1 day before").tag(1)
        Text("7 days before").tag(7)
        Text("15 days before").tag(15)
        Text("30 days before").tag(30)
        Text("Custom...").tag(-1)
      }
      .pickerStyle(.menu)
      .onChange(of: selectedDaysInAdvanceOption) { selected in
        if selected >= 0 {
          daysInAdvance = selected
          customDaysInput = ""
          updateNotificationPreferences()
        } else if customDaysInput.isEmpty {
          customDaysInput = "\(daysInAdvance)"
        }
      }

      if selectedDaysInAdvanceOption == -1 {
        TextField("Enter number of days", text: $customDaysInput)
          .keyboardType(.numberPad)
          .textFieldStyle(.roundedBorder)
          .focused($isCustomDaysFieldFocused)

        Button("Save custom days") {
          if let value = customDaysValue {
            daysInAdvance = value
            updateNotificationPreferences()
          }
          isCustomDaysFieldFocused = false
        }
      }

      Text(permissionMessage)
        .font(.caption)
        .foregroundColor(.secondary)

      if authorizationStatus == .notDetermined {
        Button("Allow Notifications") {
          NotificationService.shared.requestNotificationPermissions { _ in
            refreshAuthorizationStatus()
          }
        }
      } else if authorizationStatus == .denied {
        Button("Open iPhone Settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        }
      }
    }
  }
  .onAppear {
    refreshAuthorizationStatus()
    if presetDays.contains(daysInAdvance) {
      selectedDaysInAdvanceOption = daysInAdvance
      customDaysInput = ""
    } else {
      selectedDaysInAdvanceOption = -1
      customDaysInput = "\(daysInAdvance)"
    }
  }
  .toolbar {
    ToolbarItemGroup(placement: .keyboard) {
      Spacer()
      Button("Done") {
        if let value = customDaysValue {
          daysInAdvance = value
          updateNotificationPreferences()
        }
        isCustomDaysFieldFocused = false
      }
    }
  }
}

private func refreshAuthorizationStatus() {
  UNUserNotificationCenter.current().getNotificationSettings { settings in
    DispatchQueue.main.async {
      authorizationStatus = settings.authorizationStatus
    }
  }
}
```

## Testing

1. **Local Testing**: Use Firebase Emulator Suite to test Cloud Functions locally
   ```bash
   firebase emulators:start
   ```

2. **Production Testing**: Deploy to a test device and wait for the scheduled function, or manually trigger via Firebase Console

3. **Verify Notifications**: Check Firebase Console → Cloud Functions logs for execution details

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No notifications received | 1. Verify FCM token is being sent to Firestore<br>2. Check Cloud Function logs for errors<br>3. Verify APNs certificate is properly configured<br>4. Ensure user has notifications enabled in app |
| Notifications appear as spam | 1. Customize notification copy with clearer titles and body text<br>2. Add frequency controls<br>3. Tune notification cadence per user preference |
| Deep linking not working | 1. Verify contactId is in notification data payload<br>2. Ensure contact exists in local store when notification tapped |

## Security Considerations

- ✓ Only administrators can update APNs certificates
- ✓ Firebase Cloud Functions run as admin but validate auth tokens
- ✓ Firestore rules ensure users can only read/write their own data
- ✓ FCM tokens are stored securely in Firestore
