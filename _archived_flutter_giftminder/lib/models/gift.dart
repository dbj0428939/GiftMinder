import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'contact.dart';

part 'gift.g.dart';

@JsonSerializable()
class Gift {
  final String id;
  final String name;
  final String description;
  final PriceRange price;
  final GiftCategory category;
  final List<AgeGroup> ageGroups;
  final List<String> interests;
  final String? imageUrl;
  final Retailer retailer;
  final String? productUrl;
  final GiftRatings ratings;
  final Availability availability;
  final List<String> tags;
  final bool isSponsored;
  final DateTime createdAt;

  Gift({
    String? id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    List<AgeGroup>? ageGroups,
    List<String>? interests,
    this.imageUrl,
    required this.retailer,
    this.productUrl,
    GiftRatings? ratings,
    this.availability = Availability.available,
    List<String>? tags,
    this.isSponsored = false,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       ageGroups = ageGroups ?? [],
       interests = interests?.map((i) => i.toLowerCase()).toList() ?? [],
       ratings = ratings ?? GiftRatings(),
       tags = tags?.map((t) => t.toLowerCase()).toList() ?? [],
       createdAt = createdAt ?? DateTime.now();

  factory Gift.fromJson(Map<String, dynamic> json) => _$GiftFromJson(json);
  Map<String, dynamic> toJson() => _$GiftToJson(this);

  String get formattedPrice {
    switch (price.type) {
      case PriceType.exact:
        return '\$${price.amount!.toStringAsFixed(2)}';
      case PriceType.range:
        return '\$${price.minAmount!.toStringAsFixed(0)} - \$${price.maxAmount!.toStringAsFixed(0)}';
      case PriceType.free:
        return 'Free';
      case PriceType.unknown:
        return 'Price varies';
    }
  }

  double matchScore(Contact contact) {
    double score = 0;

    // Interest matching (highest weight)
    final matchingInterests = interests
        .where(
          (interest) => contact.interests.any(
            (contactInterest) =>
                contactInterest.contains(interest) ||
                interest.contains(contactInterest),
          ),
        )
        .toList();
    score += matchingInterests.length * 3.0;

    // Age group matching
    final contactAgeGroup = AgeGroup.fromAge(contact.age);
    if (ageGroups.contains(contactAgeGroup) ||
        ageGroups.contains(AgeGroup.allAges)) {
      score += 2.0;
    }

    // Availability bonus
    if (availability == Availability.available) {
      score += 0.5;
    }

    // Rating bonus
    score += ratings.averageRating * 0.5;

    return score;
  }

  Gift copyWith({
    String? name,
    String? description,
    PriceRange? price,
    GiftCategory? category,
    List<AgeGroup>? ageGroups,
    List<String>? interests,
    String? imageUrl,
    Retailer? retailer,
    String? productUrl,
    GiftRatings? ratings,
    Availability? availability,
    List<String>? tags,
    bool? isSponsored,
  }) {
    return Gift(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      category: category ?? this.category,
      ageGroups: ageGroups ?? List<AgeGroup>.from(this.ageGroups),
      interests: interests ?? List<String>.from(this.interests),
      imageUrl: imageUrl ?? this.imageUrl,
      retailer: retailer ?? this.retailer,
      productUrl: productUrl ?? this.productUrl,
      ratings: ratings ?? this.ratings,
      availability: availability ?? this.availability,
      tags: tags ?? List<String>.from(this.tags),
      isSponsored: isSponsored ?? this.isSponsored,
      createdAt: createdAt,
    );
  }
}

@JsonSerializable()
class PriceRange {
  final PriceType type;
  final double? amount;
  final double? minAmount;
  final double? maxAmount;

  const PriceRange({
    required this.type,
    this.amount,
    this.minAmount,
    this.maxAmount,
  });

  const PriceRange.exact(this.amount)
    : type = PriceType.exact,
      minAmount = null,
      maxAmount = null;

  const PriceRange.range(this.minAmount, this.maxAmount)
    : type = PriceType.range,
      amount = null;

  const PriceRange.free()
    : type = PriceType.free,
      amount = null,
      minAmount = null,
      maxAmount = null;

  const PriceRange.unknown()
    : type = PriceType.unknown,
      amount = null,
      minAmount = null,
      maxAmount = null;

  factory PriceRange.fromJson(Map<String, dynamic> json) =>
      _$PriceRangeFromJson(json);
  Map<String, dynamic> toJson() => _$PriceRangeToJson(this);

  double get minPrice {
    switch (type) {
      case PriceType.exact:
        return amount ?? 0;
      case PriceType.range:
        return minAmount ?? 0;
      case PriceType.free:
        return 0;
      case PriceType.unknown:
        return 0;
    }
  }

  double get maxPrice {
    switch (type) {
      case PriceType.exact:
        return amount ?? 0;
      case PriceType.range:
        return maxAmount ?? double.infinity;
      case PriceType.free:
        return 0;
      case PriceType.unknown:
        return double.infinity;
    }
  }
}

enum PriceType {
  @JsonValue('exact')
  exact,
  @JsonValue('range')
  range,
  @JsonValue('free')
  free,
  @JsonValue('unknown')
  unknown,
}

enum GiftCategory {
  @JsonValue('electronics')
  electronics('Electronics', 'phone_android'),
  @JsonValue('books')
  books('Books', 'book'),
  @JsonValue('clothing')
  clothing('Clothing', 'checkroom'),
  @JsonValue('homeDecor')
  homeDecor('Home & Decor', 'home'),
  @JsonValue('sports')
  sports('Sports & Fitness', 'fitness_center'),
  @JsonValue('beauty')
  beauty('Beauty & Personal Care', 'spa'),
  @JsonValue('toys')
  toys('Toys & Games', 'toys'),
  @JsonValue('food')
  food('Food & Beverage', 'restaurant'),
  @JsonValue('jewelry')
  jewelry('Jewelry & Accessories', 'diamond'),
  @JsonValue('art')
  art('Art & Crafts', 'palette'),
  @JsonValue('music')
  music('Music & Instruments', 'music_note'),
  @JsonValue('travel')
  travel('Travel & Experiences', 'flight'),
  @JsonValue('gardening')
  gardening('Gardening', 'local_florist'),
  @JsonValue('automotive')
  automotive('Automotive', 'directions_car'),
  @JsonValue('pets')
  pets('Pet Supplies', 'pets'),
  @JsonValue('education')
  education('Education & Learning', 'school'),
  @JsonValue('health')
  health('Health & Wellness', 'favorite'),
  @JsonValue('other')
  other('Other', 'card_giftcard');

  const GiftCategory(this.displayName, this.iconName);

  final String displayName;
  final String iconName;

  static GiftCategory fromString(String value) {
    return GiftCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => GiftCategory.other,
    );
  }
}

enum AgeGroup {
  @JsonValue('child')
  child('Child (0-12)'),
  @JsonValue('teen')
  teen('Teen (13-19)'),
  @JsonValue('youngAdult')
  youngAdult('Young Adult (20-29)'),
  @JsonValue('adult')
  adult('Adult (30-49)'),
  @JsonValue('middleAged')
  middleAged('Middle-aged (50-64)'),
  @JsonValue('senior')
  senior('Senior (65+)'),
  @JsonValue('allAges')
  allAges('All Ages');

