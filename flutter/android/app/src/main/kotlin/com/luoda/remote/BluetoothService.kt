package com.luoda.remote

/**
 * Classic Bluetooth (RFCOMM) chat / file-transfer bridge.
 *
 * Inspired by BlueLink (https://github.com/123zpc/BlueLink) for the
 * BluetoothServer / BluetoothClient / session patterns and by
 * esp32-ai-chat (https://github.com/flairziv/esp32-ai-chat) for the
 * reliable line-based transport over a socket.
 *
 * Lines on the wire are `LDESK_CHAT_V1:` envelopes (single-line, no CR/LF),
 * which the Dart side routes into the existing chat model, so PC/phone
 * history, files, voice and the "??" source label all stay consistent.
 */

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.PrintWriter
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import android.Manifest
import android.content.pm.PackageManager
import kotlin.concurrent.thread

object BluetoothService {
    private const val TAG = "LDeskBT"
    private const val CHANNEL = "bluetooth_channel"
    private const val EVENTS = "bluetooth_channel_events"
    private const val SERVICE_NAME = "点聊-BT"
    // App-specific SPP UUID: both ends run LDesk, so no collision with
    // third-party serial apps.
    private val APP_UUID: UUID = UUID.fromString("e18b0f2c-1f2a-4f8e-9c5a-6b7f1a2b3c4d")
    // 点聊设备在蓝牙广播中的名字前缀。只有安装了点聊的设备才会把本地
    // 蓝牙名设成 LD:<昵称>:<ID> 的格式，扫描端据此过滤——普通蓝牙设备
    // （耳机、音箱等）不会出现在点聊的蓝牙扫描列表里。
    private const val LD_PREFIX = "LD:"

    /** 解析点聊蓝牙设备名，返回 Pair(昵称, ID)；非点聊名字返回 null。 */
    private fun parseLdName(name: String?): Pair<String, String>? {
        val n = name?.trim() ?: return null
        if (!n.startsWith(LD_PREFIX)) return null
        val body = n.removePrefix(LD_PREFIX).trim()
        if (body.isEmpty()) return null
        val sep = body.indexOf(':')
        return if (sep > 0) {
            val nick = body.substring(0, sep).trim()
            val id = body.substring(sep + 1).trim()
            Pair(if (nick.isEmpty()) "点聊好友" else nick, id)
        } else {
            Pair(body, "")
        }
    }

    private var activity: MainActivity? = null
    private var adapter: BluetoothAdapter? = null
    private var serverSocket: BluetoothServerSocket? = null
    private var listening = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var listenRetryPosted = false
    private var discoveryReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null
    private val sessions = ConcurrentHashMap<String, BtSession>()

    @Volatile
    private var attached = false

