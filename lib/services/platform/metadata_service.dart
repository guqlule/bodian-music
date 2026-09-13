import 'package:flutter/services.dart';

/// 从本地音频文件提取元数据（标题/歌手/专辑/时长/封面）
class MetadataService {
  static final MetadataService _instance = MetadataService._internal();
  factory MetadataService() => _instance;
  MetadataService._internal();

  static const _channel = MethodChannel('com.lxmusic/metadata');

  /// 提取元数据，返回 null 表示失败
  Future<Map<String, dynamic>?> extractMetadata(String filePath) async {
    try {
      final result = await _channel.invokeMethod<Map>('extractMetadata', {
        'filePath': filePath,
      });
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return null;
    }
  }
}
