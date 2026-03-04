// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Contact _$ContactFromJson(Map<String, dynamic> json) => Contact(
  id: json['id'] as String?,
  name: json['name'] as String,
  dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
  relationship: $enumDecode(_$RelationshipEnumMap, json['relationship']),
  interests: (json['interests'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  notes: json['notes'] as String? ?? '',
  photoPath: json['photoPath'] as String?,
  giftHistory: (json['giftHistory'] as List<dynamic>?)
      ?.map((e) => GiftHistory.fromJson(e as Map<String, dynamic>))
      .toList(),
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$ContactToJson(Contact instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'dateOfBirth': instance.dateOfBirth.toIso8601String(),
  'relationship': _$RelationshipEnumMap[instance.relationship]!,
  'interests': instance.interests,
  'notes': instance.notes,
  'photoPath': instance.photoPath,
  'giftHistory': instance.giftHistory,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};

const _$RelationshipEnumMap = {
  Relationship.family: 'family',
  Relationship.friend: 'friend',
  Relationship.colleague: 'colleague',
  Relationship.partner: 'partner',
  Relationship.other: 'other',
};

GiftHistory _$GiftHistoryFromJson(Map<String, dynamic> json) => GiftHistory(
  id: json['id'] as String?,
  giftName: json['giftName'] as String,
  giftDescription: json['giftDescription'] as String?,
  price: (json['price'] as num?)?.toDouble(),
  purchaseDate: json['purchaseDate'] == null
      ? null
      : DateTime.parse(json['purchaseDate'] as String),
  occasion: json['occasion'] as String,
  retailer: json['retailer'] as String?,
  rating: (json['rating'] as num?)?.toInt(),
  notes: json['notes'] as String?,
);

Map<String, dynamic> _$GiftHistoryToJson(GiftHistory instance) =>
    <String, dynamic>{
      'id': instance.id,
      'giftName': instance.giftName,
      'giftDescription': instance.giftDescription,
      'price': instance.price,
      'purchaseDate': instance.purchaseDate.toIso8601String(),
      'occasion': instance.occasion,
      'retailer': instance.retailer,
      'rating': instance.rating,
      'notes': instance.notes,
    };