    fun attach(activity: MainActivity, engine: FlutterEngine) {
        if (attached) return
        attached = true
        this.activity = activity

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            Log.i(TAG, "method call: ${call.method}")
            handle(call, result)
        }
        Log.i(TAG, "BluetoothService attached")

        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    fun onEnableResult(enabled: Boolean) {
        postToDart("adapter", mapOf("enabled" to enabled))
        if (enabled) startListening()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(getAdapter() != null)
            "isEnabled" -> {
                result.success(
                    try {
                        getAdapter()?.isEnabled == true
                    } catch (e: SecurityException) {
                        false
                    }
                )
            }
            "enable" -> {
                requestEnable()
                result.success(null)
            }
            "pairedDevices" -> result.success(pairedDevices())
            "startScan" -> {
                startScan()
                result.success(null)
            }
            "setAdvertisedName" -> {
                val name = call.argument<String>("name").orEmpty()
                setAdvertisedName(name)
                result.success(null)
            }
            "stopScan" -> {
                stopScan()
                result.success(null)
            }
            "connect" -> {
                val mac = call.argument<String>("mac").orEmpty()
                val name = call.argument<String>("name").orEmpty()
                if (mac.isEmpty()) {
                    result.error("bad_args", "mac required", null)
                } else {
                    connect(mac, name)
                    result.success(null)
                }
            }
            "disconnect" -> {
                val mac = call.argument<String>("mac").orEmpty()
                sessions[mac]?.close()
                result.success(null)
            }
            "sendEnvelope" -> {
                val mac = call.argument<String>("mac").orEmpty()
                val envelope = call.argument<String>("envelope").orEmpty()
                val session = sessions[mac]
                result.success(session != null && session.writeLine(envelope))
            }
            "startListening" -> {
                startListening()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun getAdapter(): BluetoothAdapter? {
        adapter?.let { return it }
        adapter = try {
            val manager = activity?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            manager?.adapter ?: BluetoothAdapter.getDefaultAdapter()
        } catch (e: SecurityException) {
            Log.w(TAG, "getAdapter blocked: ${e.message}")
            null
        }
        return adapter
    }

    private fun requestEnable() {
        val a = getAdapter() ?: return
        if (a.isEnabled) {
            onEnableResult(true)
            return
        }
        try {
            val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            activity?.startActivityForResult(intent, REQ_ENABLE_BLUETOOTH)
        } catch (e: Exception) {
            postToDart("error", mapOf("message" to "无法开启蓝牙: ${e.message}"))
        }
    }

    private fun pairedDevices(): List<Map<String, String>> {
        val a = getAdapter() ?: return emptyList()
        if (!a.isEnabled) return emptyList()
        return try {
            a.bondedDevices.mapNotNull { device ->
                val name = try {
                    device.name ?: ""
                } catch (e: SecurityException) {
                    ""
                }
                // 只显示安装了点聊的设备（名字带 LD: 前缀）。
                val parsed = parseLdName(name) ?: return@mapNotNull null
                mapOf(
                    "name" to (parsed.first + ":" + parsed.second),
                    "displayName" to parsed.first,
                    "deviceId" to parsed.second,
                    "mac" to device.address
                )
            }
        } catch (e: SecurityException) {
            postToDart("error", mapOf("message" to "读取已配对设备失败，请检查蓝牙连接权限"))
            emptyList()
        }
    }

    /** 把本机蓝牙名广播为 LD:<昵称>:<ID>，让对方只能搜到点聊设备。 */
    private fun setAdvertisedName(name: String) {
        val a = getAdapter() ?: run {
            Log.w(TAG, "setAdvertisedName: no adapter")
            return
        }
        if (!a.isEnabled) {
            Log.w(TAG, "setAdvertisedName: bluetooth disabled")
            return
        }
        if (!hasBtConnectPermission()) {
            Log.w(TAG, "setAdvertisedName: no BLUETOOTH_CONNECT")
            return
        }
        val clean = name.trim()
        if (clean.isEmpty()) {
            Log.w(TAG, "setAdvertisedName: empty name")
            return
        }
        try {
            val current = try {
                a.name ?: ""
            } catch (e: SecurityException) {
                ""
            }
            if (current.startsWith(LD_PREFIX) && current == clean) return
            Log.i(TAG, "setAdvertisedName: '$current' -> '$clean'")
            a.setName(clean)
        } catch (e: Exception) {
            Log.w(TAG, "setName failed: ${e.message}")
        }
    }

    private fun startScan() {
        val a = getAdapter() ?: run {
            postToDart("error", mapOf("message" to "此设备不支持蓝牙"))
            return
        }
        if (!a.isEnabled) return
        if (discoveryReceiver == null) {
            discoveryReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    try {
                        when (intent?.action) {
                            BluetoothDevice.ACTION_FOUND -> {
                                val device = parcelDevice(intent) ?: return
                                // BLUETOOTH_CONNECT is required to read the
                                // name on Android 12+; fall back to the MAC so
                                // a missing permission can never crash the app.
                                val name = try {
                                    device.name ?: ""
                                } catch (e: SecurityException) {
                                    ""
                                }
                                // 只显示安装了点聊的设备：名字必须以 LD: 开头。
                                val parsed = parseLdName(name) ?: return
                                val bonded = try {
                                    device.bondState == BluetoothDevice.BOND_BONDED
                                } catch (e: SecurityException) {
                                    false
                                }
                                postToDart(
                                    "deviceFound",
                                    mapOf(
                                        "name" to (parsed.first + ":" + parsed.second),
                                        "displayName" to parsed.first,
                                        "deviceId" to parsed.second,
                                        "mac" to device.address,
                                        "paired" to bonded
                                    )
                                )
                            }
                            BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                                // Dart side decides whether to keep scanning.
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "onReceive failed: ${e.message}")
                    }
                }
            }
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            try {
                activity?.registerReceiver(discoveryReceiver, filter)
            } catch (e: Exception) {
                Log.w(TAG, "registerReceiver failed: ${e.message}")
            }
        }
        try {
            a.startDiscovery()
        } catch (e: SecurityException) {
            postToDart("error", mapOf("message" to "开始扫描失败，请检查蓝牙扫描权限"))
        } catch (e: Exception) {
            postToDart("error", mapOf("message" to "开始扫描失败: ${e.message}"))
        }
    }

    private fun stopScan() {
        val a = getAdapter() ?: return
        try {
            a.cancelDiscovery()
        } catch (e: SecurityException) {
            // ignore
        }
        discoveryReceiver?.let { receiver ->
            try {
                activity?.unregisterReceiver(receiver)
            } catch (e: Exception) {
                // already unregistered
            }
        }
        discoveryReceiver = null
    }

