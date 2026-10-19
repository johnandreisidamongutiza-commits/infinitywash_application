import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Local image handling shared by laundry request and payment receipt flows.
class PhotoFileService {
  static const int maxBytes = 10 * 1024 * 1024;
  static const int targetBytes = 5 * 1024 * 1024;

  /// Compresses a picked or captured image into app-private temporary storage.
  /// The original gallery file is never changed.
  static Future<File> prepareForUpload(File source) async {
    final temporary = await getTemporaryDirectory();
    final outputPath =
        '${temporary.path}${Platform.pathSeparator}infinitywash_${DateTime.now().microsecondsSinceEpoch}.jpg';
    var quality = 88;
    var dimension = 1920;
    File? result;

    while (quality >= 38) {
      try {
        final previous = File(outputPath);
        if (await previous.exists()) await previous.delete();
      } catch (_) {}
      final compressed = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        outputPath,
        quality: quality,
        minWidth: dimension,
        minHeight: dimension,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (compressed == null) break;
      result = File(compressed.path);
      if (await result.length() <= targetBytes) return result;
      quality -= 10;
      if (quality < 48 && dimension > 1280) {
        dimension = 1280;
        quality = 75;
      }
    }

    if (result == null || !await result.exists()) {
      throw const PhotoTooLargeException(
        'This photo could not be prepared. Please choose another image.',
      );
    }
    if (await result.length() > maxBytes) {
      await result.delete();
      throw const PhotoTooLargeException(
        'This photo is larger than 10 MB after compression. Please choose a smaller photo.',
      );
    }
    return result;
  }

  static Future<void> deleteTemporary(File file) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final path = file.absolute.path;
      if (path.startsWith(tempDir.absolute.path) && await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Temporary-file cleanup is best effort; the OS also clears cache files.
    }
  }
}

class PhotoTooLargeException implements Exception {
  final String message;
  const PhotoTooLargeException(this.message);

  @override
  String toString() => message;
}
