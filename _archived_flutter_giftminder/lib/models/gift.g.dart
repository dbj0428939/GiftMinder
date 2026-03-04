// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gift.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Gift _$GiftFromJson(Map<String, dynamic> json) => Gift(
  id: json['id'] as String?,
  name: json['name'] as String,
  description: json['description'] as String,
  price: PriceRange.fromJson(json['price'] as Map<String, dynamic>),
  category: $enumDecode(_$GiftCategoryEnumMap, json['category']),
  ageGroups: (json['ageGroups'] as List<dynamic>?)
      ?.map((e) => $enumDecode(_$AgeGroupEnumMap, e))
      .toList(),
  interests: (json['interests'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  imageUrl: json['imageUrl'] as String?,
  retailer: Retailer.fromJson(json['retailer'] as Map<String, dynamic>),
  productUrl: json['productUrl'] as String?,
  ratings: json['ratings'] == null
      ? null
      : GiftRatings.fromJson(json['ratings'] as Map<String, dynamic>),
  availability:
      $enumDecodeNullable(_$AvailabilityEnumMap, json['availability']) ??
      Availability.available,
  tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
  isSponsored: json['isSponsored'] as bool? ?? false,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$GiftToJson(Gift instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'price': instance.price,
  'category': _$GiftCategoryEnumMap[instance.category]!,
  'ageGroups': instance.ageGroups.map((e) => _$AgeGroupEnumMap[e]!).toList(),
  'interests': instance.interests,
  'imageUrl': instance.imageUrl,
  'retailer': instance.retailer,
  'productUrl': instance.productUrl,
  'ratings': instance.ratings,
  'availability': _$AvailabilityEnumMap[instance.availability]!,
  'tags': instance.tags,
  'isSponsored': instance.isSponsored,
  'createdAt': instance.createdAt.toIso8601String(),
};

const _$GiftCategoryEnumMap = {
  GiftCategory.electronics: 'electronics',
  GiftCategory.books: 'books',
  GiftCategory.clothing: 'clothing',
  GiftCategory.homeDecor: 'homeDecor',
  GiftCategory.sports: 'sports',
  GiftCategory.beauty: 'beauty',
  GiftCategory.toys: 'toys',
  GiftCategory.food: 'food',
  GiftCategory.jewelry: 'jewelry',
  GiftCategory.art: 'art',
  GiftCategory.music: 'music',
  GiftCategory.travel: 'travel',
  GiftCategory.gardening: 'gardening',
  GiftCategory.automotive: 'automotive',
  GiftCategory.pets: 'pets',
  GiftCategory.education: 'education',
  GiftCategory.health: 'health',
  GiftCategory.other: 'other',
};

const _$AgeGroupEnumMap = {
  AgeGroup.child: 'child',
  AgeGroup.teen: 'teen',
  AgeGroup.youngAdult: 'youngAdult',
  AgeGroup.adult: 'adult',
  AgeGroup.middleAged: 'middleAged',
  AgeGroup.senior: 'senior',
  AgeGroup.allAges: 'allAges',
};

const _$AvailabilityEnumMap = {
  Availability.available: 'available',
  Availability.limitedStock: 'limitedStock',
  Availability.preOrder: 'preOrder',
  Availability.outOfStock: 'outOfStock',
  Availability.discontinued: 'discontinued',
};

PriceRange _$PriceRangeFromJson(Map<String, dynamic> json) => PriceRange(
  type: $enumDecode(_$PriceTypeEnumMap, json['type']),
  amount: (json['amount'] as num?)?.toDouble(),
  minAmount: (json['minAmount'] as num?)?.toDouble(),
  maxAmount: (json['maxAmount'] as num?)?.toDouble(),
);

Map<String, dynamic> _$PriceRangeToJson(PriceRange instance) =>
    <String, dynamic>{
      'type': _$PriceTypeEnumMap[instance.type]!,
      'amount': instance.amount,
      'minAmount': instance.minAmount,
      'maxAmount': instance.maxAmount,
    };

const _$PriceTypeEnumMap = {
  PriceType.exact: 'exact',
  PriceType.range: 'range',
  PriceType.free: 'free',
  PriceType.unknown: 'unknown',
};

Retailer _$RetailerFromJson(Map<String, dynamic> json) => Retailer(
  name: json['name'] as String,
  type: $enumDecode(_$RetailerTypeEnumMap, json['type']),
  website: json['website'] as String?,
  isSponsored: json['isSponsored'] as bool? ?? false,
  logoUrl: json['logoUrl'] as String?,
  trustScore: (json['trustScore'] as num?)?.toDouble() ?? 3.0,
);

Map<String, dynamic> _$RetailerToJson(Retailer instance) => <String, dynamic>{
  'name': instance.name,
  'type': _$RetailerTypeEnumMap[instance.type]!,
  'website': instance.website,
  'isSponsored': instance.isSponsored,
  'logoUrl': instance.logoUrl,
  'trustScore': instance.trustScore,
};

const _$RetailerTypeEnumMap = {
  RetailerType.majorRetailer: 'majorRetailer',
  RetailerType.onlineMarketplace: 'onlineMarketplace',
  RetailerType.localBusiness: 'localBusiness',
  RetailerType.individualSeller: 'individualSeller',
  RetailerType.brand: 'brand',
  RetailerType.specialty: 'specialty',
};

GiftRatings _$GiftRatingsFromJson(Map<String, dynamic> json) => GiftRatings(
  totalRatings: (json['totalRatings'] as num?)?.toInt() ?? 0,
  averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
  fiveStars: (json['fiveStars'] as num?)?.toInt() ?? 0,
  fourStars: (json['fourStars'] as num?)?.toInt() ?? 0,
  threeStars: (json['threeStars'] as num?)?.toInt() ?? 0,
  twoStars: (json['twoStars'] as num?)?.toInt() ?? 0,
  oneStar: (json['oneStar'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$GiftRatingsToJson(GiftRatings instance) =>
    <String, dynamic>{
      'totalRatings': instance.totalRatings,
      'averageRating': instance.averageRating,
      'fiveStars': instance.fiveStars,
      'fourStars': instance.fourStars,
      'threeStars': instance.threeStars,
      'twoStars': instance.twoStars,
      'oneStar': instance.oneStar,
    };

GiftRecommendation _$GiftRecommendationFromJson(Map<String, dynamic> json) =>
    GiftRecommendation(
      id: json['id'] as String?,
      gift: Gift.fromJson(json['gift'] as Map<String, dynamic>),
      contactId: json['contactId'] as String,
      matchScore: (json['matchScore'] as num).toDouble(),
      reasons: (json['reasons'] as List<dynamic>?)
          ?.map((e) => $enumDecode(_$RecommendationReasonEnumMap, e))
          .toList(),
      confidence: $enumDecodeNullable(
        _$ConfidenceLevelEnumMap,
        json['confidence'],
      ),
      generatedAt: json['generatedAt'] == null
          ? null
          : DateTime.parse(json['generatedAt'] as String),
    );

Map<String, dynamic> _$GiftRecommendationToJson(GiftRecommendation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'gift': instance.gift,
      'contactId': instance.contactId,
      'matchScore': instance.matchScore,
      'reasons': instance.reasons
          .map((e) => _$RecommendationReasonEnumMap[e]!)
          .toList(),
      'confidence': _$ConfidenceLevelEnumMap[instance.confidence]!,
      'generatedAt': instance.generatedAt.toIso8601String(),
    };

const _$RecommendationReasonEnumMap = {
  RecommendationReason.interestMatch: 'interestMatch',
  RecommendationReason.ageAppropriate: 'ageAppropriate',
  RecommendationReason.highlyRated: 'highlyRated',
  RecommendationReason.trending: 'trending',
  RecommendationReason.priceRange: 'priceRange',
  RecommendationReason.previousGift: 'previousGift',
  RecommendationReason.seasonal: 'seasonal',
  RecommendationReason.unique: 'unique',
};

const _$ConfidenceLevelEnumMap = {
  ConfidenceLevel.low: 'low',
  ConfidenceLevel.medium: 'medium',
  ConfidenceLevel.high: 'high',
  ConfidenceLevel.veryHigh: 'veryHigh',
};
