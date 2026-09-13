import 'dart:convert';
import 'dart:io';
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

/// WebDAV 连接错误类型
enum WebdavErrorType {
  network,     // 网络不可达
  auth,        // 认证失败
  path,        // 路径不存在
  timeout,     // 超时
  server,      // 服务器错误
  unknown,     // 未知错误
}

/// WebDAV 连接错误
class WebdavException implements Exception {
  final String message;
  final WebdavErrorType type;
  final dynamic originalError;

  WebdavException(this.message, {this.type = WebdavErrorType.unknown, this.originalError});

  @override
  String toString() => message;

  /// 根据异常判断错误类型
  static WebdavException fromError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused') || msg.contains('No route to host')) {
      return WebdavException('网络不可达，请检查地址和端口', type: WebdavErrorType.network, originalError: e);
    }
    if (msg.contains('Connection reset') || msg.contains('Connection closed')) {
      return WebdavException('连接被重置，服务器可能不支持该协议', type: WebdavErrorType.network, originalError: e);
    }
    if (msg.contains('401') || msg.contains('403') || msg.contains('Unauthorized')) {
      return WebdavException('用户名或密码错误', type: WebdavErrorType.auth, originalError: e);
    }
    if (msg.contains('404') || msg.contains('Not Found')) {
      return WebdavException('路径不存在，请检查远程路径', type: WebdavErrorType.path, originalError: e);
    }
    if (msg.contains('Timeout') || msg.contains('timeout')) {
      return WebdavException('连接超时，请检查网络', type: WebdavErrorType.timeout, originalError: e);
    }
    if (msg.contains('SSL') || msg.contains('TLS') || msg.contains('certificate')) {
      return WebdavException('SSL证书错误，请检查HTTPS设置', type: WebdavErrorType.server, originalError: e);
    }
    return WebdavException('连接失败: $msg', type: WebdavErrorType.unknown, originalError: e);
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

  /// 标准化路径（去掉末尾多余的斜杠，保留开头的斜杠）
  String _normalizePath(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) p = '/$p';
    while (p.endsWith('/') && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// 构建 WebDAV 客户端
  webdav.Client _buildClient(WebdavConfig config) {
    final client = webdav.newClient(config.baseUrl);
    if (config.username.isNotEmpty) {
      final credentials = base64Encode(utf8.encode('${config.username}:${config.password}'));
      client.setHeaders({'Authorization': 'Basic $credentials'});
    }
    client.setConnectTimeout(15000);
    client.setReceiveTimeout(30000);
    return client;
  }

  /// 测试连接，返回详细结果
  Future<({bool ok, String? error, int? fileCount})> testConnectionDetailed(WebdavConfig config) async {
    try {
      final client = _buildClient(config);
      final path = _normalizePath(config.remotePath);
      final entries = await client.readDir(path);
      final audioCount = entries.where((e) {
        if (e.isDir == true) return false;
        final name = e.name ?? '';
        final ext = name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
        return const {'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'ape', 'wma', 'opus', 'alac'}.contains(ext);
      }).length;
      logDebug('[WebDAV] 连接成功: ${config.baseUrl}$path, $audioCount 首音频');
      return (ok: true, error: null, fileCount: audioCount);
    } catch (e) {
      logDebug('[WebDAV] 连接失败: $e');
      final ex = WebdavException.fromError(e);
      return (ok: false, error: ex.message, fileCount: null);
    }
  }

  /// 测试连接（简单版，兼容旧调用）
  Future<bool> testConnection(WebdavConfig config) async {
    final result = await testConnectionDetailed(config);
    return result.ok;
  }

  /// 保存配置并连接
  Future<void> connect(WebdavConfig config) async {
    _config = config;
    _client = _buildClient(config);
    logDebug('[WebDAV] 已连接: ${config.baseUrl}${_normalizePath(config.remotePath)}');
  }

  /// 断开连接
  void disconnect() {
    _client = null;
    _config = null;
    logDebug('[WebDAV] 已断开');
  }

  /// 读取远程目录
  Future<List<webdav.File>> readDir(String path) async {
    if (_client == null) throw WebdavException('WebDAV 未连接');
    try {
      return await _client!.readDir(_normalizePath(path));
    } catch (e) {
      logDebug('[WebDAV] 读取目录失败: $path, $e');
      throw WebdavException.fromError(e);
    }
  }

  /// 获取文件的 HTTP 流式 URL
  String buildFileUrl(String filePath) {
    if (_config == null) throw WebdavException('WebDAV 未连接');
    final scheme = _config!.useHttps ? 'https' : 'http';
    // 如果 filePath 是完整 URL，直接返回
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) return filePath;
    final path = filePath.startsWith('/') ? filePath : '/${_normalizePath(_config!.remotePath)}$filePath';
    return '$scheme://${_config!.host}:${_config!.port}$path';
  }

  /// 获取文件内容（用于小文件，如歌词）
  Future<List<int>> readFile(String filePath) async {
    if (_client == null) throw WebdavException('WebDAV 未连接');
    try {
      return await _client!.read(filePath);
    } catch (e) {
      throw WebdavException.fromError(e);
    }
  }
}
