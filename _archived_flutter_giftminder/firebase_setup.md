# Firebase Setup Guide for GiftMinder

This guide will help you set up Firebase for the GiftMinder Flutter app to enable sponsored content, analytics, and user consent management.

## Prerequisites

- Flutter SDK 3.10.0+
- Firebase CLI installed
- Google account
- Android Studio (for Android configuration)
- Xcode (for iOS configuration)

## 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a project"
3. Enter project name: `giftminder-app`
4. Enable Google Analytics (recommended)
5. Choose or create Analytics account
6. Click "Create project"

## 2. Install Firebase CLI

```bash
# Install Firebase CLI globally
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase in your project
cd flutter_giftminder
firebase init
```

Select the following services:
- [x] Firestore
- [x] Functions (optional, for backend logic)
- [x] Hosting (optional, for admin panel)

## 3. Configure Flutter App for Firebase

### Install FlutterFire CLI

```bash
dart pub global activate flutterfire_cli
```

### Configure Firebase for Flutter

```bash
# From the flutter_giftminder directory
flutterfire configure

# Select your Firebase project: giftminder-app
# Select platforms: iOS, Android
# This will create firebase_options.dart
```

## 4. Update main.dart

The `main.dart` has already been updated to include Firebase initialization:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const GiftMinderApp());
}
```

## 5. Firestore Database Structure

### Collections Setup

Create the following collections in Firestore:

#### `sponsored_gifts` Collection
```javascript
// Document structure
{
  "name": "Wireless Bluetooth Headphones",
  "description": "Premium noise-canceling headphones perfect for music lovers",
  "priceRange": "50_100",
  "exactPrice": 79.99,
  "category": "technology",
  "targetInterests": ["music", "technology", "fitness"],
  "targetAgeGroups": ["18_24", "25_34", "35_44"],
  "sponsorTier": "premium",
  "imageUrl": "https://example.com/headphones.jpg",
  "clickThroughUrl": "https://retailer.com/product/123",
  "affiliateUrl": "https://retailer.com/product/123?ref=giftminder",
  "commissionRate": 5.5,
  "vendorId": "vendor_amazon_123",
  "vendor": {
    "id": "vendor_amazon_123",
    "name": "Amazon",
    "logoUrl": "https://example.com/amazon-logo.png",
    "website": "https://amazon.com",
    "contactEmail": "partnerships@amazon.com",
    "status": "active",
    "partnerSince": "2024-01-01T00:00:00Z",
    "defaultCommissionRate": 5.0,
    "tier": "enterprise"
  },
  "activeFrom": "2024-01-01T00:00:00Z",
  "activeUntil": "2024-12-31T23:59:59Z",
  "isActive": true,
  "priority": 10,
  "ratings": {
    "averageRating": 4.5,
    "totalReviews": 1250,
    "ratingDistribution": {
      "1": 15,
      "2": 25,
      "3": 85,
      "4": 425,
      "5": 700
    }
  },
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-15T10:30:00Z"
}
```

#### `vendors` Collection
```javascript
{
  "name": "Amazon",
  "logoUrl": "https://example.com/amazon-logo.png",
  "website": "https://amazon.com",
  "contactEmail": "partnerships@amazon.com",
  "status": "active",
  "partnerSince": "2024-01-01T00:00:00Z",
  "defaultCommissionRate": 5.0,
  "tier": "enterprise"
}
```

#### `user_analytics` Collection
```javascript
// Document ID: anonymousUserId
{
  "anonymousId": "user_123456",
  "ageGroup": "25_34",
  "generalInterests": ["technology", "fitness", "books"],
  "preferredPriceRanges": ["25_50", "50_100"],
  "countryCode": "US",
  "consent": {
    "personalizedRecommendations": true,
    "analytics": true,
    "marketingCommunications": false,
    "sponsoredContent": true,
    "consentDate": "2024-01-01T00:00:00Z",
    "consentVersion": "1.0"
  },
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-01T00:00:00Z"
}
```

#### `gift_interactions` Collection
```javascript
{
  "giftId": "gift_headphones_123",
  "anonymousUserId": "user_123456",
  "type": "click",
  "timestamp": "2024-01-01T12:00:00Z",
  "userInterests": ["technology", "music"],
  "userAgeGroup": "25_34",
  "userPriceRange": "50_100",
  "sessionId": "session_789",
  "metadata": {
    "source": "recommendations",
    "position": 1
  }
}
```

## 6. Firestore Security Rules

Update Firestore security rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Public read access to sponsored gifts
    match /sponsored_gifts/{document} {
      allow read: if true;
      allow write: if false; // Only admins can write (via Admin SDK)
    }
    
    // Public read access to vendors
    match /vendors/{document} {
      allow read: if true;
      allow write: if false;
    }
    
    // User analytics - users can read/write their own data
    match /user_analytics/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Gift interactions - users can write their own interactions
    match /gift_interactions/{document} {
      allow read: if false; // Only backend can read
      allow write: if request.auth != null; // Authenticated users can track interactions
    }
  }
}
```

## 7. Firebase Analytics Events

### Custom Events Tracked

| Event Name | Parameters | Purpose |
|------------|------------|---------|
| `gift_interaction` | `interaction_type`, `gift_id`, `vendor_id`, `gift_category` | Track user engagement |
| `sponsored_click` | `gift_id`, `vendor_id`, `commission_rate`, `exact_price` | Revenue tracking |
| `gift_view` | `item_id`, `item_name`, `item_category`, `price` | Product impressions |
| `app_open` | Default parameters | Session tracking |
| `screen_view` | `screen_name` | Navigation tracking |
| `search` | `search_term` | Search analytics |

## 8. Sample Data Script

Create sample sponsored gifts for testing:

