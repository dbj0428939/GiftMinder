# GiftMinder

GiftMinder is a native iOS app for tracking important people, events, and gift ideas so you can plan ahead for birthdays, anniversaries, and custom dates.

## Platform

- iOS only (SwiftUI)

## Core Features

- Contact and relationship management
- Birthday, anniversary, and custom event tracking
- Gift idea organization and recommendation workflows
- Event-based notification preferences
- Firebase-backed auth and data sync

## Project Structure

```
GiftMinder/
├── GiftMinder/                 # iOS app source (SwiftUI)
├── GiftMinderTests/            # Unit tests
├── GiftMinderUITests/          # UI tests
├── functions/                  # Firebase Cloud Functions
├── firebase.json
└── firestore.rules
```

## Getting Started (iOS)

### Prerequisites

- macOS
- Xcode 15+
- iOS 17+ (recommended)

### Run

1. Open `GiftMinder.xcodeproj` in Xcode.
2. Select an iOS simulator or physical device.
3. Build and run (`⌘R`).

Optional command-line build:

```bash
xcodebuild -project GiftMinder.xcodeproj -scheme GiftMinder -destination 'platform=iOS Simulator,name=iPhone 15' build
```

## Notifications

Push notification setup and implementation details are documented in:

- `NOTIFICATIONS_SETUP.md`
- `NOTIFICATIONS_IMPLEMENTATION.md`

## Support

For support, feature requests, or bug reports:

- Email: david.b.johnson.dev@gmail.com

## License

No open-source license is currently applied to this repository.