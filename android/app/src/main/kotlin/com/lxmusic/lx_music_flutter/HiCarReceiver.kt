package com.lxmusic.lx_music_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * HiCar 生命周期广播接收器
 * 接收车机连接/断开事件，通知 Flutter 层切换车载模式
 */
class HiCarReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "HiCarReceiver"
        const val ACTION_HICAR_STARTED = "com.huawei.hicar.ACTION_HICAR_STARTED"
        const val ACTION_HICAR_STOPPED = "com.huawei.hicar.ACTION_HICAR_STOPPED"

        // 静态标志：Flutter 层可读取
        @JvmStatic
        var isHiCarConnected = false
            private set

        // 回调：Flutter 层可注册监听
        @JvmStatic
        var onHiCarStateChanged: ((Boolean) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_HICAR_STARTED -> {
                isHiCarConnected = true
                Log.i(TAG, "HiCar 车机已连接")
                onHiCarStateChanged?.invoke(true)
                // 启动 MainActivity 并通知 HiCar 已连接
                launchWithHiCarStatus(context, true)
            }
            ACTION_HICAR_STOPPED -> {
                isHiCarConnected = false
                Log.i(TAG, "HiCar 车机已断开")
                onHiCarStateChanged?.invoke(false)
                launchWithHiCarStatus(context, false)
            }
        }
    }

    private fun launchWithHiCarStatus(context: Context, connected: Boolean) {
        try {
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?: return
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            launchIntent.putExtra("hicar_connected", connected)
            context.startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e(TAG, "启动 MainActivity 失败: ${e.message}")
        }
    }
}
