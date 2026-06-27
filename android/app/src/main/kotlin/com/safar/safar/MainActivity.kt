package com.safar.safar

import android.content.Intent
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val cacheIsolationChannel = "com.safar.safar/cache_isolation"
    private val installReferrerChannel = "com.safar.safar/install_referrer"

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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installReferrerChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "getInstallReferrer") {
                getInstallReferrer(result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getInstallReferrer(result: MethodChannel.Result) {
        var client: InstallReferrerClient? = null
        var completed = false
        var closed = false

        fun closeClient() {
            if (closed) return
            closed = true
            try {
                client?.endConnection()
            } catch (_: Throwable) {
                // Best-effort close; retrieval has already resolved.
            }
        }

        fun finish(value: String?) {
            if (completed) return
            completed = true
            try {
                result.success(value)
            } finally {
                closeClient()
            }
        }

        try {
            val builtClient = InstallReferrerClient.newBuilder(this).build()
            client = builtClient
            builtClient.startConnection(
                object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(responseCode: Int) {
                        when (responseCode) {
                            InstallReferrerResponse.OK -> {
                                val referrer = try {
                                    builtClient.installReferrer.installReferrer
                                } catch (_: Throwable) {
                                    null
                                }
                                finish(referrer)
                            }

                            InstallReferrerResponse.FEATURE_NOT_SUPPORTED,
                            InstallReferrerResponse.SERVICE_UNAVAILABLE -> finish(null)

                            else -> finish(null)
                        }
                    }

                    override fun onInstallReferrerServiceDisconnected() {
                        finish(null)
                    }
                },
            )
        } catch (_: Throwable) {
            finish(null)
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
