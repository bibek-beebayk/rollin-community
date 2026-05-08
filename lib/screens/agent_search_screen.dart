import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';
import 'agent_profile_screen.dart';

class AgentSearchScreen extends StatefulWidget {
  const AgentSearchScreen({super.key});

  @override
  State<AgentSearchScreen> createState() => _AgentSearchScreenState();
}

class _AgentSearchScreenState extends State<AgentSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<User> _agents = [];
  bool _isLoading = false;
  String? _error;

  Color _availabilityColor(String availability) {
    switch (availability) {
      case 'online':
        return Colors.greenAccent;
      case 'busy':
        return Colors.orangeAccent;
      case 'away':
        return Colors.amber;
      case 'offline':
        return Colors.redAccent;
      default:
        return AppTheme.textSecondary.withValues(alpha: 0.75);
    }
  }

  String _availabilityLabel(String availability) {
    switch (availability) {
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

  String? _resolveProfileImageUrl(User user) {
    final raw =
        (user.profileThumbnail ?? user.avatar ?? user.profilePicture)?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$base$path';
  }

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String query) async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final agents = await chatProvider.searchAgents(
        authProvider.apiClient,
        query,
      );
      if (!mounted) return;
      setState(() {
        _agents = agents;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openAgentProfile(User agent) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentProfileScreen(userId: agent.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Agents'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search agents by username',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppTheme.surface.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.cardBorder,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              LinearProgressIndicator(minHeight: 2, color: AppTheme.accent),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _agents.isEmpty
                  ? Center(
                      child: Text(
                        'No agents found.',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _agents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final agent = _agents[index];
                        final profileImageUrl = _resolveProfileImageUrl(agent);
                        return Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.cardBorder,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.85),
                              backgroundImage: profileImageUrl != null
                                  ? NetworkImage(profileImageUrl)
                                  : null,
                              child: profileImageUrl == null
                                  ? Text(
                                      agent.username.isNotEmpty
                                          ? agent.username[0].toUpperCase()
                                          : 'A',
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Expanded(child: Text(agent.username)),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _availabilityColor(agent.agentAvailability)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _availabilityColor(agent.agentAvailability)
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  child: Text(
                                    _availabilityLabel(agent.agentAvailability),
                                    style: TextStyle(
                                      color: _availabilityColor(agent.agentAvailability),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              agent.agentStatusNote.isNotEmpty
                                  ? agent.agentStatusNote
                                  : (agent.isVerified ? 'Verified agent' : 'Agent'),
                              style: TextStyle(
                                color: AppTheme.textSecondary.withValues(alpha: 0.8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : () => _openAgentProfile(agent),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(74, 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Profile',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
