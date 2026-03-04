import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/gift_provider.dart';
import '../models/contact.dart';
import '../models/gift.dart';
import 'add_contact_screen.dart';

class ContactDetailScreen extends StatefulWidget {
  final Contact contact;

  const ContactDetailScreen({super.key, required this.contact});

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  late Contact _contact;
  PriceFilter _selectedPriceFilter = PriceFilter.all;
  GiftCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contact.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddContactScreen(contact: _contact),
                ),
              );
              if (result != null) {
                setState(() {
                  _contact = result;
                });
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.purple.shade100,
                      child: Text(
                        _contact.name.isNotEmpty
                            ? _contact.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _contact.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.home, // Map from relationship.iconName
                          color: Colors.purple,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _contact.relationship.displayName,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    if (_contact.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _contact.notes,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Stats Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatColumn(
                      title: 'Age',
                      value: '${_contact.age}',
                      icon: Icons.calendar_today,
                      color: Colors.blue,
                    ),
                    _StatColumn(
                      title: 'Next Birthday',
                      value: _contact.daysUntilBirthday == 0
                          ? 'Today! 🎉'
                          : _contact.daysUntilBirthday == 1
                          ? 'Tomorrow'
                          : '${_contact.daysUntilBirthday} days',
                      icon: Icons.cake,
                      color: Colors.orange,
                    ),
                    _StatColumn(
                      title: 'Interests',
                      value: '${_contact.interests.length}',
                      icon: Icons.favorite,
                      color: Colors.pink,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Interests Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Interests',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_contact.interests.isEmpty)
                      Text(
                        'No interests added yet',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _contact.interests.map((interest) {
                          return Chip(
                            label: Text(
                              interest.substring(0, 1).toUpperCase() +
                                  interest.substring(1),
                            ),
                            backgroundColor: Colors.purple.shade50,
                            labelStyle: TextStyle(
                              color: Colors.purple.shade700,
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Gift Recommendations Section
            Consumer<GiftProvider>(
              builder: (context, giftProvider, child) {
                final recommendations = giftProvider.getRecommendations(
                  _contact,
                  priceRange: _selectedPriceFilter,
                  category: _selectedCategory,
                  limit: 10,
                );

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Gift Recommendations',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.filter_list),
                              onSelected: (value) {
                                if (value.startsWith('price_')) {
                                  final priceIndex = int.parse(
                                    value.split('_')[1],
                                  );
                                  setState(() {
                                    _selectedPriceFilter =
                                        PriceFilter.values[priceIndex];
                                  });
                                } else if (value.startsWith('category_')) {
                                  final categoryIndex = int.parse(
                                    value.split('_')[1],
                                  );
                                  setState(() {
                                    _selectedCategory =
                                        GiftCategory.values[categoryIndex];
                                  });
                                } else if (value == 'clear_category') {
                                  setState(() {
                                    _selectedCategory = null;
                                  });
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'price_header',
                                  enabled: false,
                                  child: Text(
                                    'Price Range',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                ...PriceFilter.values.asMap().entries.map(
                                  (entry) => PopupMenuItem(
                                    value: 'price_${entry.key}',
                                    child: Text(entry.value.displayName),
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'category_header',
                                  enabled: false,
                                  child: Text(
                                    'Category',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'clear_category',
                                  child: Text('All Categories'),
                                ),
                                ...GiftCategory.values.asMap().entries.map(
                                  (entry) => PopupMenuItem(
                                    value: 'category_${entry.key}',
                                    child: Text(entry.value.displayName),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        if (_selectedPriceFilter != PriceFilter.all ||
                            _selectedCategory != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (_selectedPriceFilter != PriceFilter.all)
                                Chip(
                                  label: Text(_selectedPriceFilter.displayName),
                                  onDeleted: () {
                                    setState(() {
                                      _selectedPriceFilter = PriceFilter.all;
                                    });
                                  },
                                  backgroundColor: Colors.blue.shade50,
                                ),
                              if (_selectedCategory != null)
                                Chip(
                                  label: Text(_selectedCategory!.displayName),
                                  onDeleted: () {
                                    setState(() {
                                      _selectedCategory = null;
                                    });
                                  },
                                  backgroundColor: Colors.green.shade50,
                                ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 12),

                        if (recommendations.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.card_giftcard,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No recommendations found',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Try adding more interests or adjusting filters',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          SizedBox(
                            height: 280,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: recommendations.take(5).length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final recommendation = recommendations[index];
                                return _GiftRecommendationCard(
                                  recommendation: recommendation,
                                );
                              },
                            ),
                          ),

                        if (recommendations.length > 5) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton(
                              onPressed: () {
                                // TODO: Navigate to all recommendations view
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Found ${recommendations.length} total recommendations',
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                'View all ${recommendations.length} recommendations',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Gift History Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Gift History',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: () {
                            // TODO: Navigate to full gift history
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Gift history feature coming soon!',
                                ),
                              ),
                            );
                          },
                          child: const Text('View All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_contact.giftHistory.isEmpty)
                      Text(
                        'No gifts recorded yet',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      ...(_contact.giftHistory.take(3).map((gift) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.card_giftcard),
                          title: Text(gift.giftName),
                          subtitle: Text(
                            '${gift.occasion} • ${gift.formattedDate}',
                          ),
                          trailing: gift.price != null
                              ? Text(gift.formattedPrice)
                              : null,
                        );
                      }).toList()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatColumn({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _GiftRecommendationCard extends StatelessWidget {
  final GiftRecommendation recommendation;

  const _GiftRecommendationCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final gift = recommendation.gift;

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sponsored badge and image placeholder
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.phone_android, // Map from gift.category.iconName
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                ),
                if (gift.isSponsored)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'SPONSORED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gift.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    gift.formattedPrice,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),

                  const Spacer(),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getConfidenceColor(recommendation.confidence),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          recommendation.confidence.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const Spacer(),

                      if (gift.ratings.hasRatings) ...[
                        const Icon(Icons.star, size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          gift.ratings.averageRating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getConfidenceColor(ConfidenceLevel confidence) {
    switch (confidence) {
      case ConfidenceLevel.low:
        return Colors.red;
      case ConfidenceLevel.medium:
        return Colors.orange;
      case ConfidenceLevel.high:
        return Colors.blue;
      case ConfidenceLevel.veryHigh:
        return Colors.green;
    }
  }
}
