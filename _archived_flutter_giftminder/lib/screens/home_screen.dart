import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/contact_provider.dart';
import '../providers/firebase_service.dart';
import 'contacts_screen.dart';
import 'recommendations_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'consent_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _hasShownConsent = false;

  final List<Widget> _screens = [
    const ContactsScreen(),
    const RecommendationsScreen(),
    const SearchScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConsentAndInitialize();
    });
  }

  Future<void> _checkConsentAndInitialize() async {
    if (_hasShownConsent) return;

    final firebaseService = context.read<FirebaseService>();
    final contactProvider = context.read<ContactProvider>();

    // Wait for contact provider to load
    if (contactProvider.isLoading) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Check if user needs to see consent screen
    if (firebaseService.userProfile == null && mounted) {
      _hasShownConsent = true;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) => SizedBox(
          height: MediaQuery.of(context).size.height,
          child: ConsentScreen(
            onConsentComplete: () {
              Navigator.of(context).pop();
              _initializeUserProfile();
            },
          ),
        ),
      );
    } else if (firebaseService.userProfile != null) {
      _initializeUserProfile();
    }

    // Log app open for analytics
    await firebaseService.logAppOpen();
  }

  Future<void> _initializeUserProfile() async {
    final firebaseService = context.read<FirebaseService>();
    final contactProvider = context.read<ContactProvider>();

    // If user has contacts but no analytics profile, create one from contacts
    if (contactProvider.contacts.isNotEmpty &&
        firebaseService.userProfile != null &&
        firebaseService.userProfile!.generalInterests.isEmpty) {
      await firebaseService.createProfileFromContacts(contactProvider.contacts);
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Log screen views for analytics
    final firebaseService = context.read<FirebaseService>();
    final screenNames = ['contacts', 'gifts', 'search', 'profile'];
    if (index < screenNames.length) {
      firebaseService.logScreenView(screenNames[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChanged,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.card_giftcard_outlined),
            selectedIcon: Icon(Icons.card_giftcard),
            label: 'Gifts',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Shop',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
