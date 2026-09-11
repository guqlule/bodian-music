import 'package:flutter/services.dart';
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
        logDebug('Error picking file: $e');
        return null;
      }
    }
    return null;
  }

  static Future<String?> pickDirectory() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('pickDirectory');
        return result;
      } on PlatformException catch (e) {
        logDebug('Error picking directory: $e');
        return null;
      }
    }
    return null;
  }
}
