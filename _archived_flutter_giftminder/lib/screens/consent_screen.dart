import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firebase_service.dart';
import '../models/firebase_models.dart';

class ConsentScreen extends StatefulWidget {
  final VoidCallback? onConsentComplete;
  final bool isFirstTime;

  const ConsentScreen({
    super.key,
    this.onConsentComplete,
    this.isFirstTime = true,
  });

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _personalizedRecommendations = false;
  bool _analytics = false;
  bool _marketingCommunications = false;
  bool _sponsoredContent = false;
  bool _isLoading = false;
  int _currentStep = 0;

  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();

    // Load existing consent if available
    _loadExistingConsent();
  }

  Future<void> _loadExistingConsent() async {
    final firebaseService = context.read<FirebaseService>();
    final userProfile = firebaseService.userProfile;

    if (userProfile != null) {
      setState(() {
        _personalizedRecommendations = userProfile.consent.personalizedRecommendations;
        _analytics = userProfile.consent.analytics;
        _marketingCommunications = userProfile.consent.marketingCommunications;
        _sponsoredContent = userProfile.consent.sponsoredContent;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _saveConsent();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveConsent() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final firebaseService = context.read<FirebaseService>();

      final consent = UserConsent(
        personalizedRecommendations: _personalizedRecommendations,
        analytics: _analytics,
        marketingCommunications: _marketingCommunications,
        sponsoredContent: _sponsoredContent,
      );

      // Create a basic profile - will be enhanced later with actual user data
      await firebaseService.updateUserProfile(
        ageGroup: AgeGroup.age25to34, // Default, will be updated from contacts
        interests: [], // Will be populated from user's contacts
        consent: consent,
      );

      if (widget.onConsentComplete != null) {
        widget.onConsentComplete!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving preferences: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentStep = index;
                  });
                },
                children: [
                  _buildWelcomeStep(),
                  _buildPrivacyStep(),
                  _buildConsentStep(),
                ],
              ),
            ),
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: List.generate(3, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: index <= _currentStep
                    ? Colors.purple
                    : Colors.grey.shade300,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.card_giftcard,
                size: 80,
                color: Colors.purple,
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to GiftMinder!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'We help you find the perfect gifts for your loved ones by suggesting personalized recommendations.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.security,
                      color: Colors.purple,
                      size: 24,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your privacy is our priority. All personal information stays on your device.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.purple,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(
            Icons.privacy_tip_outlined,
            size: 60,
            color: Colors.purple,
          ),
          const SizedBox(height: 24),
          const Text(
            'How We Protect Your Privacy',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                _buildPrivacyPoint(
                  Icons.phone_android,
                  'Local Storage',
                  'Names, photos, and personal details of your contacts stay on your device only.',
                ),
                _buildPrivacyPoint(
                  Icons.category,
                  'Anonymous Analytics',
                  'We only collect general interest categories (like "technology" or "books"), not specific personal details.',
                ),
                _buildPrivacyPoint(
                  Icons.groups,
                  'Age Groups Only',
                  'We use age ranges (like "25-34") instead of exact ages or birthdates.',
                ),
                _buildPrivacyPoint(
                  Icons.delete_forever,
                  'Your Control',
                  'You can change these preferences anytime or delete all your data.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyPoint(IconData icon, String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Colors.purple,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsentStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Choose Your Experience',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Select the features you\'d like to enable. You can change these anytime.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView(
              children: [
                _buildConsentOption(
                  title: 'Personalized Gift Recommendations',
                  description: 'Get better gift suggestions based on your contacts\' interests',
                  value: _personalizedRecommendations,
                  onChanged: (value) {
                    setState(() {
                      _personalizedRecommendations = value;
                    });
                  },
                  icon: Icons.recommend,
                ),
                _buildConsentOption(
                  title: 'Anonymous Usage Analytics',
                  description: 'Help us improve the app with anonymous usage data',
                  value: _analytics,
                  onChanged: (value) {
                    setState(() {
                      _analytics = value;
                    });
                  },
                  icon: Icons.analytics_outlined,
                ),
                _buildConsentOption(
                  title: 'Sponsored Gift Suggestions',
                  description: 'See relevant sponsored products from our retail partners',
                  value: _sponsoredContent,
                  onChanged: (value) {
                    setState(() {
                      _sponsoredContent = value;
                    });
                  },
                  icon: Icons.store_outlined,
                ),
                _buildConsentOption(
                  title: 'Marketing Communications',
                  description: 'Receive updates about new features and special offers',
                  value: _marketingCommunications,
                  onChanged: (value) {
                    setState(() {
                      _marketingCommunications = value;
                    });
                  },
                  icon: Icons.mail_outline,
                ),
              ],
            ),
          ),
          if (_sponsoredContent || _analytics) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enabling these features helps us show you more relevant content and keep the app free.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConsentOption({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: value ? Colors.purple.shade200 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(12),
        color: value ? Colors.purple.shade50 : Colors.white,
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: (newValue) => onChanged(newValue ?? false),
        title: Row(
          children: [
            Icon(
              icon,
              color: value ? Colors.purple : Colors.grey.shade600,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: value ? Colors.purple.shade700 : Colors.black87,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 28, top: 4),
          child: Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: value ? Colors.purple.shade600 : Colors.grey.shade600,
              height: 1.3,
            ),
          ),
        ),
        activeColor: Colors.purple,
        checkColor: Colors.white,
        controlAffinity: ListTileControlAffinity.trailing,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _isLoading ? null : _previousStep,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.purple),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple,
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            flex: _currentStep > 0 ? 1 : 1,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _currentStep == 2 ? 'Get Started' : 'Continue',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
