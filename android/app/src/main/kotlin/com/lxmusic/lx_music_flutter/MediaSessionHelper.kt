package com.lxmusic.lx_music_flutter

import android.content.ComponentName
import android.media.session.MediaSessionManager
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Method

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

    @Volatile private var cachedSession: MediaSessionCompat? = null
    @Volatile private var cachedSetMetadata: Method? = null
    @Volatile private var cachedGetController: Method? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * 反射一次性拿到 audio_service.AudioService.instance 里的 mediaSession 字段。
     * 由于 audio_service 把媒体会话藏在私有字段里，外部访问只能走反射。
     */
    private fun tryGetAudioServiceSession(): MediaSessionCompat? {
        try {
            val audioServiceCls = Class.forName("com.ryanheise.audioservice.AudioService")
            val instanceField = audioServiceCls.getDeclaredField("instance")
            instanceField.isAccessible = true
            val instance = instanceField.get(null) ?: return null
            if (instance !is android.app.Service) return null

            val sessionField = audioServiceCls.getDeclaredField("mediaSession")
            sessionField.isAccessible = true
            val session = sessionField.get(instance) as? MediaSessionCompat ?: return null

            // 缓存 setMetadata / getController 方法句柄
            cachedSetMetadata = session.javaClass.getMethod(
                "setMetadata", MediaMetadataCompat::class.java
            )
            cachedGetController = session.javaClass.getMethod("getController")
            return session
        } catch (e: Exception) {
            return null
        }
    }

    /**
     * 兜底：通过 MediaSessionManager.getActiveSessions() 拿 MediaController，
     * 然后用反射 setMetadata（兼容没有 audio_service 的情况，比如未来完全迁移走）
     */
    private fun getController(): android.media.session.MediaController? {
        return try {
            val msm = activity.getSystemService(FlutterActivity.MEDIA_SESSION_SERVICE) as? MediaSessionManager
                ?: return null
            val cn = ComponentName(activity, "com.ryanheise.audioservice.AudioService")
            val sessions = msm.getActiveSessions(cn)
            if (sessions.isNullOrEmpty()) null else sessions[0]
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

                    val meta = MediaMetadataCompat.Builder()
                        .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                        .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                        .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
                        .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
                        .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, artist)
                        .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, lyric)
                        .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, title)
                        .build()

                    var success = false

                    // 路径 1：audio_service 的 MediaSession（公开 API）
                    if (cachedSession == null) {
                        cachedSession = tryGetAudioServiceSession()
                    }
                    val session = cachedSession
                    if (session != null) {
                        try {
                            cachedSetMetadata?.invoke(session, meta)
                            success = true
                        } catch (e: Exception) {
                            cachedSession = null
                            cachedSetMetadata = null
                        }
                    }

                    // 路径 2（兜底）：MediaSessionManager 拿 MediaController + 反射
                    if (!success) {
                        val ctrl = getController()
                        if (ctrl != null) {
                            try {
                                val setMeta = ctrl.javaClass.getMethod(
                                    "setMetadata", MediaMetadataCompat::class.java
                                )
                                setMeta.invoke(ctrl, meta)
                                success = true
                            } catch (_: Exception) {}
                        }
                    }

                    result.success(success)
                } catch (e: Exception) {
                    result.error("MEDIA_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}