package com.viewdex.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.viewdex.app/storage"
    private val FILE_OPEN_CHANNEL = "com.viewdex.app/file_open"

    private var initialFilePath: String? = null
    private var fileChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.let { handleIntent(it, isInitial = true) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, isInitial = false)
    }

    private fun handleIntent(intent: Intent, isInitial: Boolean) {
        val action = intent.action
        var uri: Uri? = intent.data

        if (Intent.ACTION_SEND == action && uri == null) {
            @Suppress("DEPRECATION")
            uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }

        if ((Intent.ACTION_VIEW == action || Intent.ACTION_SEND == action) && uri != null) {
            val resolvedPath = resolveUriToFilePath(uri)
            if (resolvedPath != null) {
                if (isInitial) {
                    initialFilePath = resolvedPath
                } else {
                    fileChannel?.invokeMethod("onFileOpened", resolvedPath)
                        ?: run {
                            // If channel is not yet ready, save it as initial
                            initialFilePath = resolvedPath
                        }
                }
            }
        }
    }

    private fun resolveUriToFilePath(uri: Uri): String? {
        return try {
            if ("file".equals(uri.scheme, ignoreCase = true)) {
                return uri.path
            }

            if ("content".equals(uri.scheme, ignoreCase = true)) {
                var displayName: String? = null
                try {
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1 && cursor.moveToFirst()) {
                            displayName = cursor.getString(nameIndex)
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }

                if (displayName.isNullOrBlank()) {
                    // Try to deduce extension from mime type
                    val mimeType = contentResolver.getType(uri)
                    val ext = when (mimeType) {
                        "application/pdf" -> ".pdf"
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> ".docx"
                        "application/msword" -> ".doc"
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> ".xlsx"
                        "application/vnd.ms-excel" -> ".xls"
                        "application/vnd.openxmlformats-officedocument.presentationml.presentation" -> ".pptx"
                        "application/vnd.ms-powerpoint" -> ".ppt"
                        "image/jpeg" -> ".jpg"
                        "image/png" -> ".png"
                        "text/plain" -> ".txt"
                        else -> ".tmp"
                    }
                    displayName = "opened_file$ext"
                }

                val cacheDir = File(cacheDir, "opened_external")
                if (!cacheDir.exists()) {
                    cacheDir.mkdirs()
                }

                val destinationFile = File(cacheDir, displayName!!)
                contentResolver.openInputStream(uri)?.use { inputStream ->
                    FileOutputStream(destinationFile).use { outputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }
                return destinationFile.absolutePath
            }
            null
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
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

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_OPEN_CHANNEL)
        fileChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    result.success(initialFilePath)
                    initialFilePath = null
                }
                else -> result.notImplemented()
            }
        }
    }
}
