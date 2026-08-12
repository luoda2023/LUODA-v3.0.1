package com.luoda.remote

import android.Manifest.permission.*
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.media.AudioRecord
import android.media.AudioRecord.READ_BLOCKING
import android.media.MediaCodecList
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Parcel
import android.util.Base64
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.provider.Settings.*
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat.getSystemService
import com.hjq.permissions.Permission
import com.hjq.permissions.XXPermissions
import ffi.FFI
import java.nio.ByteBuffer
import java.util.*


// intent action, extra
const val ACT_REQUEST_MEDIA_PROJECTION = "REQUEST_MEDIA_PROJECTION"
const val ACT_INIT_MEDIA_PROJECTION_AND_SERVICE = "INIT_MEDIA_PROJECTION_AND_SERVICE"
const val ACT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"
const val EXT_INIT_FROM_BOOT = "EXT_INIT_FROM_BOOT"
const val EXT_MEDIA_PROJECTION_RES_INTENT = "MEDIA_PROJECTION_RES_INTENT"
const val EXT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"

// Activity requestCode
const val REQ_INVOKE_PERMISSION_ACTIVITY_MEDIA_PROJECTION = 101
const val REQ_REQUEST_MEDIA_PROJECTION = 201
const val REQ_ENABLE_BLUETOOTH = 301

// Activity responseCode
const val RES_FAILED = -100

// Flutter channel
const val START_ACTION = "start_action"
const val GET_START_ON_BOOT_OPT = "get_start_on_boot_opt"
const val SET_START_ON_BOOT_OPT = "set_start_on_boot_opt"
const val SYNC_APP_DIR_CONFIG_PATH = "sync_app_dir"
const val GET_VALUE = "get_value"

const val KEY_IS_SUPPORT_VOICE_CALL = "KEY_IS_SUPPORT_VOICE_CALL"

const val KEY_SHARED_PREFERENCES = "KEY_SHARED_PREFERENCES"
const val KEY_START_ON_BOOT_OPT = "KEY_START_ON_BOOT_OPT"
const val KEY_APP_DIR_CONFIG_PATH = "KEY_APP_DIR_CONFIG_PATH"
const val KEY_DIRECT_CHAT_ALWAYS_ON = "KEY_DIRECT_CHAT_ALWAYS_ON"
const val KEY_MEDIA_PROJECTION_URI = "KEY_MEDIA_PROJECTION_URI"

@SuppressLint("ConstantLocale")
val LOCAL_NAME = Locale.getDefault().toString()
val SCREEN_INFO = Info(0, 0, 1, 200)

data class Info(
    var width: Int, var height: Int, var scale: Int, var dpi: Int
)

// ---- MediaProjection token persistence (grant once, reuse later) ----
// Android cannot persist a MediaProjection grant: the result Intent carries a
// Binder that dies with the process and cannot be marshalled to disk, so any
// save attempt fails with "Tried to marshall a Parcel that contains objects".
// The service therefore stays alive as a foreground service (START_STICKY +
// boot receiver) so the grant survives normal use; only a device reboot or a
// force-stop requires the user to grant again.
/**
 * Resolve the Rust config dir used by the native core. It must always match
 * Flutter's getApplicationDocumentsDirectory() (= <dataDir>/app_flutter) or
 * the seed/device id gets re-rolled and messaging/contacts break.
 *
 * The Flutter UI persists this path into prefs (sync_app_dir) on every launch,
 * but the Kotlin services can start BEFORE Flutter syncs (first launch after
 * install, boot receiver, force-stop restart). Never start the server with an
 * empty path: compute the Flutter-compatible fallback and persist it so every
 * later start in this install uses the same directory.
 */
fun resolveAppDirConfigPath(context: Context): String {
    val prefs = context.getSharedPreferences(KEY_SHARED_PREFERENCES, Context.MODE_PRIVATE)
    val saved = prefs.getString(KEY_APP_DIR_CONFIG_PATH, "")?.trim().orEmpty()
    if (saved.isNotEmpty()) return saved
    val dataDir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        context.dataDir?.absolutePath
    } else {
        context.filesDir.parentFile?.absolutePath
    }
    val fallback = if (dataDir.isNullOrEmpty()) {
        java.io.File(context.filesDir, "app_flutter").absolutePath
    } else {
        java.io.File(dataDir, "app_flutter").absolutePath
    }
    prefs.edit().putString(KEY_APP_DIR_CONFIG_PATH, fallback).apply()
    Log.d("AppDirConfig", "resolved fallback app_dir=$fallback")
    return fallback
}

