package com.lxmusic.lx_music_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle

/**
 * 构建前台服务通知（媒体样式）。
 * 完全对齐 audio_service 的实现方式。
 */
class LxNotificationBuilder(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "com.salt.music.playback"
        const val CHANNEL_NAME = "音乐播放"
        const val NOTIFICATION_ID = 1001
    }

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                mgr.createNotificationChannel(ch)
            }
        }
    }

    fun build(
        title: String,
        artist: String,
        album: String,
        isPlaying: Boolean,
        artwork: Bitmap?,
        sessionToken: MediaSessionCompat.Token,
    ): android.app.Notification {
        ensureChannel()

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentPi = launchIntent?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val prevPi = mediaButtonPi(KeyEvent.KEYCODE_MEDIA_PREVIOUS, 1)
        val playPausePi = mediaButtonPi(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 2)
        val nextPi = mediaButtonPi(KeyEvent.KEYCODE_MEDIA_NEXT, 3)
        val stopPi = mediaButtonPi(KeyEvent.KEYCODE_MEDIA_STOP, 4)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(album)
            .setContentIntent(contentPi)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(isPlaying)
            .setDeleteIntent(stopPi)
            .addAction(NotificationCompat.Action(
                android.R.drawable.ic_media_previous, "上一首", prevPi
            ))
            .addAction(
                if (isPlaying) NotificationCompat.Action(
                    android.R.drawable.ic_media_pause, "暂停", playPausePi
                ) else NotificationCompat.Action(
                    android.R.drawable.ic_media_play, "播放", playPausePi
                )
            )
            .addAction(NotificationCompat.Action(
                android.R.drawable.ic_media_next, "下一首", nextPi
            ))

        val style = MediaStyle()
            .setMediaSession(sessionToken)
            .setShowActionsInCompactView(0, 1, 2)
            .setShowCancelButton(true)
            .setCancelButtonIntent(stopPi)
        builder.setStyle(style)

        if (artwork != null) {
            builder.setLargeIcon(artwork)
        }

        return builder.build()
    }

    private fun mediaButtonPi(keyCode: Int, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setPackage(context.packageName)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}