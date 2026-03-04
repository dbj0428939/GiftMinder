import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/contact_provider.dart';
import '../models/contact.dart';

class AddContactScreen extends StatefulWidget {
  final Contact? contact;

  const AddContactScreen({super.key, this.contact});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _selectedDate;
  Relationship _selectedRelationship = Relationship.friend;
  final List<String> _interests = [];
  final _interestController = TextEditingController();

  bool get isEditing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final contact = widget.contact!;
      _nameController.text = contact.name;
      _notesController.text = contact.notes;
      _selectedDate = contact.dateOfBirth;
      _selectedRelationship = contact.relationship;
      _interests.addAll(contact.interests);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Contact' : 'Add Contact'),
        actions: [
          TextButton(
            onPressed: _saveContact,
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Profile Picture Section
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.purple.shade100,
                    child: Text(
                      _nameController.text.isNotEmpty
                          ? _nameController.text[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.purple,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 16),
                        color: Colors.white,
                        onPressed: () {
                          // TODO: Implement image picker
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Photo selection coming soon!')),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Basic Information
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Basic Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name field
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name *',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                      onChanged: (value) => setState(() {}),
                    ),

                    const SizedBox(height: 16),

                    // Date of Birth
                    InkWell(
                      onTap: _selectDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date of Birth *',
                          prefixIcon: Icon(Icons.cake),
                        ),
                        child: Text(
                          _selectedDate != null
                              ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                              : 'Select date',
                          style: TextStyle(
                            color: _selectedDate != null ? Colors.black : Colors.grey,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Relationship
                    DropdownButtonFormField<Relationship>(
                      initialValue: _selectedRelationship,
                      decoration: const InputDecoration(
                        labelText: 'Relationship',
                        prefixIcon: Icon(Icons.group),
                      ),
                      items: Relationship.values.map((relationship) {
                        return DropdownMenuItem(
                          value: relationship,
                          child: Text(relationship.displayName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedRelationship = value!;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // Age preview
                    if (_selectedDate != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Age: ${_calculateAge(_selectedDate!)} years old',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Interests
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
                    const SizedBox(height: 16),

                    // Add interest field
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _interestController,
                            decoration: const InputDecoration(
                              hintText: 'Add interest...',
                              prefixIcon: Icon(Icons.add_circle_outline),
                            ),
                            onSubmitted: _addInterest,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _addInterest(_interestController.text),
                          child: const Text('Add'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Interest chips
                    if (_interests.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _interests.map((interest) {
                          return Chip(
                            label: Text(interest.substring(0, 1).toUpperCase() + interest.substring(1)),
                            deleteIcon: const Icon(Icons.close, size: 18),
                            onDeleted: () {
                              setState(() {
                                _interests.remove(interest);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ] else ...[
                      Text(
                        'No interests added yet',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Popular interests suggestions
                    Text(
                      'Popular Interests',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _popularInterests.map((interest) {
                        return ActionChip(
                          label: Text(interest),
                          onPressed: () => _addInterest(interest),
                          backgroundColor: Colors.grey.shade100,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Notes
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        hintText: 'Additional notes about this person...',
                        prefixIcon: Icon(Icons.note),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  final List<String> _popularInterests = [
    'reading', 'music', 'movies', 'cooking', 'travel', 'photography',
    'fitness', 'gaming', 'art', 'sports', 'technology', 'gardening',
    'fashion', 'hiking', 'yoga', 'dancing', 'writing', 'crafts',
  ];

  void _addInterest(String interest) {
    final trimmedInterest = interest.trim().toLowerCase();
    if (trimmedInterest.isNotEmpty && !_interests.contains(trimmedInterest)) {
      setState(() {
        _interests.add(trimmedInterest);
        _interestController.clear();
      });
    }
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );

    if (date != null) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    final difference = now.difference(birthDate);
    return (difference.inDays / 365.25).floor();
  }

  void _saveContact() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date of birth')),
      );
      return;
    }

    final contact = Contact(
      id: widget.contact?.id,
      name: _nameController.text.trim(),
      dateOfBirth: _selectedDate!,
      relationship: _selectedRelationship,
      interests: List.from(_interests),
      notes: _notesController.text.trim(),
    );

    final provider = Provider.of<ContactProvider>(context, listen: false);

    if (isEditing) {
      provider.updateContact(contact);
    } else {
      provider.addContact(contact);
    }

    Navigator.pop(context);
  }
}
