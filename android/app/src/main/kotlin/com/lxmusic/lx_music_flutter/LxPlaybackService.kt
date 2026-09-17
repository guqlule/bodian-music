package com.lxmusic.lx_music_flutter

import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import androidx.media.MediaBrowserServiceCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat

/**
 * 自建前台媒体播放服务�? * 替代 audio_service �?AudioService：自己管�?MediaSession、通知、媒体按键、Becoming Noisy�? */
class LxPlaybackService : MediaBrowserServiceCompat() {

    companion object {
        @Volatile var instance: LxPlaybackService? = null
    }

    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var notificationBuilder: LxNotificationBuilder
    private lateinit var becomingNoisyReceiver: LxBecomingNoisyReceiver
    private lateinit var mediaButtonReceiver: LxMediaButtonReceiver

    private var currentTitle: String = ""
    private var currentArtist: String = ""
    private var currentAlbum: String = ""
    private var currentIsPlaying: Boolean = false
    private var currentArtwork: Bitmap? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationBuilder = LxNotificationBuilder(this)
        notificationBuilder.ensureChannel()

        mediaSession = MediaSessionCompat(this, "LxPlaybackService").apply {
            setCallback(LxMediaSessionCallback())
            isActive = true
        }
        sessionToken = mediaSession.sessionToken
        LxMediaBridge.attachSession(mediaSession)

        becomingNoisyReceiver = LxBecomingNoisyReceiver()
        val noisyFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.content.Context.RECEIVER_NOT_EXPORTED
        } else {
            0
        }
        registerReceiver(
            becomingNoisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            noisyFlag
        )

        mediaButtonReceiver = LxMediaButtonReceiver()
        val filter = IntentFilter(Intent.ACTION_MEDIA_BUTTON).apply {
            priority = 1000
        }
        // Android 13+ (Tiramisu/SDK 33) 要求 registerReceiver 必须显式声明
        // RECEIVER_EXPORTED 或 RECEIVER_NOT_EXPORTED。MEDIA_BUTTON 来自系统，
        // 用 NOT_EXPORTED 即可。
        val receiverFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.content.Context.RECEIVER_NOT_EXPORTED
        } else {
            0
        }
        registerReceiver(mediaButtonReceiver, filter, receiverFlag)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        androidx.media.session.MediaButtonReceiver.handleIntent(mediaSession, intent)
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        try { unregisterReceiver(becomingNoisyReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(mediaButtonReceiver) } catch (_: Exception) {}
        mediaSession.isActive = false
        mediaSession.release()
        LxMediaBridge.attachSession(null)
        super.onDestroy()
    }

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?
    ): MediaBrowserServiceCompat.BrowserRoot? {
        return MediaBrowserServiceCompat.BrowserRoot("media_root", null)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<MutableList<android.support.v4.media.MediaBrowserCompat.MediaItem>>
    ) {
        result.sendResult(mutableListOf())
    }

    /** �?LxMediaBridge �?setMetadata/setPlaybackState/setLyric 后回调�?*/
    fun onMetadataOrStateChanged() {
        val meta = mediaSession.controller.metadata
        val state = mediaSession.controller.playbackState
        currentTitle = meta?.getString(MediaMetadataCompat.METADATA_KEY_TITLE) ?: ""
        currentArtist = meta?.getString(MediaMetadataCompat.METADATA_KEY_ARTIST) ?: ""
        currentAlbum = meta?.getString(MediaMetadataCompat.METADATA_KEY_ALBUM) ?: ""
        currentArtwork = meta?.getBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART)
        currentIsPlaying = state?.state == PlaybackStateCompat.STATE_PLAYING
        rebuildNotification()
    }

    private fun rebuildNotification() {
        val n = notificationBuilder.build(
            title = currentTitle,
            artist = currentArtist,
            album = currentAlbum,
            isPlaying = currentIsPlaying,
            artwork = currentArtwork,
            sessionToken = mediaSession.sessionToken
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                LxNotificationBuilder.NOTIFICATION_ID,
                n,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(LxNotificationBuilder.NOTIFICATION_ID, n)
        }
    }
}
