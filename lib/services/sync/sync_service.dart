import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/playlist_model.dart';
import 'dart:typed_data';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  String? _serverUrl;
  String? _syncCode;
  String? _clientId;

  final _connectionStateController = StreamController<SyncConnectionState>.broadcast();
  final _syncProgressController = StreamController<SyncProgress>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _remoteListsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _remoteHistoryController = StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<SyncConnectionState> get connectionStateStream => _connectionStateController.stream;
  Stream<SyncProgress> get syncProgressStream => _syncProgressController.stream;
  Stream<String> get errorStream => _errorController.stream;
  /// 服务器下发的远端歌单列表（用于双向拉取，客户端合并进本地）
  Stream<List<Map<String, dynamic>>> get remoteListsStream => _remoteListsController.stream;
  /// 服务器下发的远端播放历史（MusicInfo JSON 列表）
  Stream<List<Map<String, dynamic>>> get remoteHistoryStream => _remoteHistoryController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect({
    required String host,
    required String syncCode,
  }) async {
    _serverUrl = host;
    _syncCode = syncCode;
    _clientId = _generateClientId();

    try {
      final encryptedCode = _encryptSyncCode(syncCode);
      final url = 'ws://$host/socket?i=$_clientId&t=$encryptedCode';
      
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: _onError,
      );

      _startHeartbeat();
      _isConnected = true;
      _connectionStateController.add(SyncConnectionState.connected);
      // 连接成功自动拉取一次远端歌单（双向同步的拉取半边）
      unawaited(requestListPull());
    } catch (e) {
      _connectionStateController.add(SyncConnectionState.error);
      _errorController.add('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _connectionStateController.add(SyncConnectionState.disconnected);
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      _handleMessage(data);
    } catch (e) {
      _errorController.add('Failed to parse message: $e');
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'];
    
    switch (type) {
      case 'ping':
        _sendPong();
        break;
      case 'sync_progress':
        _syncProgressController.add(SyncProgress(
          type: data['syncType'] ?? '',
          progress: data['progress'] ?? 0,
          total: data['total'] ?? 0,
        ));
        break;
      case 'sync_complete':
        _syncProgressController.add(SyncProgress(
          type: data['syncType'] ?? '',
          progress: 100,
          total: 100,
          isComplete: true,
        ));
        break;
      case 'error':
        _errorController.add(data['message'] ?? 'Unknown error');
        break;
      case 'pull_lists_result':
        // 服务器下发远端歌单：data 是 PlaylistInfo JSON 列表
        final raw = data['data'];
        if (raw is List) {
          final lists = raw
              .whereType<Map<String, dynamic>>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
          _remoteListsController.add(lists);
        }
        break;
      case 'pull_history_result':
        // 服务器下发远端播放历史：data 是 MusicInfo JSON 列表
        final rawH = data['data'];
        if (rawH is List) {
          final history = rawH
              .whereType<Map<String, dynamic>>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
          _remoteHistoryController.add(history);
        }
        break;
    }
  }

  void _onDisconnected() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _connectionStateController.add(SyncConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _onError(dynamic error) {
    _errorController.add('WebSocket error: $error');
    _connectionStateController.add(SyncConnectionState.error);
  }

  void _sendPong() {
    _channel?.sink.add(jsonEncode({'type': 'pong'}));
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected && _serverUrl != null && _syncCode != null) {
        connect(host: _serverUrl!, syncCode: _syncCode!);
      }
    });
  }

  String _generateClientId() {
    return 'flutter_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _encryptSyncCode(String code) {
    final bytes = Uint8List.fromList(utf8.encode(code));
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  Future<void> syncLists(List<PlaylistInfo> localLists) async {
    if (!_isConnected) {
      throw Exception('Not connected to sync server');
    }

    try {
      final listsData = localLists.map((list) => list.toJson()).toList();
      _channel?.sink.add(jsonEncode({
        'type': 'list_sync_start',
        'data': listsData,
      }));
    } catch (e) {
      _errorController.add('Sync failed: $e');
    }
  }

  Future<void> syncDislikeList(Set<String> dislikeList) async {
    if (!_isConnected) {
      throw Exception('Not connected to sync server');
    }

    try {
      _channel?.sink.add(jsonEncode({
        'type': 'dislike_sync_start',
        'data': dislikeList.toList(),
      }));
    } catch (e) {
      _errorController.add('Dislike sync failed: $e');
    }
  }

  /// 推送本地播放历史到服务器（List<MusicInfo> 的 JSON 数组）
  Future<void> syncHistory(List<dynamic> history) async {
    if (!_isConnected) return;
    try {
      final data = history
          .map((m) => Map<String, dynamic>.from(m.toJson() as Map<String, dynamic>))
          .toList();
      _channel?.sink.add(jsonEncode({
        'type': 'history_sync_start',
        'data': data,
      }));
    } catch (e) {
      _errorController.add('History sync failed: $e');
    }
  }

  /// 向服务器请求下发当前歌单（拉取半边）。服务器回 `pull_lists_result`。
  Future<void> requestListPull() async {
    if (!_isConnected) return;
    try {
      _channel?.sink.add(jsonEncode({
        'type': 'pull_lists_request',
        'clientId': _clientId,
      }));
      _channel?.sink.add(jsonEncode({
        'type': 'pull_history_request',
        'clientId': _clientId,
      }));
    } catch (e) {
      _errorController.add('Pull request failed: $e');
    }
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _syncProgressController.close();
    _errorController.close();
    _remoteListsController.close();
    _remoteHistoryController.close();
  }
}

enum SyncConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class SyncProgress {
  final String type;
  final int progress;
  final int total;
  final bool isComplete;

  SyncProgress({
    required this.type,
    required this.progress,
    required this.total,
    this.isComplete = false,
  });

  double get percentage => total > 0 ? progress / total * 100 : 0;
}
