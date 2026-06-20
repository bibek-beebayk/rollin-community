import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_input.dart';
import 'verify_otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  AnimationController? _marqueeController;
  String _userType = 'player';
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  final List<_RegisterFeature> _features = const [
    _RegisterFeature(Icons.groups_outlined, '15,000+', 'Active Members'),
    _RegisterFeature(Icons.chat_bubble_outline, '100+', 'Daily Discussions'),
    _RegisterFeature(
        Icons.card_giftcard_outlined, 'Weekly', 'Community Rewards'),
    _RegisterFeature(Icons.emoji_events_outlined, 'Events', '& Giveaways'),
    _RegisterFeature(
        Icons.support_agent_outlined, 'Direct Support', 'From Our Team'),
  ];

  @override
  void initState() {
    super.initState();
    _ensureMarqueeController();
  }

  @override
  void dispose() {
    _marqueeController?.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  AnimationController _ensureMarqueeController() {
    return _marqueeController ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  Future<void> _handleRegister() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    if (password != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final emailSentTo =
          await Provider.of<AuthProvider>(context, listen: false).register(
        username: username,
        email: email,
        userType: _userType,
        password: password,
        confirmPassword: confirmPassword,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyOtpScreen(email: emailSentTo),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopLogo(),
                    // const SizedBox(height: 8),
                    // _buildTitleBlock(),
                    // const SizedBox(height: 18),
                    _buildFeatureMarquee(),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: _buildRegisterPanel(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopLogo() {
    return Center(
      child: Image.asset(
        'assets/icon.png',
        width: 122,
        height: 122,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildFeatureMarquee() {
    final repeated = [..._features, ..._features];
    final controller = _ensureMarqueeController();
    return SizedBox(
      height: 76,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final width = MediaQuery.of(context).size.width;
            final itemWidth = width < 420 ? 220.0 : 238.0;
            final fullWidth = _features.length * (itemWidth + 10);
            final offset = -controller.value * fullWidth;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: repeated
                      .map((feature) => _buildFeatureCard(feature, itemWidth))
                      .toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeatureCard(_RegisterFeature feature, double width) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(feature.icon, color: AppTheme.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  feature.value,
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  feature.label,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.visualStyle == VisualStyle.card
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.26),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'REGISTER',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 22),
          _buildLabel('I am a...'),
          Row(
            children: [
              Expanded(
                child: _UserTypeButton(
                  label: 'Player',
                  icon: Icons.sports_esports_outlined,
                  isSelected: _userType == 'player',
                  onTap: () => setState(() => _userType = 'player'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UserTypeButton(
                  label: 'Agent',
                  icon: Icons.support_agent_outlined,
                  isSelected: _userType == 'agent',
                  onTap: () => setState(() => _userType = 'agent'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildLabel('Username'),
          CustomInput(
            hintText: 'Choose a username',
            controller: _usernameController,
            prefixIcon: Icon(
              Icons.person_outline,
              color: AppTheme.textSecondary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 14),
          _buildLabel('Email'),
          CustomInput(
            hintText: 'Enter your email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icon(
              Icons.email_outlined,
              color: AppTheme.textSecondary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 14),
          _buildLabel('Password'),
          CustomInput(
            hintText: 'Password',
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            prefixIcon: Icon(
              Icons.lock_outline,
              color: AppTheme.textSecondary.withValues(alpha: 0.85),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppTheme.textSecondary.withValues(alpha: 0.85),
              ),
              onPressed: () {
                setState(() => _isPasswordVisible = !_isPasswordVisible);
              },
            ),
          ),
          const SizedBox(height: 14),
          _buildLabel('Confirm Password'),
          CustomInput(
            hintText: 'Confirm password',
            controller: _confirmPasswordController,
            obscureText: !_isConfirmPasswordVisible,
            prefixIcon: Icon(
              Icons.lock_outline,
              color: AppTheme.textSecondary.withValues(alpha: 0.85),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _isConfirmPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppTheme.textSecondary.withValues(alpha: 0.85),
              ),
              onPressed: () {
                setState(
                  () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          CustomButton(
            text: 'Create Account',
            onPressed: _handleRegister,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 18),
          _buildSignInPrompt(),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _buildSignInPrompt() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              'Already have an account?',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(left: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Sign In',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterFeature {
  final IconData icon;
  final String value;
  final String label;

  const _RegisterFeature(this.icon, this.value, this.label);
}

class _UserTypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _UserTypeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.20)
                : AppTheme.background.withValues(alpha: 0.18),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
              width: isSelected ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
