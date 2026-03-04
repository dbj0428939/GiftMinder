# 🎁 GiftMinder

**Never forget the perfect gift again!**

GiftMinder is a comprehensive gift recommendation app that helps you track your family and friends' interests, birthdays, and preferences to suggest personalized gifts from retailers, marketplaces, and individual sellers.

## 📱 Platforms

- **iOS** - Native SwiftUI app
- **Android** - Flutter cross-platform app (also works on iOS)

## ✨ Features

### 👥 Contact Management
- Add family, friends, colleagues, and partners
- Track birthdays with countdown reminders
- Store interests, preferences, and notes
- Photo support for contacts
- Relationship categorization

### 🎯 Smart Gift Recommendations
- AI-powered matching based on interests and age
- Confidence scoring (Low/Medium/High/Very High)
- Price range filtering ($0-25, $25-50, $50-100, etc.)
- Category-based suggestions (Electronics, Books, Sports, etc.)
- Sponsored gift integration for monetization

### 🔍 Gift Discovery
- Browse gifts by category
- Search by keywords, interests, or retailer
- Filter by price, availability, and ratings
- Trending gifts section
- Sponsored/featured products

### 📊 Smart Features
- Urgent birthday alerts (30-day window)
- Popular interests suggestions
- Gift history tracking per contact
- Data import/export functionality
- Statistics and insights

### 🏪 Retailer Integration
- Major retailers (Amazon, Target, etc.)
- Online marketplaces
- Local businesses
- Individual sellers
- Brand direct sales
- Specialty stores

## 🏗️ Architecture

### iOS (SwiftUI)
```
GiftMinder/
├── GiftMinder/
│   ├── ContentView.swift          # Main app with all features
│   ├── GiftMinderApp.swift        # App entry point
│   └── Assets.xcassets/           # App assets
├── GiftMinderTests/               # Unit tests
└── GiftMinderUITests/             # UI tests
```

### Flutter (Cross-Platform)
```
flutter_giftminder/
├── lib/
│   ├── main.dart                  # App entry point
│   ├── models/                    # Data models
│   │   ├── contact.dart           # Contact model
│   │   └── gift.dart              # Gift & recommendation models
│   ├── providers/                 # State management
│   │   ├── contact_provider.dart  # Contact management
│   │   └── gift_provider.dart     # Gift recommendations
│   ├── screens/                   # UI screens
│   │   ├── home_screen.dart       # Main navigation
│   │   ├── contacts_screen.dart   # Contact list
│   │   ├── add_contact_screen.dart # Add/edit contacts
│   │   ├── contact_detail_screen.dart # Contact details
│   │   ├── recommendations_screen.dart # Gift recommendations
│   │   ├── search_screen.dart     # Gift search
│   │   └── profile_screen.dart    # Settings & stats
│   └── pubspec.yaml               # Dependencies
```

## 🚀 Getting Started

### iOS Development

#### Prerequisites
- macOS 12.0 or later
- Xcode 14.0 or later
- iOS 16.0 or later

#### Installation
1. Open `GiftMinder.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (⌘R)

```bash
cd GiftMinder
xcodebuild -scheme GiftMinder -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Flutter Development

#### Prerequisites
- Flutter SDK 3.10.0 or later
- Dart SDK 3.0.0 or later
- Android Studio / VS Code
- iOS: Xcode (for iOS development)
- Android: Android SDK

#### Installation
1. Install dependencies:
```bash
cd flutter_giftminder
flutter pub get
```

2. Generate model files:
```bash
flutter packages pub run build_runner build
```

3. Run the app:
```bash
# iOS
flutter run -d ios

# Android
flutter run -d android

# Web (for testing)
flutter run -d chrome
```

## 📊 Data Models

### Contact
```dart
class Contact {
  String id;
  String name;
  DateTime dateOfBirth;
  Relationship relationship;
  List<String> interests;
  String notes;
  String? photoPath;
  List<GiftHistory> giftHistory;
}

enum Relationship {
  family, friend, colleague, partner, other
}
```

### Gift
```dart
class Gift {
  String id;
  String name;
  String description;
  PriceRange price;
  GiftCategory category;
  List<AgeGroup> ageGroups;
  List<String> interests;
  Retailer retailer;
  GiftRatings ratings;
  bool isSponsored;
}

enum GiftCategory {
  electronics, books, clothing, homeDecor, sports, 
  beauty, toys, food, jewelry, art, music, travel, 
  gardening, automotive, pets, education, health, other
}
```

