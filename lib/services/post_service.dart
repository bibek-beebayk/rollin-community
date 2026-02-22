import '../models/post.dart';
import '../api/api_client.dart';

class PostService {
  final ApiClient apiClient;

  PostService(this.apiClient);

  Future<List<Post>> getLatestPosts() async {
    try {
      final response = await apiClient.get('/api/posts/');

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
      print('Error fetching posts: $e');
      return [];
    }
  }
}
