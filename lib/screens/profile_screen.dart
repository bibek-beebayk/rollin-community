// ignore_for_file: use_build_context_synchronously

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'change_password_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploadingPhoto = false;
  bool _isRequestingEmailOtp = false;
  bool _isVerifyingEmailOtp = false;
  bool _isUpdatingAvailability = false;

  String? _buildMediaUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final path = url.startsWith('/') ? url : '/$url';
    return '$base$path';
  }

  String _readableError(Object error) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.replaceFirst('Exception: ', '').trim();
    }
    return raw;
  }

  String _availabilityLabel(String value) {
    switch (value) {
      case 'online':
        return 'Online';
      case 'busy':
        return 'Busy';
      case 'away':
        return 'Away';
      case 'offline':
        return 'Offline';
      default:
        return 'Unknown';
    }
  }

  Future<void> _openAgentAvailabilityDialog() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || !user.isAgent) return;

    String selected = user.agentAvailability;
    final noteController = TextEditingController(text: user.agentStatusNote);

    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: Text('Availability', style: TextStyle(color: AppTheme.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    dropdownColor: AppTheme.surface,
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'online', child: Text('Online')),
                      DropdownMenuItem(value: 'busy', child: Text('Busy')),
                      DropdownMenuItem(value: 'away', child: Text('Away')),
                      DropdownMenuItem(value: 'offline', child: Text('Offline')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setLocalState(() => selected = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLength: 120,
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Optional status note',
                      hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
                      counterStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, {
                    'availability': selected,
                    'note': noteController.text.trim(),
                  }),
                  child: Text('Save', style: TextStyle(color: AppTheme.textPrimary)),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || payload == null) return;
    setState(() => _isUpdatingAvailability = true);
    try {
      await context.read<AuthProvider>().updateAgentAvailability(
            payload['availability'] ?? 'online',
            statusNote: payload['note'] ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readableError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvailability = false);
      }
    }
  }

  Future<void> _changeProfilePicture() async {
    if (_isUploadingPhoto) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (!mounted || result == null) return;

    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;

    setState(() => _isUploadingPhoto = true);
    try {
      await context.read<AuthProvider>().updateProfilePicture(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readableError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  Future<void> _openEmailChangeFlow() async {
    final passwordController = TextEditingController();
    final currentPassword = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(
            'Verify Password',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter current password',
              hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, passwordController.text);
              },
              child: Text(
                'Verify',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted || currentPassword == null || currentPassword.isEmpty) return;

    setState(() => _isRequestingEmailOtp = true);
    try {
      await context.read<AuthProvider>().verifyCurrentPassword(currentPassword);
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRequestingEmailOtp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readableError(e))),
      );
      return;
    }

    final emailController = TextEditingController();
    final newEmail = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Change Email', style: TextStyle(color: AppTheme.textPrimary)),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter new email address',
              hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, emailController.text.trim()),
              child: Text('Continue', style: TextStyle(color: AppTheme.textPrimary)),
            ),
          ],
        );
      },
    );

    if (!mounted || newEmail == null || newEmail.isEmpty) {
      setState(() => _isRequestingEmailOtp = false);
      return;
    }

    try {
      await context
          .read<AuthProvider>()
          .requestEmailChangeOTP(newEmail, currentPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP sent to $newEmail')),
      );
      await _openEmailOtpDialog(newEmail);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readableError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isRequestingEmailOtp = false);
      }
    }
  }

  Future<void> _openEmailOtpDialog(String newEmail) async {
    final otpController = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: !_isVerifyingEmailOtp,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: Text('Verify OTP', style: TextStyle(color: AppTheme.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter the OTP sent to $newEmail',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpController,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: '6-digit OTP',
                      hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75)),
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _isVerifyingEmailOtp ? null : () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                TextButton(
                  onPressed: _isVerifyingEmailOtp
                      ? null
                      : () async {
                          final otp = otpController.text.trim();
                          if (otp.length != 6) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid 6-digit OTP.')),
                            );
                            return;
                          }
                          setState(() => _isVerifyingEmailOtp = true);
                          setLocalState(() {});
                          try {
                            await this
                                .context
                                .read<AuthProvider>()
                                .verifyEmailChangeOTP(newEmail, otp);
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('Email changed successfully.')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text(_readableError(e))),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _isVerifyingEmailOtp = false);
                              setLocalState(() {});
                            }
                          }
                        },
                  child: _isVerifyingEmailOtp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Verify', style: TextStyle(color: AppTheme.textPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final imageUrl = _buildMediaUrl(user?.profilePicture ?? user?.avatar);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profile',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _changeProfilePicture,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppTheme.primary,
                          backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                          child: imageUrl == null
                              ? Text(
                                  user?.username.isNotEmpty == true
                                      ? user!.username[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: _isUploadingPhoto
                                ? const SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    size: 12,
                                    color: Colors.black,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.username ?? 'Unknown User',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'ACCOUNT',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.email_outlined, color: AppTheme.textPrimary),
              title: Text('Change Email', style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text(
                'OTP verification required',
                style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75), fontSize: 12),
              ),
              trailing: _isRequestingEmailOtp
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.arrow_forward_ios, color: AppTheme.textSecondary.withValues(alpha: 0.75), size: 16),
              tileColor: AppTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: _isRequestingEmailOtp ? null : _openEmailChangeFlow,
            ),
            const SizedBox(height: 8),
            if (user?.isAgent == true) ...[
              ListTile(
                leading: Icon(Icons.support_agent, color: AppTheme.textPrimary),
                title: Text(
                  'Set Availability',
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
                subtitle: Text(
                  _availabilityLabel(user?.agentAvailability ?? 'online'),
                  style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.75), fontSize: 12),
                ),
                trailing: _isUpdatingAvailability
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.arrow_forward_ios,
                        color: AppTheme.textSecondary.withValues(alpha: 0.75),
                        size: 16,
                      ),
                tileColor: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: _isUpdatingAvailability ? null : _openAgentAvailabilityDialog,
              ),
              const SizedBox(height: 8),
            ],
            ListTile(
              leading: Icon(Icons.lock_reset, color: AppTheme.textPrimary),
              title: Text('Change Password', style: TextStyle(color: AppTheme.textPrimary)),
              trailing: Icon(Icons.arrow_forward_ios, color: AppTheme.textSecondary.withValues(alpha: 0.75), size: 16),
              tileColor: AppTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
