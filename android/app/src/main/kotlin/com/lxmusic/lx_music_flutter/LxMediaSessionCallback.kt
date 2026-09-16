package com.lxmusic.lx_music_flutter

import android.os.Bundle
import android.support.v4.media.session.MediaSessionCompat

/**
 * �?transportControls 命令从蓝�?通知/Android Auto 转回 Dart�? * �?Dart 侧的 just_audio 实际执行播放�? */
class LxMediaSessionCallback : MediaSessionCompat.Callback() {

    override fun onPlay() {
        LxMediaBridge.emitEvent("play")
    }

    override fun onPause() {
        LxMediaBridge.emitEvent("pause")
    }

    override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
        LxMediaBridge.emitEvent("playFromMediaId", mapOf("mediaId" to mediaId))
    }

    override fun onSkipToNext() {
        LxMediaBridge.emitEvent("skipToNext")
    }

    override fun onSkipToPrevious() {
        LxMediaBridge.emitEvent("skipToPrevious")
    }

    override fun onSkipToQueueItem(id: Long) {
        LxMediaBridge.emitEvent("skipToQueueItem", mapOf("id" to id))
    }

    override fun onSeekTo(pos: Long) {
        LxMediaBridge.emitEvent("seekTo", mapOf("position" to pos))
    }

    override fun onStop() {
        LxMediaBridge.emitEvent("stop")
    }

    override fun onSetRepeatMode(repeatMode: Int) {
        LxMediaBridge.emitEvent("setRepeatMode", mapOf("repeatMode" to repeatMode))
    }

    override fun onSetShuffleMode(shuffleMode: Int) {
        LxMediaBridge.emitEvent("setShuffleMode", mapOf("shuffleMode" to shuffleMode))
    }
}
