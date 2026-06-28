import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'analytics_screen.dart';
import 'announcements_screen.dart';
import 'app_settings_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'staff_users_screen.dart';

class StaffHomeScreen extends StatefulWidget {
  final int initialIndex;

  const StaffHomeScreen({super.key, this.initialIndex = 0});

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 1).toInt();
  }

  Future<void> _openDrawerScreen(Widget screen) async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _openChatDashboardFromDrawer() {
    Navigator.of(context).pop();
    setState(() => _currentIndex = 1);
  }

  Future<void> _logout() async {
    Navigator.of(context).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Log Out', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    await authProvider.logout();
    chatProvider.disconnect();
    chatProvider.disconnectNotifications();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildStaffDrawer(dynamic user) {
    final username = user?.username ?? 'Staff';
    final userType = _formatUserType(user?.userType);

    return Drawer(
      backgroundColor: AppTheme.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.24),
                    child: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          userType,
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
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _StaffDrawerSectionTitle('Staff'),
                  _StaffDrawerNavTile(
                    icon: Icons.analytics_outlined,
                    label: 'Analytics',
                    onTap: () => _openDrawerScreen(const AnalyticsScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.campaign_outlined,
                    label: 'Announcements',
                    onTap: () => _openDrawerScreen(const AnnouncementsScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.help_outline,
                    label: 'FAQ',
                    onTap: () => _openDrawerScreen(const FAQScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.people_alt_outlined,
                    label: 'Users',
                    onTap: () => _openDrawerScreen(const StaffUsersScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    onTap: _openChatDashboardFromDrawer,
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.card_giftcard_outlined,
                    label: 'Redemptions',
                    onTap: () =>
                        _openDrawerScreen(const RewardRedemptionsScreen()),
                  ),
                  _StaffDrawerNavTile(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => _openDrawerScreen(const AppSettingsScreen()),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: AppTheme.textSecondary.withValues(alpha: 0.55),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      endDrawer: _buildStaffDrawer(user),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          StaffDashboardOverview(
            onOpenMenu: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          const DashboardScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.cardBorder),
              boxShadow: AppTheme.visualStyle == VisualStyle.card
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                _StaffNavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  label: 'Dashboard',
                  selected: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _StaffNavItem(
                  icon: Icons.support_agent_outlined,
                  activeIcon: Icons.support_agent,
                  label: 'Chat Dashboard',
                  selected: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StaffDashboardOverview extends StatefulWidget {
  final VoidCallback onOpenMenu;

  const StaffDashboardOverview({super.key, required this.onOpenMenu});

  @override
  State<StaffDashboardOverview> createState() => _StaffDashboardOverviewState();
}

class _StaffDashboardOverviewState extends State<StaffDashboardOverview> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _redemptions = const [];
  List<Map<String, dynamic>> _activity = const [];

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
      final apiClient = context.read<AuthProvider>().apiClient;
      final responses = await Future.wait([
        apiClient.get('/api/analytics/home-stats/'),
        apiClient.get('/api/rewards/streak/redemptions/'),
        apiClient.get('/api/analytics/recent-activity/?limit=6'),
      ]);

      if (!mounted) return;
      setState(() {
        _stats = _asMap(responses[0]['data'] ?? responses[0]);
        _redemptions = _extractList(responses[1])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _activity = _extractList(responses[2])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
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

  void _openScreen(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final pending =
        _redemptions.where((item) => item['status'] == 'pending').toList();
    final approved =
        _redemptions.where((item) => item['status'] == 'approved').toList();
    final completedToday = _redemptions.where((item) {
      if (item['status'] != 'completed' || item['completed_at'] == null) {
        return false;
      }
      final completedAt = DateTime.tryParse(item['completed_at'].toString());
      if (completedAt == null) return false;
      final now = DateTime.now();
      return completedAt.year == now.year &&
          completedAt.month == now.month &&
          completedAt.day == now.day;
    }).toList();
    final activeRequests = _redemptions
        .where((item) =>
            item['status'] == 'pending' || item['status'] == 'approved')
        .toList();
    final activeValue = activeRequests.fold<double>(
      0,
      (sum, item) => sum + (double.tryParse('${item['amount'] ?? 0}') ?? 0),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Staff Menu',
            onPressed: widget.onOpenMenu,
            icon: const Icon(Icons.menu_rounded),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              children: [
                _StaffHeader(isLoading: _isLoading),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _StateCard(icon: Icons.error_outline, text: _error!),
                ],
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.25,
                  children: [
                    _MetricCard(
                      label: 'Active Members',
                      value: _isLoading
                          ? '...'
                          : _formatCount(_stats['active_members']),
                      detail: 'Registered accounts',
                      icon: Icons.groups_outlined,
                      accent: const Color(0xFF8B5CF6),
                    ),
                    _MetricCard(
                      label: 'Online Now',
                      value: _isLoading
                          ? '...'
                          : _formatCount(_stats['online_now']),
                      detail: 'Seen recently',
                      icon: Icons.sensors_outlined,
                      accent: const Color(0xFF22C55E),
                    ),
                    _MetricCard(
                      label: 'Pending Requests',
                      value: _isLoading ? '...' : pending.length.toString(),
                      detail: 'Need review',
                      icon: Icons.redeem_outlined,
                      accent: const Color(0xFFF59E0B),
                    ),
                    _MetricCard(
                      label: 'Approved Queue',
                      value: _isLoading ? '...' : approved.length.toString(),
                      detail: 'Ready to complete',
                      icon: Icons.check_circle_outline,
                      accent: const Color(0xFF60A5FA),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _RedemptionQueuePanel(
                  activeValue: activeValue,
                  pending: pending.length,
                  approved: approved.length,
                  completedToday: completedToday.length,
                  redemptions: _redemptions,
                  onOpen: () => _openScreen(const RewardRedemptionsScreen()),
                ),
                const SizedBox(height: 14),
                _ActivityPanel(activity: _activity, isLoading: _isLoading),
                const SizedBox(height: 14),
                _QuickActions(
                  onAnnouncements: () =>
                      _openScreen(const AnnouncementsScreen()),
                  onAnalytics: () => _openScreen(const AnalyticsScreen()),
                  onUsers: () => _openScreen(const StaffUsersScreen()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffHeader extends StatelessWidget {
  final bool isLoading;

  const _StaffHeader({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.insights_outlined, color: AppTheme.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Staff Home',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Dashboard',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Monitor community activity, reward requests, and queues.',
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

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RedemptionQueuePanel extends StatelessWidget {
  final double activeValue;
  final int pending;
  final int approved;
  final int completedToday;
  final List<Map<String, dynamic>> redemptions;
  final VoidCallback onOpen;

  const _RedemptionQueuePanel({
    required this.activeValue,
    required this.pending,
    required this.approved,
    required this.completedToday,
    required this.redemptions,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Redemption Queue',
      subtitle: '\$${activeValue.toStringAsFixed(2)} awaiting staff action',
      actionLabel: 'Open',
      onAction: onOpen,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _QueueStat(label: 'Pending', value: pending)),
              const SizedBox(width: 8),
              Expanded(child: _QueueStat(label: 'Approved', value: approved)),
              const SizedBox(width: 8),
              Expanded(
                child: _QueueStat(
                  label: 'Done Today',
                  value: completedToday,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...const [
            ('login_streak', 'Login Streak'),
            ('scratch_bonus', 'Scratch Bonus'),
            ('win_bonus', 'Win Bonus'),
          ].map((source) {
            final active = redemptions
                .where((item) =>
                    item['source'] == source.$1 &&
                    (item['status'] == 'pending' ||
                        item['status'] == 'approved'))
                .toList();
            final value = active.fold<double>(
              0,
              (sum, item) =>
                  sum + (double.tryParse('${item['amount'] ?? 0}') ?? 0),
            );
            return _SourceRow(
              label: source.$2,
              count: active.length,
              value: value,
            );
          }),
        ],
      ),
    );
  }
}

class _QueueStat extends StatelessWidget {
  final String label;
  final int value;

  const _QueueStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final String label;
  final int count;
  final double value;

  const _SourceRow({
    required this.label,
    required this.count,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$count active requests',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$${value.toStringAsFixed(2)}',
            style: TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  final List<Map<String, dynamic>> activity;
  final bool isLoading;

  const _ActivityPanel({required this.activity, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Recent Activity',
      subtitle: 'Latest important community events',
      child: isLoading
          ? _EmptyText('Loading activity...')
          : activity.isEmpty
              ? _EmptyText('No recent activity yet.')
              : Column(
                  children: activity.map((item) {
                    final actor = _asMap(item['actor']);
                    final actorName =
                        (actor['username'] ?? 'Community').toString();
                    final title = _formatActivityTitle(item);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.background.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.20),
                            child: Text(
                              actorName.isNotEmpty
                                  ? actorName[0].toUpperCase()
                                  : 'C',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  actorName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
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

class _QuickActions extends StatelessWidget {
  final VoidCallback onAnnouncements;
  final VoidCallback onAnalytics;
  final VoidCallback onUsers;

  const _QuickActions({
    required this.onAnnouncements,
    required this.onAnalytics,
    required this.onUsers,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _QuickAction(
          title: 'Announcements',
          subtitle: 'Create and manage admin announcements.',
          icon: Icons.campaign_outlined,
          onTap: onAnnouncements,
        ),
        _QuickAction(
          title: 'Analytics',
          subtitle: 'View deeper traffic and user insights.',
          icon: Icons.analytics_outlined,
          onTap: onAnalytics,
        ),
        _QuickAction(
          title: 'Users',
          subtitle: 'Browse and filter community accounts.',
          icon: Icons.people_alt_outlined,
          onTap: onUsers,
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppTheme.accent),
        title: Text(
          title,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
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
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  final String text;

  const _EmptyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StaffNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.20)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: AppTheme.primary.withValues(alpha: 0.34))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? activeIcon : icon,
                color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffDrawerSectionTitle extends StatelessWidget {
  final String text;

  const _StaffDrawerSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.72),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _StaffDrawerNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _StaffDrawerNavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.textSecondary, size: 20),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatUserType(dynamic value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return 'Staff';
  return raw
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) =>
          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _extractList(dynamic response) {
  if (response is List) return response;
  if (response is Map) {
    final data = response['data'];
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    if (response['results'] is List) return response['results'] as List;
  }
  return const [];
}

String _formatCount(dynamic value) {
  final count = value is num ? value.round() : int.tryParse('$value') ?? 0;
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return count.toString();
}

String _formatActivityTitle(Map<String, dynamic> item) {
  final action = (item['action'] ?? '').toString();
  final target = (item['target_title'] ?? '').toString();
  if (action.isNotEmpty && target.isNotEmpty) return '$action: $target';
  if (action.isNotEmpty) return action;
  return (item['kind'] ?? 'Activity').toString();
}