### Gift Recommendation
```dart
class GiftRecommendation {
  Gift gift;
  String contactId;
  double matchScore;
  List<RecommendationReason> reasons;
  ConfidenceLevel confidence;
}

enum ConfidenceLevel {
  low, medium, high, veryHigh
}
```

## 🔧 Key Features Implementation

### Recommendation Algorithm
The app uses a sophisticated matching algorithm that considers:
- **Interest Matching** (3x weight) - Direct interest overlap
- **Age Appropriateness** (2x weight) - Age group compatibility
- **Availability** (0.5x weight) - Product availability
- **Ratings** (0.5x weight) - Product quality scores

```swift
func matchScore(for contact: Contact) -> Double {
    var score: Double = 0
    
    // Interest matching (highest weight)
    let matchingInterests = interests.filter { /* interest matching logic */ }
    score += Double(matchingInterests.count) * 3.0
    
    // Age group matching
    let contactAgeGroup = AgeGroup.fromAge(contact.age)
    if ageGroups.contains(contactAgeGroup) {
        score += 2.0
    }
    
    // Availability and rating bonuses
    if availability == .available { score += 0.5 }
    score += ratings.averageRating * 0.5
    
    return score
}
```

### Birthday Tracking
- Automatic birthday countdown calculation
- 30-day advance notifications
- Urgent alerts for upcoming birthdays
- Age calculation and group categorization

### Data Persistence
- **iOS**: UserDefaults for local storage
- **Flutter**: SharedPreferences + SQLite for complex queries
- JSON serialization for data export/import
- Backup and restore functionality

## 💰 Monetization Strategy

### Sponsored Content
- Sponsored gift placements in recommendations
- Featured retailer partnerships
- Premium recommendation features
- Affiliate marketing integration

### Revenue Streams
1. **Sponsored Gifts** - Retailers pay for premium placement
2. **Affiliate Commissions** - Commission on purchases through app
3. **Premium Features** - Advanced filtering, unlimited contacts
4. **Retailer Partnerships** - Direct integration fees

## 🔒 Privacy & Security

### Data Protection
- All personal data stored locally on device
- No cloud storage of personal information
- Optional data export for user backup
- GDPR compliance ready

### Permissions
- **iOS**: Photo library access (optional)
- **Flutter**: Storage, camera, notifications
- **No network tracking** of personal data
- **No analytics** on personal information

## 🧪 Testing

### iOS Testing
```bash
# Unit tests
xcodebuild test -scheme GiftMinderTests

# UI tests  
xcodebuild test -scheme GiftMinderUITests
```

### Flutter Testing
```bash
# Unit tests
flutter test

# Integration tests
flutter test integration_test/

# Widget tests
flutter test test/widget_test.dart
```

## 📈 Performance

### iOS Optimization
- SwiftUI declarative UI for smooth performance
- Lazy loading for large contact lists
- Efficient Core Data queries
- Memory-conscious image handling

### Flutter Optimization
- Provider state management for efficiency
- ListView.builder for large lists
- Image caching and optimization
- SQLite indexing for fast queries

## 🚀 Deployment

### iOS App Store
1. Configure app signing in Xcode
2. Update version and build numbers
3. Archive and upload to App Store Connect
4. Submit for review

### Google Play Store
1. Build release APK/AAB:
```bash
flutter build apk --release
flutter build appbundle --release
```
2. Sign with upload key
3. Upload to Google Play Console
4. Submit for review

## 🔮 Future Enhancements

### Phase 2 Features
- [ ] Machine learning recommendation improvements
- [ ] Social features (gift sharing)
- [ ] Calendar integration for events
- [ ] Wishlist creation and sharing
- [ ] Price tracking and alerts
- [ ] Barcode scanning for gift ideas

### Technical Improvements
- [ ] GraphQL API for real-time data
- [ ] Firebase integration for cloud sync
- [ ] Push notifications for birthdays
- [ ] Apple Watch / Wear OS companion apps
- [ ] AR gift visualization
- [ ] Voice assistant integration

## 🤝 Contributing

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Follow coding conventions
4. Add tests for new features
5. Submit pull request

### Code Style
- **iOS**: SwiftLint configuration
- **Flutter**: Dart analysis options
- **Documentation**: Inline code comments
- **Testing**: Minimum 80% coverage

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

For support, feature requests, or bug reports:
- 📧 Email: support@giftminder.app
- 🐛 Issues: GitHub Issues
- 📖 Docs: [Documentation Wiki](wiki)

## 🙏 Acknowledgments

- SwiftUI framework for iOS development
- Flutter framework for cross-platform development
- Material Design components
- Open source community contributors

---

**Built with ❤️ for thoughtful gift-giving**

*GiftMinder - Because the perfect gift shows you care*