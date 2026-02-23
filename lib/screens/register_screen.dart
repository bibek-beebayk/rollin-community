import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/custom_input.dart';
import '../widgets/custom_button.dart';
import '../theme/app_theme.dart';
import 'verify_otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _userType = 'player'; // Default to player
  bool _isLoading = false;

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
              confirmPassword: confirmPassword);

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
      body: Container(
        decoration: const BoxDecoration(
          color: AppTheme.background,
          image: DecorationImage(
            image: AssetImage('assets/background_pattern.png'),
            fit: BoxFit.cover,
            opacity: 0.1,
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo or Title
                  const Icon(
                    Icons.person_add_outlined,
                    size: 64,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: AppTheme.theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join Rollin Community today!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // User Type Selection
                  Text(
                    'I AM A...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _UserTypeButton(
                          label: 'Player',
                          isSelected: _userType == 'player',
                          onTap: () => setState(() => _userType = 'player'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _UserTypeButton(
                          label: 'Agent',
                          isSelected: _userType == 'agent',
                          onTap: () => setState(() => _userType = 'agent'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Inputs
                  CustomInput(
                    hintText: 'Username',
                    controller: _usernameController,
                    prefixIcon:
                        const Icon(Icons.person_outline, color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  CustomInput(
                    hintText: 'Email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon:
                        const Icon(Icons.email_outlined, color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  CustomInput(
                    hintText: 'Password',
                    controller: _passwordController,
                    obscureText: true,
                    prefixIcon:
                        const Icon(Icons.lock_outline, color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  CustomInput(
                    hintText: 'Confirm Password',
                    controller: _confirmPasswordController,
                    obscureText: true,
                    prefixIcon:
                        const Icon(Icons.lock_outline, color: Colors.white54),
                  ),
                  const SizedBox(height: 32),

                  CustomButton(
                    text: 'Create Account',
                    onPressed: _handleRegister,
                    isLoading: _isLoading,
                  ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          'Sign In',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserTypeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _UserTypeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color:
                isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color:
                  isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
