import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/custom_button.dart';
import '../theme/app_theme.dart';

class VerifyOtpScreen extends StatefulWidget {
  final String email;

  const VerifyOtpScreen({super.key, required this.email});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  int _resendCooldown = 60;
  int _expiresIn = 30 * 60; // 30 minutes
  Timer? _timer;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _startTimers();
  }

  void _startTimers() {
    _startResendTimer();
    _startExpiryTimer();
  }

  void _startResendTimer() {
    _resendCooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_resendCooldown > 0) {
            _resendCooldown--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_expiresIn > 0) {
            _expiresIn--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _expiryTimer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final otp = _controllers.map((c) => c.text).join();
    if (otp.length != 6) {
      _showError('Please enter all 6 digits');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Provider.of<AuthProvider>(context, listen: false)
          .verifyOTP(widget.email, otp);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification successful!'),
            backgroundColor: Colors.green,
          ),
        );
        // Pop back to root - AuthWrapper will show Dashboard
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
      // Clear OTP on error
      for (var c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResend() async {
    if (_resendCooldown > 0) return;

    setState(() => _isLoading = true);

    try {
      await Provider.of<AuthProvider>(context, listen: false)
          .resendOTP(widget.email);

      _showSuccess('OTP resent successfully');
      _startResendTimer();
      // Reset expiry
      setState(() => _expiresIn = 30 * 60);
      _startExpiryTimer();

      // Clear inputs
      for (var c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    // Auto submit if last digit filled
    if (index == 5 && value.isNotEmpty) {
      // Check if all filled
      if (_controllers.every((c) => c.text.isNotEmpty)) {
        _handleVerify();
      }
    }
  }

  // Handle paste
  void _onPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.length == 6 && int.tryParse(text) != null) {
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = text[i];
      }
      _handleVerify();
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
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
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 64,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Verify Email',
                    style: AppTheme.theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We sent a 6-digit code to',
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                  Text(
                    widget.email,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // OTP Inputs
                  GestureDetector(
                    onLongPress:
                        _onPaste, // Allow paste via long press context menu usually, or just custom logic
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(6, (index) {
                        return SizedBox(
                          width: 45,
                          height: 55,
                          child: TextField(
                            controller: _controllers[index],
                            focusNode: _focusNodes[index],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.1),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.2)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: AppTheme.primary, width: 2),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onChanged: (value) {
                              if (value.isNotEmpty) {
                                _onDigitChanged(index, value);
                              } else if (index > 0) {
                                // Backspace logic handled by keyboard usually, but onChanged empty might imply backspace
                                // _focusNodes[index - 1].requestFocus();
                                // TextField onChanged doesn't fire for backspace on empty.
                              }
                            },
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 32),

                  CustomButton(
                    text: 'Verify Email',
                    onPressed: _handleVerify,
                    isLoading: _isLoading,
                  ),

                  const SizedBox(height: 24),

                  // Timer & Resend
                  if (_expiresIn > 0)
                    Text(
                      'Code expires in ${_formatTime(_expiresIn)}',
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    )
                  else
                    const Text(
                      'Code expired',
                      style: TextStyle(color: Colors.redAccent),
                    ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: (_resendCooldown > 0 || _isLoading)
                        ? null
                        : _handleResend,
                    child: Text(
                      _resendCooldown > 0
                          ? 'Resend OTP in ${_resendCooldown}s'
                          : 'Resend OTP',
                      style: TextStyle(
                          color: _resendCooldown > 0
                              ? Colors.white38
                              : AppTheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
