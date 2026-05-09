package com.nfccontrol.nfcc_mobile

import android.app.PendingIntent
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var nfcAdapter: NfcAdapter? = null
    private var eventSink: EventChannel.EventSink? = null
    private val TAG = "NFCC"
    private val NFC_CHANNEL = "com.nfccontrol/nfc_intent"
    private val NFC_EVENT_CHANNEL = "com.nfccontrol/nfc_events"

    // Queue tag data if EventChannel is not yet connected
    private var pendingTagData: Map<String, Any?>? = null

    // When true, foreground dispatch is disabled so nfc_manager plugin can handle tags
    private var foregroundDispatchSuppressed = false

    // True when this activity was started by NfcReceiverActivity to flush
    // a queued NFC tap on a cold start. Triggers moveTaskToBack once
    // Flutter reports it's done dispatching.
    private var coldStartDispatch = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nfcAdapter = NfcAdapter.getDefaultAdapter(this)

        // Method channel for queries + vibration + foreground dispatch control
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNfcAvailable" -> result.success(nfcAdapter != null && nfcAdapter!!.isEnabled)
                    "vibrate" -> {
                        val rawPattern = call.argument<List<Int>>("pattern") ?: listOf(0, 150)
                        val pattern = rawPattern.map { it.toLong() }.toLongArray()
                        vibrateDevice(pattern)
                        result.success(true)
                    }
                    "disableForegroundDispatch" -> {
                        foregroundDispatchSuppressed = true
                        disableForegroundDispatch()
                        Log.d(TAG, "Foreground dispatch suppressed by Flutter")
                        result.success(true)
                    }
                    "enableForegroundDispatch" -> {
                        foregroundDispatchSuppressed = false
                        enableForegroundDispatch()
                        Log.d(TAG, "Foreground dispatch re-enabled by Flutter")
                        result.success(true)
                    }
                    "retreatIfColdStartDispatch" -> {
                        // Flutter says "I'm done dispatching that NFC tap" —
                        // if we were launched purely to handle the tag (cold
                        // start), drop NFCC back to the system stack so the
                        // user stays in whatever app they were in.
                        if (coldStartDispatch) {
                            Log.d(TAG, "Cold-start dispatch done — moveTaskToBack")
                            coldStartDispatch = false
                            moveTaskToBack(true)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Device state channel - checks BT/WiFi state for conditions
        val STATE_CHANNEL = "com.nfccontrol/device_state"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STATE_CHANNEL)
            .setMethodCallHandler(DeviceStateChecker(this))

        // Phone actions channel - executes real device actions
        val PHONE_ACTIONS_CHANNEL = "com.nfccontrol/phone_actions"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PHONE_ACTIONS_CHANNEL)
            .setMethodCallHandler(PhoneActionExecutor(this))

        // Smart Switch channel - captures foreground app/URL/draft for PC handoff
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SmartSwitchCapture.CHANNEL)
            .setMethodCallHandler(SmartSwitchCapture(this))

        // Event channel for streaming NFC tag data to Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    Log.d(TAG, "EventChannel connected")

                    // Register callback for NfcReceiverActivity (background NFC)
                    NfcReceiverActivity.onTagReceived = { uid, ndefText ->
                        val data = mapOf("uid" to uid, "ndefText" to ndefText)
                        runOnUiThread { eventSink?.success(data) }
                    }

                    // Send any pending tag data
                    pendingTagData?.let {
                        events?.success(it)
                        pendingTagData = null
                        Log.d(TAG, "Sent pending tag data")
                    }
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // If NfcReceiverActivity launched us purely to flush a queued tap,
        // remember it so we can call moveTaskToBack once Flutter is done.
        coldStartDispatch =
            intent?.getBooleanExtra("nfcc_cold_start_dispatch", false) == true

        // Handle intent that launched this activity (cold start)
        handleNfcIntent(intent)

        // Check for pending NFC tags saved by NfcReceiverActivity when app was killed
        checkPendingTag()
    }

    private fun checkPendingTag() {
        val prefs = getSharedPreferences("nfcc_pending_tag", MODE_PRIVATE)
        val uid = prefs.getString("uid", null) ?: return
        val timestamp = prefs.getLong("timestamp", 0)

        // Only process if less than 60 seconds old
        if (System.currentTimeMillis() - timestamp > 60_000) {
            prefs.edit().clear().apply()
            return
        }

        val ndefText = prefs.getString("ndefText", null)
        prefs.edit().clear().apply()

        Log.d(TAG, "Found pending NFC tag: uid=$uid ndef=$ndefText")
        pendingTagData = mapOf("uid" to uid, "ndefText" to ndefText, "action" to "pending_recovery")
    }

    override fun onResume() {
        super.onResume()
        if (!foregroundDispatchSuppressed) {
            enableForegroundDispatch()
        }
    }

    override fun onPause() {
        super.onPause()
        disableForegroundDispatch()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("nfcc_cold_start_dispatch", false)) {
            coldStartDispatch = true
        }
        // Foreground dispatch delivers NFC here when app is visible
        handleNfcIntent(intent)
    }

    private fun isNfcIntent(intent: Intent?): Boolean {
        val action = intent?.action ?: return false
        return action == NfcAdapter.ACTION_NDEF_DISCOVERED ||
               action == NfcAdapter.ACTION_TECH_DISCOVERED ||
               action == NfcAdapter.ACTION_TAG_DISCOVERED
    }

    private fun enableForegroundDispatch() {
        val adapter = nfcAdapter ?: return
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_MUTABLE
        )
        // Only catch our custom MIME type - let system handle URLs, UPI, etc.
        val filters = arrayOf(
            IntentFilter(NfcAdapter.ACTION_NDEF_DISCOVERED).apply {
                try { addDataType("application/com.nfccontrol.nfcc") } catch (_: Exception) {}
            }
        )
        try {
            adapter.enableForegroundDispatch(this, pendingIntent, filters, null)
            Log.d(TAG, "Foreground dispatch enabled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enable foreground dispatch: ${e.message}")
        }
    }

    private fun disableForegroundDispatch() {
        try {
            nfcAdapter?.disableForegroundDispatch(this)
        } catch (_: Exception) {}
    }

    private fun handleNfcIntent(intent: Intent?) {
        if (!isNfcIntent(intent)) return

        Log.d(TAG, "NFC intent received: ${intent?.action}")

        // Extract tag UID
        val tag: Tag? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(NfcAdapter.EXTRA_TAG, Tag::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(NfcAdapter.EXTRA_TAG)
        }
        val uid = tag?.id?.joinToString(":") { "%02X".format(it) } ?: "UNKNOWN"

        // Extract NDEF records
        var ndefText: String? = null
        var externalUri: String? = null
        var isOurMimeType = false
        val rawMessages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES, NdefMessage::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES)
        }

        if (rawMessages != null && rawMessages.isNotEmpty()) {
            val msg = rawMessages[0] as NdefMessage
            for (record in msg.records) {
                // Our custom MIME type: application/com.nfccontrol.nfcc
                if (record.tnf == android.nfc.NdefRecord.TNF_MIME_MEDIA) {
                    val mimeType = String(record.type, Charsets.UTF_8)
                    if (mimeType == "application/com.nfccontrol.nfcc") {
                        ndefText = String(record.payload, Charsets.UTF_8)
                        isOurMimeType = true
                        break
                    }
                }
                // URI record (UPI, URLs, tel:, mailto:, etc.)
                if (record.tnf == android.nfc.NdefRecord.TNF_WELL_KNOWN) {
                    val typeStr = String(record.type, Charsets.UTF_8)
                    if (typeStr == "U" && record.payload.isNotEmpty()) {
                        // URI record - extract full URI
                        val prefixCode = record.payload[0].toInt() and 0xFF
                        val uriBody = String(record.payload, 1, record.payload.size - 1, Charsets.UTF_8)
                        externalUri = URI_PREFIXES.getOrElse(prefixCode) { "" } + uriBody
                        Log.d(TAG, "Found URI record: $externalUri")
                    } else if (typeStr == "T" && record.payload.isNotEmpty()) {
                        // Text record (legacy)
                        val langLength = (record.payload[0].toInt() and 0x3F)
                        if (record.payload.size > langLength + 1) {
                            ndefText = String(record.payload, langLength + 1, record.payload.size - langLength - 1, Charsets.UTF_8)
                        }
                    }
                }
            }
        }

        // If this is NOT our MIME type but has a URI, dispatch to system
        if (!isOurMimeType && externalUri != null) {
            Log.d(TAG, "External URI tag detected, dispatching to system: $externalUri")
            try {
                val uriIntent = Intent(Intent.ACTION_VIEW, Uri.parse(externalUri))
                uriIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(uriIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to dispatch URI: ${e.message}")
            }
            return
        }

        Log.d(TAG, "Tag UID: $uid, NDEF: $ndefText")

        // Handle UPI payment tags: payload format "UPI:<package>:<uri>"
        if (isOurMimeType && ndefText != null && ndefText!!.startsWith("UPI:")) {
            val parts = ndefText!!.substring(4).split(":", limit = 2)
            if (parts.size == 2) {
                val packageName = parts[0]
                val upiUri = parts[1]
                Log.d(TAG, "UPI tag detected! package=$packageName uri=$upiUri")
                try {
                    val upiIntent = Intent(Intent.ACTION_VIEW, Uri.parse(upiUri))
                    upiIntent.setPackage(packageName)
                    upiIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(upiIntent)
                    Log.d(TAG, "Launched UPI app: $packageName")
                } catch (e: Exception) {
                    // App not installed — try without package restriction
                    Log.w(TAG, "App $packageName not found, trying generic: ${e.message}")
                    try {
                        val fallback = Intent(Intent.ACTION_VIEW, Uri.parse(upiUri))
                        fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(fallback)
                    } catch (e2: Exception) {
                        Log.e(TAG, "No UPI app found: ${e2.message}")
                    }
                }
                return
            }
        }

        val data = mapOf(
            "uid" to uid,
            "ndefText" to ndefText,
            "action" to intent?.action
        )

        // Send to Flutter for automation execution
        runOnUiThread {
            if (eventSink != null) {
                eventSink?.success(data)
                Log.d(TAG, "Sent tag data to Flutter")
            } else {
                // Queue for when EventChannel connects
                pendingTagData = data
                Log.d(TAG, "EventChannel not ready, queued tag data")
            }
        }
    }

    companion object {
        // NFC Forum URI prefix codes
        private val URI_PREFIXES = mapOf(
            0 to "",
            1 to "http://www.",
            2 to "https://www.",
            3 to "http://",
            4 to "https://",
            5 to "tel:",
            6 to "mailto:",
        )
    }

    @Suppress("DEPRECATION")
    private fun vibrateDevice(pattern: LongArray) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
                val vibrator = mgr.defaultVibrator
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
                } else {
                    vibrator.vibrate(pattern, -1)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Vibration failed: ${e.message}")
        }
    }
}
