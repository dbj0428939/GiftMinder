import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/firebase_models.dart';
import '../models/contact.dart';

class FirebaseService extends ChangeNotifier {
  // Firebase instances
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collections
  static const String _sponsoredGiftsCollection = 'sponsored_gifts';
  static const String _vendorsCollection = 'vendors';
  static const String _analyticsCollection = 'user_analytics';
  static const String _interactionsCollection = 'gift_interactions';

  // Local state
  UserAnalyticsProfile? _userProfile;
  List<SponsoredGift> _sponsoredGifts = [];
  List<VendorInfo> _vendors = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _sessionId;

  // Getters
  UserAnalyticsProfile? get userProfile => _userProfile;
  List<SponsoredGift> get sponsoredGifts => List.unmodifiable(_sponsoredGifts);
  List<VendorInfo> get vendors => List.unmodifiable(_vendors);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasUserConsent => _userProfile?.consent.hasMarketingConsent ?? false;

  // Analytics getters
  static FirebaseAnalytics get analytics => _analytics;
  FirebaseAnalyticsObserver get analyticsObserver =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  FirebaseService() {
    _initializeService();
  }

  // Initialize Firebase service
  Future<void> _initializeService() async {
    _setLoading(true);
    try {
      await _loadUserProfile();
      if (hasUserConsent) {
        await _loadSponsoredContent();
        await _signInAnonymously();
      }
      _generateSessionId();
      _clearError();
    } catch (e) {
      _setError('Failed to initialize Firebase: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  // User Profile Management
  Future<void> _loadUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = prefs.getString('user_analytics_profile');

      if (profileJson != null) {
        final profileData = json.decode(profileJson);
        _userProfile = UserAnalyticsProfile.fromJson(profileData);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading user profile: $e');
      }
    }
  }

  Future<void> _saveUserProfile() async {
    if (_userProfile == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = json.encode(_userProfile!.toJson());
      await prefs.setString('user_analytics_profile', profileJson);

      // Sync to Firebase if user consented
      if (hasUserConsent) {
        await _syncUserProfileToFirebase();
      }
    } catch (e) {
      _setError('Failed to save user profile: ${e.toString()}');
    }
  }

  Future<void> _syncUserProfileToFirebase() async {
    if (_userProfile == null || !hasUserConsent) return;

    try {
      await _firestore
          .collection(_analyticsCollection)
          .doc(_userProfile!.anonymousId)
          .set(_userProfile!.toJson());
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing profile to Firebase: $e');
      }
    }
  }

  // Create or update user analytics profile
  Future<void> updateUserProfile({
    required AgeGroup ageGroup,
    required List<String> interests,
    required UserConsent consent,
    String? countryCode,
    List<PriceRange>? preferredPriceRanges,
  }) async {
    final generalInterests = InterestCategorizer.categorizeInterests(interests);

    _userProfile = _userProfile?.copyWith(
      ageGroup: ageGroup,
      generalInterests: generalInterests,
      preferredPriceRanges: preferredPriceRanges,
      countryCode: countryCode,
      consent: consent,
    ) ?? UserAnalyticsProfile(
      ageGroup: ageGroup,
      generalInterests: generalInterests,
      preferredPriceRanges: preferredPriceRanges ?? [],
      countryCode: countryCode,
      consent: consent,
    );

    await _saveUserProfile();

    // Load sponsored content if user now consents
    if (hasUserConsent && _sponsoredGifts.isEmpty) {
      await _loadSponsoredContent();
    }

    notifyListeners();
  }

  // Create profile from existing contact data
  Future<void> createProfileFromContacts(List<Contact> contacts) async {
    if (contacts.isEmpty) return;

    // Calculate aggregate data from contacts
    final allInterests = <String>[];
    final ages = <int>[];

    for (final contact in contacts) {
      allInterests.addAll(contact.interests);
      ages.add(contact.age);
    }

    // Calculate most common age group
    final averageAge = ages.isNotEmpty ? ages.reduce((a, b) => a + b) / ages.length : 25;
    final ageGroup = AgeGroup.fromAge(averageAge.round());

    // Get most common interests (limit to top 10)
    final interestCount = <String, int>{};
    for (final interest in allInterests) {
      interestCount[interest] = (interestCount[interest] ?? 0) + 1;
    }

    final sortedInterests = interestCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topInterests = sortedInterests
        .take(10)
        .map((e) => e.key)
        .toList();

    // Default consent (user will be prompted)
    final consent = UserConsent(
      personalizedRecommendations: false,
      analytics: false,
      marketingCommunications: false,
      sponsoredContent: false,
    );

    await updateUserProfile(
      ageGroup: ageGroup,
      interests: topInterests,
      consent: consent,
    );
  }

