package com.infyter.app

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

// Opened by Health Connect from "Privacy policy": the same PRIVACY.md the app ships, without internet.
class HealthPermissionsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val policy = try {
            assets.open("flutter_assets/PRIVACY.md").bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            ""
        }
        val pad = (20 * resources.displayMetrics.density).toInt()
        val body = TextView(this).apply {
            text = policy
            textSize = 15f
            setTextIsSelectable(true)
            setPadding(pad, pad, pad, pad)
        }
        setContentView(ScrollView(this).apply {
            fitsSystemWindows = true
            addView(body)
        })
    }
}
