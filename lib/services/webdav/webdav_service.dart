import 'dart:convert';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../../core/utils/logger.dart';

/// WebDAV 连接配置
class WebdavConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;
  final bool useHttps;

  const WebdavConfig({
    required this.host,
    this.port = 5005,
    this.username = '',
    this.password = '',
    this.remotePath = '/music',
    this.useHttps = false,
  });

  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  WebdavConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? remotePath,
    bool? useHttps,
  }) {
    return WebdavConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
      useHttps: useHttps ?? this.useHttps,
    );
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'remotePath': remotePath,
    'useHttps': useHttps,
  };

  factory WebdavConfig.fromJson(Map<String, dynamic> json) {
    return WebdavConfig(
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 5005,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '/music',
      useHttps: json['useHttps'] as bool? ?? false,
    );
  }
}

/// WebDAV 连接管理
class WebdavService {
  static final WebdavService _instance = WebdavService._internal();
  factory WebdavService() => _instance;
  WebdavService._internal();

  WebdavConfig? _config;
  webdav.Client? _client;

  WebdavConfig? get config => _config;
  bool get isConnected => _client != null;

  /// 构建 WebDAV 客户端
  webdav.Client _buildClient(WebdavConfig config) {
    final client = webdav.newClient(config.baseUrl);
    if (config.username.isNotEmpty) {
      final credentials = base64Encode(utf8.encode('${config.username}:${config.password}'));
      client.setHeaders({'Authorization': 'Basic $credentials'});
    }
    client.setConnectTimeout(10000);
    client.setReceiveTimeout(30000);
    return client;
  }

  /// 测试连接
  Future<bool> testConnection(WebdavConfig config) async {
    try {
      final client = _buildClient(config);
      await client.readDir(config.remotePath);
      logDebug('[WebDAV] 连接成功: ${config.baseUrl}${config.remotePath}');
      return true;
    } catch (e) {
      logDebug('[WebDAV] 连接失败: $e');
      return false;
    }
  }

  /// 保存配置并连接
  Future<void> connect(WebdavConfig config) async {
    _config = config;
    _client = _buildClient(config);
    logDebug('[WebDAV] 已连接: ${config.baseUrl}${config.remotePath}');
  }

  /// 断开连接
  void disconnect() {
    _client = null;
    logDebug('[WebDAV] 已断开');
  }

  /// 读取远程目录
  Future<List<webdav.File>> readDir(String path) async {
    if (_client == null) throw Exception('WebDAV 未连接');
    try {
      return await _client!.readDir(path);
    } catch (e) {
      logDebug('[WebDAV] 读取目录失败: $path, $e');
      rethrow;
    }
  }

  /// 获取文件的 HTTP 下载/流式 URL
  /// webdav_client 本身不暴露直接 URL，需要手动拼接
  String buildFileUrl(String filePath) {
    if (_config == null) throw Exception('WebDAV 未连接');
    final scheme = _config!.useHttps ? 'https' : 'http';
    final path = filePath.startsWith('/') ? filePath : '/${_config!.remotePath}/$filePath';
    return '$scheme://${_config!.host}:${_config!.port}$path';
  }

  /// 获取文件内容（用于小文件，如歌词）
  Future<List<int>> readFile(String filePath) async {
    if (_client == null) throw Exception('WebDAV 未连接');
    return await _client!.read(filePath);
  }
}
