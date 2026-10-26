package com.aieducation.schoolbell

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

object BellScheduler {
    private const val PREFS = "school_bell_native"
    private const val KEY_PAYLOAD = "schedule_payload"

    fun replaceSchedules(context: Context, lessons: List<Map<String, Any>>, startSound: String, endSound: String, ringSeconds: Int) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = prefs.getString(KEY_PAYLOAD, "[]") ?: "[]"
        cancelPayload(context, previous)

        val array = JSONArray()
        lessons.forEach { lesson ->
            val obj = JSONObject()
            obj.put("id", lesson["id"]?.toString() ?: "")
            obj.put("name", lesson["name"]?.toString() ?: "جرس الحصة")
            obj.put("start", lesson["start"]?.toString() ?: "08:00")
            obj.put("end", lesson["end"]?.toString() ?: "08:45")
            obj.put("enabled", lesson["enabled"] as? Boolean ?: true)
            obj.put("endBellEnabled", lesson["endBellEnabled"] as? Boolean ?: true)
            val days = JSONArray()
            (lesson["days"] as? List<*>)?.forEach { item -> (item as? Number)?.let { days.put(it.toInt()) } }
            obj.put("days", days)
            obj.put("startSound", startSound)
            obj.put("endSound", endSound)
            array.put(obj)
        }
        prefs.edit().putString(KEY_PAYLOAD, array.toString()).putInt("ring_seconds", ringSeconds.coerceIn(3, 30)).apply()
        schedulePayload(context, array.toString())
    }

    fun rescheduleSaved(context: Context) {
        val payload = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PAYLOAD, "[]") ?: "[]"
        schedulePayload(context, payload)
    }

    fun scheduleNext(context: Context, lesson: JSONObject, kind: String) {
        if (!lesson.optBoolean("enabled", true)) return
        if (kind == "end" && !lesson.optBoolean("endBellEnabled", true)) return
        val days = lesson.optJSONArray("days") ?: JSONArray()
        if (days.length() == 0) return
        val time = lesson.optString(if (kind == "end") "end" else "start", "08:00").split(":")
        val hour = time.getOrNull(0)?.toIntOrNull() ?: 8
        val minute = time.getOrNull(1)?.toIntOrNull() ?: 0
        val alarmAt = nextOccurrence(days, hour, minute) ?: return
        val lessonId = lesson.optString("id")
        val requestCode = requestCode(lessonId, kind)
        val intent = Intent(context, BellAlarmReceiver::class.java).apply {
            action = "com.aieducation.schoolbell.ALARM.$requestCode"
            putExtra("lesson_id", lessonId)
            putExtra("kind", kind)
        }
        val pending = PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val info = AlarmManager.AlarmClockInfo(alarmAt.timeInMillis, null)
                alarmManager.setAlarmClock(info, pending)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, alarmAt.timeInMillis, pending)
            }
        } catch (_: SecurityException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarmAt.timeInMillis, pending)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, alarmAt.timeInMillis, pending)
            }
        }
    }

    private fun nextOccurrence(days: JSONArray, hour: Int, minute: Int): Calendar? {
        val selected = (0 until days.length()).mapNotNull { days.optInt(it, -1).takeIf { day -> day in 1..7 } }.toSet()
        if (selected.isEmpty()) return null
        val now = Calendar.getInstance()
        val candidate = Calendar.getInstance()
        candidate.set(Calendar.SECOND, 0)
        candidate.set(Calendar.MILLISECOND, 0)
        for (offset in 0..7) {
            candidate.timeInMillis = now.timeInMillis
            candidate.add(Calendar.DAY_OF_YEAR, offset)
            candidate.set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
            candidate.set(Calendar.MINUTE, minute.coerceIn(0, 59))
            candidate.set(Calendar.SECOND, 0)
            candidate.set(Calendar.MILLISECOND, 0)
            val isoDay = ((candidate.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
            if (isoDay in selected && candidate.after(now)) return candidate.clone() as Calendar
        }
        return null
    }

    private fun schedulePayload(context: Context, raw: String) {
        val array = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
        for (i in 0 until array.length()) {
            val lesson = array.optJSONObject(i) ?: continue
            scheduleNext(context, lesson, "start")
            scheduleNext(context, lesson, "end")
        }
    }

    private fun cancelPayload(context: Context, raw: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val array = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
        for (i in 0 until array.length()) {
            val lesson = array.optJSONObject(i) ?: continue
            listOf("start", "end").forEach { kind ->
                val requestCode = requestCode(lesson.optString("id"), kind)
                val intent = Intent(context, BellAlarmReceiver::class.java).apply { action = "com.aieducation.schoolbell.ALARM.$requestCode" }
                val pending = PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
                if (pending != null) alarmManager.cancel(pending)
            }
        }
    }

    private fun requestCode(id: String, kind: String): Int {
        val base = (id.hashCode().toLong() and 0x3fffffffL) % 100_000_000L
        return (base * 2L + if (kind == "end") 1L else 0L).toInt()
    }

    fun requestAlarmAccess(context: android.app.Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!manager.canScheduleExactAlarms()) {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).setData(Uri.parse("package:${context.packageName}"))
                context.startActivity(intent)
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 7301)
        }
    }
}
