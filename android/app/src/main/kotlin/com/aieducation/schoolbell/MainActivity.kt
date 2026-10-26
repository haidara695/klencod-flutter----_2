package com.aieducation.schoolbell

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.aieducation.schoolbell/native"
    private var pendingPickerResult: MethodChannel.Result? = null
    private val openAudio = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        val result = pendingPickerResult
        pendingPickerResult = null
        if (uri == null) {
            result?.success(null)
            return@registerForActivityResult
        }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            // Some document providers do not offer persistable grants; playback still works until access changes.
        }
        val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: uri.lastPathSegment ?: "صوت مختار"
        result?.success(mapOf("uri" to uri.toString(), "name" to name))
    }

    override fun onResume() {
        super.onResume()
        BellScheduler.rescheduleSaved(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "selectAudio" -> {
                    if (pendingPickerResult != null) {
                        result.error("picker_busy", "منتقي الملفات مفتوح بالفعل", null)
                    } else {
                        pendingPickerResult = result
                        openAudio.launch(arrayOf("audio/*"))
                    }
                }
                "previewAudio" -> {
                    val uri = call.argument<String>("uri")?.takeIf { it.isNotBlank() }
                    val intent = Intent(this, BellPlaybackService::class.java).apply {
                        action = BellPlaybackService.ACTION_PREVIEW
                        putExtra(BellPlaybackService.EXTRA_URI, uri)
                        putExtra(BellPlaybackService.EXTRA_TITLE, "معاينة صوت الجرس")
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(null)
                }
                "stopAudio" -> {
                    startService(Intent(this, BellPlaybackService::class.java).setAction(BellPlaybackService.ACTION_STOP))
                    result.success(null)
                }
                "syncSchedules" -> {
                    val lessons = call.argument<List<Map<String, Any>>>("lessons") ?: emptyList()
                    val startSound = call.argument<String>("startSoundUri") ?: ""
                    val endSound = call.argument<String>("endSoundUri") ?: ""
                    val ringSeconds = call.argument<Int>("ringSeconds") ?: 12
                    BellScheduler.replaceSchedules(applicationContext, lessons, startSound, endSound, ringSeconds)
                    result.success(null)
                }
                "requestAlarmAccess" -> {
                    BellScheduler.requestAlarmAccess(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
