// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../api/api_client.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';

class CreatePostScreen extends StatefulWidget {
  final Post? editPost;

  const CreatePostScreen({super.key, this.editPost});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxImagesPerPost = 5;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _visibility = 'public';
  final List<File> _selectedImages = [];
  final List<_EditableExistingImage> _existingImages = [];
  final Set<int> _removedExistingImageIds = <int>{};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.editPost != null) {
      _titleController.text = widget.editPost!.title;
      _contentController.text = widget.editPost!.content;
      _visibility = widget.editPost!.visibility;
      _existingImages.addAll(_normalizeExistingImages(widget.editPost!));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final remainingSlots = _maxImagesPerPost - _totalImageCount;
      if (remainingSlots <= 0) {
        _showImageLimitMessage();
        return;
      }

      final permissionState = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission:
              AndroidPermission(type: RequestType.image, mediaLocation: false),
          iosAccessLevel: IosAccessLevel.readWrite,
        ),
      );
      if (!mounted) return;
      if (!permissionState.hasAccess) {
        _showImageLimitMessage('Photo permission is required to select images');
        return;
      }

      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: remainingSlots,
          requestType: RequestType.image,
        ),
      );
      if (!mounted) return;
      if (assets == null || assets.isEmpty) return;

      if (assets.length > remainingSlots) {
        _showImageLimitMessage(
          'You can only add $remainingSlots more photo${remainingSlots == 1 ? '' : 's'}',
        );
        return;
      }

      final files = <File>[];
      for (final asset in assets) {
        final file = await asset.file;
        if (file != null) {
          files.add(file);
        }
      }

      if (files.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(files);
        });
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      final removed = _existingImages.removeAt(index);
      if (removed.id != null) {
        _removedExistingImageIds.add(removed.id!);
      }
    });
  }

  List<_EditableExistingImage> _normalizeExistingImages(Post post) {
    final items = <_EditableExistingImage>[];

    for (final item in post.imageItems) {
      final trimmed = item.imageUrl.trim();
      if (trimmed.isEmpty) continue;
      items.add(
        _EditableExistingImage(
          id: item.id,
          imageUrl: _resolveMediaUrl(trimmed),
        ),
      );
    }

    if (items.isEmpty) {
      for (final raw in post.images) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        items.add(_EditableExistingImage(imageUrl: _resolveMediaUrl(trimmed)));
      }
    }

    if (items.isEmpty && post.image != null && post.image!.trim().isNotEmpty) {
      items.add(_EditableExistingImage(imageUrl: _resolveMediaUrl(post.image!.trim())));
    }

    return items;
  }

  String _resolveMediaUrl(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = ApiClient.baseUrl.endsWith('/')
        ? ApiClient.baseUrl.substring(0, ApiClient.baseUrl.length - 1)
        : ApiClient.baseUrl;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$base$path';
  }

  Future<void> _submit() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post body is required')),
      );
      return;
    }

    if (_totalImageCount > _maxImagesPerPost) {
      _showImageLimitMessage();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final postService = PostService(authProvider.apiClient);
      Post? resultPost;

      if (widget.editPost != null) {
        resultPost = await postService.updatePost(
          postId: widget.editPost!.id,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          visibility: _visibility,
          newImagePaths: _selectedImages.map((e) => e.path).toList(),
          removeImageIds: _removedExistingImageIds.toList(),
          clearExistingImages: false,
        );
      } else {
        resultPost = await postService.createPost(
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          visibility: _visibility,
          imagePaths: _selectedImages.map((e) => e.path).toList(),
        );
      }

      if (mounted) {
        Navigator.pop(context, resultPost ?? true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showImageLimitMessage([String? message]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? 'You can upload up to 5 photos per post'),
      ),
    );
  }

  int get _totalImageCount => _existingImages.length + _selectedImages.length;

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final isEdit = widget.editPost != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Post' : 'Create Post'),
        actions: [
          if (_isSubmitting)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _submit,
              child: Text(
                isEdit ? 'Update' : 'Post',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Audience Selector
            _buildAudienceSelector(),
            const SizedBox(height: 20),

            // Heading Field
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Add a heading (optional)',
                hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),

            // Body Field
            TextField(
              controller: _contentController,
              maxLines: null,
              minLines: 5,
              decoration: InputDecoration(
                hintText: "What's on your mind?",
                hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),

            // Image Selection Row
            if (_selectedImages.isNotEmpty || _existingImages.isNotEmpty)
              _buildSelectedImagesStrip(),

            const SizedBox(height: 20),
            
            // Add Media Button
            _buildAddMediaButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildAudienceSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _visibility,
          dropdownColor: AppTheme.surface,
          icon: Icon(Icons.keyboard_arrow_down, color: AppTheme.textSecondary, size: 20),
          items: [
            _buildVisibilityItem('public', Icons.public, 'Public'),
            _buildVisibilityItem('connections', Icons.people, 'Connections'),
            _buildVisibilityItem('private', Icons.lock, 'Private'),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _visibility = val);
          },
        ),
      ),
    );
  }

  DropdownMenuItem<String> _buildVisibilityItem(String value, IconData icon, String label) {
    return DropdownMenuItem(
      value: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImagesStrip() {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...List.generate(_existingImages.length, (index) {
            final existing = _existingImages[index];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      existing.imageUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 100,
                        height: 100,
                        color: AppTheme.surface,
                        alignment: Alignment.center,
                        child: Icon(Icons.broken_image, color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => _removeExistingImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Existing',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          ...List.generate(_selectedImages.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                      _selectedImages[index],
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'New',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAddMediaButton() {
    final reachedLimit = _totalImageCount >= _maxImagesPerPost;
    return InkWell(
      onTap: reachedLimit ? _showImageLimitMessage : _pickImages,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder, style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              color: reachedLimit
                  ? AppTheme.textSecondary.withValues(alpha: 0.7)
                  : AppTheme.accent,
            ),
            const SizedBox(width: 8),
            Text(
              'Add Photos ($_totalImageCount/$_maxImagesPerPost)',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableExistingImage {
  final int? id;
  final String imageUrl;

  _EditableExistingImage({
    this.id,
    required this.imageUrl,
  });
}
