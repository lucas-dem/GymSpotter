package com.infyter.app

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.AppUpdateType
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Version check on Android, channel "infyter/store_update" (Dart side: lib/services/play_update.dart).
 *
 * - "device": whether the phone has a validated internet connection (ACCESS_NETWORK_STATE) and the installed
 *   versionCode.
 * - "play": what the Play Store app on the phone says about an update, through Play In-App Updates. The app
 *   itself opens no connection: it has no INTERNET permission.
 *
 * Any failure (no Play Store, not installed from Play, no connection) reaches Dart as an error, and the app
 * stays usable.
 */
object StoreUpdate {
    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "infyter/store_update").setMethodCallHandler { call, result ->
            when (call.method) {
                "device" -> result.success(
                    mapOf("online" to isOnline(app), "installedVersionCode" to installedVersionCode(app))
                )
                "play" -> askPlay(app, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun isOnline(context: Context): Boolean {
        return try {
            val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
            val caps = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (e: Exception) {
            false
        }
    }

    private fun installedVersionCode(context: Context): Long? = try {
        val info = packageInfo(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else legacyVersionCode(info)
    } catch (e: Exception) {
        null
    }

    private fun packageInfo(context: Context): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            legacyPackageInfo(context)
        }

    @Suppress("DEPRECATION")
    private fun legacyPackageInfo(context: Context): PackageInfo =
        context.packageManager.getPackageInfo(context.packageName, 0)

    @Suppress("DEPRECATION")
    private fun legacyVersionCode(info: PackageInfo): Long = info.versionCode.toLong()

    private fun askPlay(context: Context, result: MethodChannel.Result) {
        try {
            AppUpdateManagerFactory.create(context).appUpdateInfo
                .addOnSuccessListener { info ->
                    result.success(
                        mapOf(
                            "availability" to info.updateAvailability(),
                            "availableVersionCode" to info.availableVersionCode(),
                            "immediateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
                            "stalenessDays" to info.clientVersionStalenessDays(),
                        )
                    )
                }
                .addOnFailureListener { e -> result.error("play-failed", e.message, null) }
        } catch (e: Exception) {
            result.error("play-failed", e.message, null)
        }
    }
}
