import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../api/api_client.dart';

class PostService {
  final ApiClient apiClient;

  PostService(this.apiClient);

  Future<List<Post>> getLatestPosts() async {
    return _fetchPosts('/api/posts/');
  }

  Future<List<Post>> getFeedPosts() async {
    return _fetchPosts('/api/posts/feed/');
  }

  Future<List<Post>> _fetchPosts(String endpoint) async {
    try {
      final response = await apiClient.get(endpoint);

      List<dynamic> results = [];
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) {
          results = response['data'];
        } else if (response.containsKey('results')) {
          results = response['results'];
        }
      } else if (response is List) {
        results = response;
      }

      return results.map((json) => Post.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching posts: $e');
      return [];
    }
  }
}
