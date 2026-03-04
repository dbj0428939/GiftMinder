import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/gift.dart';
import '../models/contact.dart';

class GiftProvider extends ChangeNotifier {
  List<Gift> _gifts = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Gift> get gifts => List.unmodifiable(_gifts);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get totalGifts => _gifts.length;

  List<Gift> get sponsoredGifts => _gifts.where((g) => g.isSponsored).toList();

  List<Gift> get trendingGifts {
    return _gifts
        .where((g) => g.ratings.hasRatings)
        .toList()
      ..sort((a, b) {
        if (a.ratings.averageRating != b.ratings.averageRating) {
          return b.ratings.averageRating.compareTo(a.ratings.averageRating);
        }
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  Map<GiftCategory, List<Gift>> get giftsByCategory {
    final Map<GiftCategory, List<Gift>> categoryMap = {};
    for (final category in GiftCategory.values) {
      categoryMap[category] = _gifts.where((g) => g.category == category).toList();
    }
    return categoryMap;
  }

  List<String> get popularInterests {
    final Map<String, int> interestCount = {};
    for (final gift in _gifts) {
      for (final interest in gift.interests) {
        interestCount[interest] = (interestCount[interest] ?? 0) + 1;
      }
    }

    final sortedInterests = interestCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedInterests.take(20).map((e) => e.key).toList();
  }

  GiftProvider() {
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final giftsJson = prefs.getString('gifts');

      if (giftsJson != null) {
        final List<dynamic> giftsList = json.decode(giftsJson);
        _gifts = giftsList.map((json) => Gift.fromJson(json)).toList();
      } else {
        _loadSampleGifts();
      }

      _clearError();
    } catch (e) {
      _setError('Failed to load gifts: ${e.toString()}');
      _loadSampleGifts();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _saveGifts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final giftsJson = json.encode(_gifts.map((g) => g.toJson()).toList());
      await prefs.setString('gifts', giftsJson);
      _clearError();
    } catch (e) {
      _setError('Failed to save gifts: ${e.toString()}');
    }
  }

  List<GiftRecommendation> getRecommendations(Contact contact, {
    PriceFilter priceRange = PriceFilter.all,
    GiftCategory? category,
    int limit = 20,
  }) {
    var filteredGifts = _gifts;

    // Apply price filter
    filteredGifts = _applyPriceFilter(filteredGifts, priceRange);

    // Apply category filter
    if (category != null) {
      filteredGifts = filteredGifts.where((g) => g.category == category).toList();
    }

    // Create recommendations with match scores
    final recommendations = filteredGifts.map((gift) {
      final score = gift.matchScore(contact);
      final reasons = GiftRecommendation.generateReasons(gift, contact);
      return GiftRecommendation(
        gift: gift,
        contactId: contact.id,
        matchScore: score,
        reasons: reasons,
      );
    }).toList();

    // Sort by match score and prioritize sponsored items
    recommendations.sort((a, b) {
      if (a.gift.isSponsored && !b.gift.isSponsored) return -1;
      if (!a.gift.isSponsored && b.gift.isSponsored) return 1;
      return b.matchScore.compareTo(a.matchScore);
    });

    return recommendations.take(limit).toList();
  }

  List<Gift> searchGifts(String query, {GiftCategory? category}) {
    var results = _gifts;

    if (category != null) {
      results = results.where((g) => g.category == category).toList();
    }

    if (query.isNotEmpty) {
      final lowercaseQuery = query.toLowerCase();
      results = results.where((gift) {
        return gift.name.toLowerCase().contains(lowercaseQuery) ||
               gift.description.toLowerCase().contains(lowercaseQuery) ||
               gift.interests.any((interest) => interest.contains(lowercaseQuery)) ||
               gift.tags.any((tag) => tag.contains(lowercaseQuery)) ||
               gift.retailer.name.toLowerCase().contains(lowercaseQuery);
      }).toList();
    }

    // Sort results with sponsored items first
    results.sort((a, b) {
      if (a.isSponsored && !b.isSponsored) return -1;
      if (!a.isSponsored && b.isSponsored) return 1;

      if (a.ratings.hasRatings && b.ratings.hasRatings) {
        return b.ratings.averageRating.compareTo(a.ratings.averageRating);
      } else if (a.ratings.hasRatings) {
        return -1;
      } else if (b.ratings.hasRatings) {
        return 1;
      }

      return a.name.compareTo(b.name);
    });

    return results;
  }

  List<Gift> getTrendingGifts({int limit = 10}) {
    return trendingGifts.take(limit).toList();
  }

  List<Gift> getGiftsByCategory(GiftCategory category) {
    return _gifts.where((g) => g.category == category).toList();
  }

  Future<void> addGift(Gift gift) async {
    _gifts.add(gift);
    notifyListeners();
    await _saveGifts();
  }

  Future<void> updateGift(Gift updatedGift) async {
    final index = _gifts.indexWhere((g) => g.id == updatedGift.id);
    if (index != -1) {
      _gifts[index] = updatedGift;
      notifyListeners();
      await _saveGifts();
    }
  }

  Future<void> removeGift(Gift gift) async {
    _gifts.removeWhere((g) => g.id == gift.id);
    notifyListeners();
    await _saveGifts();
  }

  List<Gift> _applyPriceFilter(List<Gift> gifts, PriceFilter priceFilter) {
    switch (priceFilter) {
      case PriceFilter.all:
        return gifts;
      case PriceFilter.under25:
        return gifts.where((g) => g.price.maxPrice <= 25).toList();
      case PriceFilter.under50:
        return gifts.where((g) => g.price.maxPrice <= 50).toList();
      case PriceFilter.under100:
        return gifts.where((g) => g.price.maxPrice <= 100).toList();
      case PriceFilter.under200:
        return gifts.where((g) => g.price.maxPrice <= 200).toList();
      case PriceFilter.over200:
        return gifts.where((g) => g.price.minPrice > 200).toList();
    }
  }

  void _loadSampleGifts() {
    _gifts = [
      Gift(
        name: 'Wireless Bluetooth Headphones',
        description: 'Premium noise-cancelling wireless headphones with 30-hour battery life',
        price: const PriceRange.range(50, 200),
        category: GiftCategory.electronics,
        ageGroups: [AgeGroup.teen, AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged],
        interests: ['music', 'technology', 'travel'],
        retailer: Retailer(
          name: 'TechWorld',
          type: RetailerType.onlineMarketplace,
          trustScore: 4.2,
        ),
        ratings: GiftRatings(
          totalRatings: 1547,
          averageRating: 4.3,
          fiveStars: 847,
          fourStars: 523,
          threeStars: 127,
          twoStars: 37,
          oneStar: 13,
        ),
        tags: ['wireless', 'portable', 'premium'],
        isSponsored: true,
      ),
      Gift(
        name: 'Smart Fitness Watch',
        description: 'Track your health and fitness with this feature-packed smartwatch',
        price: const PriceRange.range(100, 400),
        category: GiftCategory.electronics,
        ageGroups: [AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged],
        interests: ['fitness', 'technology', 'health'],
        retailer: Retailer(
          name: 'FitTech',
          type: RetailerType.brand,
          trustScore: 4.5,
        ),
        ratings: GiftRatings(
          totalRatings: 892,
          averageRating: 4.1,
          fiveStars: 456,
          fourStars: 312,
          threeStars: 89,
          twoStars: 23,
          oneStar: 12,
        ),
        tags: ['fitness', 'health', 'smartwatch'],
      ),
      Gift(
        name: 'Popular Fiction Novel Set',
        description: 'Collection of bestselling novels from award-winning authors',
        price: const PriceRange.range(15, 40),
        category: GiftCategory.books,
        ageGroups: [AgeGroup.teen, AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged, AgeGroup.senior],
        interests: ['reading', 'literature', 'stories'],
        retailer: Retailer(
          name: 'BookHaven',
          type: RetailerType.specialty,
          trustScore: 4.7,
        ),
        ratings: GiftRatings(
          totalRatings: 234,
          averageRating: 4.6,
          fiveStars: 145,
          fourStars: 67,
          threeStars: 18,
          twoStars: 3,
          oneStar: 1,
        ),
        tags: ['fiction', 'bestseller', 'collection'],
      ),
      Gift(
        name: 'Photography Technique Guide',
        description: 'Comprehensive guide to mastering digital photography',
        price: const PriceRange.exact(29.99),
        category: GiftCategory.books,
        ageGroups: [AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged],
        interests: ['photography', 'art', 'learning'],
        retailer: Retailer(
          name: 'CreativeBooks',
          type: RetailerType.specialty,
          trustScore: 4.4,
        ),
        ratings: GiftRatings(
          totalRatings: 156,
          averageRating: 4.5,
          fiveStars: 89,
          fourStars: 52,
          threeStars: 12,
          twoStars: 2,
          oneStar: 1,
        ),
        tags: ['photography', 'tutorial', 'skills'],
      ),
      Gift(
        name: 'Aromatherapy Essential Oil Set',
        description: 'Premium essential oils with diffuser for relaxation and wellness',
        price: const PriceRange.range(25, 60),
        category: GiftCategory.homeDecor,
        ageGroups: [AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged, AgeGroup.senior],
        interests: ['wellness', 'relaxation', 'aromatherapy'],
        retailer: Retailer(
          name: 'ZenHome',
          type: RetailerType.specialty,
          trustScore: 4.3,
        ),
        ratings: GiftRatings(
          totalRatings: 445,
          averageRating: 4.2,
          fiveStars: 234,
          fourStars: 156,
          threeStars: 42,
          twoStars: 10,
          oneStar: 3,
        ),
        tags: ['wellness', 'aromatherapy', 'relaxation'],
        isSponsored: true,
      ),
      Gift(
        name: 'Yoga Mat Premium Set',
        description: 'High-quality yoga mat with accessories for home practice',
        price: const PriceRange.range(30, 80),
        category: GiftCategory.sports,
        ageGroups: [AgeGroup.teen, AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged, AgeGroup.senior],
        interests: ['yoga', 'fitness', 'wellness'],
        retailer: Retailer(
          name: 'YogaLife',
          type: RetailerType.specialty,
          trustScore: 4.6,
        ),
        ratings: GiftRatings(
          totalRatings: 678,
          averageRating: 4.4,
          fiveStars: 387,
          fourStars: 223,
          threeStars: 54,
          twoStars: 11,
          oneStar: 3,
        ),
        tags: ['yoga', 'fitness', 'wellness'],
      ),
      Gift(
        name: 'Hiking Backpack',
        description: 'Durable and comfortable backpack perfect for day hikes and outdoor adventures',
        price: const PriceRange.range(40, 120),
        category: GiftCategory.sports,
        ageGroups: [AgeGroup.teen, AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged],
        interests: ['hiking', 'outdoor', 'travel', 'adventure'],
        retailer: Retailer(
          name: 'OutdoorGear',
          type: RetailerType.specialty,
          trustScore: 4.8,
        ),
        ratings: GiftRatings(
          totalRatings: 892,
          averageRating: 4.7,
          fiveStars: 634,
          fourStars: 198,
          threeStars: 45,
          twoStars: 12,
          oneStar: 3,
        ),
        tags: ['hiking', 'outdoor', 'durable'],
      ),
      Gift(
        name: 'Gourmet Coffee Sample Set',
        description: 'Selection of premium coffee beans from around the world',
        price: const PriceRange.range(20, 50),
        category: GiftCategory.food,
        ageGroups: [AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged, AgeGroup.senior],
        interests: ['coffee', 'gourmet', 'tasting'],
        retailer: Retailer(
          name: 'CoffeeRoasters',
          type: RetailerType.specialty,
          trustScore: 4.5,
        ),
        ratings: GiftRatings(
          totalRatings: 267,
          averageRating: 4.3,
          fiveStars: 142,
          fourStars: 89,
          threeStars: 28,
          twoStars: 6,
          oneStar: 2,
        ),
        tags: ['coffee', 'gourmet', 'sampling'],
      ),
      Gift(
        name: 'Cooking Class Voucher',
        description: 'Learn new culinary skills with professional chef instruction',
        price: const PriceRange.range(75, 150),
        category: GiftCategory.food,
        ageGroups: [AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged],
        interests: ['cooking', 'learning', 'culinary'],
        retailer: Retailer(
          name: 'CulinarySchool',
          type: RetailerType.localBusiness,
          trustScore: 4.7,
        ),
        ratings: GiftRatings(
          totalRatings: 89,
          averageRating: 4.8,
          fiveStars: 67,
          fourStars: 18,
          threeStars: 3,
          twoStars: 1,
          oneStar: 0,
        ),
        tags: ['cooking', 'class', 'experience'],
        isSponsored: true,
      ),
      Gift(
        name: 'Professional Art Supply Kit',
        description: 'Complete set of high-quality art supplies for drawing and painting',
        price: const PriceRange.range(40, 100),
        category: GiftCategory.art,
        ageGroups: [AgeGroup.teen, AgeGroup.youngAdult, AgeGroup.adult, AgeGroup.middleAged],
        interests: ['art', 'painting', 'drawing', 'creativity'],
        retailer: Retailer(
          name: 'ArtSupplies',
          type: RetailerType.specialty,
          trustScore: 4.4,
        ),
        ratings: GiftRatings(
          totalRatings: 334,
          averageRating: 4.5,
          fiveStars: 189,
          fourStars: 112,
          threeStars: 25,
          twoStars: 6,
          oneStar: 2,
        ),
        tags: ['art', 'supplies', 'professional'],
      ),
    ];
    _saveGifts();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _loadGifts();
  }
}

enum PriceFilter {
  all('All Prices'),
  under25('Under \$25'),
  under50('Under \$50'),
  under100('Under \$100'),
  under200('Under \$200'),
  over200('Over \$200');

  const PriceFilter(this.displayName);

  final String displayName;
}
