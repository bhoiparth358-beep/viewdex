package com.viewdex.app

import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.viewdex.app/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getStorageInfo") {
                try {
                    val path = Environment.getExternalStorageDirectory().path
                    val stat = StatFs(path)
                    val blockSize = stat.blockSizeLong
                    val totalBlocks = stat.blockCountLong
                    val availableBlocks = stat.availableBlocksLong

                    val totalBytes = totalBlocks * blockSize
                    val freeBytes = availableBlocks * blockSize
                    val usedBytes = totalBytes - freeBytes

                    val map = mapOf(
                        "totalBytes" to totalBytes,
                        "usedBytes" to usedBytes,
                        "freeBytes" to freeBytes
                    )
                    result.success(map)
                } catch (e: Exception) {
                    result.error("STORAGE_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
