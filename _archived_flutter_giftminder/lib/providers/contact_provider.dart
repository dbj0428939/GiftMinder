import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/contact.dart';

class ContactProvider extends ChangeNotifier {
  List<Contact> _contacts = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Contact> get contacts => List.unmodifiable(_contacts);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get totalContacts => _contacts.length;

  List<Contact> get contactsWithUpcomingBirthdays {
    return _contacts
        .where((contact) => contact.daysUntilBirthday <= 30 && contact.daysUntilBirthday >= 0)
        .toList()
      ..sort((a, b) => a.daysUntilBirthday.compareTo(b.daysUntilBirthday));
  }

  Map<Relationship, int> get contactsByRelationshipCount {
    final Map<Relationship, int> counts = {};
    for (final relationship in Relationship.values) {
      counts[relationship] = _contacts.where((c) => c.relationship == relationship).length;
    }
    return counts;
  }

  double get averageAge {
    if (_contacts.isEmpty) return 0;
    final totalAge = _contacts.map((c) => c.age).reduce((a, b) => a + b);
    return totalAge / _contacts.length;
  }

  List<String> get mostCommonInterests {
    final Map<String, int> interestCount = {};
    for (final contact in _contacts) {
      for (final interest in contact.interests) {
        interestCount[interest] = (interestCount[interest] ?? 0) + 1;
      }
    }

    final sortedInterests = interestCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedInterests.take(10).map((e) => e.key).toList();
  }

  ContactProvider() {
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = prefs.getString('contacts');

      if (contactsJson != null) {
        final List<dynamic> contactsList = json.decode(contactsJson);
        _contacts = contactsList.map((json) => Contact.fromJson(json)).toList();
      } else {
        _loadSampleData();
      }

      _clearError();
    } catch (e) {
      _setError('Failed to load contacts: ${e.toString()}');
      _loadSampleData();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _saveContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = json.encode(_contacts.map((c) => c.toJson()).toList());
      await prefs.setString('contacts', contactsJson);
      _clearError();
    } catch (e) {
      _setError('Failed to save contacts: ${e.toString()}');
    }
  }

  Future<void> addContact(Contact contact) async {
    _contacts.add(contact);
    notifyListeners();
    await _saveContacts();
  }

  Future<void> updateContact(Contact updatedContact) async {
    final index = _contacts.indexWhere((c) => c.id == updatedContact.id);
    if (index != -1) {
      _contacts[index] = updatedContact;
      notifyListeners();
      await _saveContacts();
    }
  }

  Future<void> deleteContact(Contact contact) async {
    _contacts.removeWhere((c) => c.id == contact.id);
    notifyListeners();
    await _saveContacts();
  }

  List<Contact> searchContacts(String query) {
    if (query.isEmpty) return _contacts;

    final lowercaseQuery = query.toLowerCase();
    return _contacts.where((contact) {
      return contact.name.toLowerCase().contains(lowercaseQuery) ||
             contact.relationship.displayName.toLowerCase().contains(lowercaseQuery) ||
             contact.interests.any((interest) => interest.contains(lowercaseQuery)) ||
             contact.notes.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  List<Contact> getContactsByRelationship(Relationship relationship) {
    return _contacts.where((c) => c.relationship == relationship).toList();
  }

  List<Contact> getContactsWithUpcomingBirthdays({int days = 30}) {
    return _contacts
        .where((contact) => contact.daysUntilBirthday <= days && contact.daysUntilBirthday >= 0)
        .toList()
      ..sort((a, b) => a.daysUntilBirthday.compareTo(b.daysUntilBirthday));
  }

  Contact? getContactById(String id) {
    try {
      return _contacts.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  List<String> validateContact(Contact contact) {
    final List<String> errors = [];

    if (contact.name.trim().isEmpty) {
      errors.add('Name is required');
    }

    if (contact.dateOfBirth.isAfter(DateTime.now())) {
      errors.add('Date of birth cannot be in the future');
    }

    if (contact.age > 150) {
      errors.add('Age seems unrealistic');
    }

    return errors;
  }

  bool isValidContact(Contact contact) {
    return validateContact(contact).isEmpty;
  }

  Future<String> exportContacts() async {
    try {
      final contactsJson = json.encode(_contacts.map((c) => c.toJson()).toList());
      return contactsJson;
    } catch (e) {
      throw Exception('Failed to export contacts: ${e.toString()}');
    }
  }

  Future<bool> importContacts(String jsonString) async {
    try {
      final List<dynamic> contactsList = json.decode(jsonString);
      final importedContacts = contactsList.map((json) => Contact.fromJson(json)).toList();

      // Add imported contacts, avoiding duplicates by name
      for (final importedContact in importedContacts) {
        if (!_contacts.any((c) => c.name == importedContact.name)) {
          _contacts.add(importedContact);
        }
      }

      notifyListeners();
      await _saveContacts();
      return true;
    } catch (e) {
      _setError('Failed to import contacts: ${e.toString()}');
      return false;
    }
  }

  Future<void> addSampleContact() async {
    final sampleInterests = [
      'reading', 'music', 'sports', 'cooking', 'travel', 'photography',
      'gaming', 'art', 'fitness', 'technology', 'gardening', 'movies',
    ];

    final selectedInterests = (sampleInterests..shuffle()).take(3).toList();
    final randomAge = 18 + (DateTime.now().millisecond % 53); // Random age 18-70

    final contact = Contact(
      name: 'Sample Contact ${_contacts.length + 1}',
      dateOfBirth: DateTime.now().subtract(Duration(days: randomAge * 365)),
      relationship: Relationship.values[DateTime.now().millisecond % Relationship.values.length],
      interests: selectedInterests,
      notes: 'This is a sample contact for testing purposes',
    );

    await addContact(contact);
  }

  void _loadSampleData() {
    final now = DateTime.now();
    _contacts = [
      Contact(
        name: 'Sarah Johnson',
        dateOfBirth: DateTime(now.year - 28, now.month, now.day),
        relationship: Relationship.friend,
        interests: ['photography', 'hiking', 'coffee', 'travel', 'books'],
        notes: 'Loves outdoor activities and has a passion for capturing moments',
      ),
      Contact(
        name: 'Mom',
        dateOfBirth: DateTime(now.year - 55, now.month, now.day),
        relationship: Relationship.family,
        interests: ['gardening', 'cooking', 'reading', 'yoga', 'wine'],
        notes: 'Always enjoys trying new recipes and tending to her garden',
      ),
      Contact(
        name: 'Alex Chen',
        dateOfBirth: DateTime(now.year - 32, now.month, now.day),
        relationship: Relationship.colleague,
        interests: ['technology', 'gaming', 'music', 'fitness', 'coffee'],
        notes: 'Tech enthusiast who loves the latest gadgets',
      ),
      Contact(
        name: 'Emma Wilson',
        dateOfBirth: DateTime(now.year - 25, now.month, now.day),
        relationship: Relationship.friend,
        interests: ['art', 'painting', 'museums', 'fashion', 'travel'],
        notes: 'Creative soul with an eye for beautiful things',
      ),
    ];
    _saveContacts();
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
    await _loadContacts();
  }
}
