package com.lxmusic.lx_music_flutter

import android.media.audiofx.Visualizer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Timer
import java.util.TimerTask

class VisualizerHelper(private val activity: android.app.Activity) {
    private var visualizer: Visualizer? = null
    private var timer: Timer? = null
    private var currentSessionId = -1
    private var listener: MethodChannel? = null

    // 原生诊断（无需 adb）
    private var nativeFrameCount = 0
    private var lastGetFftResult = -1
    private var lastNativeError = ""
    private var visEnabled = false
    private var getFftErrorCount = 0

    fun setListener(channel: MethodChannel) {
        listener = channel
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCapture" -> {
                val sessionId = call.argument<Int>("sessionId") ?: 0
                val ok = startCapture(sessionId)
                // 把真实结果传回 Dart：失败时 Dart 端不应显示 cap=OK
                result.success(mapOf(
                    "ok" to ok,
                    "error" to lastNativeError,
                ))
            }
            "stopCapture" -> {
                stopCapture()
                result.success(null)
            }
            "getNativeStatus" -> {
                val vis = visualizer
                val status = mapOf(
                    "visCreated" to (vis != null),
                    "visEnabled" to visEnabled,
                    "session" to currentSessionId,
                    "frameCount" to nativeFrameCount,
                    "lastFftResult" to lastGetFftResult,
                    "fftErrorCount" to getFftErrorCount,
                    "lastError" to lastNativeError,
                    "timerActive" to (timer != null),
                    "captureSize" to (vis?.captureSize ?: 0),
                )
                result.success(status)
            }
            else -> result.notImplemented()
        }
    }

    private fun startCapture(sessionId: Int): Boolean {
        stopCapture()
        nativeFrameCount = 0
        lastGetFftResult = -1
        lastNativeError = ""
        visEnabled = false
        try {
            val vis = Visualizer(sessionId)
            val captureSize = Visualizer.getCaptureSizeRange()
            val desiredSize = 256
            vis.captureSize = desiredSize.coerceIn(captureSize[0], captureSize[1])

            // 预分配复用缓冲，避免每帧分配（60fps 下 GC 压力明显）
            fftBytes = ByteArray(desiredSize.coerceIn(captureSize[0], captureSize[1]))
            magnitudes = DoubleArray(fftBytes.size / 2)

            vis.enabled = true
            visEnabled = vis.enabled
            currentSessionId = sessionId
            visualizer = vis
            lastNativeError = "created ok"

            // ~30fps 足够频谱可视化（Dart 端有平滑），降低主线程消息频率避免卡顿
            timer = Timer()
            timer?.scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    if (vis.enabled) {
                        sendFftData(vis)
                    }
                }
            }, 0, 32)

            return true
        } catch (e: Exception) {
            // 例如：全局混音(sessionId=0) 在多数系统上需要 RECORD_AUDIO 运行时权限
            lastNativeError = "FAILED: ${e.message}"
            android.util.Log.e("LXVisualizer", "startCapture FAILED: ${e.message}", e)
            visualizer = null
            return false
        }
    }

    private var fftBytes = ByteArray(0)
    private var magnitudes = DoubleArray(0)

    private fun sendFftData(vis: Visualizer) {
        try {
            val captureSize = vis.captureSize
            if (fftBytes.size < captureSize) return
            val result = vis.getFft(fftBytes)
            lastGetFftResult = result
            if (result != Visualizer.SUCCESS) {
                // 连续失败时记录，便于诊断（-7 = 会话死亡等）
                getFftErrorCount++
                if (getFftErrorCount % 100 == 1) {
                    lastNativeError = "getFft err=$result x$getFftErrorCount"
                }
                return
            }
            getFftErrorCount = 0

            // Android 文档：FFT 数组为 captureSize 字节，
            // 前 captureSize/2 个是实部 (Rf0..Rf(n/2-1))，后一半是虚部 (If0..If(n/2-1))
            val halfSize = captureSize / 2
            for (i in 0 until halfSize) {
                val re = fftBytes[i].toDouble() / 128.0
                val im = fftBytes[i + halfSize].toDouble() / 128.0
                magnitudes[i] = Math.sqrt(re * re + im * im).coerceIn(0.0, 1.0)
            }

            nativeFrameCount++
            val channel = listener ?: return
            // DoubleArray 由标准编解码器编码为 Float64List（无装箱、零拷贝字节传输），
            // 相比 List<Double> 每帧少 128 个装箱对象 + 明显更轻的序列化
            val frame = magnitudes.copyOf(halfSize)
            activity.runOnUiThread {
                try {
                    channel.invokeMethod("onFftData", mapOf(
                        "frequencies" to frame
                    ))
                } catch (e: Exception) {
                    lastNativeError = "invokeErr: ${e.message}"
                }
            }
        } catch (e: Exception) {
            lastNativeError = "fftErr: ${e.message}"
        }
    }

    private fun stopCapture() {
        timer?.cancel()
        timer = null
        visEnabled = false
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {}
        visualizer = null
        currentSessionId = -1
    }
}
