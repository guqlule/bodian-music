package com.lxmusic.lx_music_flutter

import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 直接更新原生 MediaSession metadata。
 *
 * - 启动时一次性反射拿到 audio_service 内部的 MediaSessionCompat 引用
 * - 缓存 session 引用
 * - 之后每次推歌词只调公开 API setMetadata，不再每次 getActiveSessions / getMethod
 *
 * 车机蓝牙从 MediaSession metadata 读取歌词显示。
 */
class MediaSessionHelper {

    @Volatile private var cachedSession: MediaSessionCompat? = null

    /** 通过反射一次性拿到 audio_service.AudioService.instance.mediaSession */
    private fun resolveSession(): MediaSessionCompat? = runCatching {
        val cls = Class.forName("com.ryanheise.audioservice.AudioService")
        val instance = cls.getField("instance").get(null) as? android.app.Service
            ?: return@runCatching null
        cls.getField("mediaSession").get(instance) as? MediaSessionCompat
    }.getOrNull()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "updateLyric") {
            result.notImplemented()
            return
        }
        val session = cachedSession ?: resolveSession().also { cachedSession = it }
        if (session == null) {
            result.success(false)
            return
        }
        try {
            val title = call.argument<String>("title") ?: ""
            val artist = call.argument<String>("artist") ?: ""
            val album = call.argument<String>("album") ?: ""
            val lyric = call.argument<String>("lyric") ?: ""
            val durationMs = call.argument<Number>("durationMs")?.toLong()

            // 在现有 metadata 基础上合并更新：
            // - 保留 audio_service 设置的 duration / art / mediaId
            // - 只更新 DISPLAY_TITLE / DISPLAY_DESCRIPTION 为歌词
            // - mediaId 保持不变，避免车机认为"快速切歌"而忽略歌词更新
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
            session.setMetadata(meta)
            result.success(true)
        } catch (e: Exception) {
            result.error("MEDIA_ERROR", e.message, null)
        }
    }
}