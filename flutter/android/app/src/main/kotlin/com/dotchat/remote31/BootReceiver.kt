package com.dotchat.remote31

import android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
import android.Manifest.permission.SYSTEM_ALERT_WINDOW
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.Toast
import com.hjq.permissions.XXPermissions
import ffi.FFI
import io.flutter.embedding.android.FlutterActivity

const val DEBUG_BOOT_COMPLETED = "com.dotchat.remote31.DEBUG_BOOT_COMPLETED"

class BootReceiver : BroadcastReceiver() {
    private val logTag = "tagBootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(logTag, "onReceive ${intent.action}")

        if (Intent.ACTION_BOOT_COMPLETED == intent.action || DEBUG_BOOT_COMPLETED == intent.action) {
            // The Rust local option "direct-chat-always-on" is authoritative
            // (it is what the UI switch and the chat policy read), so use it
            // here too instead of the possibly-stale preference boolean.
            val prefs = context.getSharedPreferences(
                KEY_SHARED_PREFERENCES,
                FlutterActivity.MODE_PRIVATE,
            )
            // LUODA FIX: pin the Rust config dir before the first
            // getLocalOption, otherwise the native LocalConfig cache is
            // initialized empty and the machine seed/device id re-rolls on
            // every cold start (messages look like they come from a cloned
            // config).
            FFI.startServer(resolveAppDirConfigPath(context), "")
            if (FFI.getLocalOption("direct-chat-always-on") != "N") {
                DirectChatService.setEnabled(context, true)
            }
            // check SharedPreferences config
            if (!prefs.getBoolean(KEY_START_ON_BOOT_OPT, false)) {
                Log.d(logTag, "KEY_START_ON_BOOT_OPT is false")
                return
            }
            // check pre-permission
            if (!XXPermissions.isGranted(context, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, SYSTEM_ALERT_WINDOW)){
                Log.d(logTag, "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS or SYSTEM_ALERT_WINDOW is not granted")
                return
            }

            // Reuse the persisted MediaProjection token when available so the
            // service can start after reboot without a fresh consent dialog.
            val savedProjection = loadMediaProjectionIntent(context)
            Toast.makeText(context, "点聊已启动", Toast.LENGTH_LONG).show()
            launchMainService(context, savedProjection, fromBoot = true)
        }
    }
}
