/// Data model representing the remote version.json file.
class AppVersionInfo {
  final String latestVersion;
  final int latestBuildNumber;
  final int minSupportedBuildNumber;
  final String apkUrl;
  final List<String> releaseNotes;
  final bool forceUpdate;

  const AppVersionInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.minSupportedBuildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });

  /// Safely parse from json with type fallbacks so malformed remote fields never crash the app.
  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    // Parse build numbers with int/string fallback
    final latestBuild = _parseInt(json['latestBuildNumber']) ?? 0;
    final minSupported = _parseInt(json['minSupportedBuildNumber']) ?? 0;

    // Parse release notes: can be List<dynamic>, List<String>, or a multiline String
    final rawNotes = json['releaseNotes'];
    List<String> parsedNotes = [];
    if (rawNotes is List) {
      parsedNotes = rawNotes.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    } else if (rawNotes is String && rawNotes.trim().isNotEmpty) {
      parsedNotes = rawNotes
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return AppVersionInfo(
      latestVersion: json['latestVersion']?.toString() ?? '',
      latestBuildNumber: latestBuild,
      minSupportedBuildNumber: minSupported,
      apkUrl: json['apkUrl']?.toString() ?? '',
      releaseNotes: parsedNotes,
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latestVersion': latestVersion,
      'latestBuildNumber': latestBuildNumber,
      'minSupportedBuildNumber': minSupportedBuildNumber,
      'apkUrl': apkUrl,
      'releaseNotes': releaseNotes,
      'forceUpdate': forceUpdate,
    };
  }

  /// Determines if an update is available based on installed build number.
  bool isUpdateAvailable(int currentBuildNumber) {
    return latestBuildNumber > currentBuildNumber;
  }

  /// Determines if this update is mandatory/forced.
  /// Triggered if forceUpdate is true OR installed build is below minSupportedBuildNumber.
  bool isMandatory(int currentBuildNumber) {
    return forceUpdate || currentBuildNumber < minSupportedBuildNumber;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

