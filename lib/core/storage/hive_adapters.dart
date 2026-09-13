import 'package:hive/hive.dart';
import '../../models/music_model.dart';
import '../../models/playlist_model.dart';

class HiveAdapters {
  static void registerAdapters() {
    Hive.registerAdapter(MusicInfoAdapter());
    Hive.registerAdapter(PlaylistInfoAdapter());
  }
}

class MusicInfoAdapter extends TypeAdapter<MusicInfo> {
  @override
  final int typeId = 0;

  @override
  MusicInfo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return MusicInfo(
      id: fields[0] as String,
      name: fields[1] as String,
      singer: fields[2] as String,
      album: fields[3] as String,
      duration: fields[4] as int,
      source: fields[5] as String?,
      sourceId: fields[6] as String?,
      imgUrl: fields[7] as String?,
      songUrl: fields[8] as String?,
      lyric: fields[9] as String?,
      tlyric: fields[10] as String?,
      rlyric: fields[11] as String?,
      addTime: fields[12] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, MusicInfo obj) {
    writer.writeByte(13);
    writer.writeByte(0);
    writer.write(obj.id);
    writer.writeByte(1);
    writer.write(obj.name);
    writer.writeByte(2);
    writer.write(obj.singer);
    writer.writeByte(3);
    writer.write(obj.album);
    writer.writeByte(4);
    writer.write(obj.duration);
    writer.writeByte(5);
    writer.write(obj.source);
    writer.writeByte(6);
    writer.write(obj.sourceId);
    writer.writeByte(7);
    writer.write(obj.imgUrl);
    writer.writeByte(8);
    writer.write(obj.songUrl);
    writer.writeByte(9);
    writer.write(obj.lyric);
    writer.writeByte(10);
    writer.write(obj.tlyric);
    writer.writeByte(11);
    writer.write(obj.rlyric);
    writer.writeByte(12);
    writer.write(obj.addTime);
  }
}

class PlaylistInfoAdapter extends TypeAdapter<PlaylistInfo> {
  @override
  final int typeId = 1;

  @override
  PlaylistInfo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return PlaylistInfo(
      id: fields[0] as String,
      name: fields[1] as String,
      createTime: fields[2] as DateTime,
      updateTime: fields[3] as DateTime,
      songs: (fields[4] as List?)?.cast<MusicInfo>(),
      coverUrl: fields[5] as String?,
      description: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PlaylistInfo obj) {
    writer.writeByte(7);
    writer.writeByte(0);
    writer.write(obj.id);
    writer.writeByte(1);
    writer.write(obj.name);
    writer.writeByte(2);
    writer.write(obj.createTime);
    writer.writeByte(3);
    writer.write(obj.updateTime);
    writer.writeByte(4);
    writer.write(obj.songs);
    writer.writeByte(5);
    writer.write(obj.coverUrl);
    writer.writeByte(6);
    writer.write(obj.description);
  }
}
