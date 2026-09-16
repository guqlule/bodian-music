package com.lxmusic.lx_music_flutter

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaDescriptionCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 单例桥接器，连接 Flutter 与原�?MediaSession�? * 持有 MediaSessionCompat 引用 + MethodChannel + EventChannel�? * 替代 audio_service 的所�?Dart→native 通道�? */
object LxMediaBridge {

    @Volatile private var mediaSession: MediaSessionCompat? = null
    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attachSession(session: MediaSessionCompat?) {
        mediaSession = session
    }

    fun currentSession(): MediaSessionCompat? = mediaSession

    fun registerChannels(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, CHANNEL_METHODS).apply {
            setMethodCallHandler { call, result -> handleMethodCall(call, result) }
        }
        EventChannel(messenger, CHANNEL_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    /** 主动发送事件到 Dart（Dart 通过 EventChannel 接收）�?*/
    fun emitEvent(event: String, data: Map<String, Any?>? = null) {
        mainHandler.post {
            eventSink?.success(mapOf("event" to event, "data" to data))
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val session = mediaSession
        if (session == null) {
            result.error("NO_SESSION", "MediaSession not ready", null)
            return
        }
        try {
            when (call.method) {
                "setMetadata" -> { setMetadata(session, call); result.success(null) }
                "setPlaybackState" -> { setPlaybackState(session, call); result.success(null) }
                "setActive" -> {
                    session.isActive = call.argument<Boolean>("active") ?: true
                    result.success(null)
                }
                "setQueue" -> { setQueue(session, call); result.success(null) }
                "setLyric" -> { setLyric(session, call); result.success(null) }
                else -> result.notImplemented()
            }
            LxPlaybackService.instance?.onMetadataOrStateChanged()
        } catch (e: Exception) {
            result.error("LX_ERR", e.message, null)
        }
    }

    private fun setMetadata(session: MediaSessionCompat, call: MethodCall) {
        val title = call.argument<String>("title") ?: ""
        val artist = call.argument<String>("artist") ?: ""
        val album = call.argument<String>("album") ?: ""
        val duration = (call.argument<Number>("duration") ?: 0).toLong()
        val mediaId = call.argument<String>("mediaId") ?: ""
        val artUri = call.argument<String>("artUri")
        val lyric = call.argument<String>("lyric") ?: ""

        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, lyric)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)

        if (!artUri.isNullOrEmpty()) {
            builder.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, artUri)
            builder.putString(MediaMetadataCompat.METADATA_KEY_ART_URI, artUri)
        }

        session.setMetadata(builder.build())
    }

    private fun setPlaybackState(session: MediaSessionCompat, call: MethodCall) {
        val playing = call.argument<Boolean>("playing") ?: false
        val position = (call.argument<Number>("position") ?: 0).toLong()
        val bufferedPosition = (call.argument<Number>("bufferedPosition") ?: 0).toLong()
        val speed = (call.argument<Number>("speed") ?: 1.0).toDouble()

        val state = if (playing) PlaybackStateCompat.STATE_PLAYING
                     else PlaybackStateCompat.STATE_PAUSED

        val builder = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_STOP
            )
            .setState(state, position, speed.toFloat(), bufferedPosition.coerceAtLeast(position))

        session.setPlaybackState(builder.build())
    }

    private fun setQueue(session: MediaSessionCompat, call: MethodCall) {
        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
        val currentIndex = (call.argument<Number>("currentIndex") ?: 0).toInt()
        val queue = items.mapIndexed { i, m ->
            val desc = MediaDescriptionCompat.Builder()
                .setMediaId(m["id"] as? String ?: "")
                .setTitle(m["title"] as? String ?: "")
                .setSubtitle(m["artist"] as? String ?: "")
                .build()
            MediaSessionCompat.QueueItem(desc, i.toLong())
        }
        session.setQueue(queue)
        session.setQueueTitle("播放队列")
        // 通过 PlaybackState 设置当前队列项（MediaSessionCompat.setCurrentQueueIndex 在某些版本不可用）
        val state = session.controller.playbackState ?: PlaybackStateCompat.Builder().build()
        val newState = PlaybackStateCompat.Builder()
            .setActions(state.actions)
            .setState(state.state, state.position, state.playbackSpeed, state.lastPositionUpdateTime)
            .setActiveQueueItemId(currentIndex.toLong())
            .build()
        session.setPlaybackState(newState)
    }

    private fun setLyric(session: MediaSessionCompat, call: MethodCall) {
        val lyric = call.argument<String>("lyric") ?: ""
        val current = session.controller.metadata
        val mediaId = current?.getString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID) ?: ""
        val artist = current?.getString(MediaMetadataCompat.METADATA_KEY_ARTIST) ?: ""
        val album = current?.getString(MediaMetadataCompat.METADATA_KEY_ALBUM) ?: ""
        val duration = current?.getLong(MediaMetadataCompat.METADATA_KEY_DURATION) ?: 0L
        val artUri = current?.getString(MediaMetadataCompat.METADATA_KEY_ART_URI)

        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, lyric)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, lyric)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, lyric)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)

        if (!artUri.isNullOrEmpty()) {
            builder.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, artUri)
            builder.putString(MediaMetadataCompat.METADATA_KEY_ART_URI, artUri)
        }

        session.setMetadata(builder.build())
    }

    const val CHANNEL_METHODS = "com.lxmedia/playback_methods"
    const val CHANNEL_EVENTS = "com.lxmedia/playback_events"
}