```bash
# Install Firebase Admin SDK for Node.js
npm init -y
npm install firebase-admin

# Create sample_data.js
```

```javascript
const admin = require('firebase-admin');
const serviceAccount = require('./path/to/serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function addSampleData() {
  // Add sample vendors
  const vendors = [
    {
      id: 'amazon',
      name: 'Amazon',
      logoUrl: 'https://example.com/amazon-logo.png',
      website: 'https://amazon.com',
      contactEmail: 'partnerships@amazon.com',
      status: 'active',
      partnerSince: new Date('2024-01-01'),
      defaultCommissionRate: 5.0,
      tier: 'enterprise'
    },
    {
      id: 'target',
      name: 'Target',
      logoUrl: 'https://example.com/target-logo.png',
      website: 'https://target.com',
      contactEmail: 'partnerships@target.com',
      status: 'active',
      partnerSince: new Date('2024-01-01'),
      defaultCommissionRate: 4.0,
      tier: 'premium'
    }
  ];

  for (const vendor of vendors) {
    await db.collection('vendors').doc(vendor.id).set(vendor);
  }

  // Add sample sponsored gifts
  const gifts = [
    {
      name: 'Wireless Bluetooth Headphones',
      description: 'Premium noise-canceling headphones perfect for music lovers',
      priceRange: '50_100',
      exactPrice: 79.99,
      category: 'technology',
      targetInterests: ['music', 'technology', 'fitness'],
      targetAgeGroups: ['18_24', '25_34', '35_44'],
      sponsorTier: 'premium',
      imageUrl: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e',
      clickThroughUrl: 'https://amazon.com/dp/B08EXAMPLE',
      affiliateUrl: 'https://amazon.com/dp/B08EXAMPLE?tag=giftminder-20',
      commissionRate: 5.5,
      vendorId: 'amazon',
      activeFrom: new Date('2024-01-01'),
      activeUntil: new Date('2024-12-31'),
      isActive: true,
      priority: 10,
      ratings: {
        averageRating: 4.5,
        totalReviews: 1250,
        ratingDistribution: {
          1: 15,
          2: 25,
          3: 85,
          4: 425,
          5: 700
        }
      }
    },
    {
      name: 'Coffee Table Book: Photography',
      description: 'Beautiful photography book perfect for coffee tables',
      priceRange: '25_50',
      exactPrice: 35.99,
      category: 'books',
      targetInterests: ['photography', 'art', 'books'],
      targetAgeGroups: ['25_34', '35_44', '45_54'],
      sponsorTier: 'standard',
      imageUrl: 'https://images.unsplash.com/photo-1481627834876-b7833e8f5570',
      clickThroughUrl: 'https://target.com/p/book-example',
      affiliateUrl: 'https://target.com/p/book-example?ref=giftminder',
      commissionRate: 4.0,
      vendorId: 'target',
      activeFrom: new Date('2024-01-01'),
      activeUntil: new Date('2024-12-31'),
      isActive: true,
      priority: 5,
      ratings: {
        averageRating: 4.2,
        totalReviews: 340,
        ratingDistribution: {
          1: 5,
          2: 10,
          3: 45,
          4: 120,
          5: 160
        }
      }
    }
  ];

  for (const gift of gifts) {
    await db.collection('sponsored_gifts').add(gift);
  }

  console.log('Sample data added successfully!');
}

addSampleData().catch(console.error);
```

## 9. Analytics Dashboard

### Firebase Analytics Dashboard

1. Go to Firebase Console → Analytics
2. Set up conversion events:
   - `sponsored_click` as conversion
   - `purchase` as conversion
3. Create custom audiences based on interests
4. Set up BigQuery export for advanced analytics

### Revenue Tracking

Track commission earnings:

```dart
// When user clicks sponsored link
await firebaseService.recordGiftInteraction(
  gift: sponsoredGift,
  type: InteractionType.click,
);

// When user makes purchase (via webhook or manual entry)
await firebaseService.recordPurchase(
  gift: sponsoredGift,
  actualPrice: 79.99,
  orderId: 'order_123456',
);
```

## 10. Testing

### Test Firebase Connection

```bash
cd flutter_giftminder
flutter run
```

### Verify Firebase Analytics

1. Use Firebase Analytics DebugView
2. Install app on test device
3. Enable debug mode:
   ```bash
   # Android
   adb shell setprop debug.firebase.analytics.app com.example.gift_minder
   
   # iOS - add to build scheme
   -FIRAnalyticsDebugEnabled
   ```

## 11. Production Considerations

### Environment Configuration

```dart
// Create separate Firebase projects for dev/staging/prod
class FirebaseConfig {
  static const String projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'giftminder-dev',
  );
}
```

### Privacy Compliance

1. Update privacy policy to mention data collection
2. Implement data export functionality
3. Implement data deletion functionality
4. Regular consent renewal prompts

### Performance

1. Use Firestore offline persistence
2. Implement proper caching strategies
3. Monitor Firebase usage costs
4. Implement query limits and pagination

## 12. Troubleshooting

### Common Issues

1. **Build errors**: Ensure all dependencies are properly installed
2. **Firebase connection**: Check internet connection and Firebase config
3. **Analytics not showing**: Enable debug mode and check device time
4. **Permissions**: Ensure proper Firestore security rules

### Debug Commands

```bash
# Check Firebase project status
firebase projects:list

# Test Firestore rules
firebase firestore:rules:test

# Deploy security rules
firebase deploy --only firestore:rules

# View Firebase logs
firebase functions:log
```

## Next Steps

1. Set up Firebase project using this guide
2. Add sample data for testing
3. Test consent flow and analytics
4. Configure vendor partnerships
5. Implement admin panel for managing sponsored content
6. Set up monitoring and alerts for revenue tracking