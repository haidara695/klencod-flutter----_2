package com.aieducation.schoolbell

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

class BellAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val lessonId = intent.getStringExtra("lesson_id") ?: return
        val kind = intent.getStringExtra("kind") ?: "start"
        val raw = context.getSharedPreferences("school_bell_native", Context.MODE_PRIVATE).getString("schedule_payload", "[]") ?: "[]"
        val schedules = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
        var lesson: JSONObject? = null
        for (i in 0 until schedules.length()) {
            val item = schedules.optJSONObject(i) ?: continue
            if (item.optString("id") == lessonId) { lesson = item; break }
        }
        val item = lesson ?: return
        if (!item.optBoolean("enabled", true)) return
        if (kind == "end" && !item.optBoolean("endBellEnabled", true)) return

        // Set the next weekly occurrence before starting playback; this keeps the timetable alive after delivery.
        BellScheduler.scheduleNext(context, item, kind)
        val isEnd = kind == "end"
        val uri = item.optString(if (isEnd) "endSound" else "startSound", "").takeIf { it.isNotBlank() }
        val label = item.optString("name", "جرس الحصة")
        val service = Intent(context, BellPlaybackService::class.java).apply {
            action = BellPlaybackService.ACTION_PLAY_ALARM
            putExtra(BellPlaybackService.EXTRA_URI, uri)
            putExtra(BellPlaybackService.EXTRA_TITLE, if (isEnd) "نهاية الحصة: $label" else "بداية الحصة: $label")
            putExtra(BellPlaybackService.EXTRA_DURATION, context.getSharedPreferences("school_bell_native", Context.MODE_PRIVATE).getInt("ring_seconds", 12))
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(service) else context.startService(service)
        } catch (_: Exception) {
            // The alarm remains scheduled; the notification/foreground-service permission may need user attention.
        }
    }
}
