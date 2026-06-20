import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

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
      final response = await context
          .read<AuthProvider>()
          .apiClient
          .get('/api/announcements/');
      final data = _extractList(response);
      if (!mounted) return;
      setState(() {
        _items = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
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

  @override
  Widget build(BuildContext context) {
    return _RollinListShell(
      title: 'Announcements',
      subtitle: 'Official updates from Rollin Community',
      icon: Icons.campaign_outlined,
      onRefresh: _load,
      isLoading: _isLoading,
      error: _error,
      emptyText: 'No announcements yet.',
      children: _items.map((item) {
        final priority =
            (item['priority_label'] ?? item['priority'] ?? 'Normal').toString();
        return _InfoCard(
          icon: item['is_pinned'] == true
              ? Icons.push_pin_outlined
              : Icons.campaign_outlined,
          title: (item['title'] ?? 'Announcement').toString(),
          eyebrow:
              '${item['category_label'] ?? item['category'] ?? 'General'} • $priority',
          body:
              _plainText((item['summary'] ?? item['content'] ?? '').toString()),
          accent:
              item['priority'] == 'urgent' ? Colors.redAccent : AppTheme.accent,
        );
      }).toList(),
    );
  }
}

class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

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
      final response =
          await context.read<AuthProvider>().apiClient.get('/api/faqs/');
      final data = _extractList(response);
      if (!mounted) return;
      setState(() {
        _items = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
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

  @override
  Widget build(BuildContext context) {
    return _RollinListShell(
      title: 'FAQ',
      subtitle: 'Answers for account, rewards, events, and community questions',
      icon: Icons.help_outline,
      onRefresh: _load,
      isLoading: _isLoading,
      error: _error,
      emptyText: 'No FAQs published yet.',
      children: _items.map((item) {
        return _InfoCard(
          icon: item['is_featured'] == true
              ? Icons.star_outline
              : Icons.help_outline,
          title: (item['question'] ?? 'Question').toString(),
          eyebrow: (item['category_label'] ?? item['category'] ?? 'Account')
              .toString(),
          body: _plainText((item['answer'] ?? '').toString()),
          accent:
              item['is_featured'] == true ? AppTheme.accent : AppTheme.primary,
        );
      }).toList(),
    );
  }
}

class GuidelinesScreen extends StatelessWidget {
  const GuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = const [
      (
        'Be respectful',
        'Keep conversations friendly, fair, and useful for players and agents.'
      ),
      (
        'No spam or scams',
        'Do not post fake offers, phishing links, repeated promotions, or misleading claims.'
      ),
      (
        'Protect private info',
        'Never share passwords, OTPs, payment details, or private account data.'
      ),
      (
        'Use the right channels',
        'Use chat for support, posts for community updates, and reports for safety issues.'
      ),
      (
        'Keep rewards fair',
        'Do not abuse bonuses, streaks, events, or redemption flows.'
      ),
    ];
    return _RollinListShell(
      title: 'Guidelines',
      subtitle: 'Community rules for a safe Hi-Rollin player hub',
      icon: Icons.shield_outlined,
      onRefresh: null,
      isLoading: false,
      error: null,
      emptyText: '',
      children: items
          .map((item) => _InfoCard(
                icon: Icons.check_circle_outline,
                title: item.$1,
                eyebrow: 'Community Standard',
                body: item.$2,
                accent: AppTheme.accent,
              ))
          .toList(),
    );
  }
}

class RewardRedemptionsScreen extends StatefulWidget {
  const RewardRedemptionsScreen({super.key});

  @override
  State<RewardRedemptionsScreen> createState() =>
      _RewardRedemptionsScreenState();
}

class _RewardRedemptionsScreenState extends State<RewardRedemptionsScreen> {
  bool _isLoading = true;
  String? _error;
  int? _updatingId;
  List<Map<String, dynamic>> _items = const [];

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
      final response = await context
          .read<AuthProvider>()
          .apiClient
          .get('/api/rewards/streak/redemptions/');
      final data = _extractList(response);
      if (!mounted) return;
      setState(() {
        _items = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
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

  Future<void> _updateRequest(int id, String status) async {
    setState(() {
      _updatingId = id;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().apiClient.patch(
        '/api/rewards/streak/redemptions/$id/',
        body: {'status': status},
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _updatingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RollinListShell(
      title: 'Redemptions',
      subtitle: 'Review player streak redemption requests',
      icon: Icons.card_giftcard_outlined,
      onRefresh: _load,
      isLoading: _isLoading,
      error: _error,
      emptyText: 'No redemption requests yet.',
      children: _items.map((item) {
        final user = item['user'];
        final username =
            user is Map ? (user['username'] ?? 'Player').toString() : 'Player';
        final status = (item['status'] ?? 'pending').toString();
        final id = item['id'] is int
            ? item['id'] as int
            : int.tryParse('${item['id']}');
        final canAct =
            id != null && (status == 'pending' || status == 'approved');
        return _InfoCard(
          icon: Icons.redeem_outlined,
          title: '$username • \$${item['amount'] ?? '0.00'}',
          eyebrow:
              (item['status_label'] ?? item['status'] ?? 'Pending').toString(),
          body: (item['note'] ?? 'No note provided.').toString(),
          accent: AppTheme.accent,
          footer: canAct
              ? _RedemptionActions(
                  isUpdating: _updatingId == id,
                  onApprove: status == 'pending'
                      ? () => _updateRequest(id, 'approved')
                      : null,
                  onComplete: () => _updateRequest(id, 'completed'),
                  onReject: () => _updateRequest(id, 'rejected'),
                )
              : null,
        );
      }).toList(),
    );
  }
}

class _RollinListShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Future<void> Function()? onRefresh;
  final bool isLoading;
  final String? error;
  final String emptyText;
  final List<Widget> children;

  const _RollinListShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onRefresh,
    required this.isLoading,
    required this.error,
    required this.emptyText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _HeaderCard(title: title, subtitle: subtitle, icon: icon),
        const SizedBox(height: 16),
        if (isLoading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator()))
        else if (error != null)
          _StateCard(icon: Icons.error_outline, text: error!)
        else if (children.isEmpty)
          _StateCard(icon: Icons.inbox_outlined, text: emptyText)
        else
          ...children,
      ],
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          child: onRefresh == null
              ? content
              : RefreshIndicator(onRefresh: onRefresh!, child: content),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _HeaderCard(
      {required this.title, required this.subtitle, required this.icon});

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
            width: 48,
            height: 48,
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
                Text(title,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String eyebrow;
  final String body;
  final Color accent;
  final Widget? footer;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.eyebrow,
    required this.body,
    required this.accent,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.itemDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow.toUpperCase(),
                    style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(title,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                if (body.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(body,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.4),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis),
                ],
                if (footer != null) ...[
                  const SizedBox(height: 12),
                  footer!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RedemptionActions extends StatelessWidget {
  final bool isUpdating;
  final VoidCallback? onApprove;
  final VoidCallback onComplete;
  final VoidCallback onReject;

  const _RedemptionActions({
    required this.isUpdating,
    required this.onApprove,
    required this.onComplete,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (isUpdating) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.accent,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onApprove != null)
          _SmallActionButton(
            label: 'Approve',
            onPressed: onApprove!,
            color: AppTheme.primary,
          ),
        _SmallActionButton(
          label: 'Complete',
          onPressed: onComplete,
          color: AppTheme.accent,
          foregroundColor: Colors.black,
        ),
        _SmallActionButton(
          label: 'Reject',
          onPressed: onReject,
          color: Colors.redAccent,
        ),
      ],
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color color;
  final Color foregroundColor;

  const _SmallActionButton({
    required this.label,
    required this.onPressed,
    required this.color,
    this.foregroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foregroundColor,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
      decoration: AppTheme.itemDecoration(),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 34),
          const SizedBox(height: 10),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

String _plainText(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<dynamic> _extractList(dynamic response) {
  if (response is List) return response;
  if (response is Map) {
    final data = response['data'];
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List;
    }
    if (response['results'] is List) {
      return response['results'] as List;
    }
  }
  return const [];
}
