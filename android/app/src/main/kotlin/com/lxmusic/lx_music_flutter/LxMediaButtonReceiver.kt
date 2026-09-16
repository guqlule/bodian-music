package com.lxmusic.lx_music_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.support.v4.media.session.PlaybackStateCompat
import android.view.KeyEvent

/**
 * 接收耳机线控、车机方向盘按键的 media button 事件，
 * 转发给 MediaSession（由 Callback 进一步转给 Dart）。
 */
class LxMediaButtonReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MEDIA_BUTTON) return
        val event = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return
        if (event.action != KeyEvent.ACTION_DOWN) return

        val session = LxMediaBridge.currentSession() ?: return
        val controller = session.controller

        when (event.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY -> controller.transportControls.play()
            KeyEvent.KEYCODE_MEDIA_PAUSE -> controller.transportControls.pause()
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                if (controller.playbackState?.state == PlaybackStateCompat.STATE_PLAYING) {
                    controller.transportControls.pause()
                } else {
                    controller.transportControls.play()
                }
            }
            KeyEvent.KEYCODE_MEDIA_NEXT -> controller.transportControls.skipToNext()
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> controller.transportControls.skipToPrevious()
            KeyEvent.KEYCODE_MEDIA_STOP -> controller.transportControls.stop()
        }
    }
}