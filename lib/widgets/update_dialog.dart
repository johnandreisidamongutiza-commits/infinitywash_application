import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/app_version_info.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

enum _UpdateUiState {
  ready,
  downloading,
  installing,
  error,
}

class UpdateDialog extends StatefulWidget {
  final AppVersionInfo info;
  final bool isMandatory;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.isMandatory,
    required this.currentVersion,
  });

  /// Static helper to display the update dialog.
  /// Returns `true` if dismissed (user clicked "Later"), or `false` if mandatory / closed.
  static Future<bool> show({
    required BuildContext context,
    required UpdateCheckResult result,
  }) async {
    final info = result.versionInfo;
    if (info == null) return true;

    final dismissed = await showDialog<bool>(
      context: context,
      barrierDismissible: !result.isMandatory,
      builder: (context) => UpdateDialog(
        info: info,
        isMandatory: result.isMandatory,
        currentVersion: result.currentVersionName,
      ),
    );

    return dismissed ?? false;
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdateUiState _state = _UpdateUiState.ready;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _downloadedFilePath;

  @override
  void dispose() {
    if (_state == _UpdateUiState.downloading) {
      UpdateService.instance.cancelDownload();
    }
    super.dispose();
  }

  Future<void> _startUpdate() async {
    // 1. Check & request install permission on Android
    final hasPermission = await _ensureInstallPermission();
    if (!hasPermission) return;

    // 2. Start download
    setState(() {
      _state = _UpdateUiState.downloading;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _errorMessage = null;
    });

    try {
      final file = await UpdateService.instance.downloadApk(
        apkUrl: widget.info.apkUrl,
        onProgress: (progress, received, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _receivedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );

      _downloadedFilePath = file.path;

      if (!mounted) return;

      setState(() {
        _state = _UpdateUiState.installing;
      });

      // 3. Launch the Android Package Installer
      await _launchInstaller(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateUiState.error;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool> _ensureInstallPermission() async {
    final granted = await UpdateService.instance.checkInstallPermission();
    if (granted) return true;

    final requested = await UpdateService.instance.requestInstallPermission();
    if (requested) return true;

    if (!mounted) return false;

    // Show friendly explanation modal before taking the user to settings
    final proceedToSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: AppTheme.actionBlue),
            SizedBox(width: 8),
            Text('Permission Needed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'To install updates outside the Play Store, Android requires you to allow installs from Infinity Wash.\n\n'
          'Please toggle "Allow from this source" on the next screen.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textLight)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.actionBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (proceedToSettings == true) {
      await UpdateService.instance.openInstallSettings();
    }

    return false;
  }

  Future<void> _launchInstaller(String filePath) async {
    final result = await UpdateService.instance.installApk(filePath);
    if (result.type != ResultType.done && mounted) {
      setState(() {
        _state = _UpdateUiState.error;
        _errorMessage = 'Could not launch installer: ${result.message}';
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    // Intercept back button: blocked on mandatory update or during active download
    final canPop = !widget.isMandatory && _state != _UpdateUiState.downloading;

    return PopScope(
      canPop: canPop,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon & Title
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.isMandatory
                          ? AppTheme.errorRed.withValues(alpha: 0.12)
                          : AppTheme.lightBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.isMandatory ? Icons.warning_rounded : Icons.system_update_rounded,
                      color: widget.isMandatory ? AppTheme.errorRed : AppTheme.actionBlue,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isMandatory ? 'Update Required' : 'Update Available',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'v${widget.currentVersion}  →  v${widget.info.latestVersion}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.actionBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Mandatory Banner if required
              if (widget.isMandatory)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.errorRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppTheme.errorRed),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This update is required to continue using Infinity Wash.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.errorRed,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Dynamic Body based on state
              _buildContent(),

              const SizedBox(height: 20),

              // Action Buttons
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _UpdateUiState.ready:
        return _buildReleaseNotes();

      case _UpdateUiState.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Downloading update...',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textDark),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress >= 0 ? _progress : null,
                minHeight: 8,
                backgroundColor: AppTheme.softGray,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.actionBlue),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _progress >= 0 ? '${(_progress * 100).toInt()}%' : 'Preparing...',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.actionBlue,
                  ),
                ),
                if (_totalBytes > 0)
                  Text(
                    '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
              ],
            ),
          ],
        );

      case _UpdateUiState.installing:
        return Column(
          children: [
            const Icon(Icons.install_mobile, size: 40, color: AppTheme.actionBlue),
            const SizedBox(height: 8),
            const Text(
              'Ready to Install',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            const SizedBox(height: 4),
            const Text(
              'Follow the on-screen prompts from Android to finish installing.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
          ],
        );

      case _UpdateUiState.error:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.errorRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 20, color: AppTheme.errorRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage ?? 'Download interrupted. Please check your connection and retry.',
                  style: const TextStyle(fontSize: 13, color: AppTheme.errorRed),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildReleaseNotes() {
    if (widget.info.releaseNotes.isEmpty) {
      return const Text(
        'A new version is available with performance improvements and bug fixes.',
        style: TextStyle(fontSize: 13, color: AppTheme.textLight, height: 1.4),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "What's New:",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 140),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.info.releaseNotes.map((note) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          color: AppTheme.actionBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          note,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textDark,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    switch (_state) {
      case _UpdateUiState.ready:
        return Row(
          children: [
            if (!widget.isMandatory) ...[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.borderGray),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Later', style: TextStyle(color: AppTheme.textLight)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.actionBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _startUpdate,
                child: const Text(
                  'Update Now',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );

      case _UpdateUiState.downloading:
        return Center(
          child: TextButton(
            onPressed: () {
              UpdateService.instance.cancelDownload();
              setState(() {
                _state = _UpdateUiState.ready;
              });
            },
            child: const Text('Cancel Download', style: TextStyle(color: AppTheme.textLight)),
          ),
        );

      case _UpdateUiState.installing:
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.actionBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            if (_downloadedFilePath != null) {
              _launchInstaller(_downloadedFilePath!);
            }
          },
          child: const Text('Open Installer Again'),
        );

      case _UpdateUiState.error:
        return Row(
          children: [
            if (!widget.isMandatory) ...[
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Dismiss', style: TextStyle(color: AppTheme.textLight)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.actionBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _startUpdate,
                child: const Text('Retry Update'),
              ),
            ),
          ],
        );
    }
  }
}

