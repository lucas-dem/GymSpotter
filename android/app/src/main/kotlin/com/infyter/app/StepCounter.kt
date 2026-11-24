package com.infyter.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Raw step sensor readings, permission and availability; which day the steps belong to is decided in Dart (step_anchor.dart).
class StepCounter(private val activity: Activity, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "infyter/steps")
    private val events = EventChannel(messenger, "infyter/steps/events")
    private val sensors = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager?
    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())
    private val reads = mutableSetOf<OneRead>()
    private val waiting = mutableListOf<MethodChannel.Result>()
    private var watcher: SensorEventListener? = null
    private var rationaleBefore = false

    init {
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isAvailable())
                "permissionStatus" -> result.success(permissionStatus())
                "requestPermission" -> requestPermission(result)
                "readCounter" -> readOnce(result)
                "loadAnchor" -> result.success(prefs.getString(ANCHOR, null))
                "saveAnchor" -> {
                    val anchor = call.argument<String>("anchor")
                    if (anchor == null) {
                        result.error("bad-args", "anchor missing", null)
                    } else {
                        prefs.edit().putString(ANCHOR, anchor).apply()
                        result.success(null)
                    }
                }
                "clearAnchor" -> {
                    prefs.edit().remove(ANCHOR).apply()
                    result.success(null)
                }
                "forget" -> {
                    // A "deny for good" lives on in Android; forgetting it would make the next "Activar" ask silently.
                    val keepAsked = permissionStatus() == "denied"
                    val edit = prefs.edit().remove(ANCHOR).remove(SILENT)
                    if (!keepAsked) edit.remove(ASKED)
                    edit.apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        events.setStreamHandler(this)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        if (grantResults.any { it != PackageManager.PERMISSION_GRANTED }) {
            // A tap outside the dialog (Android 11+) is a silent "no"; two in a row also mean no dialog is shown any more.
            val silent = if (rationaleBefore || rationale()) SILENT_TO_MARK else prefs.getInt(SILENT, 0) + 1
            if (silent >= SILENT_TO_MARK) {
                prefs.edit().putBoolean(ASKED, true).remove(SILENT).apply()
            } else {
                prefs.edit().putInt(SILENT, silent).apply()
            }
        }
        val answer = permissionStatus()
        val results = waiting.toList()
        waiting.clear()
        results.forEach { it.success(answer) }
    }

    fun dispose() {
        stopWatching()
        reads.toList().forEach { it.finish(null) }
        onPermissionResult(PERMISSION_REQUEST, IntArray(0))
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        stopWatching()
        val manager = sensors ?: return
        val sensor = stepSensor() ?: return
        if (!granted()) return
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                sink.success(reading(event))
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        if (manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)) watcher = listener
    }

    override fun onCancel(arguments: Any?) = stopWatching()

    private fun stopWatching() {
        watcher?.let { sensors?.unregisterListener(it) }
        watcher = null
    }

    private fun stepSensor(): Sensor? = sensors?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

    private fun isAvailable(): Boolean {
        val packages = activity.packageManager
        if (packages.hasSystemFeature(PackageManager.FEATURE_WATCH)) return false
        // Before ACTIVITY_RECOGNITION is granted some Android versions hide the sensor from the list, but not the feature.
        return packages.hasSystemFeature(PackageManager.FEATURE_SENSOR_STEP_COUNTER) || stepSensor() != null
    }

    private fun granted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            activity.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED

    // After one "deny" Android still shows the dialog again; settings are only needed once it stops showing it.
    private fun permissionStatus(): String = when {
        granted() -> {
            if (prefs.contains(ASKED) || prefs.contains(SILENT)) prefs.edit().remove(ASKED).remove(SILENT).apply()
            "granted"
        }
        !prefs.getBoolean(ASKED, false) -> "notDetermined"
        rationale() -> "notDetermined"
        else -> "denied"
    }

    private fun rationale(): Boolean =
        activity.shouldShowRequestPermissionRationale(Manifest.permission.ACTIVITY_RECOGNITION)

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || granted()) {
            result.success("granted")
            return
        }
        waiting.add(result)
        if (waiting.size > 1) return
        rationaleBefore = rationale()
        try {
            activity.requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), PERMISSION_REQUEST)
        } catch (e: Exception) {
            val failed = waiting.toList()
            waiting.clear()
            failed.forEach { it.error("request-failed", e.message, null) }
        }
    }

    private fun readOnce(result: MethodChannel.Result) {
        val manager = sensors
        val sensor = stepSensor()
        if (manager == null || sensor == null || !granted()) {
            result.success(null)
            return
        }
        val read = OneRead(result)
        reads.add(read)
        if (!manager.registerListener(read, sensor, SensorManager.SENSOR_DELAY_NORMAL)) {
            read.finish(null)
            return
        }
        handler.postDelayed(read, READ_TIMEOUT_MS)
    }

    // Dated with the event's own time (elapsedRealtime base), so a cached value is not taken as counted now.
    private fun reading(event: SensorEvent): Map<String, Long> {
        val nowElapsed = SystemClock.elapsedRealtime()
        val nowWall = System.currentTimeMillis()
        val eventElapsed = event.timestamp / 1_000_000L
        val at = if (eventElapsed in 0..nowElapsed) eventElapsed else nowElapsed
        return mapOf(
            "counter" to event.values[0].toLong(),
            "wallMs" to nowWall - (nowElapsed - at),
            "elapsedMs" to at,
            "bootCount" to bootCount(),
        )
    }

    private fun bootCount(): Long = try {
        Settings.Global.getInt(activity.contentResolver, Settings.Global.BOOT_COUNT, -1).toLong()
    } catch (e: Exception) {
        -1L
    }

    private inner class OneRead(private val result: MethodChannel.Result) : SensorEventListener, Runnable {
        override fun onSensorChanged(event: SensorEvent) = finish(reading(event))

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

        override fun run() = finish(null)

        fun finish(value: Map<String, Long>?) {
            if (!reads.remove(this)) return
            handler.removeCallbacks(this)
            sensors?.unregisterListener(this)
            result.success(value)
        }
    }

    private companion object {
        const val PREFS = "infyter_steps"
        const val ASKED = "permission_asked"
        const val ANCHOR = "infyter_steps_anchor_v1"
        const val PERMISSION_REQUEST = 7461
        const val READ_TIMEOUT_MS = 3000L
        const val SILENT = "silent_denials"
        const val SILENT_TO_MARK = 2
    }
}
