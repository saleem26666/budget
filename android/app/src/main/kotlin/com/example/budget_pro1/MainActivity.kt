package com.example.budget_pro1

import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "budget_pro/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getStorageLocations") {
                    result.success(getStorageLocations())
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun getStorageLocations(): List<Map<String, String>> {
        val locations = mutableListOf<Map<String, String>>()
        val phoneDocs = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOCUMENTS
        )
        locations.add(
            mapOf(
                "id" to "phone",
                "label" to "Phone storage",
                "path" to File(phoneDocs, "BudgetPro").absolutePath,
            )
        )

        val sdRoot = findRemovableRoot()
        if (sdRoot != null) {
            locations.add(
                mapOf(
                    "id" to "sdcard",
                    "label" to "SD card",
                    "path" to File(sdRoot, "BudgetPro").absolutePath,
                )
            )
        }
        return locations
    }

    private fun findRemovableRoot(): File? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val sm = getSystemService(STORAGE_SERVICE) as StorageManager
            for (volume in sm.storageVolumes) {
                if (!volume.isRemovable) continue
                val dir = volumeDirectory(volume) ?: continue
                if (dir.exists() || dir.mkdirs() || dir.parentFile?.exists() == true) {
                    return dir
                }
            }
        }
        val storage = File("/storage")
        val children = storage.listFiles() ?: return null
        for (child in children) {
            val name = child.name
            if (name.matches(Regex("^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$"))) {
                return child
            }
        }
        return null
    }

    private fun volumeDirectory(volume: android.os.storage.StorageVolume): File? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return volume.directory
        }
        return try {
            val method = volume.javaClass.getMethod("getPath")
            File(method.invoke(volume) as String)
        } catch (_: Exception) {
            null
        }
    }
}
