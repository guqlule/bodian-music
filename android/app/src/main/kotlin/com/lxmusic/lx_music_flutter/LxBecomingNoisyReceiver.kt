package com.lxmusic.lx_music_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager

/**
 * 耳机拔出/蓝牙断开时自动暂停�? * 通知 Dart 触发 just_audio.pause()�? */
class LxBecomingNoisyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
            LxMediaBridge.emitEvent("becomingNoisy")
        }
    }
}
