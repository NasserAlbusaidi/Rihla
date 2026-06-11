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
        flushPendingSharedPrefsWrites()
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        if (intent != null) {
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK,
            )
            startActivity(intent)
        }
        Runtime.getRuntime().exit(0)
    }

    // FirebaseAuth persists its current user via SharedPreferences.apply(),
    // whose disk write sits queued on android.app.QueuedWork until an activity
    // pause flushes it. Runtime.exit(0) skips the lifecycle entirely, so the
    // apply() queued by an auth swap milliseconds earlier is lost and the cold
    // boot resurrects the PRE-swap user — restoreWithGoogle/restoreWithEmailLink
    // succeed server-side yet never survive the restart. Drain QueuedWork
    // before exiting; if the (unsupported-list) API is unavailable, a bounded
    // sleep gives the queued writer time to hit disk.
    private fun flushPendingSharedPrefsWrites() {
        try {
            Class.forName("android.app.QueuedWork")
                .getMethod("waitToFinish")
                .invoke(null)
        } catch (_: Throwable) {
            try {
                Thread.sleep(300)
            } catch (_: InterruptedException) {
                // Proceed to exit; best-effort flush window elapsed.
            }
        }
    }
}
