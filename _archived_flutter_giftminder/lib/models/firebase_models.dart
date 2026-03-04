import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'firebase_models.g.dart';

// User preferences for anonymous analytics and targeting
@JsonSerializable()
class UserAnalyticsProfile {
  final String anonymousId;
  final AgeGroup ageGroup;
  final List<String> generalInterests;
  final List<PriceRange> preferredPriceRanges;
  final String? countryCode;
  final UserConsent consent;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserAnalyticsProfile({
    String? anonymousId,
    required this.ageGroup,
    List<String>? generalInterests,
    List<PriceRange>? preferredPriceRanges,
    this.countryCode,
    required this.consent,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : anonymousId = anonymousId ?? const Uuid().v4(),
        generalInterests = generalInterests ?? [],
        preferredPriceRanges = preferredPriceRanges ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory UserAnalyticsProfile.fromJson(Map<String, dynamic> json) =>
      _$UserAnalyticsProfileFromJson(json);
  Map<String, dynamic> toJson() => _$UserAnalyticsProfileToJson(this);

  UserAnalyticsProfile copyWith({
    AgeGroup? ageGroup,
    List<String>? generalInterests,
    List<PriceRange>? preferredPriceRanges,
    String? countryCode,
    UserConsent? consent,
  }) {
    return UserAnalyticsProfile(
      anonymousId: anonymousId,
      ageGroup: ageGroup ?? this.ageGroup,
      generalInterests: generalInterests ?? List.from(this.generalInterests),
      preferredPriceRanges: preferredPriceRanges ?? List.from(this.preferredPriceRanges),
      countryCode: countryCode ?? this.countryCode,
      consent: consent ?? this.consent,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

@JsonSerializable()
class UserConsent {
  final bool personalizedRecommendations;
  final bool analytics;
  final bool marketingCommunications;
  final bool sponsoredContent;
  final DateTime consentDate;
  final String consentVersion;

  UserConsent({
    required this.personalizedRecommendations,
    required this.analytics,
    required this.marketingCommunications,
    required this.sponsoredContent,
    DateTime? consentDate,
    this.consentVersion = '1.0',
  }) : consentDate = consentDate ?? DateTime.now();

  factory UserConsent.fromJson(Map<String, dynamic> json) =>
      _$UserConsentFromJson(json);
  Map<String, dynamic> toJson() => _$UserConsentToJson(this);

  bool get hasMarketingConsent =>
      personalizedRecommendations && analytics && sponsoredContent;

  UserConsent copyWith({
    bool? personalizedRecommendations,
    bool? analytics,
    bool? marketingCommunications,
    bool? sponsoredContent,
    String? consentVersion,
  }) {
    return UserConsent(
      personalizedRecommendations: personalizedRecommendations ?? this.personalizedRecommendations,
      analytics: analytics ?? this.analytics,
      marketingCommunications: marketingCommunications ?? this.marketingCommunications,
      sponsoredContent: sponsoredContent ?? this.sponsoredContent,
      consentDate: DateTime.now(),
      consentVersion: consentVersion ?? this.consentVersion,
    );
  }
}

@JsonSerializable()
class SponsoredGift {
  final String id;
  final String vendorId;
  final String name;
  final String description;
  final PriceRange priceRange;
  final double exactPrice;
  final String category;
  final List<String> targetInterests;
  final List<AgeGroup> targetAgeGroups;
  final SponsorTier sponsorTier;
  final String imageUrl;
  final String clickThroughUrl;
  final String? affiliateUrl;
  final double commissionRate;
  final VendorInfo vendor;
  final DateTime activeFrom;
  final DateTime activeUntil;
  final bool isActive;
  final int priority;
  final GiftRatings? ratings;

  SponsoredGift({
    String? id,
    required this.vendorId,
    required this.name,
    required this.description,
    required this.priceRange,
    required this.exactPrice,
    required this.category,
    List<String>? targetInterests,
    List<AgeGroup>? targetAgeGroups,
    required this.sponsorTier,
    required this.imageUrl,
    required this.clickThroughUrl,
    this.affiliateUrl,
    required this.commissionRate,
    required this.vendor,
    DateTime? activeFrom,
    DateTime? activeUntil,
    this.isActive = true,
    this.priority = 0,
    this.ratings,
  })  : id = id ?? const Uuid().v4(),
        targetInterests = targetInterests ?? [],
        targetAgeGroups = targetAgeGroups ?? [],
        activeFrom = activeFrom ?? DateTime.now(),
        activeUntil = activeUntil ?? DateTime.now().add(const Duration(days: 30));

  factory SponsoredGift.fromJson(Map<String, dynamic> json) =>
      _$SponsoredGiftFromJson(json);
  Map<String, dynamic> toJson() => _$SponsoredGiftToJson(this);

  bool get isCurrentlyActive {
    final now = DateTime.now();
    return isActive &&
           now.isAfter(activeFrom) &&
           now.isBefore(activeUntil);
  }

  double calculateMatchScore(UserAnalyticsProfile profile) {
    double score = 0.0;

    // Interest matching (highest weight)
    final matchingInterests = targetInterests
        .where((interest) => profile.generalInterests.contains(interest))
        .length;
    score += matchingInterests * 3.0;

    // Age group matching
    if (targetAgeGroups.contains(profile.ageGroup)) {
      score += 2.0;
    }

    // Price range matching
    if (profile.preferredPriceRanges.contains(priceRange)) {
      score += 1.5;
    }

    // Sponsor tier bonus
    score += sponsorTier.priorityBonus;

    // Ratings bonus
    if (ratings != null) {
      score += ratings!.averageRating * 0.5;
    }

    return score;
  }

  String get formattedPrice => '\$${exactPrice.toStringAsFixed(2)}';
}

@JsonSerializable()
class VendorInfo {
  final String id;
  final String name;
  final String logoUrl;
  final String website;
  final String contactEmail;
  final VendorStatus status;
  final DateTime partnerSince;
  final double defaultCommissionRate;
  final VendorTier tier;

  VendorInfo({
    String? id,
    required this.name,
    required this.logoUrl,
    required this.website,
    required this.contactEmail,
    this.status = VendorStatus.active,
    DateTime? partnerSince,
    required this.defaultCommissionRate,
    this.tier = VendorTier.standard,
  })  : id = id ?? const Uuid().v4(),
        partnerSince = partnerSince ?? DateTime.now();

  factory VendorInfo.fromJson(Map<String, dynamic> json) =>
      _$VendorInfoFromJson(json);
  Map<String, dynamic> toJson() => _$VendorInfoToJson(this);

  bool get isActive => status == VendorStatus.active;
}

@JsonSerializable()
class GiftInteraction {
  final String id;
  final String giftId;
  final String anonymousUserId;
  final InteractionType type;
  final DateTime timestamp;
  final List<String> userInterests;
  final AgeGroup userAgeGroup;
  final PriceRange userPriceRange;
  final String? sessionId;
  final Map<String, dynamic>? metadata;

  GiftInteraction({
    String? id,
    required this.giftId,
    required this.anonymousUserId,
    required this.type,
    DateTime? timestamp,
    List<String>? userInterests,
    required this.userAgeGroup,
    required this.userPriceRange,
    this.sessionId,
    this.metadata,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now(),
        userInterests = userInterests ?? [];

  factory GiftInteraction.fromJson(Map<String, dynamic> json) =>
      _$GiftInteractionFromJson(json);
  Map<String, dynamic> toJson() => _$GiftInteractionToJson(this);
}

@JsonSerializable()
class GiftRatings {
  final double averageRating;
  final int totalReviews;
  final Map<int, int> ratingDistribution; // star count -> number of reviews

  GiftRatings({
    required this.averageRating,
    required this.totalReviews,
    Map<int, int>? ratingDistribution,
  }) : ratingDistribution = ratingDistribution ?? {};

  factory GiftRatings.fromJson(Map<String, dynamic> json) =>
      _$GiftRatingsFromJson(json);
  Map<String, dynamic> toJson() => _$GiftRatingsToJson(this);

  String get formattedRating => '${averageRating.toStringAsFixed(1)} ★';
}

// Enums
enum AgeGroup {
  @JsonValue('under_18')
  under18,
  @JsonValue('18_24')
  age18to24,
  @JsonValue('25_34')
  age25to34,
  @JsonValue('35_44')
  age35to44,
  @JsonValue('45_54')
  age45to54,
  @JsonValue('55_64')
  age55to64,
  @JsonValue('65_plus')
  age65Plus;

  static AgeGroup fromAge(int age) {
    if (age < 18) return AgeGroup.under18;
    if (age < 25) return AgeGroup.age18to24;
    if (age < 35) return AgeGroup.age25to34;
    if (age < 45) return AgeGroup.age35to44;
    if (age < 55) return AgeGroup.age45to54;
    if (age < 65) return AgeGroup.age55to64;
    return AgeGroup.age65Plus;
  }

  String get displayName {
    switch (this) {
      case AgeGroup.under18:
        return 'Under 18';
      case AgeGroup.age18to24:
        return '18-24';
      case AgeGroup.age25to34:
        return '25-34';
      case AgeGroup.age35to44:
        return '35-44';
      case AgeGroup.age45to54:
        return '45-54';
      case AgeGroup.age55to64:
        return '55-64';
      case AgeGroup.age65Plus:
        return '65+';
    }
  }
}

enum PriceRange {
  @JsonValue('under_25')
  under25,
  @JsonValue('25_50')
  range25to50,
  @JsonValue('50_100')
  range50to100,
  @JsonValue('100_250')
  range100to250,
  @JsonValue('250_500')
  range250to500,
  @JsonValue('over_500')
  over500;

  String get displayName {
    switch (this) {
      case PriceRange.under25:
        return 'Under \$25';
      case PriceRange.range25to50:
        return '\$25-\$50';
      case PriceRange.range50to100:
        return '\$50-\$100';
      case PriceRange.range100to250:
        return '\$100-\$250';
      case PriceRange.range250to500:
        return '\$250-\$500';
      case PriceRange.over500:
        return 'Over \$500';
    }
  }

  static PriceRange fromPrice(double price) {
    if (price < 25) return PriceRange.under25;
    if (price < 50) return PriceRange.range25to50;
    if (price < 100) return PriceRange.range50to100;
    if (price < 250) return PriceRange.range100to250;
    if (price < 500) return PriceRange.range250to500;
    return PriceRange.over500;
  }

  bool containsPrice(double price) {
    switch (this) {
      case PriceRange.under25:
        return price < 25;
      case PriceRange.range25to50:
        return price >= 25 && price < 50;
      case PriceRange.range50to100:
        return price >= 50 && price < 100;
      case PriceRange.range100to250:
        return price >= 100 && price < 250;
      case PriceRange.range250to500:
        return price >= 250 && price < 500;
      case PriceRange.over500:
        return price >= 500;
    }
  }
}

enum SponsorTier {
  @JsonValue('featured')
  featured,
  @JsonValue('premium')
  premium,
  @JsonValue('standard')
  standard;

  String get displayName {
    switch (this) {
      case SponsorTier.featured:
        return 'Featured';
      case SponsorTier.premium:
        return 'Premium';
      case SponsorTier.standard:
        return 'Standard';
    }
  }

  double get priorityBonus {
    switch (this) {
      case SponsorTier.featured:
        return 2.0;
      case SponsorTier.premium:
        return 1.0;
      case SponsorTier.standard:
        return 0.0;
    }
  }
}

enum VendorStatus {
  @JsonValue('active')
  active,
  @JsonValue('inactive')
  inactive,
  @JsonValue('pending')
  pending,
  @JsonValue('suspended')
  suspended;
}

enum VendorTier {
  @JsonValue('enterprise')
  enterprise,
  @JsonValue('premium')
  premium,
  @JsonValue('standard')
  standard;
}

enum InteractionType {
  @JsonValue('view')
  view,
  @JsonValue('click')
  click,
  @JsonValue('save')
  save,
  @JsonValue('share')
  share,
  @JsonValue('purchase')
  purchase;

  String get displayName {
    switch (this) {
      case InteractionType.view:
        return 'Viewed';
      case InteractionType.click:
        return 'Clicked';
      case InteractionType.save:
        return 'Saved';
      case InteractionType.share:
        return 'Shared';
      case InteractionType.purchase:
        return 'Purchased';
    }
  }
}

// Helper class for interest categorization
class InterestCategorizer {
  static const Map<String, List<String>> _categoryMap = {
    'technology': [
      'iphone', 'android', 'computer', 'laptop', 'tablet', 'gaming',
      'tech', 'electronics', 'gadgets', 'smartphone', 'smart home',
      'ai', 'programming', 'coding', 'software'
    ],
    'fitness': [
      'gym', 'yoga', 'running', 'fitness', 'workout', 'exercise',
      'sports', 'health', 'nutrition', 'cycling', 'swimming', 'hiking'
    ],
    'arts': [
      'painting', 'drawing', 'art', 'photography', 'music', 'guitar',
      'piano', 'singing', 'dance', 'theater', 'crafts', 'pottery'
    ],
    'books': [
      'reading', 'books', 'literature', 'writing', 'novels', 'poetry',
      'biography', 'history', 'science fiction', 'mystery'
    ],
    'travel': [
      'travel', 'vacation', 'adventure', 'backpacking', 'camping',
      'hiking', 'beach', 'mountains', 'culture', 'languages'
    ],
    'food': [
      'cooking', 'baking', 'food', 'restaurant', 'cuisine', 'wine',
      'coffee', 'tea', 'gourmet', 'vegetarian', 'vegan'
    ],
    'fashion': [
      'fashion', 'clothing', 'style', 'shoes', 'jewelry', 'accessories',
      'makeup', 'beauty', 'skincare', 'perfume'
    ],
    'home': [
      'home decor', 'interior design', 'gardening', 'plants', 'furniture',
      'organization', 'cleaning', 'diy', 'renovation'
    ]
  };

  static List<String> categorizeInterests(List<String> specificInterests) {
    final Set<String> categories = {};

    for (final interest in specificInterests) {
      final lowerInterest = interest.toLowerCase();
      for (final category in _categoryMap.keys) {
        if (_categoryMap[category]!.any((keyword) =>
            lowerInterest.contains(keyword))) {
          categories.add(category);
        }
      }
    }

    return categories.toList();
  }

  static String? categorizeInterest(String interest) {
    final lowerInterest = interest.toLowerCase();
    for (final category in _categoryMap.keys) {
      if (_categoryMap[category]!.any((keyword) =>
          lowerInterest.contains(keyword))) {
        return category;
      }
    }
    return 'other';
  }
}
