package com.lxmusic.lx_music_flutter

import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 直接更新原生 MediaSession metadata�?
 *
 * - 启动时一次性反射拿�?audio_service 内部�?MediaSessionCompat 引用
 * - 缓存 session 引用
 * - 之后每次推歌词只调公开 API setMetadata，不再每�?getActiveSessions / getMethod
 *
 * 车机蓝牙�?MediaSession metadata 读取歌词显示�?
 */
class MediaSessionHelper(private val context: android.content.Context) {

    @Volatile private var cachedSession: MediaSessionCompat? = null

    /** 校验缓存�?session 是否仍有效（releaseMediaSession 会置 null�?*/
    private fun validSession(): MediaSessionCompat? {
        cachedSession?.let { s ->
            // session.release() �?controller �?null �?metadata 不可�?
            if (s.controller != null) return s
        }
        cachedSession = null
        return resolveSession()?.also { cachedSession = it }
    }

    /** 通过反射一次性拿�?audio_service.AudioService.instance.mediaSession */
    private fun resolveSession(): MediaSessionCompat? = runCatching {
        val cls = Class.forName("com.ryanheise.audioservice.AudioService")
        val instanceField = cls.getDeclaredField("instance")
        instanceField.isAccessible = true
        val instance = instanceField.get(null) as? android.app.Service
            ?: return@runCatching null
        val sessionField = cls.getDeclaredField("mediaSession")
        sessionField.isAccessible = true
        sessionField.get(instance) as? MediaSessionCompat
    }.getOrNull()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateLyric" -> handleUpdateLyric(call, result)
            "clearLyric" -> handleClearLyric(result)
            "setPlaybackStateLyric" -> handleSetPlaybackStateLyric(call, result)
            "isCarMode" -> {
                result.success(CarModeDetector.isCarConnected(context))
            }
            else -> result.notImplemented()
        }
    }

    /** 将歌词写�?PlaybackState extras（Jovi InCar 可能从这里读�?*/
    private fun handleSetPlaybackStateLyric(call: MethodCall, result: MethodChannel.Result) {
        val session = validSession()
        if (session == null) {
            result.success(false)
            return
        }
        try {
            val lyric = call.argument<String>("lyric") ?: ""
            val existing = session.controller?.playbackState
            if (existing != null) {
                val bundle = android.os.Bundle(existing.extras ?: android.os.Bundle()).apply {
                    putString("lyric", lyric)
                    putString("lyrics", lyric)
                    putString("android.media.metadata.LYRICS", lyric)
                }
                session.setPlaybackState(
                    android.support.v4.media.session.PlaybackStateCompat.Builder(existing)
                        .setExtras(bundle)
                        .build()
                )
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("MEDIA_ERROR", e.message, null)
        }
    }

    /** 切歌时清空歌�?extras，避免旧歌歌词残�?*/
    private fun handleClearLyric(result: MethodChannel.Result) {
        val session = validSession()
        if (session == null) {
            result.success(false)
            return
        }
        try {
            session.setExtras(android.os.Bundle().apply {
                putString("lyric", "")
                putString("lyrics", "")
                putString("android.media.metadata.LYRICS", "")
                putString("displayDescription", "")
            })
            result.success(true)
        } catch (e: Exception) {
            result.error("MEDIA_ERROR", e.message, null)
        }
    }

    private fun handleUpdateLyric(call: MethodCall, result: MethodChannel.Result) {
        val session = validSession()
        if (session == null) {
            android.util.Log.w("MediaSessionHelper", "resolveSession failed, cannot update lyric")
            result.success(false)
            return
        }
        try {
            val title = call.argument<String>("title") ?: ""
            val artist = call.argument<String>("artist") ?: ""
            val album = call.argument<String>("album") ?: ""
            val lyric = call.argument<String>("lyric") ?: ""
            val durationMs = call.argument<Number>("durationMs")?.toLong()
            val positionMs = call.argument<Number>("positionMs")?.toLong()

            // 在现有 metadata 基础上合并更新，保留 audio_service 设置的
            // mediaId / duration / 封面等字段（参考 MetadataManager 复用 prevMetadata）。
            val existing = session.controller?.metadata
            val builder = if (existing != null) {
                MediaMetadataCompat.Builder(existing)
            } else {
                MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, call.argument<String>("mediaId") ?: "")
            }

            builder
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, lyric)

            // 投屏车机（Jovi InCar / HiCar）的歌词字段各家命名不一，
            // 且无法在车上抓包定位，所以把所有常见 key 都写一遍。
            // key 必须始终存在（即使为空），否则车机可能因为读不到 key 而显示"暂无歌词"。
            builder.putString("android.media.metadata.LYRICS", lyric)
            builder.putString("LYRICS", lyric)
            builder.putString("lyric", lyric)
            builder.putString("lyrics", lyric)
            builder.putString("lyric_line", lyric)
            builder.putString("current_lyric", lyric)

            // 只在 durationMs 提供且有效时更新，否则保留 existing 的 duration
            if (durationMs != null && durationMs > 0) {
                builder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            } else if (existing != null) {
                val existingDuration = existing.getLong(MediaMetadataCompat.METADATA_KEY_DURATION)
                if (existingDuration > 0) {
                    builder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, existingDuration)
                }
            }

            val meta = builder.build()

            // 先写 extras 再写 metadata：
            // Jovi InCar 可能在 onMetadataChanged 回调里读 getExtras()，
            // 如果先 setMetadata 后 setExtras，Jovi 读到的还是旧 extras。
            val extras = android.os.Bundle().apply {
                putString("lyric", lyric)
                putString("lyrics", lyric)
                putString("lyric_line", lyric)
                putString("current_lyric", lyric)
                putString("LYRICS", lyric)
                putString("android.media.metadata.LYRICS", lyric)
                putString("displayDescription", lyric)
            }
            session.setExtras(extras)

            session.setMetadata(meta)

            // 保证 session 是 active，否则蓝牙栈不会把 metadata 变化推给车机
            if (!session.isActive) {
                session.setActive(true)
            }

            // 参考 MetadataManager.updateTitles()：setMetadata 之后在**同一次调用里**
            // 立即重推 PlaybackState。播放位置随时间推进，这次推送会触发车机重读 title。
            // 必须在同一个同步调用内完成，跨调用/延迟推送时序不可靠。
            if (positionMs != null) {
                val pb = session.controller?.playbackState
                val state = pb?.state ?: android.support.v4.media.session.PlaybackStateCompat.STATE_PLAYING
                val actions = pb?.actions ?: 0L
                val buffered = pb?.bufferedPosition ?: 0L
                val speed = pb?.playbackSpeed?.takeIf { it > 0f } ?: 1f
                session.setPlaybackState(
                    android.support.v4.media.session.PlaybackStateCompat.Builder()
                        .setActions(actions)
                        .setState(state, positionMs, speed, android.os.SystemClock.elapsedRealtime())
                        .setBufferedPosition(buffered)
                        .build()
                )
            }

            result.success(true)
        } catch (e: Exception) {
            result.error("MEDIA_ERROR", e.message, null)
        }
    }
}