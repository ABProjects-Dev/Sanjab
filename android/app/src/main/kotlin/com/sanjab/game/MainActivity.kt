package com.sanjab.game

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * فعالیت اصلی برنامهٔ «شتر مرغ».
 *
 * تنها وظیفهٔ بومی این کلاس، روشن نگه‌داشتن صفحهٔ گوشی در طول بازی است؛
 * تمام منطق بازی در Dart (Flutter) پیاده‌سازی شده و هیچ وابستگی‌ای به کد
 * نسخهٔ Kotlin قبلی وجود ندارد.
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
        // تم تاریک ثابت برنامه
        window.setBackgroundDrawableResource(android.R.color.black)
    }
}
