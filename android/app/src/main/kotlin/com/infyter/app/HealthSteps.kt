package com.infyter.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.health.connect.AggregateRecordsRequest
import android.health.connect.AggregateRecordsResponse
import android.health.connect.HealthConnectException
import android.health.connect.HealthConnectManager
import android.health.connect.TimeInstantRangeFilter
import android.health.connect.datatypes.StepsRecord
import android.os.Build
import android.os.OutcomeReceiver
import android.os.ext.SdkExtensions
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

// Daily steps from Health Connect, which counts the phone's steps by itself on Android 14+ even with the app closed.
// Read only, in the foreground; which source wins in Health Connect is the user's choice there.
class HealthSteps(private val activity: Activity, messenger: BinaryMessenger) {
    private val methods = MethodChannel(messenger, "infyter/health_steps")
    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val waiting = mutableListOf<MethodChannel.Result>()

    init {
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(supported())
                "permissionStatus" -> result.success(permissionStatus())
                "requestPermission" -> requestPermission(result)
                "readDays" -> readDays(call, result)
                "openSettings" -> result.success(openSettings())
                else -> result.notImplemented()
            }
        }
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        // Empty results mean the request was interrupted, not answered.
        if (grantResults.isNotEmpty() && !granted()) prefs.edit().putBoolean(DENIED, true).apply()
        answerWaiting()
    }

    fun dispose() {
        answerWaiting()
        methods.setMethodCallHandler(null)
    }

    private fun answerWaiting() {
        val answer = permissionStatus()
        val results = waiting.toList()
        waiting.clear()
        results.forEach { it.success(answer) }
    }

    // The check the steps guide gives for on-device step counting: Android 14 with SDK extension 20 or higher.
    private fun supported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        if (activity.packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH)) return false
        return try {
            SdkExtensions.getExtensionVersion(Build.VERSION_CODES.UPSIDE_DOWN_CAKE) >= MIN_EXTENSION &&
                Api34.manager(activity) != null
        } catch (e: Exception) {
            false
        }
    }

    private fun granted(): Boolean =
        activity.checkSelfPermission(READ_STEPS) == PackageManager.PERMISSION_GRANTED

    private fun permissionStatus(): String = when {
        !supported() -> "denied"
        granted() -> {
            if (prefs.contains(DENIED)) prefs.edit().remove(DENIED).apply()
            "granted"
        }
        prefs.getBoolean(DENIED, false) -> "denied"
        else -> "notDetermined"
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (!supported() || granted()) {
            result.success(permissionStatus())
            return
        }
        waiting.add(result)
        if (waiting.size > 1) return
        try {
            activity.requestPermissions(arrayOf(READ_STEPS), PERMISSION_REQUEST)
        } catch (e: Exception) {
            val failed = waiting.toList()
            waiting.clear()
            failed.forEach { it.error("request-failed", e.message, null) }
        }
    }

    private fun readDays(call: MethodCall, result: MethodChannel.Result) {
        val days = (call.argument<Number>("days")?.toInt() ?: 1).coerceIn(1, MAX_DAYS)
        val fromMs = call.argument<Number>("fromMs")?.toLong()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE || !supported() || !granted()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        Api34.readDays(activity, days, fromMs) { result.success(it) }
    }

    private fun openSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        val intent = Intent(Api34.MANAGE_PERMISSIONS).putExtra(Intent.EXTRA_PACKAGE_NAME, activity.packageName)
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private object Api34 {
        const val MANAGE_PERMISSIONS = HealthConnectManager.ACTION_MANAGE_HEALTH_PERMISSIONS

        fun manager(context: Context): HealthConnectManager? =
            context.getSystemService(HealthConnectManager::class.java)

        // One aggregate per local day, oldest first; a day with no data, 0 steps or an error is left out (a gap, never 0).
        fun readDays(context: Context, days: Int, fromMs: Long?, done: (List<Map<String, Any>>) -> Unit) {
            val manager = manager(context)
            if (manager == null) {
                done(emptyList())
                return
            }
            val zone = ZoneId.systemDefault()
            val now = Instant.now()
            val today = LocalDate.now(zone)
            val from = fromMs?.let { Instant.ofEpochMilli(it) }
            val ranges = (days - 1 downTo 0).mapNotNull { back ->
                val date = today.minusDays(back.toLong())
                val end = minOf(date.plusDays(1).atStartOfDay(zone).toInstant(), now)
                var start = date.atStartOfDay(zone).toInstant()
                if (from != null && from.isAfter(start)) start = from
                if (start.isBefore(end)) DayRange(date.toString(), start, end) else null
            }
            val out = mutableListOf<Map<String, Any>>()
            fun next(index: Int) {
                if (index >= ranges.size) {
                    done(out)
                    return
                }
                val range = ranges[index]
                val filter = TimeInstantRangeFilter.Builder().setStartTime(range.start).setEndTime(range.end).build()
                val request = AggregateRecordsRequest.Builder<Long>(filter)
                    .addAggregationType(StepsRecord.STEPS_COUNT_TOTAL)
                    .build()
                try {
                    manager.aggregate(
                        request,
                        context.mainExecutor,
                        object : OutcomeReceiver<AggregateRecordsResponse<Long>, HealthConnectException> {
                            override fun onResult(response: AggregateRecordsResponse<Long>) {
                                val steps = response.get(StepsRecord.STEPS_COUNT_TOTAL)
                                if (steps != null && steps > 0) out.add(mapOf("day" to range.day, "steps" to steps))
                                next(index + 1)
                            }

                            override fun onError(error: HealthConnectException) = next(index + 1)
                        },
                    )
                } catch (e: Exception) {
                    next(index + 1)
                }
            }
            next(0)
        }
    }

    private class DayRange(val day: String, val start: Instant, val end: Instant)

    private companion object {
        const val PREFS = "infyter_steps"
        const val DENIED = "hc_denied"
        const val READ_STEPS = "android.permission.health.READ_STEPS"
        const val PERMISSION_REQUEST = 7462
        const val MIN_EXTENSION = 20
        const val MAX_DAYS = 7
    }
}
