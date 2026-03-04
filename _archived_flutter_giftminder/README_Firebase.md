# Firebase Integration for GiftMinder

This README covers the Firebase setup and integration for sponsored content monetization in the GiftMinder Flutter app.

## Overview

The Firebase integration enables:
- **Anonymous user analytics** (with consent)
- **Sponsored gift recommendations** from retail partners
- **Revenue tracking** through affiliate commissions
- **GDPR-compliant data handling**
- **Real-time sponsored content management**

## Quick Start

### 1. Install Dependencies

All Firebase dependencies are already added to `pubspec.yaml`:

```yaml
dependencies:
  firebase_core: ^2.24.2
  cloud_firestore: ^4.13.6
  firebase_analytics: ^10.7.4
  firebase_auth: ^4.15.3
```

### 2. Firebase Project Setup

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Login and configure
firebase login
flutterfire configure
```

### 3. Generate JSON Models

```bash
cd flutter_giftminder
flutter packages pub run build_runner build
```

## Architecture

### Data Flow

```
User Interactions → Anonymous Analytics → Firestore
                                    ↓
Sponsored Content ← Recommendation Engine ← User Preferences
```

### Key Components

1. **FirebaseService** - Main service provider
2. **UserAnalyticsProfile** - Anonymous user data model
3. **SponsoredGift** - Sponsored product model
4. **ConsentScreen** - GDPR compliance UI
5. **InteractionTracking** - Revenue analytics

## Data Models

### UserAnalyticsProfile

Stores anonymous user preferences:

```dart
UserAnalyticsProfile(
  anonymousId: "uuid",
  ageGroup: AgeGroup.age25to34,
  generalInterests: ["technology", "fitness"],
  consent: UserConsent(/* consent flags */),
)
```

### SponsoredGift

Represents vendor products:

```dart
SponsoredGift(
  name: "Product Name",
  priceRange: PriceRange.range50to100,
  targetInterests: ["technology"],
  commissionRate: 5.5,
  vendor: VendorInfo(/* vendor details */),
)
```

## Firebase Collections

### `sponsored_gifts`
- Product catalog from retail partners
- Targeting criteria (interests, age groups)
- Commission rates and affiliate links

### `vendors`
- Retail partner information
- Commission rates and contact details
- Partnership status and tiers

### `user_analytics` 
- Anonymous user preference profiles
- Consent records and timestamps
- Geographic and demographic data

### `gift_interactions`
- Click-through tracking
- Revenue attribution
- User engagement metrics

## Usage Examples

### Initialize Firebase Service

```dart
// In main.dart - already implemented
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (context) => FirebaseService()),
    // ... other providers
  ],
)
```

### Get Personalized Recommendations

```dart
final firebaseService = context.read<FirebaseService>();
final recommendations = firebaseService.getPersonalizedRecommendations(
  limit: 10,
  priceFilter: PriceRange.range25to50,
);
```

### Track User Interactions

```dart
// Track when user views a sponsored gift
await firebaseService.recordGiftInteraction(
  gift: sponsoredGift,
  type: InteractionType.view,
);

// Track when user clicks affiliate link
await firebaseService.recordGiftInteraction(
  gift: sponsoredGift,
  type: InteractionType.click,
);
```

### Record Purchase (Revenue Tracking)

```dart
await firebaseService.recordPurchase(
  gift: sponsoredGift,
  actualPrice: 79.99,
  orderId: 'order_123456',
);
```

## Privacy & Consent

### Consent Management

The app implements granular consent with four categories:

1. **Personalized Recommendations** - Better gift matching
2. **Anonymous Analytics** - App improvement data  
3. **Sponsored Content** - Show relevant sponsored products
4. **Marketing Communications** - Feature updates and offers

### Data Protection

- **Local Storage**: Personal data (names, photos) stays on device
- **Anonymous Analytics**: Only general categories shared
- **Age Groups**: Ranges instead of exact ages
- **User Control**: Full data export and deletion

### GDPR Compliance

```dart
// Export user data
final userData = await firebaseService.exportUserData();

// Delete all user data
await firebaseService.deleteUserData();
```

## Revenue Model

### Commission Tracking

```dart
// When user clicks sponsored product
analytics.logEvent('sponsored_click', {
  'gift_id': gift.id,
  'vendor_id': gift.vendorId, 
  'commission_rate': gift.commissionRate,
  'potential_revenue': gift.exactPrice * (gift.commissionRate / 100),
});
```

### Revenue Streams

1. **Affiliate Commissions** - % of purchase price
2. **Sponsored Placements** - Premium positioning fees  
3. **Featured Products** - Enhanced visibility fees
4. **Partnership Tiers** - Volume-based commission rates

## Testing

### Debug Mode

```bash
# Android
adb shell setprop debug.firebase.analytics.app com.example.gift_minder

# iOS - add to scheme arguments
-FIRAnalyticsDebugEnabled
```

### Sample Data

Use the provided sample data script to populate test products:

```bash
node sample_data.js
```

## Security Rules

Firestore rules ensure data protection:

```javascript
// Public read for sponsored content
match /sponsored_gifts/{document} {
  allow read: if true;
  allow write: if false; // Admin only
}

// User can only access their own analytics
match /user_analytics/{userId} {
  allow read, write: if request.auth.uid == userId;
}
```

## Performance Optimization

### Caching Strategy

```dart
// Cache sponsored gifts locally
final prefs = await SharedPreferences.getInstance();
prefs.setString('cached_gifts', jsonEncode(gifts));
```

### Query Optimization

```dart
// Efficient Firestore queries
.where('isActive', isEqualTo: true)
.where('activeUntil', isGreaterThan: Timestamp.now())
.orderBy('priority', descending: true)
.limit(20)
```

## Monitoring

### Key Metrics

- **Click-through rate** on sponsored content
- **Conversion rate** from clicks to purchases  
- **Revenue per user** from affiliate commissions
- **User consent rates** by category
- **Recommendation relevance** scores

### Analytics Dashboard

Monitor performance in Firebase Console:
- Custom events and conversions
- User engagement and retention
- Revenue attribution by vendor
- Geographic and demographic insights

## Troubleshooting

### Common Issues

1. **Firebase not initialized**
   ```dart
   await Firebase.initializeApp(
     options: DefaultFirebaseOptions.currentPlatform,
   );
   ```

2. **Missing permissions**
   - Check Firestore security rules
   - Verify user authentication

3. **Analytics not showing**
   - Enable debug mode
   - Check network connectivity
   - Verify project configuration

### Debug Commands

```bash
# Check Firebase status
firebase projects:list

# Test Firestore rules  
firebase firestore:rules:test

# Deploy updates
firebase deploy --only firestore:rules
```

## Next Steps

1. **Set up Firebase project** following the setup guide
2. **Add sample sponsored content** for testing
3. **Configure vendor partnerships** and commission rates
4. **Test consent flow** with real devices
5. **Monitor analytics** and optimize recommendations
6. **Scale with demand** as user base grows

## Legal Considerations

- Update privacy policy to reflect data collection
- Ensure compliance with local privacy laws (GDPR, CCPA)
- Implement proper consent management
- Provide clear data deletion mechanisms
- Regular security audits and updates

---

**Note**: This integration is designed to monetize through legitimate sponsored content and affiliate partnerships, not by selling personal user data. All privacy laws are respected, and user consent is paramount.