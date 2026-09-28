package com.lxmusic.lx_music_flutter

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.media.session.MediaSessionManager
import android.util.Log

/**
 * 车机接入检测。
 *
 * 用于区分两种车机显示策略：
 * - 蓝牙 AVRCP 车机：只认 MediaMetadata 的 title 字段 → title 写歌词行
 * - Jovi InCar / HiCar 等投屏车机：主位是 title，歌词读 LYRICS 字段 → title 保持歌名
 *
 * 两者抢同一个 title 字段，必须先判断车机类型才能选对策略。
 *
 * 注意：不用 A2DP 连接状态做信号，蓝牙耳机也会触发，会误判成车机。
 */
object CarModeDetector {
    private const val TAG = "CarModeDetector"

    /** 车机端 App 包名特征 */
    private val CAR_APP_TOKENS = listOf(
        "incar", "jovi", "hicar", "carplay", "carlauncher",
        "com.android.car", "android.auto", "banco", "apollo"
    )

    @Volatile
    var lastResult: Boolean = false
        private set

    fun isCarConnected(context: Context?): Boolean {
        if (context == null) return lastResult

        // 1) HiCar 广播（华为车机）
        if (HiCarReceiver.isHiCarConnected) return true.also { lastResult = true }

        // 2) 系统车机 UI 模式（Android Auto / HiCar / 车载模式）
        try {
            val um = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            if (um?.currentModeType == Configuration.UI_MODE_TYPE_CAR) {
                return true.also { lastResult = true }
            }
        } catch (e: Throwable) {
            Log.d(TAG, "uiMode check failed: ${e.message}")
        }

        // 3) 车机端以 MediaController 身份连入（车机要显示歌名/歌词，必然连我们的 MediaSession）
        try {
            val msm = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            val sessions = msm?.getActiveSessions(null)
            if (sessions != null) {
                for (s in sessions) {
                    val pkg = s.packageName ?: continue
                    if (pkg == context.packageName) continue
                    val lower = pkg.lowercase()
                    if (CAR_APP_TOKENS.any { lower.contains(it) }) {
                        Log.i(TAG, "car controller connected: $pkg")
                        return true.also { lastResult = true }
                    }
                }
            }
        } catch (e: Throwable) {
            Log.d(TAG, "getActiveSessions failed: ${e.message}")
        }

        return false.also { lastResult = false }
    }
}