  // Sponsored Content Management
  Future<void> _loadSponsoredContent() async {
    if (!hasUserConsent) return;

    _setLoading(true);
    try {
      await Future.wait([
        _loadSponsoredGifts(),
        _loadVendors(),
      ]);
      _clearError();
    } catch (e) {
      _setError('Failed to load sponsored content: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadSponsoredGifts() async {
    try {
      final snapshot = await _firestore
          .collection(_sponsoredGiftsCollection)
          .where('isActive', isEqualTo: true)
          .where('activeUntil', isGreaterThan: Timestamp.now())
          .orderBy('activeUntil')
          .orderBy('priority', descending: true)
          .get();

      _sponsoredGifts = snapshot.docs
          .map((doc) => SponsoredGift.fromJson({
                ...doc.data(),
                'id': doc.id,
              }))
          .toList();

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading sponsored gifts: $e');
      }
    }
  }

  Future<void> _loadVendors() async {
    try {
      final snapshot = await _firestore
          .collection(_vendorsCollection)
          .where('status', isEqualTo: 'active')
          .get();

      _vendors = snapshot.docs
          .map((doc) => VendorInfo.fromJson({
                ...doc.data(),
                'id': doc.id,
              }))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading vendors: $e');
      }
    }
  }

  // Get personalized gift recommendations
  List<SponsoredGift> getPersonalizedRecommendations({
    int limit = 10,
    PriceRange? priceFilter,
    String? categoryFilter,
  }) {
    if (!hasUserConsent || _userProfile == null) return [];

    var filteredGifts = _sponsoredGifts.where((gift) => gift.isCurrentlyActive);

    // Apply filters
    if (priceFilter != null) {
      filteredGifts = filteredGifts.where((gift) => gift.priceRange == priceFilter);
    }

    if (categoryFilter != null) {
      filteredGifts = filteredGifts.where((gift) => gift.category == categoryFilter);
    }

    // Calculate match scores and sort
    final scoredGifts = filteredGifts
        .map((gift) => {
              'gift': gift,
              'score': gift.calculateMatchScore(_userProfile!),
            })
        .toList();

    scoredGifts.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    return scoredGifts
        .take(limit)
        .map((item) => item['gift'] as SponsoredGift)
        .toList();
  }

  // Get gifts by category
  List<SponsoredGift> getGiftsByCategory(String category, {int limit = 20}) {
    return _sponsoredGifts
        .where((gift) => gift.isCurrentlyActive && gift.category == category)
        .take(limit)
        .toList();
  }

  // Get featured gifts
  List<SponsoredGift> getFeaturedGifts({int limit = 5}) {
    return _sponsoredGifts
        .where((gift) =>
            gift.isCurrentlyActive && gift.sponsorTier == SponsorTier.featured)
        .take(limit)
        .toList();
  }