  const AgeGroup(this.displayName);

  final String displayName;

  static AgeGroup fromAge(int age) {
    if (age <= 12) return AgeGroup.child;
    if (age <= 19) return AgeGroup.teen;
    if (age <= 29) return AgeGroup.youngAdult;
    if (age <= 49) return AgeGroup.adult;
    if (age <= 64) return AgeGroup.middleAged;
    return AgeGroup.senior;
  }

  static AgeGroup fromString(String value) {
    return AgeGroup.values.firstWhere(
      (a) => a.name == value,
      orElse: () => AgeGroup.allAges,
    );
  }
}

@JsonSerializable()
class Retailer {
  final String name;
  final RetailerType type;
  final String? website;
  final bool isSponsored;
  final String? logoUrl;
  final double trustScore; // 0.0 to 5.0

  Retailer({
    required this.name,
    required this.type,
    this.website,
    this.isSponsored = false,
    this.logoUrl,
    this.trustScore = 3.0,
  });

  factory Retailer.fromJson(Map<String, dynamic> json) =>
      _$RetailerFromJson(json);
  Map<String, dynamic> toJson() => _$RetailerToJson(this);

  Retailer copyWith({
    String? name,
    RetailerType? type,
    String? website,
    bool? isSponsored,
    String? logoUrl,
    double? trustScore,
  }) {
    return Retailer(
      name: name ?? this.name,
      type: type ?? this.type,
      website: website ?? this.website,
      isSponsored: isSponsored ?? this.isSponsored,
      logoUrl: logoUrl ?? this.logoUrl,
      trustScore: trustScore ?? this.trustScore,
    );
  }
}

enum RetailerType {
  @JsonValue('majorRetailer')
  majorRetailer('Major Retailer', 'store'),
  @JsonValue('onlineMarketplace')
  onlineMarketplace('Online Marketplace', 'shopping_cart'),
  @JsonValue('localBusiness')
  localBusiness('Local Business', 'storefront'),
  @JsonValue('individualSeller')
  individualSeller('Individual Seller', 'person'),
  @JsonValue('brand')
  brand('Brand Direct', 'verified'),
  @JsonValue('specialty')
  specialty('Specialty Store', 'star');

