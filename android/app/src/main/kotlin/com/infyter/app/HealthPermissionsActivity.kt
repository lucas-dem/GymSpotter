package com.infyter.app

import android.app.Activity
import android.graphics.Typeface
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.BulletSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
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
            text = render(PolicyMarkdown.parse(policy), pad / 2)
            textSize = 15f
            setTextIsSelectable(true)
            setPadding(pad, pad, pad, pad)
        }
        setContentView(ScrollView(this).apply {
            fitsSystemWindows = true
            addView(body)
        })
    }

    private fun render(blocks: List<PolicyMarkdown.Block>, bulletGap: Int): CharSequence {
        val out = SpannableStringBuilder()
        blocks.forEachIndexed { index, block ->
            if (index > 0) out.append(if (block is PolicyMarkdown.Block.Item && blocks[index - 1] is PolicyMarkdown.Block.Item) "\n" else "\n\n")
            val start = out.length
            when (block) {
                is PolicyMarkdown.Block.Heading -> {
                    out.append(block.text)
                    out.setSpan(StyleSpan(Typeface.BOLD), start, out.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    out.setSpan(RelativeSizeSpan(if (block.level == 1) 1.35f else 1.15f), start, out.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                is PolicyMarkdown.Block.Paragraph -> out.append(block.text)
                is PolicyMarkdown.Block.Item -> {
                    out.append(block.number?.let { "$it. ${block.text}" } ?: block.text)
                    if (block.number == null) {
                        out.setSpan(BulletSpan(bulletGap), start, out.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    }
                }
            }
        }
        return out
    }
}

// Turns the shipped Markdown into plain blocks: headings, paragraphs with their hard wraps joined, and list items.
object PolicyMarkdown {
    sealed class Block {
        data class Heading(val level: Int, val text: String) : Block()
        data class Paragraph(val text: String) : Block()
        data class Item(val number: String?, val text: String) : Block()
    }

    private val heading = Regex("^(#{1,6})\\s+(.*?)\\s*#*\\s*$")
    private val bullet = Regex("^\\s*[-*+]\\s+(.*)$")
    private val ordered = Regex("^\\s*(\\d+)[.)]\\s+(.*)$")
    private val rule = Regex("^\\s*([-*_])(\\s*\\1){2,}\\s*$")

    fun parse(markdown: String): List<Block> {
        val blocks = mutableListOf<Block>()
        val pending = StringBuilder()
        var pendingNumber: String? = null
        var pendingItem = false

        fun flush() {
            if (pending.isEmpty()) return
            val text = inline(pending.toString())
            blocks += if (pendingItem) Block.Item(pendingNumber, text) else Block.Paragraph(text)
            pending.setLength(0)
            pendingItem = false
            pendingNumber = null
        }

        fun append(text: String) {
            if (pending.isNotEmpty()) pending.append(' ')
            pending.append(text.trim())
        }

        for (line in markdown.replace("\r\n", "\n").split('\n')) {
            if (line.isBlank() || rule.matches(line)) {
                flush()
                continue
            }
            val h = heading.find(line)
            if (h != null) {
                flush()
                blocks += Block.Heading(h.groupValues[1].length, inline(h.groupValues[2]))
                continue
            }
            val b = bullet.find(line)
            val o = if (b == null) ordered.find(line) else null
            if (b != null || o != null) {
                flush()
                pendingItem = true
                pendingNumber = o?.groupValues?.get(1)
                append(b?.groupValues?.get(1) ?: o!!.groupValues[2])
                continue
            }
            append(line)
        }
        flush()
        return blocks
    }

    private val link = Regex("\\[([^\\]]*)]\\(([^)]*)\\)")
    private val autolink = Regex("<((?:https?://|mailto:)[^>]+)>")
    private val code = Regex("`([^`]*)`")
    private val strong = Regex("(\\*\\*|__)(.+?)\\1")
    private val emphasis = Regex("(?<![\\w*])\\*(?!\\s)(.+?)(?<!\\s)\\*(?![\\w*])")
    private val escaped = Regex("\\\\([\\\\`*_{}\\[\\]()#+\\-.!])")

    private const val SHELTER = 0xE000

    fun inline(text: String): String = escaped
        .replace(text) { (SHELTER + it.groupValues[1][0].code).toChar().toString() }
        .replace(link, "$1")
        .replace(autolink, "$1")
        .replace(code, "$1")
        .replace(strong, "$2")
        .replace(emphasis, "$1")
        .map { if (it.code in SHELTER until SHELTER + 0x80) (it.code - SHELTER).toChar() else it }
        .joinToString("")
}
