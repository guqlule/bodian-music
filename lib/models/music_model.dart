import 'package:hive/hive.dart';

@HiveType(typeId: 0)
class MusicInfo extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String singer;

  @HiveField(3)
  final String album;

  @HiveField(4)
  final int duration;

  @HiveField(5)
  final String? source;

  @HiveField(6)
  final String? sourceId;

  @HiveField(7)
  final String? imgUrl;

  @HiveField(8)
  final String? songUrl;

  @HiveField(9)
  final String? lyric;

  @HiveField(10)
  final String? tlyric;

  @HiveField(11)
  final String? rlyric;

  @HiveField(12)
  final DateTime? addTime;

  @HiveField(13)
  final String? songId;

  @HiveField(14)
  final String? songmid;

  @HiveField(15)
  final String? strMediaMid;

  @HiveField(16)
  final String? copyrightId;

  @HiveField(17)
  final String? hash;

  @HiveField(18)
  final List<QualityType>? types;

  MusicInfo({
    required this.id,
    required this.name,
    required this.singer,
    required this.album,
    required this.duration,
    this.source,
    this.sourceId,
    this.imgUrl,
    this.songUrl,
    this.lyric,
    this.tlyric,
    this.rlyric,
    this.addTime,
    this.songId,
    this.songmid,
    this.strMediaMid,
    this.copyrightId,
    this.hash,
    this.types,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'singer': singer,
      'album': album,
      'duration': duration,
      'source': source,
      'sourceId': sourceId,
      'imgUrl': imgUrl,
      'songUrl': songUrl,
      'lyric': lyric,
      'tlyric': tlyric,
      'rlyric': rlyric,
      'addTime': addTime?.toIso8601String(),
      'songId': songId,
      'songmid': songmid,
      'strMediaMid': strMediaMid,
      'copyrightId': copyrightId,
      'hash': hash,
      'types': types?.map((t) => t.toJson()).toList(),
    };
  }

  factory MusicInfo.fromJson(Map<String, dynamic> json) {
    // duration 可能被 JSON 解码为 double（导入数据等场景）
    final rawDuration = json['duration'];
    final duration = rawDuration is int
        ? rawDuration
        : (rawDuration is num ? rawDuration.toInt() : 0);
    // addTime 容错解析
    final rawAddTime = json['addTime'];
    final addTime = rawAddTime is String && rawAddTime.isNotEmpty
        ? DateTime.tryParse(rawAddTime)
        : null;
    // types 元素可能是 Map<dynamic, dynamic>（Hive 反序列化）
    final rawTypes = json['types'];

    return MusicInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      singer: json['singer'] ?? '',
      album: json['album'] ?? '',
      duration: duration,
      source: json['source'],
      sourceId: json['sourceId'],
      imgUrl: json['imgUrl'],
      songUrl: json['songUrl'],
      lyric: json['lyric'],
      tlyric: json['tlyric'],
      rlyric: json['rlyric'],
      addTime: addTime,
      songId: json['songId'],
      songmid: json['songmid'],
      strMediaMid: json['strMediaMid'],
      copyrightId: json['copyrightId'],
      hash: json['hash'],
      types: rawTypes is List
          ? rawTypes
              .map((t) => QualityType.fromJson(
                  t is Map ? Map<String, dynamic>.from(t) : <String, dynamic>{}))
              .toList()
          : null,
    );
  }

  MusicInfo copyWith({
    String? id,
    String? name,
    String? singer,
    String? album,
    int? duration,
    String? source,
    String? sourceId,
    String? imgUrl,
    String? songUrl,
    String? lyric,
    String? tlyric,
    String? rlyric,
    DateTime? addTime,
    String? songId,
    String? songmid,
    String? strMediaMid,
    String? copyrightId,
    String? hash,
    List<QualityType>? types,
  }) {
    return MusicInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      singer: singer ?? this.singer,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      imgUrl: imgUrl ?? this.imgUrl,
      songUrl: songUrl ?? this.songUrl,
      lyric: lyric ?? this.lyric,
      tlyric: tlyric ?? this.tlyric,
      rlyric: rlyric ?? this.rlyric,
      addTime: addTime ?? this.addTime,
      songId: songId ?? this.songId,
      songmid: songmid ?? this.songmid,
      strMediaMid: strMediaMid ?? this.strMediaMid,
      copyrightId: copyrightId ?? this.copyrightId,
      hash: hash ?? this.hash,
      types: types ?? this.types,
    );
  }
}

class QualityType {
  final String type;
  final String size;
  final String? hash;

  QualityType({
    required this.type,
    required this.size,
    this.hash,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'size': size,
      'hash': hash,
    };
  }

  factory QualityType.fromJson(Map<String, dynamic> json) {
    return QualityType(
      type: json['type'] ?? '',
      size: json['size'] ?? '',
      hash: json['hash'],
    );
  }
}
