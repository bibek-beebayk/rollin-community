import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/social_connection.dart';
import '../models/user.dart';

class ConnectionSearchPage {
  final List<User> users;
  final bool hasMore;
  final int count;
  final int offset;
  final int limit;

  const ConnectionSearchPage({
    required this.users,
    required this.hasMore,
    required this.count,
    required this.offset,
    required this.limit,
  });
}

class SocialProvider with ChangeNotifier {
  Map<String, dynamic> _onboardingState = const {
    'has_seen_agent_suggestions': false,
    'has_seen_player_suggestions': false,
    'has_completed_social_onboarding': false,
  };

  Map<String, dynamic> get onboardingState => _onboardingState;
  bool get hasCompletedOnboarding =>
      _onboardingState['has_completed_social_onboarding'] == true;

  Future<Map<String, dynamic>> fetchOnboardingState(ApiClient apiClient) async {
    final response = await apiClient.get('/api/social/onboarding/state/');
    final data = (response is Map && response.containsKey('data'))
        ? response['data']
        : response;
    if (data is Map<String, dynamic>) {
      _onboardingState = data;
      notifyListeners();
    }
    return _onboardingState;
  }

  Future<Map<String, dynamic>> updateOnboardingState(
    ApiClient apiClient, {
    bool? hasSeenAgentSuggestions,
    bool? hasSeenPlayerSuggestions,
    bool? hasCompletedSocialOnboarding,
  }) async {
    final payload = <String, dynamic>{};
    if (hasSeenAgentSuggestions != null) {
      payload['has_seen_agent_suggestions'] = hasSeenAgentSuggestions;
    }
    if (hasSeenPlayerSuggestions != null) {
      payload['has_seen_player_suggestions'] = hasSeenPlayerSuggestions;
    }
    if (hasCompletedSocialOnboarding != null) {
      payload['has_completed_social_onboarding'] = hasCompletedSocialOnboarding;
    }

    final response = await apiClient.patch(
      '/api/social/onboarding/state/',
      body: payload,
    );
    final data = (response is Map && response.containsKey('data'))
        ? response['data']
        : response;
    if (data is Map<String, dynamic>) {
      _onboardingState = data;
      notifyListeners();
    }
    return _onboardingState;
  }

  Future<List<User>> fetchSuggestedAgents(ApiClient apiClient) async {
    final response = await apiClient.get('/api/social/suggestions/agents/');
    final data = (response is Map && response.containsKey('data'))
        ? response['data']
        : (response is List ? response : []);
    return _usersFromList(data);
  }

  Future<List<User>> fetchSuggestedPlayers(ApiClient apiClient) async {
    final response = await apiClient.get('/api/social/suggestions/players/');
    final data = (response is Map && response.containsKey('data'))
        ? response['data']
        : (response is List ? response : []);
    return _usersFromList(data);
  }

  Future<List<User>> searchAgentConnections(
    ApiClient apiClient, {
    String query = '',
  }) async {
    final page = await searchAgentConnectionsPaged(
      apiClient,
      query: query,
      section: 'all',
      limit: 50,
      offset: 0,
    );
    return page.users;
  }

  Future<List<User>> searchPlayerConnections(
    ApiClient apiClient, {
    String query = '',
  }) async {
    final page = await searchPlayerConnectionsPaged(
      apiClient,
      query: query,
      section: 'all',
      limit: 50,
      offset: 0,
    );
    return page.users;
  }

  Future<ConnectionSearchPage> searchAgentConnectionsPaged(
    ApiClient apiClient, {
    String query = '',
    String section = 'all',
    int limit = 10,
    int offset = 0,
  }) async {
    final q = query.trim();
    final params = <String>[
      'section=${Uri.encodeQueryComponent(section)}',
      'limit=$limit',
      'offset=$offset',
      if (q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
    ];
    final endpoint = '/api/social/connections/search/agents/?${params.join('&')}';
    final response = await apiClient.get(endpoint);
    return _parseConnectionSearchPageResponse(response);
  }

  Future<ConnectionSearchPage> searchPlayerConnectionsPaged(
    ApiClient apiClient, {
    String query = '',
    String section = 'all',
    int limit = 10,
    int offset = 0,
  }) async {
    final q = query.trim();
    final params = <String>[
      'section=${Uri.encodeQueryComponent(section)}',
      'limit=$limit',
      'offset=$offset',
      if (q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
    ];
    final endpoint = '/api/social/connections/search/players/?${params.join('&')}';
    final response = await apiClient.get(endpoint);
    return _parseConnectionSearchPageResponse(response);
  }

  Future<User> fetchPublicProfile(ApiClient apiClient, int userId) async {
    final response = await apiClient.get('/api/social/profiles/$userId/');
    final data = (response is Map && response.containsKey('data'))
        ? response['data']
        : response;
    if (data is Map<String, dynamic>) {
      return User.fromJson(data);
    }
    throw Exception('Invalid profile response');
  }

  Future<Map<String, dynamic>> createConnection(
    ApiClient apiClient, {
    required int targetUserId,
    bool initiatedFromOnboarding = false,
  }) async {
    final response = await apiClient.post(
      '/api/social/connections/create/',
      body: {
        'target_user_id': targetUserId,
        'initiated_from_onboarding': initiatedFromOnboarding,
      },
    );
    final data = (response is Map && response.containsKey('data'))
        ? response['data']
        : response;
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw Exception('Invalid connection response');
  }

  Future<void> disconnectConnection(
    ApiClient apiClient, {
    required int targetUserId,
  }) async {
    await apiClient.post(
      '/api/social/connections/disconnect/',
      body: {
        'target_user_id': targetUserId,
      },
    );
  }

  Future<void> acceptConnection(
    ApiClient apiClient, {
    required int connectionId,
  }) async {
    await apiClient.post('/api/social/connections/$connectionId/accept/', body: {});
  }

  Future<void> rejectConnection(
    ApiClient apiClient, {
    required int connectionId,
  }) async {
    await apiClient.post('/api/social/connections/$connectionId/reject/', body: {});
  }

  Future<List<SocialConnection>> fetchConnections(ApiClient apiClient) async {
    final response = await apiClient.get('/api/social/connections/');
    final data = (response is Map && response.containsKey('data'))
        ? response['data']
        : (response is List ? response : []);

    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(SocialConnection.fromJson)
        .toList(growable: false);
  }

  List<User> _usersFromList(dynamic data) {
    if (data is! List) return const [];
    final users = <User>[];
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        users.add(User.fromJson(item));
      }
    }
    return users;
  }

  ConnectionSearchPage _parseConnectionSearchPageResponse(dynamic response) {
    final payload = (response is Map && response.containsKey('data'))
        ? response['data']
        : response;

    if (payload is! Map) {
      return const ConnectionSearchPage(
        users: [],
        hasMore: false,
        count: 0,
        offset: 0,
        limit: 10,
      );
    }

    final users = _usersFromList(payload['results']);
    final meta = payload['meta'];
    final count = meta is Map ? _asInt(meta['count']) : 0;
    final hasMore = meta is Map ? (meta['has_more'] == true) : false;
    final offset = meta is Map ? _asInt(meta['offset']) : 0;
    final limit = meta is Map ? _asInt(meta['limit'], fallback: 10) : 10;

    return ConnectionSearchPage(
      users: users,
      hasMore: hasMore,
      count: count,
      offset: offset,
      limit: limit,
    );
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}
