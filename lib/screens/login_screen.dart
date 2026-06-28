import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/notification_service.dart';
import '../widgets/custom_input.dart';
import '../widgets/custom_button.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'post_registration_router_screen.dart';
import 'staff_home_screen.dart';

const bool _showGoogleSignIn = false;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  AnimationController? _marqueeController;
  bool _rememberMe = false;
  bool _isPasswordVisible = false;
  bool _isGoogleLoading = false;

  final List<_LoginFeature> _features = const [
    _LoginFeature(Icons.groups_outlined, '15,000+', 'Active Members'),
    _LoginFeature(Icons.chat_bubble_outline, '100+', 'Daily Discussions'),
    _LoginFeature(Icons.card_giftcard_outlined, 'Weekly', 'Community Rewards'),
    _LoginFeature(Icons.emoji_events_outlined, 'Events', '& Giveaways'),
    _LoginFeature(
        Icons.support_agent_outlined, 'Direct Support', 'From Our Team'),
  ];

  @override
  void initState() {
    super.initState();
    _ensureMarqueeController();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _marqueeController?.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  AnimationController _ensureMarqueeController() {
    return _marqueeController ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberMe = prefs.getBool('remember_me') ?? false;
      if (_rememberMe) {
        _emailController.text = prefs.getString('saved_username') ?? '';
        _passwordController.text = prefs.getString('saved_password') ?? '';
      }
    });
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      await authProvider.login(
        _emailController.text,
        _passwordController.text,
      );

      // Warm up staff data in background so Dashboard opens faster.
      unawaited(_preloadStaffSession(authProvider, chatProvider));

      // Save credentials if Remember Me is checked
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool('remember_me', true);
        await prefs.setString('saved_username', _emailController.text);
        await prefs.setString('saved_password', _passwordController.text);
      } else {
        await prefs.setBool('remember_me', false);
        await prefs.remove('saved_username');
        await prefs.remove('saved_password');
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => authProvider.isStaff
              ? const StaffHomeScreen()
              : const PostRegistrationRouterScreen(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleGoogleLogin() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    setState(() => _isGoogleLoading = true);
    try {
      final googleUser = await GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: AppConfig.googleWebClientId.isNotEmpty
            ? AppConfig.googleWebClientId
            : null,
      ).signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = googleAuth.idToken;
      if (credential == null || credential.isEmpty) {
        throw Exception('Google did not return an ID token.');
      }

      await authProvider.googleLogin(credential);
      unawaited(_preloadStaffSession(authProvider, chatProvider));

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => authProvider.isStaff
              ? const StaffHomeScreen()
              : const PostRegistrationRouterScreen(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _preloadStaffSession(
      AuthProvider authProvider, ChatProvider chatProvider) async {
    try {
      if (!authProvider.isStaff) return;
      final token = authProvider.accessToken;
      if (token == null || token.isEmpty) return;

      await Future.wait([
        chatProvider.fetchActiveChats(authProvider.apiClient),
        chatProvider.fetchSupportStations(authProvider.apiClient),
      ]);

      chatProvider.connectNotifications(token);
      await NotificationService.initialize(authProvider.apiClient);
    } catch (e) {
      debugPrint('LoginScreen: staff preload failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = Provider.of<AuthProvider>(context).isLoading;
    final isBusy = isLoading || _isGoogleLoading;

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
                      child: _buildLoginPanel(isBusy),
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

  // Widget _buildTitleBlock() {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(horizontal: 18),
  //     child: Column(
  //       children: [
  //         Text(
  //           'Hi-Rollin',
  //           textAlign: TextAlign.center,
  //           style: TextStyle(
  //             color: AppTheme.textPrimary,
  //             fontSize: 34,
  //             fontWeight: FontWeight.w900,
  //             height: 1,
  //           ),
  //         ),
  //         const SizedBox(height: 8),
  //         Text(
  //           'The official community for Hi-Rollin players!',
  //           textAlign: TextAlign.center,
  //           style: TextStyle(
  //             color: AppTheme.textSecondary,
  //             fontSize: 14,
  //             fontWeight: FontWeight.w600,
  //             height: 1.35,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

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
            final fullWidth = (_features.length * (itemWidth + 10));
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

  Widget _buildFeatureCard(_LoginFeature feature, double width) {
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

  Widget _buildLoginPanel(bool isLoading) {
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
            'LOGIN',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          // const SizedBox(height: 5),
          // Text(
          //   'Login to continue to Rollin Community',
          //   style: TextStyle(
          //     color: AppTheme.textSecondary,
          //     fontSize: 13,
          //     fontWeight: FontWeight.w600,
          //   ),
          // ),
          const SizedBox(height: 22),
          _buildLabel('Username or email'),
          CustomInput(
            hintText: 'Enter username or email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icon(
              Icons.person_outline,
              color: AppTheme.textSecondary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          _buildLabel('Password'),
          CustomInput(
            hintText: 'Enter your password',
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
                setState(() {
                  _isPasswordVisible = !_isPasswordVisible;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildRememberMe()),
              TextButton(
                onPressed: _openForgotPassword,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          CustomButton(
            text: 'Login',
            onPressed: _handleLogin,
            isLoading: isLoading,
          ),
          if (_showGoogleSignIn) ...[
            const SizedBox(height: 18),
            _buildDivider(),
            const SizedBox(height: 18),
            _buildGoogleButton(isLoading),
          ],
          const SizedBox(height: 18),
          _buildRegisterPrompt(),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppTheme.cardBorder)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'or continue with',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.cardBorder)),
      ],
    );
  }

  Widget _buildGoogleButton(bool isBusy) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: isBusy ? null : _handleGoogleLogin,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          side: BorderSide(color: AppTheme.cardBorder),
          backgroundColor: AppTheme.background.withValues(alpha: 0.20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: _isGoogleLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.textPrimary,
                ),
              )
            : const _GoogleMark(),
        label: Text(
          _isGoogleLoading ? 'Connecting...' : 'Sign in with Google',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildRememberMe() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _rememberMe = !_rememberMe),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: _rememberMe,
            onChanged: (value) {
              setState(() {
                _rememberMe = value ?? false;
              });
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.primary
                  : AppTheme.surface.withValues(alpha: 0.75),
            ),
            checkColor: Colors.white,
            side: BorderSide(color: AppTheme.cardBorder),
          ),
          Flexible(
            child: Text(
              'Remember me',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterPrompt() {
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
              "Don't have an account?",
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _openRegister,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(left: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Create one',
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

  void _openForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
    );
  }

  void _openRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _LoginFeature {
  final IconData icon;
  final String value;
  final String label;

  const _LoginFeature(this.icon, this.value, this.label);
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.16;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - stroke / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -0.05, 1.55,
        false, paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 1.50, 1.55,
        false, paint);
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 3.05, 1.05,
        false, paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 4.10, 1.38,
        false, paint);
    paint
      ..color = const Color(0xFF4285F4)
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(size.width * 0.55, size.height * 0.50),
      Offset(size.width * 0.92, size.height * 0.50),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