  // Analytics and Interaction Tracking
  Future<void> recordGiftInteraction({
    required SponsoredGift gift,
    required InteractionType type,
    Map<String, dynamic>? metadata,
  }) async {
    if (!hasUserConsent || _userProfile == null) return;

    try {
      final interaction = GiftInteraction(
        giftId: gift.id,
        anonymousUserId: _userProfile!.anonymousId,
        type: type,
        userInterests: _userProfile!.generalInterests,
        userAgeGroup: _userProfile!.ageGroup,
        userPriceRange: gift.priceRange,
        sessionId: _sessionId,
        metadata: metadata,
      );

      // Save to Firebase
      await _firestore
          .collection(_interactionsCollection)
          .add(interaction.toJson());

      // Track in Firebase Analytics
      await _analytics.logEvent(
        name: 'gift_interaction',
        parameters: {
          'interaction_type': type.name,
          'gift_id': gift.id,
          'vendor_id': gift.vendorId,
          'gift_category': gift.category,
          'price_range': gift.priceRange.name,
          'sponsor_tier': gift.sponsorTier.name,
        },
      );

      // Track click-through for revenue tracking
      if (type == InteractionType.click) {
        await _analytics.logEvent(
          name: 'sponsored_click',
          parameters: {
            'gift_id': gift.id,
            'vendor_id': gift.vendorId,
            'commission_rate': gift.commissionRate,
            'exact_price': gift.exactPrice,
          },
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error recording interaction: $e');
      }
    }
  }

  Future<void> recordPurchase({
    required SponsoredGift gift,
    required double actualPrice,
    String? orderId,
  }) async {
    if (!hasUserConsent) return;

    try {
      final commissionAmount = actualPrice * (gift.commissionRate / 100);

      await _analytics.logPurchase(
        currency: 'USD',
        value: actualPrice,
        parameters: {
          'gift_id': gift.id,
          'vendor_id': gift.vendorId,
          'commission_amount': commissionAmount,
          'order_id': orderId ?? '',
        },
      );

      await recordGiftInteraction(
        gift: gift,
        type: InteractionType.purchase,
        metadata: {
          'actual_price': actualPrice,
          'commission_amount': commissionAmount,
          'order_id': orderId,
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error recording purchase: $e');
      }
    }
  }

  // User engagement analytics
  Future<void> logAppOpen() async {
    await _analytics.logAppOpen();
    _generateSessionId();
  }

  Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }

  Future<void> logSearch(String searchTerm) async {
    if (!hasUserConsent) return;

    await _analytics.logSearch(searchTerm: searchTerm);
  }

  // Anonymous authentication for Firebase
  Future<void> _signInAnonymously() async {
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error signing in anonymously: $e');
      }
    }
  }

  // Session management
  void _generateSessionId() {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  }

  // Data export for GDPR compliance
  Future<Map<String, dynamic>> exportUserData() async {
    final data = <String, dynamic>{};

    if (_userProfile != null) {
      data['analytics_profile'] = _userProfile!.toJson();
    }

    if (hasUserConsent) {
      try {
        // Get user's interactions
        final interactions = await _firestore
            .collection(_interactionsCollection)
            .where('anonymousUserId', isEqualTo: _userProfile?.anonymousId)
            .get();

        data['interactions'] = interactions.docs
            .map((doc) => doc.data())
            .toList();
      } catch (e) {
        data['interactions'] = 'Error retrieving interaction data';
      }
    }

    return data;
  }

  // Delete user data (GDPR right to be forgotten)
  Future<void> deleteUserData() async {
    try {
      if (_userProfile != null) {
        // Delete from Firebase
        if (hasUserConsent) {
          await _firestore
              .collection(_analyticsCollection)
              .doc(_userProfile!.anonymousId)
              .delete();

          // Delete interactions
          final interactions = await _firestore
              .collection(_interactionsCollection)
              .where('anonymousUserId', isEqualTo: _userProfile!.anonymousId)
              .get();

          final batch = _firestore.batch();
          for (final doc in interactions.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }

        // Delete local data
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('user_analytics_profile');

        _userProfile = null;
        _sponsoredGifts.clear();
        _vendors.clear();

        notifyListeners();
      }
    } catch (e) {
      _setError('Failed to delete user data: ${e.toString()}');
    }
  }

  // Refresh sponsored content
  Future<void> refreshSponsoredContent() async {
    if (hasUserConsent) {
      await _loadSponsoredContent();
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    if (loading) _clearError();
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    _isLoading = false;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  @override
  void dispose() {
    // Clean up any subscriptions or listeners
    super.dispose();
  }
}

// Extension for easier analytics tracking
extension FirebaseAnalyticsExtensions on FirebaseAnalytics {
  Future<void> logGiftView(SponsoredGift gift) async {
    await logEvent(
      name: 'view_item',
      parameters: {
        'item_id': gift.id,
        'item_name': gift.name,
        'item_category': gift.category,
        'item_brand': gift.vendor.name,
        'price': gift.exactPrice,
        'currency': 'USD',
      },
    );
  }

  Future<void> logGiftClick(SponsoredGift gift) async {
    await logEvent(
      name: 'select_item',
      parameters: {
        'item_id': gift.id,
        'item_name': gift.name,
        'item_category': gift.category,
        'content_type': 'sponsored_gift',
      },
    );
  }

  Future<void> logPurchase({
    required String currency,
    required double value,
    Map<String, dynamic>? parameters,
  }) async {
    await logEvent(
      name: 'purchase',
      parameters: {
        'currency': currency,
        'value': value,
        ...?parameters,
      },
    );
  }
}
