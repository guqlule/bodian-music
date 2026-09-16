package com.lxmusic.lx_music_flutter

import android.content.ComponentName
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Method

class MediaSessionHelper(private val activity: FlutterActivity) {

    private var cachedController: MediaController? = null
    private var cachedSetMetaMethod: Method? = null
    private var cachedSetExtrasMethod: Method? = null

    private fun getController(): MediaController? {
        val msm = activity.getSystemService(FlutterActivity.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            ?: return null
        val cn = ComponentName(activity, "com.ryanheise.audioservice.AudioService")
        val controllers = msm.getActiveSessions(cn)
        if (controllers.isNullOrEmpty()) {
            cachedController = null
            cachedSetMetaMethod = null
            cachedSetExtrasMethod = null
            return null
        }
        val ctrl = controllers[0]
        if (ctrl !== cachedController) {
            cachedController = ctrl
            cachedSetMetaMethod = null
            cachedSetExtrasMethod = null
        }
        return ctrl
    }

    private fun getSetMetaMethod(ctrl: MediaController): Method? {
        cachedSetMetaMethod?.let { return it }
        return try {
            ctrl.javaClass.getMethod("setMetadata", android.media.MediaMetadata::class.java)
                .also { cachedSetMetaMethod = it }
        } catch (_: Exception) { null }
    }

    private fun getSetExtrasMethod(ctrl: MediaController): Method? {
        cachedSetExtrasMethod?.let { return it }
        return try {
            ctrl.javaClass.getMethod("setExtras", Bundle::class.java)
                .also { cachedSetExtrasMethod = it }
        } catch (_: Exception) { null }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateLyric" -> {
                try {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val lyric = call.argument<String>("lyric") ?: ""

                    val ctrl = getController()
                    if (ctrl == null) {
                        result.success(false)
                        return
                    }

                    // 1. 更新 metadata
                    getSetMetaMethod(ctrl)?.let { method ->
                        val meta = android.media.MediaMetadata.Builder()
                            .putString(android.media.MediaMetadata.METADATA_KEY_TITLE, title)
                            .putString(android.media.MediaMetadata.METADATA_KEY_ARTIST, artist)
                            .putString(android.media.MediaMetadata.METADATA_KEY_ALBUM, album)
                            .putString("android.media.metadata.DISPLAY_TITLE", title)
                            .putString("android.media.metadata.DISPLAY_SUBTITLE", artist)
                            .putString("android.media.metadata.DISPLAY_DESCRIPTION", album)
                            .build()
                        method.invoke(ctrl, meta)
                    }

                    // 2. 更新 extras（歌词）
                    getSetExtrasMethod(ctrl)?.let { method ->
                        val extras = Bundle().apply {
                            putString("lyric", lyric)
                            putString("android.intent.extra.TEXT", lyric)
                        }
                        method.invoke(ctrl, extras)
                    }

                    result.success(true)
                } catch (e: Exception) {
                    result.error("MEDIA_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
