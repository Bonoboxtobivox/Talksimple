package com.talksimple.talksimple

import android.content.Context
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Device facts the app's notice bar needs; see
        // lib/services/device_status.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "talksimple/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPowerSaveMode" -> {
                        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(power.isPowerSaveMode)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
