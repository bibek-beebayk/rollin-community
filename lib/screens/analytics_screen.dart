import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _days = 30;
  String _userType = '';
  String _eventType = '';
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _dashboard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = <String, String>{
        'days': _days.toString(),
        if (_userType.isNotEmpty) 'user_type': _userType,
        if (_eventType.isNotEmpty) 'event_type': _eventType,
      };
      final suffix = query.entries
          .map((entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
          .join('&');
      final response = await context
          .read<AuthProvider>()
          .apiClient
          .get('/api/analytics/dashboard/?$suffix');
      final data = _asMap(response['data'] ?? response);
      if (!mounted) return;
      setState(() {
        _dashboard = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kpis = _asMap(_dashboard?['kpis']);
    final recentEvents = _asList(_dashboard?['recent_events']);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _HeaderCard(
                  title: 'Staff Analytics',
                  subtitle:
                      'Track visits, registrations, logins, traffic sources, and the pages players use most.',
                  icon: Icons.analytics_outlined,
                ),
                const SizedBox(height: 14),
                _FilterPanel(
                  days: _days,
                  userType: _userType,
                  eventType: _eventType,
                  onDaysChanged: (value) {
                    setState(() => _days = value);
                    _load();
                  },
                  onUserTypeChanged: (value) {
                    setState(() => _userType = value);
                    _load();
                  },
                  onEventTypeChanged: (value) {
                    setState(() => _eventType = value);
                    _load();
                  },
                ),
                const SizedBox(height: 10),
                if (_isLoading)
                  const _LoadingBlock()
                else if (_error != null)
                  _StateCard(icon: Icons.error_outline, text: _error!)
                else ...[
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.35,
                    children: [
                      _MetricCard(
                        label: 'Visits',
                        value: _formatCount(kpis['visits']),
                        icon: Icons.remove_red_eye_outlined,
                        accent: const Color(0xFF9B5CFF),
                      ),
                      _MetricCard(
                        label: 'Unique Visitors',
                        value: _formatCount(kpis['unique_visitors']),
                        icon: Icons.person_search_outlined,
                        accent: const Color(0xFF2DD4BF),
                      ),
                      _MetricCard(
                        label: 'Registrations',
                        value: _formatCount(kpis['registrations']),
                        icon: Icons.person_add_alt_1_outlined,
                        accent: const Color(0xFFFFC857),
                      ),
                      _MetricCard(
                        label: 'Logins',
                        value: _formatCount(kpis['logins']),
                        icon: Icons.login_outlined,
                        accent: const Color(0xFF60A5FA),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _BucketPanel(
                    title: 'Top Pages',
                    items: _asList(_dashboard?['top_pages']),
                    emptyText: 'No page data yet.',
                  ),
                  _BucketPanel(
                    title: 'Traffic Sources',
                    items: _asList(_dashboard?['traffic_sources']),
                    emptyText: 'No source data yet.',
                  ),
                  _BucketPanel(
                    title: 'Devices',
                    items: _asList(_dashboard?['devices']),
                    emptyText: 'No device data yet.',
                  ),
                  _BucketPanel(
                    title: 'User Types',
                    items: _asList(_dashboard?['user_types']),
                    emptyText: 'No user type data yet.',
                  ),
                  _SectionCard(
                    title: 'Recent Events',
                    child: recentEvents.isEmpty
                        ? Text(
                            'No analytics events yet.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          )
                        : Column(
                            children: recentEvents
                                .map((item) => _RecentEventTile(
                                      event: _asMap(item),
                                    ))
                                .toList(),
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

class _FilterPanel extends StatelessWidget {
  final int days;
  final String userType;
  final String eventType;
  final ValueChanged<int> onDaysChanged;
  final ValueChanged<String> onUserTypeChanged;
  final ValueChanged<String> onEventTypeChanged;

  const _FilterPanel({
    required this.days,
    required this.userType,
    required this.eventType,
    required this.onDaysChanged,
    required this.onUserTypeChanged,
    required this.onEventTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _CompactFilterMenu<int>(
              icon: Icons.date_range_outlined,
              value: days,
              items: const {
                7: '7d',
                30: '30d',
                90: '90d',
              },
              onChanged: onDaysChanged,
            ),
            const SizedBox(width: 8),
            _CompactFilterMenu<String>(
              icon: Icons.people_alt_outlined,
              value: userType,
              items: const {
                '': 'All users',
                'player': 'Players',
                'agent': 'Agents',
                'staff': 'Staff',
              },
              onChanged: onUserTypeChanged,
            ),
            const SizedBox(width: 8),
            _CompactFilterMenu<String>(
              icon: Icons.bolt_outlined,
              value: eventType,
              items: const {
                '': 'All events',
                'page_view': 'Page views',
                'register': 'Registers',
                'login': 'Logins',
                'redemption': 'Redemptions',
              },
              onChanged: onEventTypeChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactFilterMenu<T> extends StatelessWidget {
  final IconData icon;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  const _CompactFilterMenu({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = items[value] ?? items.values.first;

    return PopupMenuButton<T>(
      tooltip: selectedLabel,
      color: AppTheme.surface,
      onSelected: onChanged,
      itemBuilder: (context) => items.entries.map((entry) {
        final selected = entry.key == value;
        return PopupMenuItem<T>(
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

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _MetricCard({
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BucketPanel extends StatelessWidget {
  final String title;
  final List<dynamic> items;
  final String emptyText;

  const _BucketPanel({
    required this.title,
    required this.items,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final max = items
        .map((item) => _asInt(_asMap(item)['count']))
        .fold<int>(0, (current, count) => count > current ? count : current);

    return _SectionCard(
      title: title,
      child: items.isEmpty
          ? Text(emptyText, style: TextStyle(color: AppTheme.textSecondary))
          : Column(
              children: items.take(6).map((item) {
                final map = _asMap(item);
                final label = (map['label'] ?? 'Unknown').toString();
                final count = _asInt(map['count']);
                final progress = max == 0 ? 0.0 : count / max;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label.isEmpty ? 'Unknown' : label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            _formatCount(count),
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor:
                              AppTheme.textSecondary.withValues(alpha: 0.12),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _RecentEventTile extends StatelessWidget {
  final Map<String, dynamic> event;

  const _RecentEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final user = _asMap(event['user']);
    final username = user['username']?.toString();
    final eventName = (event['event_name'] ?? event['event_type'] ?? 'Event')
        .toString()
        .replaceAll('_', ' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.20),
            child: Icon(Icons.bolt_outlined, color: AppTheme.accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(eventName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (username != null && username.isNotEmpty) username,
                    if ((event['path'] ?? '').toString().isNotEmpty)
                      event['path'].toString(),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: CircularProgressIndicator(),
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
