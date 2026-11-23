package com.sanjab.game

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity of Sanjab.
 *
 * The only native responsibility is keeping the screen awake during play; all game
 * logic lives in Dart (Flutter) and nothing depends on the old Kotlin build.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.sanjab.game/screen"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepScreenOn" -> {
                        val enabled = call.arguments as? Boolean ?: false
                        runOnUiThread { applyKeepScreenOn(enabled) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun applyKeepScreenOn(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Fixed dark background of the app
        window.setBackgroundDrawableResource(android.R.color.black)
    }
}
