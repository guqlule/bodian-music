import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart' as fp;
import '../../core/utils/logger.dart';
import 'dart:io';

class FilePickerService {
  static const MethodChannel _channel = MethodChannel('com.lxmusic/file_picker');

  static Future<String?> pickFile({required String extension}) async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('pickFile', {
          'extension': extension,
        });
        return result;
      } on PlatformException catch (e) {
        logDebug('Error picking file (native): $e');
      }
    }
    // 跨平台兜底：使用 file_picker 包
    try {
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: [extension],
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files.first.path;
      }
    } catch (e) {
      logDebug('Error picking file (package): $e');
    }
    return null;
  }

  static Future<String?> pickDirectory() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('pickDirectory');
        return result;
      } on PlatformException catch (e) {
        logDebug('Error picking directory (native): $e');
      }
    }
    // 跨平台兜底：使用 file_picker 包
    try {
      final result = await fp.FilePicker.platform.getDirectoryPath();
      return result;
    } catch (e) {
      logDebug('Error picking directory (package): $e');
    }
    return null;
  }
}