  const RetailerType(this.displayName, this.iconName);

  final String displayName;
  final String iconName;

  static RetailerType fromString(String value) {
    return RetailerType.values.firstWhere(
      (r) => r.name == value,
      orElse: () => RetailerType.individualSeller,
    );
  }
}

@JsonSerializable()
class GiftRatings {
  final int totalRatings;
  final double averageRating;
  final int fiveStars;
  final int fourStars;
  final int threeStars;
  final int twoStars;
  final int oneStar;

  GiftRatings({
    this.totalRatings = 0,
    this.averageRating = 0.0,
    this.fiveStars = 0,
    this.fourStars = 0,
    this.threeStars = 0,
    this.twoStars = 0,
    this.oneStar = 0,
  });

  factory GiftRatings.fromJson(Map<String, dynamic> json) =>
      _$GiftRatingsFromJson(json);
  Map<String, dynamic> toJson() => _$GiftRatingsToJson(this);

  bool get hasRatings => totalRatings > 0;

  List<int> get starDistribution => [
    oneStar,
    twoStars,
    threeStars,
    fourStars,
    fiveStars,
  ];

  GiftRatings copyWith({
    int? totalRatings,
    double? averageRating,
    int? fiveStars,
    int? fourStars,
    int? threeStars,
    int? twoStars,
    int? oneStar,
  }) {
    return GiftRatings(
      totalRatings: totalRatings ?? this.totalRatings,
      averageRating: averageRating ?? this.averageRating,
      fiveStars: fiveStars ?? this.fiveStars,
      fourStars: fourStars ?? this.fourStars,
      threeStars: threeStars ?? this.threeStars,
      twoStars: twoStars ?? this.twoStars,
      oneStar: oneStar ?? this.oneStar,
    );
  }
}

enum Availability {
  @JsonValue('available')
  available('Available', 'check_circle'),
  @JsonValue('limitedStock')
  limitedStock('Limited Stock', 'warning'),
  @JsonValue('preOrder')
  preOrder('Pre-order', 'schedule'),
  @JsonValue('outOfStock')
  outOfStock('Out of Stock', 'cancel'),
  @JsonValue('discontinued')
  discontinued('Discontinued', 'block');

  const Availability(this.displayName, this.iconName);

  final String displayName;
  final String iconName;

