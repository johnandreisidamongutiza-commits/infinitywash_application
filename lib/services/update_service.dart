import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/update_config.dart';
import '../models/app_version_info.dart';

/// Result object returned by the update check.
class UpdateCheckResult {
  final bool hasUpdate;
  final bool isMandatory;
  final int currentBuildNumber;
  final String currentVersionName;
  final AppVersionInfo? versionInfo;
  final String? errorMessage;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.isMandatory,
    required this.currentBuildNumber,
    required this.currentVersionName,
    this.versionInfo,
    this.errorMessage,
  });
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5), // Large enough for APK downloads
      followRedirects: true,
      maxRedirects: 5,
    ),
  );

  CancelToken? _downloadCancelToken;

  /// Fetches remote version.json and compares it against the installed app version.
  /// Fails silently without crashing or interrupting the user on network or JSON errors.
  Future<UpdateCheckResult> checkForUpdate({String? customUrl}) async {
    int currentBuild = 0;
    String currentVersion = '1.0.0';

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      currentVersion = packageInfo.version;
      currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    } catch (e) {
      debugPrint('⚠️ [UpdateService] Could not read local package info: $e');
    }

    final url = customUrl ?? UpdateConfig.versionJsonUrl;

    // Prevent network call if the URL is still the default placeholder
    if (url.contains('YOUR_GITHUB_USERNAME')) {
      debugPrint(
        'ℹ️ [UpdateService] versionJsonUrl is not configured yet. Skipping check.',
      );
      return UpdateCheckResult(
        hasUpdate: false,
        isMandatory: false,
        currentBuildNumber: currentBuild,
        currentVersionName: currentVersion,
      );
    }

    try {
      // Append cache-busting timestamp so GitHub raw CDN never serves stale data
      final separator = url.contains('?') ? '&' : '?';
      final cacheBustedUrl = '$url${separator}_t=${DateTime.now().millisecondsSinceEpoch}';

      final response = await _dio.get<dynamic>(
        cacheBustedUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        dynamic decoded;
        if (response.data is String) {
          decoded = jsonDecode(response.data as String);
        } else {
          decoded = response.data;
        }

        if (decoded is Map<String, dynamic>) {
          final info = AppVersionInfo.fromJson(decoded);
          final hasUpdate = info.isUpdateAvailable(currentBuild);
          final isMandatory = info.isMandatory(currentBuild);

          debugPrint(
            'ℹ️ [UpdateService] Current: $currentVersion+$currentBuild | '
            'Latest: ${info.latestVersion}+${info.latestBuildNumber} | '
            'Update: $hasUpdate | Mandatory: $isMandatory',
          );

          return UpdateCheckResult(
            hasUpdate: hasUpdate,
            isMandatory: isMandatory,
            currentBuildNumber: currentBuild,
            currentVersionName: currentVersion,
            versionInfo: info,
          );
        }
      }

      return UpdateCheckResult(
        hasUpdate: false,
        isMandatory: false,
        currentBuildNumber: currentBuild,
        currentVersionName: currentVersion,
        errorMessage: 'Invalid response from update server',
      );
    } catch (e) {
      // Silent error: do not crash the app, log and continue smoothly
      debugPrint('ℹ️ [UpdateService] Silent update check error: $e');
      return UpdateCheckResult(
        hasUpdate: false,
        isMandatory: false,
        currentBuildNumber: currentBuild,
        currentVersionName: currentVersion,
        errorMessage: e.toString(),
      );
    }
  }

  /// Checks if the app has permission to install unknown apps on Android 8.0+.
  Future<bool> checkInstallPermission() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.requestInstallPackages.status;
    return status.isGranted;
  }

  /// Requests the "Install unknown apps" permission or prompts the user.
  Future<bool> requestInstallPermission() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.requestInstallPackages.request();
    return status.isGranted;
  }

  /// Opens the system settings screen for "Install unknown apps" if permission was permanently denied.
  Future<bool> openInstallSettings() async {
    return await openAppSettings();
  }

  /// Downloads the APK from [apkUrl] with real-time progress callbacks.
  ///
  /// Returns the downloaded APK [File], or throws on failure.
  Future<File> downloadApk({
    required String apkUrl,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    _downloadCancelToken?.cancel('New download initiated');
    _downloadCancelToken = CancelToken();

    final tempDir = await getTemporaryDirectory();
    final savePath = '${tempDir.path}/infinitywash_update.apk';

    // Delete existing file if any to start with a clean slate
    final targetFile = File(savePath);
    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (e) {
        debugPrint('⚠️ [UpdateService] Could not delete old update file: $e');
      }
    }

    await _dio.download(
      apkUrl,
      savePath,
      cancelToken: _downloadCancelToken,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final progress = received / total;
          onProgress(progress.clamp(0.0, 1.0), received, total);
        } else {
          // Total size unknown, indeterminate
          onProgress(-1.0, received, total);
        }
      },
    );

    return targetFile;
  }

  /// Cancels an ongoing APK download.
  void cancelDownload() {
    _downloadCancelToken?.cancel('User cancelled download');
    _downloadCancelToken = null;
  }

  /// Opens the downloaded APK in the Android system package installer.
  Future<OpenResult> installApk(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return OpenResult(
        type: ResultType.fileNotFound,
        message: 'APK file not found at $filePath',
      );
    }

    return await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
  }
}

