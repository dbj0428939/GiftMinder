import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'contact.g.dart';

@JsonSerializable()
class Contact {
  final String id;
  String name;
  DateTime dateOfBirth;
  Relationship relationship;
  List<String> interests;
  String notes;
  String? photoPath;
  List<GiftHistory> giftHistory;
  DateTime createdAt;
  DateTime updatedAt;

  Contact({
    String? id,
    required this.name,
    required this.dateOfBirth,
    required this.relationship,
    List<String>? interests,
    this.notes = '',
    this.photoPath,
    List<GiftHistory>? giftHistory,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        interests = interests ?? [],
        giftHistory = giftHistory ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Contact.fromJson(Map<String, dynamic> json) => _$ContactFromJson(json);
  Map<String, dynamic> toJson() => _$ContactToJson(this);

  int get age {
    final now = DateTime.now();
    final difference = now.difference(dateOfBirth);
    return (difference.inDays / 365.25).floor();
  }

  DateTime get nextBirthday {
    final now = DateTime.now();
    final currentYear = now.year;

    var nextBirthday = DateTime(
      currentYear,
      dateOfBirth.month,
      dateOfBirth.day,
    );

    if (nextBirthday.isBefore(now)) {
      nextBirthday = DateTime(
        currentYear + 1,
        dateOfBirth.month,
        dateOfBirth.day,
      );
    }

    return nextBirthday;
  }

  int get daysUntilBirthday {
    final now = DateTime.now();
    final difference = nextBirthday.difference(now);
    return difference.inDays;
  }

  void addInterest(String interest) {
    final lowercaseInterest = interest.toLowerCase().trim();
    if (lowercaseInterest.isNotEmpty && !interests.contains(lowercaseInterest)) {
      interests.add(lowercaseInterest);
      updatedAt = DateTime.now();
    }
  }

  void removeInterest(String interest) {
    interests.removeWhere((i) => i.toLowerCase() == interest.toLowerCase());
    updatedAt = DateTime.now();
  }

  void addGiftHistory(GiftHistory gift) {
    giftHistory.add(gift);
    updatedAt = DateTime.now();
  }

  Contact copyWith({
    String? name,
    DateTime? dateOfBirth,
    Relationship? relationship,
    List<String>? interests,
    String? notes,
    String? photoPath,
    List<GiftHistory>? giftHistory,
  }) {
    return Contact(
      id: id,
      name: name ?? this.name,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      relationship: relationship ?? this.relationship,
      interests: interests ?? List<String>.from(this.interests),
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
      giftHistory: giftHistory ?? List<GiftHistory>.from(this.giftHistory),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

enum Relationship {
  @JsonValue('family')
  family('Family', 'home'),
  @JsonValue('friend')
  friend('Friend', 'people'),
  @JsonValue('colleague')
  colleague('Colleague', 'work'),
  @JsonValue('partner')
  partner('Partner', 'favorite'),
  @JsonValue('other')
  other('Other', 'help_outline');

  const Relationship(this.displayName, this.iconName);

  final String displayName;
  final String iconName;

  static Relationship fromString(String value) {
    return Relationship.values.firstWhere(
      (r) => r.name == value,
      orElse: () => Relationship.other,
    );
  }
}

@JsonSerializable()
class GiftHistory {
  final String id;
  final String giftName;
  final String? giftDescription;
  final double? price;
  final DateTime purchaseDate;
  final String occasion;
  final String? retailer;
  final int? rating; // 1-5 stars
  final String? notes;

  GiftHistory({
    String? id,
    required this.giftName,
    this.giftDescription,
    this.price,
    DateTime? purchaseDate,
    required this.occasion,
    this.retailer,
    this.rating,
    this.notes,
  })  : id = id ?? const Uuid().v4(),
        purchaseDate = purchaseDate ?? DateTime.now();

  factory GiftHistory.fromJson(Map<String, dynamic> json) =>
      _$GiftHistoryFromJson(json);
  Map<String, dynamic> toJson() => _$GiftHistoryToJson(this);

  String get formattedPrice {
    if (price == null) return 'Price not recorded';
    return '\$${price!.toStringAsFixed(2)}';
  }

  String get formattedDate {
    return '${purchaseDate.day}/${purchaseDate.month}/${purchaseDate.year}';
  }

  GiftHistory copyWith({
    String? giftName,
    String? giftDescription,
    double? price,
    DateTime? purchaseDate,
    String? occasion,
    String? retailer,
    int? rating,
    String? notes,
  }) {
    return GiftHistory(
      id: id,
      giftName: giftName ?? this.giftName,
      giftDescription: giftDescription ?? this.giftDescription,
      price: price ?? this.price,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      occasion: occasion ?? this.occasion,
      retailer: retailer ?? this.retailer,
      rating: rating ?? this.rating,
      notes: notes ?? this.notes,
    );
  }
}
