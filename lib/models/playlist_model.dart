import 'package:hive/hive.dart';
import 'music_model.dart';

@HiveType(typeId: 1)
class PlaylistInfo extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  final DateTime createTime;

  @HiveField(3)
  DateTime updateTime;

  @HiveField(4)
  List<MusicInfo> songs;

  @HiveField(5)
  String? coverUrl;

  @HiveField(6)
  String? description;

  PlaylistInfo({
    required this.id,
    required this.name,
    required this.createTime,
    required this.updateTime,
    List<MusicInfo>? songs,
    this.coverUrl,
    this.description,
  }) : songs = songs ?? [];

  int get songCount => songs.length;

  int get totalDuration => songs.fold(0, (sum, song) => sum + song.duration);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createTime': createTime.toIso8601String(),
      'updateTime': updateTime.toIso8601String(),
      'songs': songs.map((s) => s.toJson()).toList(),
      'coverUrl': coverUrl,
      'description': description,
    };
  }

  factory PlaylistInfo.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic v) {
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return PlaylistInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '未命名歌单',
      createTime: parseTime(json['createTime']),
      updateTime: parseTime(json['updateTime']),
      // Hive 反序列化后元素是 Map<dynamic, dynamic>，必须转换为
      // Map<String, dynamic> 才能传给 MusicInfo.fromJson（否则运行时抛类型错误）
      songs: (json['songs'] as List?)
          ?.map((s) => MusicInfo.fromJson(
              s is Map ? Map<String, dynamic>.from(s) : <String, dynamic>{}))
          .toList(),
      coverUrl: json['coverUrl'],
      description: json['description'],
    );
  }

  void addSong(MusicInfo song) {
    if (!songs.any((s) => s.id == song.id)) {
      songs.add(song);
      updateTime = DateTime.now();
      save();
    }
  }

  void removeSong(String songId) {
    songs.removeWhere((s) => s.id == songId);
    updateTime = DateTime.now();
    save();
  }

  void reorderSong(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex--;
    }
    final song = songs.removeAt(oldIndex);
    songs.insert(newIndex, song);
    updateTime = DateTime.now();
    save();
  }
}
