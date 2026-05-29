package com.safar.safar

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val cacheIsolationChannel = "com.safar.safar/cache_isolation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            cacheIsolationChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "restart") {
                restartApp()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    // True process restart for the #45 cross-UID cache barrier: relaunch the app
    // via its launch Intent, then kill the process. The next launch is a genuine
    // cold boot (un-started Firestore) where the boot barrier may legally call
    // clearPersistence() — NOT a flutter_phoenix widget rebirth.
    private fun restartApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        if (intent != null) {
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK,
            )
            startActivity(intent)
        }
        Runtime.getRuntime().exit(0)
    }
}
