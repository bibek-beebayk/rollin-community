import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../models/post_comment.dart';
import '../api/api_client.dart';

class PostService {
  final ApiClient apiClient;
  static final Map<int, List<PostComment>> _commentsCache = {};
  static final Map<int, DateTime> _commentsCacheUpdatedAt = {};
  static const Duration _commentsCacheTtl = Duration(seconds: 45);

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

  Future<Map<String, dynamic>?> toggleLike(int postId) async {
    try {
      final response = await apiClient.post('/api/posts/$postId/like/', body: {});
      final data = (response is Map<String, dynamic> && response['data'] is Map<String, dynamic>)
          ? response['data'] as Map<String, dynamic>
          : (response is Map<String, dynamic> ? response : null);
      return data;
    } catch (e) {
      debugPrint('Error toggling like for post: $postId, error: $e');
      return null;
    }
  }

  Future<List<PostComment>> getComments(int postId) async {
    final cached = getCachedComments(postId);
    if (cached != null) {
      return cached;
    }
    return fetchComments(postId);
  }

  Future<List<PostComment>> fetchComments(int postId) async {
    try {
      final response = await apiClient.get('/api/posts/$postId/comments/');
      final raw = (response is Map<String, dynamic> && response['data'] is List)
          ? response['data'] as List
          : (response is List ? response : const []);
      final comments = raw
          .whereType<Map<String, dynamic>>()
          .map(PostComment.fromJson)
          .toList();
      _commentsCache[postId] = comments;
      _commentsCacheUpdatedAt[postId] = DateTime.now();
      return comments;
    } catch (e) {
      debugPrint('Error fetching comments for post: $postId, error: $e');
      return [];
    }
  }

  Future<PostComment?> addComment(
    int postId, {
    required String content,
    int? parentId,
  }) async {
    try {
      final body = <String, dynamic>{'content': content};
      if (parentId != null) body['parent'] = parentId;
      final response = await apiClient.post('/api/posts/$postId/comments/', body: body);
      final data = (response is Map<String, dynamic> && response['data'] is Map<String, dynamic>)
          ? response['data'] as Map<String, dynamic>
          : (response is Map<String, dynamic> ? response : null);
      if (data == null) return null;
      final created = PostComment.fromJson(data);
      _upsertCommentInCache(postId, created);
      return created;
    } catch (e) {
      debugPrint('Error adding comment on post: $postId, error: $e');
      return null;
    }
  }

  Future<PostComment?> updateComment(
    int postId,
    int commentId, {
    required String content,
  }) async {
    try {
      final response = await apiClient.patch(
        '/api/posts/$postId/comments/$commentId/',
        body: {'content': content},
      );
      final data =
          (response is Map<String, dynamic> && response['data'] is Map<String, dynamic>)
              ? response['data'] as Map<String, dynamic>
              : (response is Map<String, dynamic> ? response : null);
      if (data == null) return null;
      final updated = PostComment.fromJson(data);
      _replaceCommentInCache(postId, updated);
      return updated;
    } catch (e) {
      debugPrint('Error updating comment $commentId on post $postId: $e');
      return null;
    }
  }

  Future<int> deleteComment(int postId, int commentId) async {
    try {
      final response = await apiClient.delete('/api/posts/$postId/comments/$commentId/');
      int deletedCount = 1;
      if (response is Map<String, dynamic>) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          final raw = data['deleted_count'];
          if (raw is int) {
            deletedCount = raw;
          } else if (raw is String) {
            deletedCount = int.tryParse(raw) ?? deletedCount;
          }
        }
      }
      _removeCommentFromCache(postId, commentId);
      return deletedCount;
    } catch (e) {
      debugPrint('Error deleting comment $commentId on post $postId: $e');
      return 0;
    }
  }

  List<PostComment>? getCachedComments(int postId) {
    final updatedAt = _commentsCacheUpdatedAt[postId];
    final cached = _commentsCache[postId];
    if (updatedAt == null || cached == null) return null;
    if (DateTime.now().difference(updatedAt) > _commentsCacheTtl) return null;
    return cached;
  }

  void _upsertCommentInCache(int postId, PostComment comment) {
    final current = List<PostComment>.from(_commentsCache[postId] ?? const []);
    if (comment.parentId == null) {
      current.add(comment);
    } else {
      bool inserted = false;
      List<PostComment> insertReply(List<PostComment> list) {
        return list.map((item) {
          if (item.id == comment.parentId) {
            inserted = true;
            return PostComment(
              id: item.id,
              parentId: item.parentId,
              content: item.content,
              author: item.author,
              createdAt: item.createdAt,
              replies: [...item.replies, comment],
            );
          }
          if (item.replies.isEmpty) return item;
          return PostComment(
            id: item.id,
            parentId: item.parentId,
            content: item.content,
            author: item.author,
            createdAt: item.createdAt,
            replies: insertReply(item.replies),
          );
        }).toList();
      }

      final updated = insertReply(current);
      if (inserted) {
        _commentsCache[postId] = updated;
      } else {
        current.add(comment);
        _commentsCache[postId] = current;
      }
      _commentsCacheUpdatedAt[postId] = DateTime.now();
      return;
    }

    _commentsCache[postId] = current;
    _commentsCacheUpdatedAt[postId] = DateTime.now();
  }

  void _replaceCommentInCache(int postId, PostComment updatedComment) {
    final current = List<PostComment>.from(_commentsCache[postId] ?? const []);
    if (current.isEmpty) return;

    List<PostComment> replace(List<PostComment> list) {
      return list.map((item) {
        if (item.id == updatedComment.id) {
          return PostComment(
            id: item.id,
            parentId: item.parentId,
            content: updatedComment.content,
            author: item.author,
            createdAt: item.createdAt,
            replies: item.replies,
          );
        }
        if (item.replies.isEmpty) return item;
        return PostComment(
          id: item.id,
          parentId: item.parentId,
          content: item.content,
          author: item.author,
          createdAt: item.createdAt,
          replies: replace(item.replies),
        );
      }).toList();
    }

    _commentsCache[postId] = replace(current);
    _commentsCacheUpdatedAt[postId] = DateTime.now();
  }

  void _removeCommentFromCache(int postId, int commentId) {
    final current = List<PostComment>.from(_commentsCache[postId] ?? const []);
    if (current.isEmpty) return;

    List<PostComment> removeById(List<PostComment> list) {
      final next = <PostComment>[];
      for (final item in list) {
        if (item.id == commentId) continue;
        next.add(
          PostComment(
            id: item.id,
            parentId: item.parentId,
            content: item.content,
            author: item.author,
            createdAt: item.createdAt,
            replies: removeById(item.replies),
          ),
        );
      }
      return next;
    }

    _commentsCache[postId] = removeById(current);
    _commentsCacheUpdatedAt[postId] = DateTime.now();
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
