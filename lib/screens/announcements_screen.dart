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
  String _activeFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final isStaff = context.read<AuthProvider>().isStaff;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final endpoint =
          isStaff ? '/api/announcements/manage/' : '/api/announcements/';
      final response =
          await context.read<AuthProvider>().apiClient.get(endpoint);
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
    final isStaff = context.watch<AuthProvider>().isStaff;
    final filteredItems =
        _items.where((item) => _matchesAnnouncementFilter(item)).toList();

    if (isStaff) {
      return _buildStaffAnnouncements(filteredItems);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Announcements'),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
              children: [
                const _AnnouncementPageHeader(),
                const SizedBox(height: 18),
                _AnnouncementFilters(
                  activeFilter: _activeFilter,
                  onFilterChanged: (filter) {
                    setState(() => _activeFilter = filter);
                  },
                  onRefresh: _load,
                  isRefreshing: _isLoading,
                ),
                const SizedBox(height: 14),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  _StateCard(icon: Icons.error_outline, text: _error!)
                else if (filteredItems.isEmpty)
                  const _StateCard(
                    icon: Icons.inbox_outlined,
                    text: 'No announcements found for this filter.',
                  )
                else
                  ...filteredItems.map((item) {
                    final priority =
                        (item['priority_label'] ?? item['priority'] ?? 'Normal')
                            .toString();
                    return _InfoCard(
                      icon: item['is_pinned'] == true
                          ? Icons.push_pin_outlined
                          : Icons.campaign_outlined,
                      title: (item['title'] ?? 'Announcement').toString(),
                      eyebrow:
                          '${item['category_label'] ?? item['category'] ?? 'General'} • $priority',
                      body: _plainText(
                          (item['summary'] ?? item['content'] ?? '')
                              .toString()),
                      accent: item['priority'] == 'urgent'
                          ? Colors.redAccent
                          : AppTheme.accent,
                      onTap: () => _openAnnouncementDetails(item),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _matchesAnnouncementFilter(Map<String, dynamic> item) {
    if (_activeFilter == 'all') return true;
    final category = (item['category'] ?? '').toString().toLowerCase();
    return category == _activeFilter;
  }

  void _openAnnouncementDetails(Map<String, dynamic> item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnnouncementDetailsScreen(announcement: item),
      ),
    );
  }

  Widget _buildStaffAnnouncements(List<Map<String, dynamic>> filteredItems) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Announcements'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Create announcement',
            onPressed: () => _openAnnouncementForm(),
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _AnnouncementFilters(
                        activeFilter: _activeFilter,
                        onFilterChanged: (filter) {
                          setState(() => _activeFilter = filter);
                        },
                        onRefresh: _load,
                        isRefreshing: _isLoading,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: FilledButton(
                        onPressed: () => _openAnnouncementForm(),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Icon(Icons.add_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  _StateCard(icon: Icons.error_outline, text: _error!)
                else if (filteredItems.isEmpty)
                  const _StateCard(
                    icon: Icons.inbox_outlined,
                    text: 'No announcements found.',
                  )
                else
                  ...filteredItems.map(
                    (item) => _StaffAnnouncementCard(
                      announcement: item,
                      onEdit: () => _openAnnouncementForm(item: item),
                      onDelete: () => _confirmDelete(item),
                      onView: () => _openAnnouncementDetails(item),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAnnouncementForm({Map<String, dynamic>? item}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AnnouncementFormScreen(announcement: item),
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final id = item['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Delete announcement?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          'This action cannot be undone.',
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
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final apiClient = context.read<AuthProvider>().apiClient;
      await apiClient.delete(
        '/api/announcements/$id/',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement deleted.')),
      );
      await _load();
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
}

class AnnouncementDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> announcement;

  const AnnouncementDetailsScreen({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final title = (announcement['title'] ?? 'Announcement').toString();
    final category = (announcement['category_label'] ??
            announcement['category'] ??
            'General')
        .toString();
    final priority =
        (announcement['priority_label'] ?? announcement['priority'] ?? 'Normal')
            .toString();
    final content = _plainText(
        (announcement['content'] ?? announcement['summary'] ?? '').toString());
    final coverImage = (announcement['cover_image'] ?? '').toString();
    final publishedAt = (announcement['published_at'] ??
            announcement['created_at'] ??
            announcement['updated_at'] ??
            '')
        .toString();
    final accent = announcement['priority'] == 'urgent'
        ? Colors.redAccent
        : AppTheme.accent;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Announcement'),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
            children: [
              if (coverImage.isNotEmpty)
                _ZoomableAnnouncementImage(imageUrl: coverImage),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _DetailPill(label: category, color: accent),
                        _DetailPill(label: priority, color: AppTheme.primary),
                        if (announcement['is_pinned'] == true)
                          _DetailPill(
                            label: 'Pinned',
                            color: AppTheme.accent,
                            darkText: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 26,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (publishedAt.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _formatDate(publishedAt),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      content.isEmpty
                          ? 'No announcement content available.'
                          : content,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15.5,
                        height: 1.6,
                        fontWeight: FontWeight.w500,
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
}

class _AnnouncementPageHeader extends StatelessWidget {
  const _AnnouncementPageHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMMUNITY',
            style: TextStyle(
              color: AppTheme.primary.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Announcements',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Official Rollin Community updates, maintenance notices, rewards, and event alerts.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementFilters extends StatelessWidget {
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;
  final Future<void> Function() onRefresh;
  final bool isRefreshing;
  final bool compact;

  const _AnnouncementFilters({
    required this.activeFilter,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.isRefreshing,
    this.compact = false,
  });

  static const filters = [
    ('all', 'All'),
    ('event', 'Events'),
    ('reward', 'Rewards'),
    ('maintenance', 'Maintenance'),
  ];

  @override
  Widget build(BuildContext context) {
    final labels = {
      for (final filter in filters) filter.$1: filter.$2,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          _AnnouncementFilterMenu(
            value: activeFilter,
            labels: labels,
            onChanged: onFilterChanged,
          ),
          if (!compact) ...[
            const Spacer(),
            SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                onPressed: isRefreshing ? null : onRefresh,
                tooltip: 'Refresh',
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.background.withValues(alpha: 0.24),
                  foregroundColor: AppTheme.textPrimary,
                  disabledBackgroundColor:
                      AppTheme.background.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(color: AppTheme.cardBorder),
                  ),
                ),
                icon: isRefreshing
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.textSecondary,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnnouncementFilterMenu extends StatelessWidget {
  final String value;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;

  const _AnnouncementFilterMenu({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = labels[value] ?? labels.values.first;

    return PopupMenuButton<String>(
      tooltip: selectedLabel,
      color: AppTheme.surface,
      onSelected: onChanged,
      itemBuilder: (context) => labels.entries.map((entry) {
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
            Icon(
              Icons.tune_rounded,
              color: AppTheme.textSecondary,
              size: 16,
            ),
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

class _StaffAnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> announcement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onView;

  const _StaffAnnouncementCard({
    required this.announcement,
    required this.onEdit,
    required this.onDelete,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final title = (announcement['title'] ?? 'Announcement').toString();
    final category = (announcement['category_label'] ??
            announcement['category'] ??
            'General')
        .toString();
    final priority =
        (announcement['priority_label'] ?? announcement['priority'] ?? 'Normal')
            .toString();
    final isPinned = announcement['is_pinned'] == true;
    final isPublished = announcement['is_published'] == true;
    final body = _plainText(
        (announcement['summary'] ?? announcement['content'] ?? '').toString());
    final accent = announcement['priority'] == 'urgent'
        ? Colors.redAccent
        : AppTheme.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPinned
              ? AppTheme.accent.withValues(alpha: 0.55)
              : AppTheme.cardBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.campaign_outlined,
                  color: accent,
                  size: 20,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniStatusPill(
                            label: category, color: AppTheme.primary),
                        _MiniStatusPill(label: priority, color: accent),
                        _MiniStatusPill(
                          label: isPublished ? 'Published' : 'Draft',
                          color: isPublished
                              ? const Color(0xFF22C55E)
                              : Colors.amber,
                        ),
                        if (isPinned)
                          _MiniStatusPill(
                            label: 'Pinned',
                            color: AppTheme.accent,
                          ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                color: AppTheme.surface,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: AppTheme.textSecondary,
                ),
                onSelected: (value) {
                  if (value == 'view') onView();
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'view',
                    child: _PopupRow(
                        icon: Icons.visibility_outlined, text: 'View'),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: _PopupRow(icon: Icons.edit_outlined, text: 'Edit'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: _PopupRow(
                      icon: Icons.delete_outline,
                      text: 'Delete',
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnnouncementFormScreen extends StatefulWidget {
  final Map<String, dynamic>? announcement;

  const AnnouncementFormScreen({super.key, this.announcement});

  @override
  State<AnnouncementFormScreen> createState() => _AnnouncementFormScreenState();
}

class _AnnouncementFormScreenState extends State<AnnouncementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _summaryController;
  late final TextEditingController _contentController;
  late String _category;
  late String _audience;
  late String _priority;
  late bool _isPinned;
  late bool _isPublished;
  bool _isSaving = false;
  String? _error;

  bool get _isEditing => widget.announcement != null;

  @override
  void initState() {
    super.initState();
    final item = widget.announcement ?? const <String, dynamic>{};
    _titleController =
        TextEditingController(text: (item['title'] ?? '').toString());
    _summaryController =
        TextEditingController(text: (item['summary'] ?? '').toString());
    _contentController = TextEditingController(
        text: _plainText((item['content'] ?? '').toString()));
    _category = (item['category'] ?? 'general').toString();
    _audience = (item['audience'] ?? 'all').toString();
    _priority = (item['priority'] ?? 'normal').toString();
    _isPinned = item['is_pinned'] == true;
    _isPublished = item['is_published'] != false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final fields = {
      'title': _titleController.text.trim(),
      'summary': _summaryController.text.trim(),
      'content': _contentController.text.trim(),
      'category': _category,
      'audience': _audience,
      'priority': _priority,
      'is_pinned': _isPinned.toString(),
      'is_published': _isPublished.toString(),
    };

    try {
      final apiClient = context.read<AuthProvider>().apiClient;
      if (_isEditing) {
        await apiClient.postMultipartWithFields(
          '/api/announcements/${widget.announcement!['id']}/',
          fields: fields,
          filePaths: const {},
          isPatch: true,
        );
      } else {
        await apiClient.postMultipartWithFields(
          '/api/announcements/',
          fields: fields,
          filePaths: const {},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Announcement updated.' : 'Announcement created.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Announcement' : 'New Announcement'),
        backgroundColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (_error != null) ...[
                  _StateCard(icon: Icons.error_outline, text: _error!),
                  const SizedBox(height: 12),
                ],
                _FormSection(
                  children: [
                    _StaffTextField(
                      controller: _titleController,
                      label: 'Title',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Title is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _StaffTextField(
                      controller: _summaryController,
                      label: 'Summary',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _StaffTextField(
                      controller: _contentController,
                      label: 'Content',
                      maxLines: 8,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Content is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _FormSection(
                  children: [
                    _StaffDropdown(
                      label: 'Category',
                      value: _category,
                      items: const {
                        'general': 'General',
                        'event': 'Event',
                        'reward': 'Reward',
                        'maintenance': 'Maintenance',
                      },
                      onChanged: (value) => setState(() => _category = value),
                    ),
                    const SizedBox(height: 12),
                    _StaffDropdown(
                      label: 'Audience',
                      value: _audience,
                      items: const {
                        'all': 'All',
                        'player': 'Players',
                        'agent': 'Agents',
                        'staff': 'Staff',
                      },
                      onChanged: (value) => setState(() => _audience = value),
                    ),
                    const SizedBox(height: 12),
                    _StaffDropdown(
                      label: 'Priority',
                      value: _priority,
                      items: const {
                        'low': 'Low',
                        'normal': 'Normal',
                        'high': 'High',
                        'urgent': 'Urgent',
                      },
                      onChanged: (value) => setState(() => _priority = value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _FormSection(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Pinned',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        'Feature this announcement at the top.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      value: _isPinned,
                      onChanged: (value) => setState(() => _isPinned = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Published',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        'Visible to selected audience.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      value: _isPublished,
                      onChanged: (value) =>
                          setState(() => _isPublished = value),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? 'Saving...' : 'Save Announcement'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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

class _ZoomableAnnouncementImage extends StatelessWidget {
  final String imageUrl;

  const _ZoomableAnnouncementImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final image = InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          clipBehavior: Clip.none,
          child: child,
        );

        if (wasSynchronouslyLoaded || frame != null) return image;

        return Container(
          height: 220,
          alignment: Alignment.center,
          color: AppTheme.surface.withValues(alpha: 0.55),
          child: CircularProgressIndicator(color: AppTheme.accent),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        height: 220,
        alignment: Alignment.center,
        color: AppTheme.surface.withValues(alpha: 0.7),
        child: Icon(
          Icons.image_not_supported_outlined,
          color: AppTheme.textSecondary,
          size: 38,
        ),
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool darkText;

  const _DetailPill({
    required this.label,
    required this.color,
    this.darkText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: darkText ? 0.92 : 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: darkText ? Colors.black : color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MiniStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PopupRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _PopupRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 18, color: effectiveColor),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            color: effectiveColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FormSection extends StatelessWidget {
  final List<Widget> children;

  const _FormSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _StaffTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final String? Function(String?)? validator;

  const _StaffTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(color: AppTheme.textPrimary),
      decoration: _staffInputDecoration(label),
    );
  }
}

class _StaffDropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _StaffDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedValue = items.containsKey(value) ? value : items.keys.first;
    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      dropdownColor: AppTheme.surface,
      iconEnabledColor: AppTheme.textSecondary,
      style: TextStyle(
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      decoration: _staffInputDecoration(label),
      items: items.entries
          .map(
            (entry) => DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

InputDecoration _staffInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: AppTheme.textSecondary),
    filled: true,
    fillColor: AppTheme.background.withValues(alpha: 0.28),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: AppTheme.cardBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: AppTheme.cardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: AppTheme.primary),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  );
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
    final isStaff = context.read<AuthProvider>().isStaff;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final endpoint = isStaff ? '/api/faqs/manage/' : '/api/faqs/';
      final response =
          await context.read<AuthProvider>().apiClient.get(endpoint);
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
    final isStaff = context.watch<AuthProvider>().isStaff;

    if (isStaff) {
      return _buildStaffFaqs();
    }

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

  Widget _buildStaffFaqs() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('FAQ'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Create FAQ',
            onPressed: () => _openFaqForm(),
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _openFaqForm(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add FAQ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  _StateCard(icon: Icons.error_outline, text: _error!)
                else if (_items.isEmpty)
                  const _StateCard(
                    icon: Icons.inbox_outlined,
                    text: 'No FAQs yet.',
                  )
                else
                  ..._items.map(
                    (item) => _StaffFaqCard(
                      faq: item,
                      onEdit: () => _openFaqForm(item: item),
                      onDelete: () => _confirmDeleteFaq(item),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFaqForm({Map<String, dynamic>? item}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FAQFormScreen(faq: item),
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _confirmDeleteFaq(Map<String, dynamic> item) async {
    final id = item['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Delete FAQ?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          'This action cannot be undone.',
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
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final apiClient = context.read<AuthProvider>().apiClient;
      await apiClient.delete('/api/faqs/$id/');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FAQ deleted.')),
      );
      await _load();
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
}

class _StaffFaqCard extends StatelessWidget {
  final Map<String, dynamic> faq;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StaffFaqCard({
    required this.faq,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final question = (faq['question'] ?? 'Question').toString();
    final answer = _plainText((faq['answer'] ?? '').toString());
    final category =
        (faq['category_label'] ?? faq['category'] ?? 'Account').toString();
    final audience =
        (faq['audience_label'] ?? faq['audience'] ?? 'All').toString();
    final isFeatured = faq['is_featured'] == true;
    final isPublished = faq['is_published'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFeatured
              ? AppTheme.accent.withValues(alpha: 0.55)
              : AppTheme.cardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (isFeatured ? AppTheme.accent : AppTheme.primary)
                    .withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isFeatured ? Icons.star_outline : Icons.help_outline,
                color: isFeatured ? AppTheme.accent : AppTheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MiniStatusPill(label: category, color: AppTheme.primary),
                      _MiniStatusPill(label: audience, color: AppTheme.accent),
                      _MiniStatusPill(
                        label: isPublished ? 'Published' : 'Draft',
                        color: isPublished
                            ? const Color(0xFF22C55E)
                            : Colors.amber,
                      ),
                      if (isFeatured)
                        _MiniStatusPill(
                          label: 'Featured',
                          color: AppTheme.accent,
                        ),
                    ],
                  ),
                  if (answer.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      answer,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              color: AppTheme.surface,
              icon: Icon(
                Icons.more_vert_rounded,
                color: AppTheme.textSecondary,
              ),
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: _PopupRow(icon: Icons.edit_outlined, text: 'Edit'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: _PopupRow(
                    icon: Icons.delete_outline,
                    text: 'Delete',
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FAQFormScreen extends StatefulWidget {
  final Map<String, dynamic>? faq;

  const FAQFormScreen({super.key, this.faq});

  @override
  State<FAQFormScreen> createState() => _FAQFormScreenState();
}

class _FAQFormScreenState extends State<FAQFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _questionController;
  late final TextEditingController _answerController;
  late final TextEditingController _sortOrderController;
  late String _category;
  late String _audience;
  late bool _isFeatured;
  late bool _isPublished;
  bool _isSaving = false;
  String? _error;

  bool get _isEditing => widget.faq != null;

  @override
  void initState() {
    super.initState();
    final item = widget.faq ?? const <String, dynamic>{};
    _questionController =
        TextEditingController(text: (item['question'] ?? '').toString());
    _answerController = TextEditingController(
        text: _plainText((item['answer'] ?? '').toString()));
    _sortOrderController = TextEditingController(
      text: (item['sort_order'] ?? 0).toString(),
    );
    _category = (item['category'] ?? 'account').toString();
    _audience = (item['audience'] ?? 'all').toString();
    _isFeatured = item['is_featured'] == true;
    _isPublished = item['is_published'] != false;
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final body = {
      'question': _questionController.text.trim(),
      'answer': _answerController.text.trim(),
      'category': _category,
      'audience': _audience,
      'sort_order': int.tryParse(_sortOrderController.text.trim()) ?? 0,
      'is_featured': _isFeatured,
      'is_published': _isPublished,
    };

    try {
      final apiClient = context.read<AuthProvider>().apiClient;
      if (_isEditing) {
        await apiClient.patch(
          '/api/faqs/${widget.faq!['id']}/',
          body: body,
        );
      } else {
        await apiClient.post('/api/faqs/', body: body);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'FAQ updated.' : 'FAQ created.'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit FAQ' : 'New FAQ'),
        backgroundColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.dashboardBackground(),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (_error != null) ...[
                  _StateCard(icon: Icons.error_outline, text: _error!),
                  const SizedBox(height: 12),
                ],
                _FormSection(
                  children: [
                    _StaffTextField(
                      controller: _questionController,
                      label: 'Question',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Question is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _StaffTextField(
                      controller: _answerController,
                      label: 'Answer',
                      maxLines: 8,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Answer is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _FormSection(
                  children: [
                    _StaffDropdown(
                      label: 'Category',
                      value: _category,
                      items: const {
                        'account': 'Account',
                        'rewards': 'Rewards',
                        'events': 'Events',
                        'community': 'Community',
                        'technical': 'Technical',
                        'general': 'General',
                      },
                      onChanged: (value) => setState(() => _category = value),
                    ),
                    const SizedBox(height: 12),
                    _StaffDropdown(
                      label: 'Audience',
                      value: _audience,
                      items: const {
                        'all': 'All',
                        'player': 'Players',
                        'agent': 'Agents',
                        'staff': 'Staff',
                      },
                      onChanged: (value) => setState(() => _audience = value),
                    ),
                    const SizedBox(height: 12),
                    _StaffTextField(
                      controller: _sortOrderController,
                      label: 'Sort Order',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _FormSection(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Featured',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        'Highlight this FAQ near the top.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      value: _isFeatured,
                      onChanged: (value) => setState(() => _isFeatured = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Published',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        'Visible to selected audience.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      value: _isPublished,
                      onChanged: (value) =>
                          setState(() => _isPublished = value),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? 'Saving...' : 'Save FAQ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
  String _statusFilter = '';
  String _sourceFilter = '';
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
      final query = <String, String>{
        if (_statusFilter.isNotEmpty) 'status': _statusFilter,
        if (_sourceFilter.isNotEmpty) 'source': _sourceFilter,
      };
      final suffix = query.entries
          .map((entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
          .join('&');
      final endpoint =
          '/api/rewards/streak/redemptions/${suffix.isEmpty ? '' : '?$suffix'}';
      final apiClient = context.read<AuthProvider>().apiClient;
      final response = await apiClient.get(endpoint);
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

  Future<void> _updateRequest(int id, String status,
      {String staffNote = ''}) async {
    setState(() {
      _updatingId = id;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().apiClient.patch(
        '/api/rewards/streak/redemptions/$id/',
        body: {
          'status': status,
          if (staffNote.trim().isNotEmpty) 'staff_note': staffNote.trim(),
        },
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

  Future<void> _promptRedemptionAction({
    required int id,
    required String status,
    required String username,
    required String source,
  }) async {
    if (status == 'rejected') {
      final reason = await _promptRejectReason();
      if (reason == null) return;
      final confirmed = await _confirmRedemptionAction(
        title: 'Reject request?',
        message:
            'Reject $username\'s $source request with the provided reason?',
        confirmLabel: 'Reject',
        danger: true,
      );
      if (confirmed == true) {
        await _updateRequest(id, status, staffNote: reason);
      }
      return;
    }

    final confirmed = await _confirmRedemptionAction(
      title: status == 'approved' ? 'Approve request?' : 'Complete request?',
      message: status == 'approved'
          ? 'Approve $username\'s $source request?'
          : 'Mark $username\'s $source request as completed? This cannot be changed later.',
      confirmLabel: status == 'approved' ? 'Approve' : 'Complete',
      danger: false,
    );
    if (confirmed == true) {
      await _updateRequest(id, status);
    }
  }

  Future<String?> _promptRejectReason() async {
    return showDialog<String>(
      context: context,
      builder: (_) => const _RejectReasonDialog(),
    );
  }

  Future<bool?> _confirmRedemptionAction({
    required String title,
    required String message,
    required String confirmLabel,
    required bool danger,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title, style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(message, style: TextStyle(color: AppTheme.textSecondary)),
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
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: danger ? Colors.redAccent : AppTheme.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = _items.map((item) {
      final user = item['user'];
      final username =
          user is Map ? (user['username'] ?? 'Player').toString() : 'Player';
      final status = (item['status'] ?? 'pending').toString();
      final source =
          (item['source_label'] ?? item['source'] ?? 'Redemption').toString();
      final sourceValue = (item['source'] ?? '').toString();
      final sourceColor = _redemptionSourceColor(sourceValue);
      final statusLabel =
          (item['status_label'] ?? item['status'] ?? 'Pending').toString();
      final hiRollinUsername = (item['hi_rollin_username'] ?? '').toString();
      final id =
          item['id'] is int ? item['id'] as int : int.tryParse('${item['id']}');
      final canAct =
          id != null && (status == 'pending' || status == 'approved');
      return _InfoCard(
        icon: _redemptionSourceIcon(sourceValue),
        title: '$username • \$${item['amount'] ?? '0.00'}',
        eyebrow: 'Redemption request',
        body: [
          if (hiRollinUsername.trim().isEmpty)
            'No Hi-Rollin username provided.',
        ].join(),
        accent: AppTheme.accent,
        badges: [
          _RedemptionBadge(
            label: source,
            color: sourceColor,
          ),
          _RedemptionBadge(
            label: statusLabel,
            color: _redemptionStatusColor(status),
          ),
        ],
        highlight: hiRollinUsername.trim().isNotEmpty
            ? _HiRollinUsernameBadge(username: hiRollinUsername)
            : null,
        tint: sourceColor,
        footer: canAct
            ? _RedemptionActions(
                isUpdating: _updatingId == id,
                status: status,
                onApprove: () => _promptRedemptionAction(
                  id: id,
                  status: 'approved',
                  username: username,
                  source: source,
                ),
                onComplete: () => _promptRedemptionAction(
                  id: id,
                  status: 'completed',
                  username: username,
                  source: source,
                ),
                onReject: () => _promptRedemptionAction(
                  id: id,
                  status: 'rejected',
                  username: username,
                  source: source,
                ),
              )
            : null,
      );
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Redemptions'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const _HeaderCard(
                  title: 'Redemptions',
                  subtitle: 'Review player bonus redemption requests',
                  icon: Icons.card_giftcard_outlined,
                ),
                const SizedBox(height: 12),
                _RedemptionFilterBar(
                  status: _statusFilter,
                  source: _sourceFilter,
                  onStatusChanged: (value) {
                    setState(() => _statusFilter = value);
                    _load();
                  },
                  onSourceChanged: (value) {
                    setState(() => _sourceFilter = value);
                    _load();
                  },
                ),
                const SizedBox(height: 14),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  _StateCard(icon: Icons.error_outline, text: _error!)
                else if (children.isEmpty)
                  const _StateCard(
                    icon: Icons.inbox_outlined,
                    text: 'No redemption requests found.',
                  )
                else
                  ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RedemptionFilterBar extends StatelessWidget {
  final String status;
  final String source;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSourceChanged;

  const _RedemptionFilterBar({
    required this.status,
    required this.source,
    required this.onStatusChanged,
    required this.onSourceChanged,
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
            _RedemptionFilterMenu(
              icon: Icons.verified_outlined,
              value: status,
              items: const {
                '': 'All status',
                'pending': 'Pending',
                'approved': 'Approved',
                'completed': 'Completed',
                'rejected': 'Rejected',
              },
              onChanged: onStatusChanged,
            ),
            const SizedBox(width: 8),
            _RedemptionFilterMenu(
              icon: Icons.redeem_outlined,
              value: source,
              items: const {
                '': 'All sources',
                'login_streak': 'Login Streak',
                'scratch_bonus': 'Scratch Bonus',
                'win_bonus': 'Win Bonus',
              },
              onChanged: onSourceChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _RedemptionFilterMenu extends StatelessWidget {
  final IconData icon;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _RedemptionFilterMenu({
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

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() {
        _error = 'Reason is required.';
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(
        'Rejection reason',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a reason the player can understand.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 4,
            autofocus: true,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Reason for rejection',
              hintStyle: TextStyle(color: AppTheme.textSecondary),
              errorText: _error.isEmpty ? null : _error,
              filled: true,
              fillColor: AppTheme.background.withValues(alpha: 0.28),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.primary),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Submit'),
        ),
      ],
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
  final List<Widget> badges;
  final Widget? highlight;
  final Widget? footer;
  final VoidCallback? onTap;
  final Color? tint;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.eyebrow,
    required this.body,
    required this.accent,
    this.badges = const [],
    this.highlight,
    this.footer,
    this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: tint == null
          ? AppTheme.itemDecoration()
          : BoxDecoration(
              color: tint!.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(
                color: tint!.withValues(alpha: 0.22),
              ),
            ),
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
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: badges,
                  ),
                ],
                if (highlight != null) ...[
                  const SizedBox(height: 8),
                  highlight!,
                ],
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
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary.withValues(alpha: 0.65),
              size: 22,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: card,
    );
  }
}

class _RedemptionBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _RedemptionBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
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

Color _redemptionStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return const Color(0xFFF59E0B);
    case 'approved':
      return const Color(0xFF60A5FA);
    case 'completed':
      return const Color(0xFF22C55E);
    case 'rejected':
      return Colors.redAccent;
    default:
      return AppTheme.accent;
  }
}

Color _redemptionSourceColor(String source) {
  switch (source.toLowerCase()) {
    case 'login_streak':
      return const Color(0xFF8B5CF6);
    case 'scratch_bonus':
      return const Color(0xFFF59E0B);
    case 'win_bonus':
      return const Color(0xFFEC4899);
    default:
      return AppTheme.primary;
  }
}

IconData _redemptionSourceIcon(String source) {
  switch (source.toLowerCase()) {
    case 'login_streak':
      return Icons.local_fire_department_outlined;
    case 'scratch_bonus':
      return Icons.style_outlined;
    case 'win_bonus':
      return Icons.emoji_events_outlined;
    default:
      return Icons.redeem_outlined;
  }
}

class _HiRollinUsernameBadge extends StatelessWidget {
  final String username;

  const _HiRollinUsernameBadge({required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_circle_outlined,
            color: AppTheme.accent,
            size: 17,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RedemptionActions extends StatelessWidget {
  final bool isUpdating;
  final String status;
  final VoidCallback onApprove;
  final VoidCallback onComplete;
  final VoidCallback onReject;

  const _RedemptionActions({
    required this.isUpdating,
    required this.status,
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
        if (status == 'pending') ...[
          _SmallActionButton(
            label: 'Approve',
            onPressed: onApprove,
            color: AppTheme.primary,
          ),
          _SmallActionButton(
            label: 'Reject',
            onPressed: onReject,
            color: Colors.redAccent,
          ),
        ] else if (status == 'approved')
          _SmallActionButton(
            label: 'Complete',
            onPressed: onComplete,
            color: AppTheme.accent,
            foregroundColor: Colors.black,
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

String _formatDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
