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

  Future<List<Post>> getMyPosts() async {
    return _fetchPosts('/api/posts/my-posts/');
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

  Future<Post?> createPost({
    String? title,
    required String content,
    required String visibility,
    List<String>? imagePaths,
  }) async {
    try {
      final fields = {
        'title': title ?? '',
        'raw_content': content,
        'visibility': visibility,
      };

      final filePaths = <String, List<String>>{};
      if (imagePaths != null && imagePaths.isNotEmpty) {
        filePaths['images'] = imagePaths;
      }

      final response = await apiClient.postMultipartWithFields(
        '/api/posts/',
        fields: fields,
        filePaths: filePaths,
      );

      final postJson = _extractPostJson(response);
      if (postJson != null) {
        return Post.fromJson(postJson);
      }
      return null;
    } catch (e) {
      debugPrint('Error creating post: $e');
      rethrow;
    }
  }

  Future<Post?> updatePost({
    required int postId,
    String? title,
    required String content,
    required String visibility,
    List<String>? newImagePaths,
    List<int>? removeImageIds,
    bool clearExistingImages = false,
  }) async {
    try {
      final fields = {
        'title': title ?? '',
        'raw_content': content,
        'visibility': visibility,
      };

      if (clearExistingImages) {
        fields['clear_images'] = 'true';
      }
      if (removeImageIds != null && removeImageIds.isNotEmpty) {
        fields['remove_image_ids'] = removeImageIds.join(',');
      }

      final filePaths = <String, List<String>>{};
      if (newImagePaths != null && newImagePaths.isNotEmpty) {
        filePaths['images'] = newImagePaths;
      }

      final response = await apiClient.postMultipartWithFields(
        '/api/posts/$postId/',
        fields: fields,
        filePaths: filePaths,
        isPatch: true,
      );

      final postJson = _extractPostJson(response);
      if (postJson != null) {
        return Post.fromJson(postJson);
      }
      return null;
    } catch (e) {
      debugPrint('Error updating post: $e');
      rethrow;
    }
  }

  Future<bool> deletePost(int postId) async {
    try {
      await apiClient.delete('/api/posts/$postId/');
      return true;
    } catch (e) {
      debugPrint('Error deleting post: $postId, error: $e');
      return false;
    }
  }

  Map<String, dynamic>? _extractPostJson(dynamic response) {
    if (response is Map<String, dynamic>) {
      final data = response['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return response;
    }
    return null;
  }
}
