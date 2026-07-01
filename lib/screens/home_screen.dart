// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../models/event.dart';
import '../models/login_streak.dart';
import '../models/post.dart';
import '../services/event_service.dart';
import '../services/post_service.dart';
import '../services/reward_service.dart';
import '../services/notification_service.dart';
import '../api/api_client.dart';
import 'package:video_player/video_player.dart';
import 'change_password_screen.dart';
import 'post_details_screen.dart';
import 'post_feed_screen.dart';
import 'agent_search_screen.dart';
import '../widgets/share_post_to_chat_dialog.dart';

class HomeScreen extends StatefulWidget {
  final bool showAppBar;
  final VoidCallback? onOpenCommunityFeed;

  const HomeScreen({
    super.key,
    this.showAppBar = true,
    this.onOpenCommunityFeed,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Event> _events = [];
  bool _isLoadingEvents = true;
  List<Event> _recentEvents = [];
  bool _isLoadingRecentEvents = true;
  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoadingRecentActivity = true;

  List<Post> _communityPosts = [];
  bool _isLoadingPosts = true;
  Map<String, dynamic>? _homeInfo;
  bool _isLoadingHomeInfo = true;
  LoginStreakStatus? _streak;
  bool _isLoadingStreak = true;
  bool _isRedeemingStreak = false;
  String? _streakError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchEvents();
      _fetchRecentEvents();
      _fetchRecentActivity();
      _fetchPosts();
      _fetchHomeInfo();
      _loadStreak(recordVisit: true);
    });
  }

  Future<void> _fetchEvents() async {
    final authProvider = context.read<AuthProvider>();
    final eventService = EventService(authProvider.apiClient);

    // Initialize notifications (permissions + FCM token)
    NotificationService.initialize(authProvider.apiClient);

    try {
      final events = await eventService.getActiveEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading events: $e');
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  Future<void> _fetchRecentEvents() async {
    final authProvider = context.read<AuthProvider>();
    final eventService = EventService(authProvider.apiClient);

    try {
      final events = await eventService.getUpcomingEvents(limit: 5);
      if (mounted) {
        setState(() {
          _recentEvents = events.take(5).toList();
          _isLoadingRecentEvents = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading recent events: $e');
      if (mounted) {
        setState(() {
          _isLoadingRecentEvents = false;
        });
      }
    }
  }

  Future<void> _fetchRecentActivity() async {
    final authProvider = context.read<AuthProvider>();

    try {
      final response = await authProvider.apiClient
          .get('/api/analytics/recent-activity/?limit=5');
      final data = _extractList(response);
      if (mounted) {
        setState(() {
          _recentActivity = data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .take(5)
              .toList();
          _isLoadingRecentActivity = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading recent activity: $e');
      if (mounted) {
        setState(() {
          _isLoadingRecentActivity = false;
        });
      }
    }
  }

  Future<void> _fetchPosts() async {
    final authProvider = context.read<AuthProvider>();
    final postService = PostService(authProvider.apiClient);

    try {
      final results = await Future.wait([
        postService.getLatestPosts(),
        postService.getFeedPosts(),
      ]);
      final pinnedPosts = results[0];
      final feedPosts = results[1];
      final pinnedIds = pinnedPosts.map((post) => post.id).toSet();
      final recentPosts = feedPosts
          .where((post) => !pinnedIds.contains(post.id))
          .take(5)
          .toList();

      if (mounted) {
        setState(() {
          _communityPosts = [...pinnedPosts, ...recentPosts];
          _isLoadingPosts = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    // Optional: Only show loading indicators if desired,
    // but RefreshIndicator already has a spinner.
    await Future.wait([
      _fetchEvents(),
      _fetchRecentEvents(),
      _fetchRecentActivity(),
      _fetchPosts(),
      _fetchHomeInfo(),
      _loadStreak(recordVisit: false),
    ]);
  }

  bool _isPlayer(dynamic user) {
    return (user?.userType ?? '').toString().toLowerCase() == 'player';
  }

  bool _isAgent(dynamic user) {
    return (user?.userType ?? '').toString().toLowerCase() == 'agent';
  }

  Future<void> _loadStreak({required bool recordVisit}) async {
    final authProvider = context.read<AuthProvider>();
    if (!_isPlayer(authProvider.user)) {
      if (mounted) {
        setState(() {
          _isLoadingStreak = false;
          _streak = null;
          _streakError = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingStreak = true;
        _streakError = null;
      });
    }

    final rewardService = RewardService(authProvider.apiClient);
    try {
      final streak = recordVisit
          ? await rewardService.recordVisit()
          : await rewardService.getStreak();
      if (!mounted) return;
      setState(() {
        _streak = streak;
        _isLoadingStreak = false;
      });
    } catch (e) {
      if (recordVisit) {
        try {
          final streak = await rewardService.getStreak();
          if (!mounted) return;
          setState(() {
            _streak = streak;
            _isLoadingStreak = false;
          });
          return;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _streakError = e.toString().replaceAll('Exception: ', '');
        _isLoadingStreak = false;
      });
    }
  }

  Future<void> _requestStreakRedemption() async {
    final authProvider = context.read<AuthProvider>();
    setState(() {
      _isRedeemingStreak = true;
      _streakError = null;
    });

    try {
      await RewardService(authProvider.apiClient).requestRedemption();
      await _loadStreak(recordVisit: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _streakError = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isRedeemingStreak = false);
      }
    }
  }

  String _homeInfoText(dynamic value) {
    return (value ?? '').toString().trim();
  }

  List<Map<String, String>> _homeInfoPoints() {
    final points = <Map<String, String>>[];
    final dynamic pointsRaw = _homeInfo?['points'];
    if (pointsRaw is! List) return points;

    for (final item in pointsRaw) {
      if (item is! Map) continue;
      final content = _homeInfoText(item['content']);
      if (content.isEmpty) continue;
      final icon = (item['icon'] ?? 'info_outline').toString().trim();
      points.add({
        'icon': icon.isEmpty ? 'info_outline' : icon,
        'content': content,
      });
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final user = context.watch<AuthProvider>().user;

    final showLiveEventsSection = _isLoadingEvents || _events.isNotEmpty;
    final showCommunityPostsSection =
        _isLoadingPosts || _communityPosts.isNotEmpty;
    final showRecentCards = _isPlayer(user) || _isAgent(user);
    final showRoleInfo = !_isLoadingHomeInfo && _hasRenderableHomeInfo();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: widget.showAppBar,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('Rollin Community',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          top: widget.showAppBar,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.accent,
            backgroundColor: AppTheme.surface,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // _buildHeroCard(user),
                  // const SizedBox(height: 16),
                  if (user?.hasUsablePassword == false) ...[
                    _buildPasswordSetupNotice(),
                    const SizedBox(height: 16),
                  ],
                  if (_isPlayer(user)) ...[
                    _buildPlayerQuickCards(context),
                    // const SizedBox(height: 16),
                    _buildSectionSeparator(),
                  ],
                  if (showRoleInfo) ...[
                    _buildRoleInfoSection(user),
                    _buildSectionSeparator(),
                  ],
                  if (showCommunityPostsSection) ...[
                    _buildHomeSection(
                      title: 'Community Posts',
                      child: _buildCommunityPostsList(),
                    ),
                    _buildSectionSeparator(),
                  ],
                  if (showLiveEventsSection) ...[
                    _buildHomeSection(
                      title: 'Live Events',
                      child: _buildEventsList(),
                    ),
                    _buildSectionSeparator(),
                  ],
                  if (showRecentCards) ...[
                    _buildRecentEventsCard(),
                    _buildSectionSeparator(compact: true),
                    _buildRecentActivityCard(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(dynamic user) {
    final username = (user?.username ?? 'Player').toString();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.28)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.28),
            AppTheme.surface.withValues(alpha: 0.92),
            AppTheme.accent.withValues(alpha: 0.10),
          ],
        ),
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WELCOME BACK',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _capitalizeUsername(username),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  'Catch the latest pinned posts, live events, and community rewards.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppTheme.background.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
            ),
            padding: const EdgeInsets.all(8),
            child: Image.asset('assets/icon.png', fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordSetupNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          AppTheme.accent.withValues(alpha: 0.10),
          AppTheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
        boxShadow: AppTheme.visualStyle == VisualStyle.card
            ? [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.lock_reset_outlined,
              color: AppTheme.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set up your password',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You signed in with Google. Add a password so you can also log in with your username or email.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChangePasswordScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                    label: const Text('Set password'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      backgroundColor: AppTheme.accent.withValues(alpha: 0.18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchHomeInfo() async {
    final authProvider = context.read<AuthProvider>();
    try {
      final response = await authProvider.apiClient.get('/api/auth/home-info/');
      final data = (response is Map && response.containsKey('data'))
          ? response['data']
          : response;
      if (mounted) {
        setState(() {
          _homeInfo = data is Map<String, dynamic> ? data : null;
          _isLoadingHomeInfo = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading home info: $e');
      if (mounted) {
        setState(() {
          _isLoadingHomeInfo = false;
        });
      }
    }
  }

  bool _hasRenderableHomeInfo() {
    final title = _homeInfoText(_homeInfo?['title']);
    final subtitle = _homeInfoText(_homeInfo?['subtitle']);
    final footer = _homeInfoText(_homeInfo?['footer']);
    final hasPoints = _homeInfoPoints().isNotEmpty;

    return title.isNotEmpty ||
        subtitle.isNotEmpty ||
        footer.isNotEmpty ||
        hasPoints;
  }

  Widget _buildRoleInfoSection(dynamic user) {
    final title = _homeInfoText(_homeInfo?['title']);
    final subtitle = _homeInfoText(_homeInfo?['subtitle']);
    final footer = _homeInfoText(_homeInfo?['footer']);
    final serverPoints = _homeInfoPoints();

    if (_isLoadingHomeInfo || !_hasRenderableHomeInfo()) {
      return const SizedBox.shrink();
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final titleColor = isLight ? const Color(0xFF1F2937) : AppTheme.textPrimary;
    final subtitleColor = isLight
        ? const Color(0xFF475569)
        : AppTheme.textPrimary.withValues(alpha: 0.65);
    final pointColor = isLight
        ? const Color(0xFF334155)
        : AppTheme.textPrimary.withValues(alpha: 0.9);
    final footerColor = isLight
        ? const Color(0xFF64748B)
        : AppTheme.textSecondary.withValues(alpha: 0.9);
    final dividerColor = isLight
        ? const Color(0xFF94A3B8).withValues(alpha: 0.35)
        : AppTheme.textPrimary.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.itemDecoration(
        customRadius: BorderRadius.circular(AppTheme.radius + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (title.isNotEmpty && subtitle.isNotEmpty)
            const SizedBox(height: 4),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: TextStyle(
                color: subtitleColor,
                fontSize: 12,
              ),
            ),
          if (serverPoints.isNotEmpty) const SizedBox(height: 12),
          ...serverPoints.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        _iconFromName(
                            (point['icon'] ?? 'info_outline').toString()),
                        size: 16,
                        color: AppTheme.accent.withValues(alpha: 0.9)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (point['content'] ?? '').toString(),
                        style: TextStyle(
                          color: pointColor,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          if (footer.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: dividerColor),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Text(
                footer,
                style: TextStyle(
                  color: footerColor,
                  fontSize: 11.5,
                  height: 1.3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLoginStreakCard() {
    final streak = _streak;
    final targetDays = streak?.targetDays ?? 7;
    final currentStreak =
        streak == null ? 0 : streak.currentStreak.clamp(0, targetDays).toInt();
    final progress =
        targetDays <= 0 ? 0.0 : (currentStreak / targetDays).clamp(0.0, 1.0);
    final rewardAmount =
        double.tryParse((streak?.rewardAmount ?? '5.00').toString()) ?? 5.0;
    final receivableBonus =
        double.tryParse((streak?.receivableBonus ?? '0.00').toString()) ?? 0.0;
    final activeRequest = streak?.activeRedemptionRequest;
    final rewardAvailable = streak?.rewardAvailable == true;
    final title = rewardAvailable
        ? 'Bonus unlocked'
        : streak == null
            ? 'Visit streak'
            : '${streak.daysRemaining} days to unlock';
    final body = rewardAvailable
        ? '\$${receivableBonus.toStringAsFixed(2)} is ready to redeem.'
        : 'Visit daily for $targetDays consecutive days to earn Hi-Rollin credit.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.itemDecoration(
        customRadius: BorderRadius.circular(AppTheme.radius + 6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Daily Login Streak',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  '\$${rewardAmount.toStringAsFixed(0)} Credit',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLoadingStreak && streak == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.accent,
                  strokeWidth: 2.5,
                ),
              ),
            )
          else ...[
            Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 7,
                          backgroundColor:
                              AppTheme.cardBorder.withValues(alpha: 0.55),
                          color: AppTheme.accent,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$currentStreak',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          Text(
                            '/ $targetDays',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        body,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ClipRRect(
            //   borderRadius: BorderRadius.circular(999),
            //   child: LinearProgressIndicator(
            //     value: progress,
            //     minHeight: 7,
            //     backgroundColor: AppTheme.cardBorder.withValues(alpha: 0.46),
            //     color: AppTheme.accent,
            //   ),
            // ),
            const SizedBox(height: 14),
            if (activeRequest != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Redeem request: ${activeRequest.statusLabel ?? activeRequest.status}',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: rewardAvailable && !_isRedeemingStreak
                      ? _requestStreakRedemption
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppTheme.cardBorder.withValues(alpha: 0.70),
                    disabledForegroundColor:
                        AppTheme.textSecondary.withValues(alpha: 0.72),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isRedeemingStreak
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Request Redeem',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
          ],
          if (_streakError != null) ...[
            const SizedBox(height: 10),
            Text(
              _streakError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactLoginStreakCard() {
    final streak = _streak;
    final targetDays = streak?.targetDays ?? 7;
    final currentStreak =
        streak == null ? 0 : streak.currentStreak.clamp(0, targetDays).toInt();
    final progress =
        targetDays <= 0 ? 0.0 : (currentStreak / targetDays).clamp(0.0, 1.0);
    final rewardAvailable = streak?.rewardAvailable == true;
    final activeRequest = streak?.activeRedemptionRequest;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.itemDecoration(
        customRadius: BorderRadius.circular(AppTheme.radius + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_outlined,
                  color: AppTheme.accent, size: 20),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Daily Streak',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoadingStreak && streak == null)
            SizedBox(
              height: 58,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
              ),
            )
          else ...[
            Text(
              '$currentStreak / $targetDays days',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              rewardAvailable ? 'Bonus unlocked' : '\$5 credit reward',
              style: TextStyle(
                color:
                    rewardAvailable ? AppTheme.accent : AppTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppTheme.cardBorder.withValues(alpha: 0.46),
                color: AppTheme.accent,
              ),
            ),
            if (activeRequest != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  activeRequest.statusLabel ?? activeRequest.status,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: FilledButton(
                    onPressed: rewardAvailable && !_isRedeemingStreak
                        ? _requestStreakRedemption
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.cardBorder.withValues(alpha: 0.70),
                      disabledForegroundColor:
                          AppTheme.textSecondary.withValues(alpha: 0.72),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isRedeemingStreak
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Redeem',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
          ],
          if (_streakError != null) ...[
            const SizedBox(height: 8),
            Text(
              _streakError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayerQuickCards(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildFindAgentsCard(context, compact: true)),
          const SizedBox(width: 12),
          Expanded(child: _buildCompactLoginStreakCard()),
        ],
      ),
    );
  }

  Widget _buildFindAgentsCard(BuildContext context, {bool compact = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AgentSearchScreen()),
          );
        },
        child: Ink(
          padding: compact
              ? const EdgeInsets.all(14)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.person_search,
                          color: AppTheme.accent, size: 20),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Find Agents',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Connect with verified support',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'Browse',
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.chevron_right,
                            color: AppTheme.accent, size: 16),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(Icons.person_search, color: AppTheme.accent),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Find Agents',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                  ],
                ),
        ),
      ),
    );
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'app_registration_outlined':
        return Icons.app_registration_outlined;
      case 'attach_money_outlined':
        return Icons.attach_money_outlined;
      case 'login_outlined':
        return Icons.login_outlined;
      case 'campaign_outlined':
        return Icons.campaign_outlined;
      case 'schedule_outlined':
        return Icons.schedule_outlined;
      case 'support_agent_outlined':
        return Icons.support_agent_outlined;
      case 'verified_user_outlined':
        return Icons.verified_user_outlined;
      case 'chat_bubble_outline':
        return Icons.chat_bubble_outline;
      case 'notifications_active_outlined':
        return Icons.notifications_active_outlined;
      case 'info_outline':
      default:
        return Icons.info_outline;
    }
  }

  Widget _buildHomeSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }

  Widget _buildSectionSeparator({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 16 : 24),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 3,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.cardBorder.withValues(alpha: 0.85),
                    AppTheme.cardBorder.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEventsCard() {
    final recentEvents = _recentEvents.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.itemDecoration(
        customRadius: BorderRadius.circular(AppTheme.radius + 6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(
                  Icons.event_available_outlined,
                  color: AppTheme.accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Events',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Latest community events',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Top 5',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLoadingRecentEvents)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.accent,
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (recentEvents.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    color: AppTheme.textSecondary.withValues(alpha: 0.65),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No recent events available right now.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...recentEvents.asMap().entries.map((entry) {
              final index = entry.key;
              final event = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == recentEvents.length - 1 ? 0 : 10,
                ),
                child: _RecentEventRow(event: event),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard() {
    final activity = _recentActivity.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.itemDecoration(
        customRadius: BorderRadius.circular(AppTheme.radius + 6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(
                  Icons.bolt_outlined,
                  color: AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Activity',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Latest community updates',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Top 5',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLoadingRecentActivity)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.accent,
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (activity.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    color: AppTheme.textSecondary.withValues(alpha: 0.65),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No recent activity yet.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...activity.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == activity.length - 1 ? 0 : 10,
                ),
                child: _RecentActivityRow(activity: item),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildEventsList() {
    if (_isLoadingEvents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_events.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy,
                color: AppTheme.textSecondary.withValues(alpha: 0.3), size: 30),
            const SizedBox(height: 6),
            Text(
              'No events currently active',
              style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.7)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 240,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final screenWidth = MediaQuery.of(context).size.width;
          final cardWidth = screenWidth > 600 ? 320.0 : screenWidth * 0.75;

          return Container(
            width: cardWidth,
            margin: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.visualStyle == VisualStyle.flat
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
              image: event.bannerImage != null
                  ? DecorationImage(
                      image: NetworkImage(event.bannerImage!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.32),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                  stops: const [0.2, 1.0],
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    // TODO: Show event details
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (event.startDate != null || event.endDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              event.startDate != null && event.endDate != null
                                  ? '${DateFormat('MMM d, y').format(event.startDate!)} - ${DateFormat('MMM d, y').format(event.endDate!)}'
                                  : event.startDate != null
                                      ? DateFormat('MMM d, y')
                                          .format(event.startDate!)
                                      : DateFormat('MMM d, y')
                                          .format(event.endDate!),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          event.title,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          event.description,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCommunityPostsList() {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_communityPosts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.surface.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.article_outlined,
                  color: AppTheme.textSecondary.withValues(alpha: 0.3),
                  size: 48),
              const SizedBox(height: 12),
              Text(
                'No community posts available',
                style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._communityPosts.map(
          (post) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCommunityPostCard(post),
          ),
        ),
        const SizedBox(height: 2),
        OutlinedButton.icon(
          onPressed: _openCommunityFeed,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('View more posts'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textPrimary,
            side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.55)),
            backgroundColor: AppTheme.accent.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityPostCard(Post post) {
    final cleanContent =
        post.content.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');
    final coverImage = post.images.isNotEmpty ? post.images.first : null;
    final isPinned = post.isPinned;

    return Container(
      decoration: BoxDecoration(
        color: isPinned
            ? Color.alphaBlend(
                AppTheme.accent.withValues(alpha: 0.08),
                AppTheme.surface,
              )
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.visualStyle == VisualStyle.flat
            ? null
            : [
                BoxShadow(
                  color: isPinned
                      ? AppTheme.accent.withValues(alpha: 0.16)
                      : Colors.black.withValues(alpha: 0.18),
                  blurRadius: isPinned ? 18 : 14,
                  offset: const Offset(0, 7),
                ),
              ],
        border: Border.all(
          color: isPinned
              ? AppTheme.accent.withValues(alpha: 0.45)
              : AppTheme.cardBorder,
          width: isPinned ? 1.2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PostDetailsScreen(post: post),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isPinned)
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.accent,
                        AppTheme.primary.withValues(alpha: 0.9),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                ),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (post.video != null && post.video!.trim().isNotEmpty)
                      SizedBox(
                        width: 128,
                        child: ClipRRect(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isPinned ? 0 : 16),
                            bottomLeft: const Radius.circular(16),
                          ),
                          child: _PostVideoPreview(
                            videoUrl: _resolvePostMediaUrl(post.video!),
                            fallbackImageUrl: coverImage != null
                                ? _resolvePostMediaUrl(coverImage)
                                : null,
                          ),
                        ),
                      )
                    else if (coverImage != null && coverImage.trim().isNotEmpty)
                      SizedBox(
                        width: 128,
                        child: ClipRRect(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isPinned ? 0 : 16),
                            bottomLeft: const Radius.circular(16),
                          ),
                          child: Image.network(
                            _resolvePostMediaUrl(coverImage),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _capitalizeUsername(
                                        post.author?.username ?? 'Unknown'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary
                                          .withValues(alpha: 0.78),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (isPinned) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.push_pin_outlined,
                                    size: 14,
                                    color: AppTheme.accent,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              post.title.isNotEmpty
                                  ? post.title
                                  : 'Untitled post',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                height: 1.18,
                              ),
                            ),
                            if (cleanContent.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                cleanContent,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.9),
                                  fontSize: 12.5,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _getFriendlyTime(post.createdAt.toLocal()),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppTheme.textSecondary
                                          .withValues(alpha: 0.7),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => showSharePostToChatDialog(
                                    context,
                                    post: post,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.send_outlined,
                                      size: 16,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  void _openCommunityFeed() {
    if (widget.onOpenCommunityFeed != null) {
      widget.onOpenCommunityFeed!();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PostFeedScreen()),
    );
  }

  String _capitalizeUsername(String input) {
    if (input.isEmpty) return input;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return input;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  String _resolvePostMediaUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${ApiClient.baseUrl}$trimmed';
    }
    return '${ApiClient.baseUrl}/$trimmed';
  }

  String _getFriendlyTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) {
      return diff.inMinutes == 1 ? '1 min ago' : '${diff.inMinutes} mins ago';
    }
    if (diff.inHours < 24) {
      return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
    }
    if (diff.inDays < 7) {
      return diff.inDays == 1 ? '1 day ago' : '${diff.inDays} days ago';
    }
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    }
    final years = (diff.inDays / 365).floor();
    return years == 1 ? '1 year ago' : '$years years ago';
  }
}

class _PostVideoPreview extends StatefulWidget {
  final String videoUrl;
  final String? fallbackImageUrl;

  const _PostVideoPreview({
    required this.videoUrl,
    this.fallbackImageUrl,
  });

  @override
  State<_PostVideoPreview> createState() => _PostVideoPreviewState();
}

class _PostVideoPreviewState extends State<_PostVideoPreview>
    with AutomaticKeepAliveClientMixin {
  static VideoPlayerController? _activePreviewController;
  static _PostVideoPreviewState? _activePreviewState;

  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _isInitializing = false;
  bool _isPlaying = false;
  bool _isMuted = true;

  @override
  bool get wantKeepAlive => true;

  Future<void> _initController() async {
    if (_isInitializing || _ready) return;
    _isInitializing = true;
    if (mounted) setState(() {});
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _isInitializing = false;
        _isMuted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _isInitializing = false;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_failed) return;
    if (!_ready || _controller == null) {
      await _initController();
      if (!_ready || _controller == null) return;
    }
    final controller = _controller!;
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) setState(() => _isPlaying = false);
      if (identical(_activePreviewState, this)) {
        _activePreviewState = null;
        _activePreviewController = null;
      }
      return;
    }

    if (_activePreviewController != null &&
        !identical(_activePreviewController, controller)) {
      await _activePreviewController!.pause();
      if (_activePreviewState != null && _activePreviewState!.mounted) {
        _activePreviewState!
            .setState(() => _activePreviewState!._isPlaying = false);
      }
    }

    await controller.play();
    _activePreviewController = controller;
    _activePreviewState = this;
    if (mounted) setState(() => _isPlaying = true);
  }

  Future<void> _openFullscreen() async {
    if (_failed) return;
    if (!_ready || _controller == null) {
      await _initController();
      if (!_ready || _controller == null) return;
    }
    final controller = _controller!;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenPostVideoPlayer(
          videoUrl: widget.videoUrl,
          externalController: controller,
          initialMuted: _isMuted,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _isPlaying = controller.value.isPlaying;
    });
  }

  @override
  void dispose() {
    if (identical(_activePreviewState, this)) {
      _activePreviewState = null;
      _activePreviewController = null;
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fallback = widget.fallbackImageUrl;

    if (_failed) {
      if (fallback != null && fallback.isNotEmpty) {
        return Image.network(
          fallback,
          height: 180,
          fit: BoxFit.cover,
        );
      }
      return Container(
        height: 180,
        color: Colors.black26,
        alignment: Alignment.center,
        child: Icon(Icons.videocam_off,
            color: AppTheme.textSecondary.withValues(alpha: 0.75)),
      );
    }

    if (!_ready || _controller == null) {
      if (fallback != null && fallback.isNotEmpty) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayPause,
          child: SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  fallback,
                  fit: BoxFit.cover,
                ),
                if (_isInitializing)
                  Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: AppTheme.textPrimary,
                      size: 44,
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePlayPause,
        child: Container(
          height: 180,
          color: Colors.black26,
          alignment: Alignment.center,
          child: _isInitializing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.play_circle_fill,
                  color: AppTheme.textPrimary,
                  size: 44,
                ),
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePlayPause,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: _isPlaying ? 0.0 : 1.0,
                child: Icon(
                  Icons.play_circle_fill,
                  color: AppTheme.textPrimary,
                  size: 44,
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _openFullscreen,
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.fullscreen,
                      color: AppTheme.textPrimary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final controller = _controller;
                    if (controller == null) return;
                    final nextMuted = !_isMuted;
                    await controller.setVolume(nextMuted ? 0 : 1);
                    if (mounted) {
                      setState(() => _isMuted = nextMuted);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: AppTheme.textPrimary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityRow extends StatelessWidget {
  final Map<String, dynamic> activity;

  const _RecentActivityRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    final actor = _asMap(activity['actor']);
    final actorName = (actor['username'] ?? 'Community').toString();
    final avatarUrl = (actor['avatar'] ?? '').toString().trim();
    final title = _formatActivityTitle(activity);
    final createdAt = (activity['created_at'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _RecentActivityAvatar(
            avatarUrl: avatarUrl,
            fallbackText: actorName,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: actorName,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: ' $title',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.25),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatRelativeTime(createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            _activityIcon((activity['kind'] ?? '').toString()),
            color: AppTheme.accent.withValues(alpha: 0.86),
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _RecentActivityAvatar extends StatelessWidget {
  final String avatarUrl;
  final String fallbackText;

  const _RecentActivityAvatar({
    required this.avatarUrl,
    required this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    final initial = fallbackText.trim().isEmpty
        ? 'C'
        : fallbackText.trim()[0].toUpperCase();

    if (avatarUrl.isEmpty) {
      return _avatarFallback(initial);
    }

    return ClipOval(
      child: Image.network(
        avatarUrl,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarFallback(initial),
      ),
    );
  }

  Widget _avatarFallback(String initial) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.20),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.20)),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RecentEventRow extends StatelessWidget {
  final Event event;

  const _RecentEventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final date = event.startDate ?? event.endDate;
    final month = date == null ? 'TBA' : DateFormat('MMM').format(date);
    final day = date == null ? '--' : DateFormat('dd').format(date);
    final range = _eventRangeLabel(event);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  month.toUpperCase(),
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  day,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (event.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.description.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (event.bannerImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.network(
                event.bannerImage!,
                width: 54,
                height: 54,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _RecentEventIconFallback(),
              ),
            )
          else
            const _RecentEventIconFallback(),
        ],
      ),
    );
  }

  static String _eventRangeLabel(Event event) {
    final start = event.startDate;
    final end = event.endDate;
    if (start != null && end != null) {
      final sameDay = start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      if (sameDay) return DateFormat('MMM d, y').format(start);
      return '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d, y').format(end)}';
    }
    if (start != null) return DateFormat('MMM d, y').format(start);
    if (end != null) return 'Ends ${DateFormat('MMM d, y').format(end)}';
    return 'Date to be announced';
  }
}

class _RecentEventIconFallback extends StatelessWidget {
  const _RecentEventIconFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.20)),
      ),
      child: Icon(
        Icons.emoji_events_outlined,
        color: AppTheme.accent,
        size: 22,
      ),
    );
  }
}

List<dynamic> _extractList(dynamic response) {
  if (response is List) return response;
  if (response is Map) {
    final data = response['data'];
    if (data is List) return data;
    final results = response['results'];
    if (results is List) return results;
  }
  return const [];
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _formatActivityTitle(Map<String, dynamic> item) {
  final action = (item['action'] ?? '').toString().trim();
  final target = (item['target_title'] ?? '').toString().trim();
  if (action.isNotEmpty && target.isNotEmpty) return '$action $target';
  if (action.isNotEmpty) return action;
  return (item['kind'] ?? 'activity').toString();
}

String _formatRelativeTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return '';
  final now = DateTime.now();
  final local = parsed.toLocal();
  final diff = now.difference(local);

  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d, y').format(local);
}

IconData _activityIcon(String kind) {
  switch (kind.toLowerCase()) {
    case 'post':
      return Icons.article_outlined;
    case 'comment':
      return Icons.chat_bubble_outline;
    case 'event':
      return Icons.event_available_outlined;
    case 'reward':
      return Icons.card_giftcard_outlined;
    case 'account':
      return Icons.person_add_alt_1_outlined;
    default:
      return Icons.bolt_outlined;
  }
}

class _FullScreenPostVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final VideoPlayerController? externalController;
  final bool initialMuted;

  const _FullScreenPostVideoPlayer({
    required this.videoUrl,
    this.externalController,
    this.initialMuted = true,
  });

  @override
  State<_FullScreenPostVideoPlayer> createState() =>
      _FullScreenPostVideoPlayerState();
}

class _FullScreenPostVideoPlayerState
    extends State<_FullScreenPostVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ownsController = true;
  bool _ready = false;
  bool _failed = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    if (widget.externalController != null) {
      _controller = widget.externalController;
      _ownsController = false;
      _ready = _controller!.value.isInitialized;
      _controller!.setVolume(widget.initialMuted ? 0 : 1);
    } else {
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(widget.initialMuted ? 0 : 1);
      if (!mounted) return;
      setState(() => _ready = true);
      await c.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: Center(
          child: Icon(Icons.videocam_off,
              color: AppTheme.textSecondary.withValues(alpha: 0.75), size: 42),
        ),
      );
    }

    if (!_ready || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
            if (_showControls)
              Positioned(
                top: 32,
                left: 8,
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            if (_showControls)
              Center(
                child: IconButton(
                  iconSize: 56,
                  color: AppTheme.textPrimary,
                  icon: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                  ),
                  onPressed: () async {
                    if (_controller!.value.isPlaying) {
                      await _controller!.pause();
                    } else {
                      await _controller!.play();
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
