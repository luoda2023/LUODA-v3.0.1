package com.luoda.remote

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Base64
import androidx.annotation.Keep
import androidx.core.app.NotificationCompat
import ffi.FFI
import io.flutter.embedding.android.FlutterActivity
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap

class DirectChatService : Service() {
    companion object {
        private const val CHANNEL_ID = "ldesk_direct_messages"
        private const val MESSAGE_CHANNEL_ID = "ldesk_direct_message_alerts"
        private const val NOTIFICATION_ID = 2001

        fun setEnabled(context: Context, enabled: Boolean) {
            val intent = Intent(context, DirectChatService::class.java)
            if (!enabled) {
                context.stopService(intent)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private val contactNames = ConcurrentHashMap<Int, String>()

    override fun onCreate() {
        super.onCreate()
        FFI.initDirectChatService(this)
        startForeground(NOTIFICATION_ID, buildNotification())
        val prefs = applicationContext.getSharedPreferences(
            KEY_SHARED_PREFERENCES,
            FlutterActivity.MODE_PRIVATE,
        )
        val configPath = prefs.getString(KEY_APP_DIR_CONFIG_PATH, "") ?: ""
        FFI.startServer(configPath, "")
        FFI.startService()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @Keep
    fun rustSetByName(name: String, arg1: String, arg2: String) {
        when (name) {
            "add_connection" -> rememberChatContact(arg1)
            "direct_chat_message" -> showDirectMessage(arg1)
        }
    }

    private fun rememberChatContact(payload: String) {
        runCatching {
            val client = JSONObject(payload)
            if (!client.optBoolean("authorized") || !client.optBoolean("is_chat")) {
                return
            }
            val id = client.getInt("id")
            val displayName = client.optString("name").ifBlank {
                client.optString("peer_id").ifBlank { "LDesk" }
            }
            contactNames[id] = displayName
        }
    }

    private fun showDirectMessage(payload: String) {
        runCatching {
            val event = JSONObject(payload)
            val id = event.getInt("id")
            val preview = decodeMessagePreview(event.optString("text")) ?: return
            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        MESSAGE_CHANNEL_ID,
                        "LDesk messages",
                        NotificationManager.IMPORTANCE_HIGH,
                    ).apply {
                        description = "Alerts for incoming direct messages"
                    },
                )
            }
            val openApp = PendingIntent.getActivity(
                this,
                id,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = NotificationCompat.Builder(this, MESSAGE_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(contactNames[id] ?: "LDesk")
                .setContentText(preview.take(160))
                .setStyle(NotificationCompat.BigTextStyle().bigText(preview.take(500)))
                .setContentIntent(openApp)
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .build()
            manager.notify(3000 + (id and 0x0FFF), notification)
        }
    }

    private fun decodeMessagePreview(raw: String): String? {
        const val prefix = "LDESK_CHAT_V1:"
        if (!raw.startsWith(prefix)) return raw.ifBlank { null }
        return runCatching {
            val encoded = raw.removePrefix(prefix)
            val decoded = String(
                Base64.decode(encoded, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING),
                StandardCharsets.UTF_8,
            )
            val envelope = JSONObject(decoded)
            if (envelope.optString("type") != "message") return null
            envelope.getJSONObject("data").optString("text").ifBlank { null }
        }.getOrNull()
    }

    private fun buildNotification(): android.app.Notification {
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "LDesk messages",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Keeps direct messages available"
                },
            )
        }
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("LDesk")
            .setContentText("Direct messages are available")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