fun saveMediaProjectionIntent(context: Context, data: Intent) {
    // Intentionally empty: MediaProjection tokens are Binders and cannot be
    // persisted. Keeping the call site unchanged avoids touching callers.
}

fun loadMediaProjectionIntent(context: Context): Intent? {
    return try {
        val prefs = context.getSharedPreferences(KEY_SHARED_PREFERENCES, Context.MODE_PRIVATE)
        val encoded = prefs.getString(KEY_MEDIA_PROJECTION_URI, "") ?: return null
        if (encoded.isEmpty()) return null
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        val parcel = Parcel.obtain()
        parcel.unmarshall(bytes, 0, bytes.size)
        parcel.setDataPosition(0)
        val intent = Intent.CREATOR.createFromParcel(parcel)
        parcel.recycle()
        Log.d("MediaProjectionStore", "loaded projection token len=${encoded.length}")
        intent
    } catch (e: Exception) {
        Log.e("MediaProjectionStore", "load failed: ${e.message}")
        null
    }
}

fun launchMainService(context: Context, mediaProjectionResultIntent: Intent?, fromBoot: Boolean = false) {
    val serviceIntent = Intent(context, MainService::class.java)
    serviceIntent.action = ACT_INIT_MEDIA_PROJECTION_AND_SERVICE
    if (fromBoot) serviceIntent.putExtra(EXT_INIT_FROM_BOOT, true)
    if (mediaProjectionResultIntent != null) {
        serviceIntent.putExtra(EXT_MEDIA_PROJECTION_RES_INTENT, mediaProjectionResultIntent)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(serviceIntent)
    } else {
        context.startService(serviceIntent)
    }
}

fun isSupportVoiceCall(): Boolean {
    // https://developer.android.com/reference/android/media/MediaRecorder.AudioSource#VOICE_COMMUNICATION
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
}

fun requestPermission(context: Context, type: String) {
    fun notifyResult(result: Boolean) {
        Handler(Looper.getMainLooper()).post {
            MainActivity.flutterMethodChannel?.invokeMethod(
                "on_android_permission_result",
                mapOf("type" to type, "result" to result)
            )
        }
    }
    try {
        XXPermissions.with(context)
            .permission(type)
            .request { _, all ->
                notifyResult(all)
            }
    } catch (e: Exception) {
        // e.g. BLUETOOTH_SCAN manifest misuse on Android 12+: never let a
        // permission-request failure crash the app or hang the caller.
        android.util.Log.w("LDeskBT", "requestPermission failed for $type: ${e.message}")
        notifyResult(false)
    }
}

fun startAction(context: Context, action: String) {
    try {
        context.startActivity(Intent(action).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // don't pass package name when launch ACTION_ACCESSIBILITY_SETTINGS
            if (ACTION_ACCESSIBILITY_SETTINGS != action) {
                data = Uri.parse("package:" + context.packageName)
            }
        })
    } catch (e: Exception) {
        e.printStackTrace()
    }
}

class AudioReader(val bufSize: Int, private val maxFrames: Int) {
    private var currentPos = 0
    private val bufferPool: Array<ByteBuffer>

    init {
        if (maxFrames < 0 || maxFrames > 32) {
            throw Exception("Out of bounds")
        }
        if (bufSize <= 0) {
            throw Exception("Wrong bufSize")
        }
        bufferPool = Array(maxFrames) {
            ByteBuffer.allocateDirect(bufSize)
        }
    }

    private fun next() {
        currentPos++
        if (currentPos >= maxFrames) {
            currentPos = 0
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    fun readSync(audioRecord: AudioRecord): ByteBuffer? {
        val buffer = bufferPool[currentPos]
        val res = audioRecord.read(buffer, bufSize, READ_BLOCKING)
        return if (res > 0) {
            next()
            buffer
        } else {
            null
        }
    }
}


fun getScreenSize(windowManager: WindowManager) : Pair<Int, Int>{
    var w = 0
    var h = 0
    @Suppress("DEPRECATION")
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val m = windowManager.maximumWindowMetrics
        w = m.bounds.width()
        h = m.bounds.height()
    } else {
        val dm = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(dm)
        w = dm.widthPixels
        h = dm.heightPixels
    }
    return Pair(w, h)
}

 fun translate(input: String): String {
    Log.d("common", "translate:$LOCAL_NAME")
    return FFI.translateLocale(LOCAL_NAME, input)
}
