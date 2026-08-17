package com.example.peacock.feature.effects

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import com.example.peacock.R
import com.example.peacock.ui.MainActivity
import kotlinx.coroutines.flow.MutableSharedFlow

object EffectPlaybackBus {
    val stop = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
}

class EffectPlaybackService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Maurya RAM Effects", NotificationManager.IMPORTANCE_LOW),
        )
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Maurya:EffectPlayback")
            .apply { acquire(2 * 60 * 60 * 1000L) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            EffectPlaybackBus.stop.tryEmit(Unit)
            stopSelf()
            return START_NOT_STICKY
        }
        val name = intent?.getStringExtra(EXTRA_NAME).orEmpty()
        val step = intent?.getStringExtra(EXTRA_STEP).orEmpty()
        val open = PendingIntent.getActivity(
            this, 1, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 2, Intent(this, EffectPlaybackService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(if (name.isBlank()) "Maurya RAM Effect" else name)
                .setContentText(if (step.isBlank()) "临时播放 · 不写Flash" else step)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .addAction(0, "停止 / 停止", stop)
                .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val types = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or
                if (intent?.getBooleanExtra(EXTRA_MICROPHONE, false) == true) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                } else 0
            startForeground(NOTIFICATION_ID, notification, types)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL = "maurya_effect_playback"
        private const val NOTIFICATION_ID = 380
        private const val ACTION_STOP = "com.example.peacock.effect.STOP"
        private const val EXTRA_NAME = "name"
        private const val EXTRA_STEP = "step"
        private const val EXTRA_MICROPHONE = "microphone"

        fun start(context: Context, name: String, step: String = "", usesMicrophone: Boolean = false) {
            val intent = Intent(context, EffectPlaybackService::class.java)
                .putExtra(EXTRA_NAME, name).putExtra(EXTRA_STEP, step)
                .putExtra(EXTRA_MICROPHONE, usesMicrophone)
            context.startForegroundService(intent)
        }
        fun stop(context: Context) {
            context.stopService(Intent(context, EffectPlaybackService::class.java))
        }
    }
}
