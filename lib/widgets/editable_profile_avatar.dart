import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../services/profile_local_db.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_error.dart';

/// A reusable profile avatar that displays the current profile image
/// (or user initials / icon as fallback) and allows picking / uploading
/// a new photo via camera or gallery to Firebase Storage, while caching
/// the image locally in SQLite for instant offline access.
class EditableProfileAvatar extends StatefulWidget {
  final String? avatarUrl;
  final String? name;
  final String? role;
  final double radius;
  final bool isEditable;
  final ValueChanged<String?>? onAvatarChanged;
  final BoxBorder? customBorder;

  const EditableProfileAvatar({
    super.key,
    required this.avatarUrl,
    this.name,
    this.role,
    this.radius = 60,
    this.isEditable = true,
    this.onAvatarChanged,
    this.customBorder,
  });

  @override
  State<EditableProfileAvatar> createState() => _EditableProfileAvatarState();
}

class _EditableProfileAvatarState extends State<EditableProfileAvatar> {
  final ProfileService _profileService = ProfileService();
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  String? _currentAvatarUrl;
  String? _localFilePath;

  @override
  void initState() {
    super.initState();
    _currentAvatarUrl = widget.avatarUrl;
    _checkLocalCache();
  }

  @override
  void didUpdateWidget(covariant EditableProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.avatarUrl != oldWidget.avatarUrl) {
      _currentAvatarUrl = widget.avatarUrl;
      _checkLocalCache();
    }
  }

  /// Checks the local SQLite database for a persisted offline photo.
  Future<void> _checkLocalCache() async {
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user != null) {
        final record = await ProfileLocalDatabase.instance.getAvatar(user.id);
        if (record?.localPath != null && mounted) {
          final file = File(record!.localPath!);
          if (await file.exists()) {
            setState(() {
              _localFilePath = record.localPath;
              if (record.avatarUrl != null && record.avatarUrl!.isNotEmpty) {
                _currentAvatarUrl = record.avatarUrl;
              }
            });
          }
        }

        // If local picture exists but hasn't synced to Firebase yet, attempt opportunistic background sync
        if (record != null && !record.isSynced) {
          _profileService.syncPendingAvatar().then((syncedUrl) {
            if (syncedUrl != null && mounted) {
              setState(() => _currentAvatarUrl = syncedUrl);
              widget.onAvatarChanged?.call(syncedUrl);
            }
          });
        }
      }
    } catch (_) {}
  }

  void _showImageSourcePicker() {
    if (!widget.isEditable || _isUploading) return;

    final hasAvatar = (_localFilePath != null && _localFilePath!.isNotEmpty) ||
        (_currentAvatarUrl != null && _currentAvatarUrl!.trim().isNotEmpty);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Change Profile Picture',
              style: GoogleFonts.lexend(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 18),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded, color: AppTheme.accentBlue),
              ),
              title: Text(
                'Take Photo',
                style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.photo_library_rounded, color: Colors.purple.shade700),
              ),
              title: Text(
                'Choose from Gallery',
                style: GoogleFonts.lexend(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            if (hasAvatar) ...[
              const Divider(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.errorRed.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed),
                ),
                title: Text(
                  'Remove Photo',
                  style: GoogleFonts.lexend(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.errorRed,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() => _isUploading = true);

      final file = File(pickedFile.path);
      // Saved in SQLite FIRST, then Firebase Storage gets it from SQLite
      final newUrl = await _profileService.uploadAvatar(file);

      // Refresh SQLite cached local path immediately
      await _checkLocalCache();

      if (!mounted) return;
      setState(() {
        if (newUrl != null) {
          _currentAvatarUrl = newUrl;
        }
        _isUploading = false;
      });

      widget.onAvatarChanged?.call(newUrl ?? _currentAvatarUrl);

      final isSynced = newUrl != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isSynced ? Icons.check_circle_outline : Icons.cloud_queue_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isSynced
                      ? 'Profile picture updated & synced!'
                      : 'Profile picture saved locally! Will sync to cloud when connected.',
                  style: GoogleFonts.lexend(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: isSynced ? Colors.green.shade600 : Colors.amber.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapErrorToMessage(e),
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUploading = true);
    try {
      await _profileService.deleteAvatar();
      if (!mounted) return;
      setState(() {
        _currentAvatarUrl = null;
        _localFilePath = null;
        _isUploading = false;
      });

      widget.onAvatarChanged?.call(null);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile picture removed.',
            style: GoogleFonts.lexend(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapErrorToMessage(e),
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Widget _buildFallbackContent() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.softGray,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/logo.jpg',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: AppTheme.softGray,
            alignment: Alignment.center,
            child: Icon(
              Icons.person,
              color: AppTheme.textDark,
              size: widget.radius * 0.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarImage() {
    // 1. Check local SQLite cached file first (instant, 0ms, works completely offline)
    if (_localFilePath != null && _localFilePath!.isNotEmpty) {
      final file = File(_localFilePath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallbackContent(),
        );
      }
    }

    // 2. Fallback to Firebase Storage URL via CachedNetworkImage
    if (_currentAvatarUrl != null && _currentAvatarUrl!.trim().isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _currentAvatarUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: AppTheme.softGray,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accentBlue,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildFallbackContent(),
      );
    }

    // 3. Fallback initials
    return _buildFallbackContent();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;

    final avatarCircle = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        shape: BoxShape.circle,
        border: widget.customBorder ??
            Border.all(
              color: AppTheme.accentBlue,
              width: widget.radius > 45 ? 2.5 : 1.5,
            ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.18),
            blurRadius: widget.radius > 45 ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.all(widget.radius > 45 ? 3 : 2),
      child: ClipOval(
        child: _buildAvatarImage(),
      ),
    );

    return GestureDetector(
      onTap: widget.isEditable ? _showImageSourcePicker : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          avatarCircle,

          // Uploading spinner overlay
          if (_isUploading)
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          // Edit camera/pencil badge
          if (widget.isEditable && !_isUploading)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(widget.radius > 45 ? 7 : 5),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: widget.radius > 45 ? 18 : 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
