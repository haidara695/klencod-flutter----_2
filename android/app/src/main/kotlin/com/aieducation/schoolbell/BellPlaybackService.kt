package com.aieducation.schoolbell

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings

class BellPlaybackService : Service() {
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { stopPlayback() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopPlayback()
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PREVIEW, ACTION_PLAY_ALARM -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "جرس المدرسة"
                val uri = intent.getStringExtra(EXTRA_URI)
                val notification = buildNotification(title)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                startPlayback(uri)
                handler.removeCallbacks(timeout)
                // A school bell should not ring indefinitely, including when the selected track is long.
                val durationSeconds = intent.getIntExtra(EXTRA_DURATION, 12).coerceIn(3, 30)
                handler.postDelayed(timeout, durationSeconds * 1_000L)
            }
            else -> {
                stopSelf(startId)
                return START_NOT_STICKY
            }
        }
        return START_NOT_STICKY
    }

    private fun startPlayback(rawUri: String?) {
        stopCurrentPlayer()
        try {
            val next = MediaPlayer()
            next.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            if (rawUri.isNullOrBlank()) {
                next.setDataSource(this, Settings.System.DEFAULT_ALARM_ALERT_URI)
            } else {
                next.setDataSource(this, Uri.parse(rawUri))
            }
            next.setOnCompletionListener { stopPlayback() }
            next.setOnErrorListener { _, _, _ -> stopPlayback(); true }
            next.prepare()
            player = next
            next.start()
        } catch (_: Exception) {
            // Missing/revoked file access or a silent default sound should not crash the service.
            stopPlayback()
        }
    }

    private fun stopCurrentPlayer() {
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
    }

    private fun stopPlayback() {
        handler.removeCallbacks(timeout)
        stopCurrentPlayer()
        stopForeground(true)
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "جرس المدرسة", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "تنبيهات بداية ونهاية الحصص المدرسية"
                setSound(null, null)
                enableVibration(true)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String): Notification {
        val stopIntent = Intent(this, BellPlaybackService::class.java).setAction(ACTION_STOP)
        val stopPending = PendingIntent.getService(this, 9082, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        return builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText("جرس المدرسة يعمل — اضغط إيقاف لإسكاته")
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_pause, "إيقاف", stopPending)
            .build()
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeout)
        stopCurrentPlayer()
        super.onDestroy()
    }

    companion object {
        const val ACTION_PREVIEW = "com.aieducation.schoolbell.PREVIEW"
        const val ACTION_PLAY_ALARM = "com.aieducation.schoolbell.PLAY_ALARM"
        const val ACTION_STOP = "com.aieducation.schoolbell.STOP"
        const val EXTRA_URI = "sound_uri"
        const val EXTRA_TITLE = "bell_title"
        const val EXTRA_DURATION = "duration_seconds"
        private const val CHANNEL_ID = "school_bell_alarm_channel"
        private const val NOTIFICATION_ID = 1412
    }
}
