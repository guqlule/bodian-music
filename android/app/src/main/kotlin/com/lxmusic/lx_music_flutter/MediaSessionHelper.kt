package com.lxmusic.lx_music_flutter

import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 直接更新原生 MediaSession metadata。
 *
 * 优化策略：
 * - 启动时一次性反射拿到 audio_service 内部的 MediaSessionCompat 引用
 * - 缓存 session 引用 + setMetadata Method 句柄
 * - 之后每次推歌词只做 method.invoke（缓存的方法句柄），
 *   **不再每次 getActiveSessions / getMethod**
 *
 * 车机蓝牙从 MediaSession metadata 读取歌词显示。
 */
class MediaSessionHelper(private val activity: FlutterActivity) {

    private var cachedSession: MediaSessionCompat? = null

    private fun resolveSession(): MediaSessionCompat? {
        try {
            val audioServiceCls = Class.forName("com.ryanheise.audioservice.AudioService")
            val instance: Any? = audioServiceCls.getDeclaredField("instance").apply {
                isAccessible = true
            }.get(null)
            val session = (instance as? android.app.Service)?.let { svc ->
                audioServiceCls.getDeclaredField("mediaSession").apply {
                    isAccessible = true
                }.get(svc) as? MediaSessionCompat
            }
            return session
        } catch (e: Exception) {
            return null
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "updateLyric") {
            result.notImplemented()
            return
        }
        try {
            val title = call.argument<String>("title") ?: ""
            val artist = call.argument<String>("artist") ?: ""
            val album = call.argument<String>("album") ?: ""
            val lyric = call.argument<String>("lyric") ?: ""

            val meta = MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, lyric)
                .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, title)
                .build()

            val session = cachedSession ?: resolveSession().also { cachedSession = it }
            if (session != null) {
                session.setMetadata(meta)
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.error("MEDIA_ERROR", e.message, null)
        }
    }
}