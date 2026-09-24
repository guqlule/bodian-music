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
class MediaSessionHelper {

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

            // 在现�?metadata 基础上合并更新：
            // - 保留 audio_service 设置�?duration / art / mediaId
            // - 只更�?DISPLAY_TITLE / DISPLAY_DESCRIPTION 为歌�?
            // - mediaId 保持不变，避免车机认�?快速切�?而忽略歌词更�?
            val existing = session.controller?.metadata
            val builder = if (existing != null) {
                MediaMetadataCompat.Builder(existing)
            } else {
                MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            }

            builder
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, lyric)

            // 部分国产车机（尤其是支持"蓝牙歌词"的车机）读取自定�?LYRICS 字段显示歌词�?
            // 使用标准 key "android.media.metadata.LYRICS"，该 key �?MediaMetadataCompat �?
            // 未定义常量但底层 Bundle 支持任意字符�?key�?
            if (lyric.isNotEmpty()) {
                builder.putString("android.media.metadata.LYRICS", lyric)
            }

            // 只在 durationMs 提供且有效时更新，否则保�?existing �?duration
            if (durationMs != null && durationMs > 0) {
                builder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            } else if (existing != null) {
                val existingDuration = existing.getLong(MediaMetadataCompat.METADATA_KEY_DURATION)
                if (existingDuration > 0) {
                    builder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, existingDuration)
                }
            }

            val meta = builder.build()

            // 先写 extras 再写 metadata�?
            // Jovi InCar 可能�?onMetadataChanged 回调里读�?getExtras()�?
            // 如果�?setMetadata �?setExtras，Jovi 读到的还是旧 extras�?
            val extras = android.os.Bundle().apply {
                putString("lyric", lyric)
                putString("lyrics", lyric)
                putString("android.media.metadata.LYRICS", lyric)
                putString("displayDescription", lyric)
            }
            session.setExtras(extras)

            session.setMetadata(meta)

            result.success(true)
        } catch (e: Exception) {
            result.error("MEDIA_ERROR", e.message, null)
        }
    }
}