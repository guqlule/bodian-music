package com.lxmusic.lx_music_flutter

import android.content.ComponentName
import android.media.session.MediaSessionManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 原生 MediaSession 直接更新通道。
 * 绕过 audio_service 的 mediaItem.add()，直接更新 MediaSession metadata，
 * 避免通知重建导致的崩溃（对齐原版 lx-music-mobile 方案）。
 */
class MediaSessionHelper(private val activity: FlutterActivity) {

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateLyric" -> {
                try {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val lyric = call.argument<String>("lyric") ?: ""

                    val msm = activity.getSystemService(FlutterActivity.MEDIA_SESSION_SERVICE) as? MediaSessionManager
                    val cn = ComponentName(activity, "com.ryanheise.audioservice.AudioService")
                    val sessions = msm?.getActiveSessions(cn)
                    if (sessions != null && sessions.isNotEmpty()) {
                        val session = sessions[0]
                        try {
                            val setMeta = session.javaClass.getMethod("setMetadata", android.media.MediaMetadata::class.java)
                            val metaBuilder = android.media.MediaMetadata.Builder()
                            metaBuilder.putString(android.media.MediaMetadata.METADATA_KEY_TITLE, title)
                            metaBuilder.putString(android.media.MediaMetadata.METADATA_KEY_ARTIST, artist)
                            metaBuilder.putString(android.media.MediaMetadata.METADATA_KEY_ALBUM, album)
                            metaBuilder.putString("android.media.metadata.DISPLAY_TITLE", title)
                            metaBuilder.putString("android.media.metadata.DISPLAY_SUBTITLE", artist)
                            metaBuilder.putString("android.media.metadata.DISPLAY_DESCRIPTION", album)
                            setMeta.invoke(session, metaBuilder.build())
                        } catch (_: Exception) {}

                        // 通过 extras 传递歌词（部分车机从 extras 读取）
                        try {
                            val extras = android.os.Bundle().apply {
                                putString("lyric", lyric)
                                putString("android.intent.extra.TEXT", lyric)
                            }
                            val setExtras = session.javaClass.getMethod("setMetadata", android.media.MediaMetadata::class.java)
                            // extras 需要通过 setExtras 方法设置
                            val setExtrasMethod = session.javaClass.getMethod("setExtras", android.os.Bundle::class.java)
                            setExtrasMethod.invoke(session, extras)
                        } catch (_: Exception) {}

                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (e: Exception) {
                    result.error("MEDIA_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
