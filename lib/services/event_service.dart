import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/event.dart';

class EventService {
  final ApiClient _apiClient;

  EventService(this._apiClient);

  Future<List<Event>> getActiveEvents() async {
    try {
      final response = await _apiClient.get('/api/events/active/');

      List<dynamic> data = [];
      if (response is Map && response.containsKey('data')) {
        data = response['data'];
      } else if (response is List) {
        data = response;
      }
      // Depending on API, response could be direct list or paginated results
      if (response is Map && response.containsKey('results')) {
        data = response['results'];
      }

      return data.map((json) => Event.fromJson(json)).toList();
    } catch (e) {
      debugPrint('EventService: Error fetching events: $e');
      // Return empty list instead of throwing to avoid crashing UI
      return [];
    }
  }
}
