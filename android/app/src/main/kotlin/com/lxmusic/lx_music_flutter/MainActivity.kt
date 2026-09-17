package com.lxmusic.lx_music_flutter

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.audiofx.Equalizer
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {
    private val FILE_CHANNEL = "com.lxmusic/file_picker"
    private val EQ_CHANNEL = "com.lxmusic/equalizer"
    private val MEDIA_CHANNEL = "com.lxmusic/media_session"
    private val VIS_CHANNEL = "com.lxmusic/visualizer"
    private val META_CHANNEL = "com.lxmusic/metadata"
    private var filePickerResult: MethodChannel.Result? = null

    private var equalizer: Equalizer? = null
    private var eqEnabled = false
    private var eqSessionId = -1
    private lateinit var mediaSessionHelper: MediaSessionHelper
    private lateinit var visualizerHelper: VisualizerHelper

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaSessionHelper = MediaSessionHelper()
        visualizerHelper = VisualizerHelper(this)

        val visChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIS_CHANNEL)
        visChannel.setMethodCallHandler { call, result ->
            visualizerHelper.handle(call, result)
        }
        visualizerHelper.setListener(visChannel)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL).setMethodCallHandler { call, result ->
            handleFileMethodCall(call, result)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EQ_CHANNEL).setMethodCallHandler { call, result ->
            handleEqMethodCall(call, result)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            mediaSessionHelper.handle(call, result)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, META_CHANNEL).setMethodCallHandler { call, result ->
            handleMetadataCall(call, result)
        }
    }

    private fun handleEqMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "getBands" -> {
                try {
                    val eq = equalizer
                    if (eq == null) {
                        result.success(null)
                        return true
                    }
                    val params = mutableMapOf<String, Any>()
                    params["enabled"] = eqEnabled
                    params["bandCount"] = eq.numberOfBands.toInt()

                    val bands = mutableListOf<Map<String, Any>>()
                    for (i in 0 until eq.numberOfBands) {
                        val bandLevelRange = eq.bandLevelRange
                        bands.add(mapOf(
                            "index" to i,
                            "centerFreq" to eq.getCenterFreq(i.toShort()),
                            "minLevel" to bandLevelRange[0],
                            "maxLevel" to bandLevelRange[1],
                            "currentLevel" to eq.getBandLevel(i.toShort()),
                        ))
                    }
                    params["bands"] = bands
                    result.success(params)
                } catch (e: Exception) {
                    result.error("EQ_ERROR", e.message, null)
                }
                true
            }
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                eqEnabled = enabled
                try {
                    equalizer?.enabled = enabled
                } catch (_: Exception) {}
                result.success(null)
                true
            }
            "setBandLevel" -> {
                val index = call.argument<Int>("index") ?: 0
                val level = call.argument<Int>("level") ?: 0
                try {
                    equalizer?.setBandLevel(index.toShort(), level.toShort())
                } catch (_: Exception) {}
                result.success(null)
                true
            }
            "attachSession" -> {
                val sessionId = call.argument<Int>("sessionId") ?: 0
                attachEqualizer(sessionId)
                result.success(null)
                true
            }
            "release" -> {
                releaseEqualizer()
                result.success(null)
                true
            }
            else -> false
        }
    }

    private fun attachEqualizer(audioSessionId: Int) {
        if (audioSessionId == eqSessionId && equalizer != null) return
        releaseEqualizer()
        try {
            eqSessionId = audioSessionId
            equalizer = Equalizer(0, audioSessionId).apply {
                enabled = eqEnabled
            }
        } catch (e: Exception) {
            equalizer = null
            eqSessionId = -1
        }
    }

    private fun releaseEqualizer() {
        try {
            equalizer?.release()
        } catch (_: Exception) {}
        equalizer = null
        eqSessionId = -1
    }

    private fun handleFileMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "pickFile" -> {
                val extension = call.argument<String>("extension")
                pickFile(extension, result)
                true
            }
            "pickDirectory" -> {
                pickDirectory(result)
                true
            }
            "setKeepScreenOn" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                runOnUiThread {
                    if (enabled) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }
                result.success(null)
                true
            }
            "isCarUiMode" -> {
                // 检测是否运行在车机环境（Android Auto/HiCar/车载UI模式）
                val uiMode = resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_TYPE_MASK
                val isAndroidCar = uiMode == android.content.res.Configuration.UI_MODE_TYPE_CAR
                val isHiCar = HiCarReceiver.isHiCarConnected
                result.success(isAndroidCar || isHiCar)
                true
            }
            "isHiCarConnected" -> {
                result.success(HiCarReceiver.isHiCarConnected)
                true
            }
            else -> false
        }
    }

    private fun pickFile(extension: String?, result: MethodChannel.Result) {
        filePickerResult = result
        
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            
            if (!extension.isNullOrEmpty()) {
                val mimeTypes = getMimeTypes(extension)
                if (mimeTypes != null && mimeTypes.isNotEmpty()) {
                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                }
            }
        }
        
        startActivityForResult(intent, 1001)
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        filePickerResult = result
        
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        startActivityForResult(intent, 1002)
    }

    private fun getMimeTypes(extension: String): Array<String>? {
        return when (extension.lowercase()) {
            "js" -> arrayOf("application/javascript", "text/javascript", "text/plain")
            "json" -> arrayOf("application/json", "text/plain")
            "txt" -> arrayOf("text/plain")
            else -> arrayOf("*/*")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val result = filePickerResult ?: return

        if (resultCode == Activity.RESULT_OK && data != null) {
            val uri = data.data
            if (uri != null) {
                when (requestCode) {
                    1001 -> {
                        try {
                            val content = readUriContent(uri)
                            result.success(content)
                        } catch (e: Exception) {
                            result.error("READ_ERROR", "Failed to read file: ${e.message}", null)
                        }
                    }
                    1002 -> {
                        try {
                            val path = uri.path
                            result.success(path)
                        } catch (e: Exception) {
                            result.error("PATH_ERROR", "Failed to get path: ${e.message}", null)
                        }
                    }
                }
            } else {
                result.error("NO_URI", "No URI returned", null)
            }
        } else {
            result.success(null)
        }
        
        filePickerResult = null
    }

    private fun readUriContent(uri: Uri): String {
        val inputStream = contentResolver.openInputStream(uri)
        val reader = BufferedReader(InputStreamReader(inputStream))
        val stringBuilder = StringBuilder()
        var line: String?
        
        while (reader.readLine().also { line = it } != null) {
            stringBuilder.append(line).append("\n")
        }
        
        reader.close()
        inputStream?.close()
        
        return stringBuilder.toString()
    }

    private fun handleMetadataCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extractMetadata" -> {
                val filePath = call.argument<String>("filePath") ?: ""
                extractMetadata(filePath, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun extractMetadata(filePath: String, result: MethodChannel.Result) {
        try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(filePath)

            val metadata = mutableMapOf<String, Any?>()
            metadata["title"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            metadata["artist"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
            metadata["album"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            metadata["duration"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()

            // 提取封面图并保存到缓存
            val artBytes = retriever.embeddedPicture
            if (artBytes != null) {
                try {
                    val cacheDir = File(cacheDir, "album_art")
                    cacheDir.mkdirs()
                    val artFile = File(cacheDir, "${filePath.hashCode()}.jpg")
                    if (!artFile.exists()) {
                        FileOutputStream(artFile).use { it.write(artBytes) }
                    }
                    metadata["artPath"] = artFile.absolutePath
                } catch (_: Exception) {
                    metadata["artPath"] = null
                }
            } else {
                metadata["artPath"] = null
            }

            retriever.release()
            result.success(metadata)
        } catch (e: Exception) {
            result.success(null)
        }
    }
}