    @Suppress("DEPRECATION")
    private fun parcelDevice(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    /** Android 12+ requires BLUETOOTH_CONNECT to open an RFCOMM server socket. */
    private fun hasBtConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return try {
            activity?.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }

    /** Retry listening every 3s until BLUETOOTH_CONNECT is granted, so the
     *  auto-started service can pick up incoming RFCOMM connections right
     *  after the user completes the one-time permission wizard. */
    private fun scheduleListenRetry() {
        if (listenRetryPosted) return
        listenRetryPosted = true
        mainHandler.postDelayed({
            listenRetryPosted = false
            if (!listening) startListening()
        }, 3000)
    }

    /** Accept loop for incoming RFCOMM connections (server role). */
    fun startListening() {
        if (listening) return
        val a = getAdapter() ?: return
        if (!a.isEnabled) return
        if (!hasBtConnectPermission()) {
            Log.w(TAG, "BLUETOOTH_CONNECT not granted yet; retrying listen")
            scheduleListenRetry()
            return
        }
        listening = true
        thread(name = "LDeskBT-Accept") {
            try {
                serverSocket = try {
                    a.listenUsingRfcommWithServiceRecord(SERVICE_NAME, APP_UUID)
                } catch (e: SecurityException) {
                    Log.w(TAG, "RFCOMM listen blocked by missing BLUETOOTH_CONNECT")
                    serverSocket = null
                    listening = false
                    scheduleListenRetry()
                    return@thread
                }
                while (!Thread.currentThread().isInterrupted) {
                    val socket = try {
                        serverSocket?.accept() ?: break
                    } catch (e: Exception) {
                        break
                    }
                    val remote = socket.remoteDevice
                    sessions[remote.address]?.close()
                    val session = BtSession(socket)
                    sessions[remote.address] = session
                    session.start()
                    val remoteName = try { remote.name ?: "" } catch (e: SecurityException) { "" }
                    postToDart(
                        "connected",
                        mapOf("mac" to remote.address, "name" to remoteName)
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "accept loop ended", e)
            } finally {
                listening = false
                try {
                    serverSocket?.close()
                } catch (_: Exception) {
                }
                serverSocket = null
            }
        }
    }

    /** Client role: connect to a discovered/paired device. */
    private fun connect(mac: String, name: String) {
        val a = getAdapter() ?: run {
            postToDart("error", mapOf("message" to "此设备不支持蓝牙"))
            return
        }
        if (!a.isEnabled) {
            postToDart("error", mapOf("message" to "蓝牙未开启"))
            return
        }
        val device = a.getRemoteDevice(mac)
        thread(name = "LDeskBT-Connect") {
            try {
                sessions[mac]?.close()
                try {
                    a.cancelDiscovery()
                } catch (_: SecurityException) {
                }
                val socket = device.createRfcommSocketToServiceRecord(APP_UUID)
                socket.connect() // blocks until connected or fails
                val session = BtSession(socket)
                sessions[mac]?.close()
                sessions[mac] = session
                session.start()
                postToDart("connected", mapOf("mac" to mac, "name" to name))
            } catch (e: SecurityException) {
                Log.e(TAG, "connect blocked by permission", e)
                postToDart("error", mapOf("message" to "连接失败，请检查蓝牙连接权限"))
            } catch (e: Exception) {
                Log.e(TAG, "connect failed", e)
                postToDart("error", mapOf("message" to "连接失败: ${e.message}"))
            }
        }
    }

    private fun postToDart(event: String, data: Map<String, Any?>) {
        val sink = eventSink ?: return
        val payload = HashMap<String, Any?>()
        payload["event"] = event
        payload.putAll(data)
        Handler(Looper.getMainLooper()).post {
            try {
                sink.success(payload)
            } catch (e: Exception) {
                Log.w(TAG, "event sink error", e)
            }
        }
    }

    /** One active RFCOMM link; line-based envelope transport. */
    private class BtSession(private val socket: BluetoothSocket) {
        private val mac: String = socket.remoteDevice.address
        private val reader = BufferedReader(InputStreamReader(socket.inputStream))
        private val writer = PrintWriter(
            BufferedWriter(OutputStreamWriter(socket.outputStream, StandardCharsets.UTF_8)),
            true
        )
        private val writeLock = Any()
        @Volatile
        var closed = false
            private set

        fun start() {
            thread(name = "LDeskBT-Read-$mac") { readLoop() }
        }

        private fun readLoop() {
            try {
                while (!closed) {
                    val line = reader.readLine() ?: break
                    if (line.isEmpty()) continue
                    postToDart("wire", mapOf("mac" to mac, "envelope" to line))
                }
            } catch (e: Exception) {
                Log.d(TAG, "read loop ended: ${e.message}")
            } finally {
                close()
                postToDart("disconnected", mapOf("mac" to mac))
            }
        }

        fun writeLine(line: String): Boolean {
            if (closed) return false
            synchronized(writeLock) {
                try {
                    writer.println(line)
                    if (writer.checkError()) {
                        close()
                        return false
                    }
                    return true
                } catch (e: Exception) {
                    close()
                    return false
                }
            }
        }

        fun close() {
            if (closed) return
            closed = true
            sessions.remove(mac)
            try {
                socket.close()
            } catch (_: Exception) {
            }
        }
    }
}
