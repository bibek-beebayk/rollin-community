import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class StaffUsersScreen extends StatefulWidget {
  const StaffUsersScreen({super.key});

  @override
  State<StaffUsersScreen> createState() => _StaffUsersScreenState();
}

class _StaffUsersScreenState extends State<StaffUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  String _userType = '';
  String _status = '';
  int _offset = 0;
  int _total = 0;
  bool _hasMore = false;
  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _users = [];

  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _offset = 0;
        _hasMore = false;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
        _error = null;
      });
    }

    try {
      final nextOffset = reset ? 0 : _offset;
      final params = <String, String>{
        'limit': _limit.toString(),
        'offset': nextOffset.toString(),
        if (_userType.isNotEmpty) 'user_type': _userType,
        if (_status.isNotEmpty) 'status': _status,
        if (_searchController.text.trim().isNotEmpty)
          'search': _searchController.text.trim(),
      };
      final suffix = params.entries
          .map((entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
          .join('&');
      final response = await context
          .read<AuthProvider>()
          .apiClient
          .get('/api/auth/users/?$suffix');
      final data = _asMap(response['data'] ?? response);
      final results = _asList(data['results'])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final meta = _asMap(data['meta']);
      final total = _asInt(meta['total'] ?? data['count']);

      if (!mounted) return;
      setState(() {
        _users = reset ? results : [..._users, ...results];
        _stats = _asMap(data['stats']);
        _total = total > 0 ? total : _users.length;
        _offset = nextOffset + results.length;
        _hasMore = results.length == _limit && _users.length < _total;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _load(reset: true);
    });
  }

  void _setUserType(String value) {
    setState(() => _userType = value);
    _load(reset: true);
  }

  void _setStatus(String value) {
    setState(() => _status = value);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _HeaderCard(
                  title: 'User Management',
                  subtitle:
                      'Browse registered players, agents, and staff accounts with quick filters.',
                  icon: Icons.people_alt_outlined,
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.55,
                  children: [
                    _StatCard(
                      label: 'Total Users',
                      value: _formatCount(_stats['total'] ?? _total),
                      icon: Icons.groups_outlined,
                      accent: const Color(0xFF9B5CFF),
                    ),
                    _StatCard(
                      label: 'Players',
                      value: _formatCount(_stats['players']),
                      icon: Icons.sports_esports_outlined,
                      accent: const Color(0xFF2DD4BF),
                    ),
                    _StatCard(
                      label: 'Agents',
                      value: _formatCount(_stats['agents']),
                      icon: Icons.support_agent_outlined,
                      accent: const Color(0xFFFFC857),
                    ),
                    _StatCard(
                      label: 'Staff',
                      value: _formatCount(_stats['staff']),
                      icon: Icons.admin_panel_settings_outlined,
                      accent: const Color(0xFF60A5FA),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _FilterCard(
                  searchController: _searchController,
                  userType: _userType,
                  status: _status,
                  onSearchChanged: _onSearchChanged,
                  onUserTypeChanged: _setUserType,
                  onStatusChanged: _setStatus,
                ),
                const SizedBox(height: 14),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  _StateCard(icon: Icons.error_outline, text: _error!)
                else if (_users.isEmpty)
                  const _StateCard(
                    icon: Icons.person_off_outlined,
                    text: 'No users match these filters.',
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Showing ${_users.length} of $_total',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ..._users.map((user) => _UserCard(user: user)),
                  if (_hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ElevatedButton.icon(
                        onPressed:
                            _isLoadingMore ? null : () => _load(reset: false),
                        icon: _isLoadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_more),
                        label:
                            Text(_isLoadingMore ? 'Loading...' : 'Load More'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  final TextEditingController searchController;
  final String userType;
  final String status;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onUserTypeChanged;
  final ValueChanged<String> onStatusChanged;

  const _FilterCard({
    required this.searchController,
    required this.userType,
    required this.status,
    required this.onSearchChanged,
    required this.onUserTypeChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search username or email',
              hintStyle: TextStyle(color: AppTheme.textSecondary),
              prefixIcon:
                  Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
              filled: true,
              fillColor: AppTheme.background.withValues(alpha: 0.24),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: AppTheme.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: AppTheme.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CompactUserFilterMenu(
                  icon: Icons.people_alt_outlined,
                  value: userType,
                  items: const {
                    '': 'All roles',
                    'player': 'Players',
                    'agent': 'Agents',
                    'staff': 'Staff',
                  },
                  onChanged: onUserTypeChanged,
                ),
                const SizedBox(width: 8),
                _CompactUserFilterMenu(
                  icon: Icons.verified_user_outlined,
                  value: status,
                  items: const {
                    '': 'All status',
                    'active': 'Active',
                    'inactive': 'Inactive',
                    'verified': 'Verified',
                    'unverified': 'Unverified',
                    'test': 'Test',
                  },
                  onChanged: onStatusChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactUserFilterMenu extends StatelessWidget {
  final IconData icon;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _CompactUserFilterMenu({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = items[value] ?? items.values.first;

    return PopupMenuButton<String>(
      tooltip: selectedLabel,
      color: AppTheme.surface,
      onSelected: onChanged,
      itemBuilder: (context) => items.entries.map((entry) {
        final selected = entry.key == value;
        return PopupMenuItem<String>(
          value: entry.key,
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 17,
                color: selected ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                entry.value,
                style: TextStyle(
                  color:
                      selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.background.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.textSecondary, size: 16),
            const SizedBox(width: 6),
            Text(
              selectedLabel,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.textSecondary,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;

  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final username = (user['username'] ?? 'Unknown').toString();
    final email = (user['email'] ?? '').toString();
    final userType = (user['user_type'] ?? 'member').toString();
    final verified = user['is_verified'] == true;
    final active = user['is_active'] != false;
    final imageUrl = _resolveImage(user);
    final externalId = (user['external_user_id'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.22),
            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
            child: imageUrl == null
                ? Text(
                    username.isNotEmpty ? username[0].toUpperCase() : 'U',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _Pill(
                      label: _title(userType),
                      color: _roleColor(userType),
                    ),
                  ],
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(
                      label: active ? 'Active' : 'Inactive',
                      color: active ? const Color(0xFF22C55E) : Colors.red,
                    ),
                    _Pill(
                      label: verified ? 'Verified' : 'Unverified',
                      color: verified ? const Color(0xFF60A5FA) : Colors.amber,
                    ),
                    if (externalId.isNotEmpty)
                      _Pill(
                        label: 'Hi-Rollin: $externalId',
                        color: AppTheme.accent,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppTheme.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _StateCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _asList(dynamic value) {
  if (value is List) return value;
  return const [];
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _formatCount(dynamic value) {
  final count = _asInt(value);
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return count.toString();
}

String _title(String value) {
  return value
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) =>
          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

Color _roleColor(String userType) {
  switch (userType.toLowerCase()) {
    case 'staff':
      return const Color(0xFF60A5FA);
    case 'agent':
      return const Color(0xFFFFC857);
    case 'player':
      return const Color(0xFF2DD4BF);
    default:
      return AppTheme.accent;
  }
}

String? _resolveImage(Map<String, dynamic> user) {
  final raw =
      (user['profile_thumbnail'] ?? user['avatar'] ?? user['profile_picture'])
          ?.toString()
          .trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  final base = AppConfig.baseUrl.endsWith('/')
      ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
      : AppConfig.baseUrl;
  final path = raw.startsWith('/') ? raw : '/$raw';
  return '$base$path';
}
