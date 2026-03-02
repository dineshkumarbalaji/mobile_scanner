package com.example.mobile_scanner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import android.os.Build

class MainActivity: FlutterActivity() {
    private val ASSETS_CHANNEL = "com.example.mobile_scanner/assets"
    private val DEVICE_CHANNEL = "com.example.mobile_scanner/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Handle asset copying
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ASSETS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "copyAsset") {
                val assetPath = call.argument<String>("assetPath")
                val destPath = call.argument<String>("destPath")
                if (assetPath != null && destPath != null) {
                    try {
                        val inputStream: InputStream = context.assets.open("flutter_assets/$assetPath")
                        val outFile = File(destPath)
                        val outputStream: OutputStream = FileOutputStream(outFile)

                        val buffer = ByteArray(8192)
                        var length: Int
                        while (inputStream.read(buffer).also { length = it } > 0) {
                            outputStream.write(buffer, 0, length)
                        }

                        outputStream.flush()
                        outputStream.close()
                        inputStream.close()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("COPY_FAILED", "Failed to copy asset", e.toString())
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing assetPath or destPath", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // Handle device/emulator detection
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isEmulator") {
                val isEmulator = detectEmulator()
                result.success(isEmulator)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun detectEmulator(): Boolean {
        // Check for common emulator indicators
        val qemu = System.getProperty("ro.kernel.qemu") == "1"
        val manufacturer = Build.MANUFACTURER
        val model = Build.MODEL
        val product = Build.PRODUCT
        val device = Build.DEVICE
        val hardware = Build.HARDWARE
        val fingerprint = Build.FINGERPRINT
        val board = Build.BOARD

        val isEmulator = (
            qemu ||
            fingerprint.contains("generic") ||
            fingerprint.contains("unknown") ||
            model.contains("google_sdk") ||
            model.contains("Emulator") ||
            model.contains("Android SDK") ||
            manufacturer.contains("Genymotion") ||
            manufacturer.contains("unknown") ||
            device?.contains("generic") ?: false ||
            product?.contains("generic") ?: false ||
            product?.contains("google_sdk") ?: false ||
            product?.contains("sdk") ?: false ||
            hardware?.contains("ranchu") ?: false ||
            board?.contains("goldfish") ?: false
        )

        return isEmulator
    }
}
