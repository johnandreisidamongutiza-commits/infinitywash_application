package com.example.infinitywash

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "infinitywash/app_settings"
    private val foregroundNotificationsChannelName = "infinitywash/foreground_notifications"
    private val screenWakeChannelName = "infinitywash/screen_wake"
    private val notificationChannelId = "infinitywash_default"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenWakeChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepScreenOn" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        runOnUiThread {
                            if (enable) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", applicationContext.packageName, null)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // No settings activity resolvable on this device.
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            foregroundNotificationsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "showForegroundNotification" -> {
                    try {
                        val title = call.argument<String>("title") ?: "InfinityWash"
                        val body = call.argument<String>("body") ?: "You have a new notification."
                        val notificationId = call.argument<Int>("id")
                            ?: (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
                        showForegroundNotification(notificationId, title, body)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("notification_failed", error.message, null)
                    }
                }
                "playNotificationSound" -> {
                    try {
                        playDefaultNotificationSound()
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("sound_failed", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
            .build()

        val channel = NotificationChannel(
            notificationChannelId,
            "InfinityWash notifications",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Order updates and announcements"
            enableVibration(true)
            setSound(defaultSoundUri, audioAttributes)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun playDefaultNotificationSound() {
        try {
            val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val ringtone = RingtoneManager.getRingtone(applicationContext, defaultSoundUri)
            ringtone?.let {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    it.isLooping = false
                }
                it.play()
            }
        } catch (_: Exception) {
            // Ignore sound error
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator?.vibrate(
                    VibrationEffect.createOneShot(350, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(
                        VibrationEffect.createOneShot(350, VibrationEffect.DEFAULT_AMPLITUDE)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(350)
                }
            }
        } catch (_: Exception) {
            // Ignore vibration error
        }
    }

    private fun showForegroundNotification(id: Int, title: String, body: String) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                id,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val notification = NotificationCompat.Builder(this, notificationChannelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setSound(defaultSoundUri)
            .setDefaults(NotificationCompat.DEFAULT_VIBRATE)
            .setContentIntent(pendingIntent)
            .build()

        NotificationManagerCompat.from(this).notify(id, notification)
    }
}
