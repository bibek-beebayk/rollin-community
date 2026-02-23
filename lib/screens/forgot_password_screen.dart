import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/custom_input.dart';
import '../widgets/custom_button.dart';
import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 1;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _resetToken = '';
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleStep1() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await Provider.of<AuthProvider>(context, listen: false)
          .forgotPasswordInit(email);
      if (!mounted) return;
      setState(() {
        _step = 2;
        _isLoading = false;
        _errorMessage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('OTP sent to your registered email.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _handleStep2() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit OTP.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final token = await Provider.of<AuthProvider>(context, listen: false)
          .forgotPasswordVerify(email, otp);
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _step = 3;
        _isLoading = false;
        _errorMessage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP verified. Set your new password.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _handleStep3() async {
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (newPass.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await Provider.of<AuthProvider>(context, listen: false)
          .forgotPasswordConfirm(_resetToken, newPass, confirmPass);

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate back to Login
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Background Blobs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8B5CF6).withValues(alpha: 0.3), // Violet
                    Colors.transparent
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFEC4899).withValues(alpha: 0.3), // Pink
                    Colors.transparent
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),

          // Back Button
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 450),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _buildCurrentStep(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFD8B4FE), Color(0xFFEC4899)],
          ).createShader(bounds),
          child: const Text(
            'Reset Password',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _getSubtitleText(),
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),

        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              width: double.infinity,
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ),

        const SizedBox(height: 32),

        if (_step == 1) _buildStep1Form(),
        if (_step == 2) _buildStep2Form(),
        if (_step == 3) _buildStep3Form(),
      ],
    );
  }

  String _getSubtitleText() {
    switch (_step) {
      case 1:
        return 'Enter your email to receive an OTP.';
      case 2:
        return 'Enter the 6-digit OTP sent to ${_emailController.text}.';
      case 3:
        return 'Create a new password.';
      default:
        return '';
    }
  }

  Widget _buildStep1Form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLabel('Email Address'),
        CustomInput(
          hintText: 'Enter your email',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 24),
        CustomButton(
          text: 'Send OTP',
          onPressed: _handleStep1,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildStep2Form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLabel('OTP Code'),
        CustomInput(
          hintText: 'Enter 6-digit OTP',
          controller: _otpController,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 24),
        CustomButton(
          text: 'Verify OTP',
          onPressed: _handleStep2,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildStep3Form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLabel('New Password'),
        CustomInput(
          hintText: 'Min. 6 characters',
          controller: _newPasswordController,
          obscureText: true,
        ),
        const SizedBox(height: 16),
        _buildLabel('Confirm New Password'),
        CustomInput(
          hintText: 'Re-enter password',
          controller: _confirmPasswordController,
          obscureText: true,
        ),
        const SizedBox(height: 24),
        CustomButton(
          text: 'Reset Password',
          onPressed: _handleStep3,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