  static Availability fromString(String value) {
    return Availability.values.firstWhere(
      (a) => a.name == value,
      orElse: () => Availability.available,
    );
  }
}

@JsonSerializable()
class GiftRecommendation {
  final String id;
  final Gift gift;
  final String contactId;
  final double matchScore;
  final List<RecommendationReason> reasons;
  final ConfidenceLevel confidence;
  final DateTime generatedAt;

  GiftRecommendation({
    String? id,
    required this.gift,
    required this.contactId,
    required this.matchScore,
    List<RecommendationReason>? reasons,
    ConfidenceLevel? confidence,
    DateTime? generatedAt,
  }) : id = id ?? const Uuid().v4(),
       reasons = reasons ?? [],
       confidence = confidence ?? ConfidenceLevel.fromScore(matchScore),
       generatedAt = generatedAt ?? DateTime.now();

  factory GiftRecommendation.fromJson(Map<String, dynamic> json) =>
      _$GiftRecommendationFromJson(json);
  Map<String, dynamic> toJson() => _$GiftRecommendationToJson(this);

  static List<RecommendationReason> generateReasons(
    Gift gift,
    Contact contact,
  ) {
    final List<RecommendationReason> reasons = [];

    // Check for interest matches
    final matchingInterests = gift.interests
        .where(
          (interest) => contact.interests.any(
            (contactInterest) =>
                contactInterest.contains(interest) ||
                interest.contains(contactInterest),
          ),
        )
        .toList();

    if (matchingInterests.isNotEmpty) {
      reasons.add(RecommendationReason.interestMatch);
    }

    // Check age appropriateness
    final contactAgeGroup = AgeGroup.fromAge(contact.age);
    if (gift.ageGroups.contains(contactAgeGroup) ||
        gift.ageGroups.contains(AgeGroup.allAges)) {
      reasons.add(RecommendationReason.ageAppropriate);
    }

    // Check ratings
    if (gift.ratings.hasRatings && gift.ratings.averageRating >= 4.0) {
      reasons.add(RecommendationReason.highlyRated);
    }

    // Check for sponsorship/uniqueness
    if (gift.isSponsored || gift.retailer.type == RetailerType.specialty) {
      reasons.add(RecommendationReason.unique);
    }

    // Check price appropriateness
    if (gift.price.type == PriceType.free || gift.price.maxPrice < 100) {
      reasons.add(RecommendationReason.priceRange);
    }

    return reasons;
  }
}

enum RecommendationReason {
  @JsonValue('interestMatch')
  interestMatch('Matches their interests'),
  @JsonValue('ageAppropriate')
  ageAppropriate('Perfect for their age group'),
  @JsonValue('highlyRated')
  highlyRated('Highly rated by others'),
  @JsonValue('trending')
  trending('Currently trending'),
  @JsonValue('priceRange')
  priceRange('Within suggested price range'),
  @JsonValue('previousGift')
  previousGift('Similar to previous successful gifts'),
  @JsonValue('seasonal')
  seasonal('Perfect for the season'),
  @JsonValue('unique')
  unique('Something unique and special');

  const RecommendationReason(this.displayText);

  final String displayText;

  static RecommendationReason fromString(String value) {
    return RecommendationReason.values.firstWhere(
      (r) => r.name == value,
      orElse: () => RecommendationReason.unique,
    );
  }
}

enum ConfidenceLevel {
  @JsonValue('low')
  low('Low'),
  @JsonValue('medium')
  medium('Medium'),
  @JsonValue('high')
  high('High'),
  @JsonValue('veryHigh')
  veryHigh('Very High');

  const ConfidenceLevel(this.displayName);

  final String displayName;

  static ConfidenceLevel fromScore(double score) {
    if (score < 2) return ConfidenceLevel.low;
    if (score < 5) return ConfidenceLevel.medium;
    if (score < 8) return ConfidenceLevel.high;
    return ConfidenceLevel.veryHigh;
  }

  static ConfidenceLevel fromString(String value) {
    return ConfidenceLevel.values.firstWhere(
      (c) => c.name == value,
      orElse: () => ConfidenceLevel.low,
    );
  }
}
