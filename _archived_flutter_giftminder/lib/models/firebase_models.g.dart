// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'firebase_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserAnalyticsProfile _$UserAnalyticsProfileFromJson(
  Map<String, dynamic> json,
) => UserAnalyticsProfile(
  anonymousId: json['anonymousId'] as String?,
  ageGroup: $enumDecode(_$AgeGroupEnumMap, json['ageGroup']),
  generalInterests: (json['generalInterests'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  preferredPriceRanges: (json['preferredPriceRanges'] as List<dynamic>?)
      ?.map((e) => $enumDecode(_$PriceRangeEnumMap, e))
      .toList(),
  countryCode: json['countryCode'] as String?,
  consent: UserConsent.fromJson(json['consent'] as Map<String, dynamic>),
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$UserAnalyticsProfileToJson(
  UserAnalyticsProfile instance,
) => <String, dynamic>{
  'anonymousId': instance.anonymousId,
  'ageGroup': _$AgeGroupEnumMap[instance.ageGroup]!,
  'generalInterests': instance.generalInterests,
  'preferredPriceRanges': instance.preferredPriceRanges
      .map((e) => _$PriceRangeEnumMap[e]!)
      .toList(),
  'countryCode': instance.countryCode,
  'consent': instance.consent,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};

const _$AgeGroupEnumMap = {
  AgeGroup.under18: 'under_18',
  AgeGroup.age18to24: '18_24',
  AgeGroup.age25to34: '25_34',
  AgeGroup.age35to44: '35_44',
  AgeGroup.age45to54: '45_54',
  AgeGroup.age55to64: '55_64',
  AgeGroup.age65Plus: '65_plus',
};

const _$PriceRangeEnumMap = {
  PriceRange.under25: 'under_25',
  PriceRange.range25to50: '25_50',
  PriceRange.range50to100: '50_100',
  PriceRange.range100to250: '100_250',
  PriceRange.range250to500: '250_500',
  PriceRange.over500: 'over_500',
};

UserConsent _$UserConsentFromJson(Map<String, dynamic> json) => UserConsent(
  personalizedRecommendations: json['personalizedRecommendations'] as bool,
  analytics: json['analytics'] as bool,
  marketingCommunications: json['marketingCommunications'] as bool,
  sponsoredContent: json['sponsoredContent'] as bool,
  consentDate: json['consentDate'] == null
      ? null
      : DateTime.parse(json['consentDate'] as String),
  consentVersion: json['consentVersion'] as String? ?? '1.0',
);

Map<String, dynamic> _$UserConsentToJson(UserConsent instance) =>
    <String, dynamic>{
      'personalizedRecommendations': instance.personalizedRecommendations,
      'analytics': instance.analytics,
      'marketingCommunications': instance.marketingCommunications,
      'sponsoredContent': instance.sponsoredContent,
      'consentDate': instance.consentDate.toIso8601String(),
      'consentVersion': instance.consentVersion,
    };

SponsoredGift _$SponsoredGiftFromJson(Map<String, dynamic> json) =>
    SponsoredGift(
      id: json['id'] as String?,
      vendorId: json['vendorId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      priceRange: $enumDecode(_$PriceRangeEnumMap, json['priceRange']),
      exactPrice: (json['exactPrice'] as num).toDouble(),
      category: json['category'] as String,
      targetInterests: (json['targetInterests'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      targetAgeGroups: (json['targetAgeGroups'] as List<dynamic>?)
          ?.map((e) => $enumDecode(_$AgeGroupEnumMap, e))
          .toList(),
      sponsorTier: $enumDecode(_$SponsorTierEnumMap, json['sponsorTier']),
      imageUrl: json['imageUrl'] as String,
      clickThroughUrl: json['clickThroughUrl'] as String,
      affiliateUrl: json['affiliateUrl'] as String?,
      commissionRate: (json['commissionRate'] as num).toDouble(),
      vendor: VendorInfo.fromJson(json['vendor'] as Map<String, dynamic>),
      activeFrom: json['activeFrom'] == null
          ? null
          : DateTime.parse(json['activeFrom'] as String),
      activeUntil: json['activeUntil'] == null
          ? null
          : DateTime.parse(json['activeUntil'] as String),
      isActive: json['isActive'] as bool? ?? true,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      ratings: json['ratings'] == null
          ? null
          : GiftRatings.fromJson(json['ratings'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SponsoredGiftToJson(SponsoredGift instance) =>
    <String, dynamic>{
      'id': instance.id,
      'vendorId': instance.vendorId,
      'name': instance.name,
      'description': instance.description,
      'priceRange': _$PriceRangeEnumMap[instance.priceRange]!,
      'exactPrice': instance.exactPrice,
      'category': instance.category,
      'targetInterests': instance.targetInterests,
      'targetAgeGroups': instance.targetAgeGroups
          .map((e) => _$AgeGroupEnumMap[e]!)
          .toList(),
      'sponsorTier': _$SponsorTierEnumMap[instance.sponsorTier]!,
      'imageUrl': instance.imageUrl,
      'clickThroughUrl': instance.clickThroughUrl,
      'affiliateUrl': instance.affiliateUrl,
      'commissionRate': instance.commissionRate,
      'vendor': instance.vendor,
      'activeFrom': instance.activeFrom.toIso8601String(),
      'activeUntil': instance.activeUntil.toIso8601String(),
      'isActive': instance.isActive,
      'priority': instance.priority,
      'ratings': instance.ratings,
    };

const _$SponsorTierEnumMap = {
  SponsorTier.featured: 'featured',
  SponsorTier.premium: 'premium',
  SponsorTier.standard: 'standard',
};

VendorInfo _$VendorInfoFromJson(Map<String, dynamic> json) => VendorInfo(
  id: json['id'] as String?,
  name: json['name'] as String,
  logoUrl: json['logoUrl'] as String,
  website: json['website'] as String,
  contactEmail: json['contactEmail'] as String,
  status:
      $enumDecodeNullable(_$VendorStatusEnumMap, json['status']) ??
      VendorStatus.active,
  partnerSince: json['partnerSince'] == null
      ? null
      : DateTime.parse(json['partnerSince'] as String),
  defaultCommissionRate: (json['defaultCommissionRate'] as num).toDouble(),
  tier:
      $enumDecodeNullable(_$VendorTierEnumMap, json['tier']) ??
      VendorTier.standard,
);

Map<String, dynamic> _$VendorInfoToJson(VendorInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'logoUrl': instance.logoUrl,
      'website': instance.website,
      'contactEmail': instance.contactEmail,
      'status': _$VendorStatusEnumMap[instance.status]!,
      'partnerSince': instance.partnerSince.toIso8601String(),
      'defaultCommissionRate': instance.defaultCommissionRate,
      'tier': _$VendorTierEnumMap[instance.tier]!,
    };

const _$VendorStatusEnumMap = {
  VendorStatus.active: 'active',
  VendorStatus.inactive: 'inactive',
  VendorStatus.pending: 'pending',
  VendorStatus.suspended: 'suspended',
};

const _$VendorTierEnumMap = {
  VendorTier.enterprise: 'enterprise',
  VendorTier.premium: 'premium',
  VendorTier.standard: 'standard',
};

GiftInteraction _$GiftInteractionFromJson(Map<String, dynamic> json) =>
    GiftInteraction(
      id: json['id'] as String?,
      giftId: json['giftId'] as String,
      anonymousUserId: json['anonymousUserId'] as String,
      type: $enumDecode(_$InteractionTypeEnumMap, json['type']),
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
      userInterests: (json['userInterests'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      userAgeGroup: $enumDecode(_$AgeGroupEnumMap, json['userAgeGroup']),
      userPriceRange: $enumDecode(_$PriceRangeEnumMap, json['userPriceRange']),
      sessionId: json['sessionId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$GiftInteractionToJson(GiftInteraction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'giftId': instance.giftId,
      'anonymousUserId': instance.anonymousUserId,
      'type': _$InteractionTypeEnumMap[instance.type]!,
      'timestamp': instance.timestamp.toIso8601String(),
      'userInterests': instance.userInterests,
      'userAgeGroup': _$AgeGroupEnumMap[instance.userAgeGroup]!,
      'userPriceRange': _$PriceRangeEnumMap[instance.userPriceRange]!,
      'sessionId': instance.sessionId,
      'metadata': instance.metadata,
    };

const _$InteractionTypeEnumMap = {
  InteractionType.view: 'view',
  InteractionType.click: 'click',
  InteractionType.save: 'save',
  InteractionType.share: 'share',
  InteractionType.purchase: 'purchase',
};

GiftRatings _$GiftRatingsFromJson(Map<String, dynamic> json) => GiftRatings(
  averageRating: (json['averageRating'] as num).toDouble(),
  totalReviews: (json['totalReviews'] as num).toInt(),
  ratingDistribution: (json['ratingDistribution'] as Map<String, dynamic>?)
      ?.map((k, e) => MapEntry(int.parse(k), (e as num).toInt())),
);

Map<String, dynamic> _$GiftRatingsToJson(GiftRatings instance) =>
    <String, dynamic>{
      'averageRating': instance.averageRating,
      'totalReviews': instance.totalReviews,
      'ratingDistribution': instance.ratingDistribution.map(
        (k, e) => MapEntry(k.toString(), e),
      ),
    };
