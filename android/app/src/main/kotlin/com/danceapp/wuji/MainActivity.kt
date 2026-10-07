package com.danceapp.wuji

import android.media.MediaScannerConnection
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wuji/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanMedia" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("args", "path required", null)
                            return@setMethodCallHandler
                        }
                        // 触发系统媒体扫描：相册类 App 只认 MediaStore，
                        // 扫描后刚保存的视频/图片立刻可见
                        MediaScannerConnection.scanFile(this, arrayOf(path), null) { _, uri ->
                            result.success(uri?.toString())
                        }
                    }
                    // 导入/导出大文件期间保持屏幕常亮，防止锁屏后进程被冻结中断
                    "setKeepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
