package com.dotchat.remote31

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Base64
import java.io.File
import java.io.RandomAccessFile
import androidx.annotation.Keep
import androidx.core.app.NotificationCompat
import ffi.FFI
import io.flutter.embedding.android.FlutterActivity
import org.json.JSONArray
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
    private val contactPeerIds = ConcurrentHashMap<Int, String>()

    override fun onCreate() {
        super.onCreate()
        FFI.initDirectChatService(this)
        startForeground(NOTIFICATION_ID, buildNotification())
        val configPath = resolveAppDirConfigPath(applicationContext)
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
            val peerId = client.optString("peer_id").trim()
            if (peerId.isNotEmpty()) {
                contactPeerIds[id] = peerId
            }
            val displayName = client.optString("name").ifBlank {
                peerId.ifBlank { "点聊" }
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
                        "点聊消息",
                        NotificationManager.IMPORTANCE_HIGH,
                    ).apply {
                        description = "收到点聊消息提醒"
                    },
                )
            }
            val openApp = PendingIntent.getActivity(
                this,
                id,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            persistIncomingMessage(event)
            val notification = NotificationCompat.Builder(this, MESSAGE_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(contactNames[id] ?: "点聊")
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
        val prefix = "LDESK_CHAT_V1:"
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

/// Writes an incoming direct message into the shared chat store so the
    /// Flutter UI (message list) shows it even when MainService / the app
    /// process is not running. Uses the same .lock file as the Dart side.
    private fun persistIncomingMessage(event: JSONObject) {
        runCatching {
            val raw = event.optString("text").ifBlank { return }
            val prefix = "LDESK_CHAT_V1:"
            if (!raw.startsWith(prefix)) return
            val encoded = raw.removePrefix(prefix)
            val decoded = String(
                Base64.decode(encoded, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING),
                StandardCharsets.UTF_8,
            )
            val envelope = JSONObject(decoded)
            if (envelope.optString("type") != "message") return
            val data = envelope.optJSONObject("data") ?: return
            val id = data.optString("id")
            val originDeviceId = data.optString("origin_device_id")
            if (id.isEmpty() || originDeviceId.isEmpty()) return
            val connId = event.optInt("id")
            val peerId = contactPeerIds[connId] ?: ""
            val conversationKey = peerId.ifEmpty { originDeviceId }
            data.put("conversation_id", conversationKey)
            data.put("direction", "incoming")
            data.put("delivery", "delivered")
            if (!data.has("disposition") || data.optString("disposition").isEmpty()) {
                data.put("disposition", "active")
            }
            if (!data.has("kind") || data.optString("kind").isEmpty()) {
                data.put("kind", "text")
            }
            if (!data.has("sent_at") || data.optString("sent_at").isEmpty()) {
                data.put("sent_at", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).format(java.util.Date()))
            }
            if (!data.has("sender_id") || data.optString("sender_id").isEmpty()) {
                data.put("sender_id", originDeviceId)
            }
            if (!data.has("sender_name") || data.optString("sender_name").isEmpty()) {
                data.put("sender_name", contactNames[connId] ?: originDeviceId)
            }
            if (!data.has("sender_avatar")) data.put("sender_avatar", "")
            val store = File(filesDir, "ldesk_direct_chat_v1.json")
            val lockFile = File(filesDir, "ldesk_direct_chat_v1.json.lock")
            lockFile.parentFile?.mkdirs()
            RandomAccessFile(lockFile, "rw").use { lock ->
                lock.channel.lock()
                val root = if (store.exists()) {
                    runCatching { JSONObject(store.readText()) }.getOrNull()
                        ?: JSONObject()
                } else {
                    JSONObject()
                }
                if (!root.has("schema")) root.put("schema", 1)
                if (!root.has("next_sequence")) root.put("next_sequence", 0)
                if (!root.has("records")) root.put("records", JSONArray())
                val records = root.optJSONArray("records")
                var exists = false
                for (i in 0 until records.length()) {
                    val r = records.optJSONObject(i)
                    if (r != null && r.optString("id") == id) {
                        exists = true
                        break
                    }
                }
                if (!exists) {
                    records.put(data)
                    root.put("next_sequence", root.optInt("next_sequence") + 1)
                    // Merge an older conversation keyed by the sender's device
                    // UUID into the DotChat-id conversation so replies can be
                    // dialed and the UI never shows the same person twice.
                    if (conversationKey != originDeviceId) {
                        for (i in 0 until records.length()) {
                            val r = records.optJSONObject(i)
                            if (r != null && r.optString("conversation_id") == originDeviceId) {
                                r.put("conversation_id", conversationKey)
                            }
                        }
                    }
                    store.parentFile?.mkdirs()
                    // Atomic write: write the temp file first, then rename so
                    // the Dart reader never sees a partially-written JSON blob.
                    val tmp = File(filesDir, "ldesk_direct_chat_v1.json.tmp")
                    tmp.writeText(root.toString())
                    if (!tmp.renameTo(store)) {
                        store.writeText(root.toString())
                    }
                }
            }
        }
    }

    private fun buildNotification(): android.app.Notification {
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "点聊消息",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "保持点聊消息在线可用"
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
            .setContentTitle("点聊")
            .setContentText("点聊消息服务运行中")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
