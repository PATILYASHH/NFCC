package com.nfccontrol.nfcc_mobile

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Method-channel handler for `nfcc/smart_switch`. Exposes:
 *
 *  capture()                       → Map<String, Any?>  payload to ship to PC
 *  hasAccessibilityPermission()    → Bool
 *  hasUsageStatsPermission()       → Bool
 *  hasNotificationListenerPerm()   → Bool
 *  openAccessibilitySettings()
 *  openUsageStatsSettings()
 *  openNotificationListenerSettings()
 *
 * Capture is foreground-first: the foreground package decides which app
 * we're handing off, and MediaSession is consulted only when that app is
 * itself a media app. A backgrounded music player never wins over the
 * app the user is actually looking at.
 */
class SmartSwitchCapture(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "nfcc/smart_switch"

        // Foreground packages that we know how to capture as media handoffs.
        // YT Music variants stay tagged "youtube" — the YouTubeUrlNormalizer
        // preserves music.youtube.com URLs so they hand off to the desktop
        // YT Music PWA / browser correctly.
        private val MEDIA_PACKAGES = mapOf(
            "com.google.android.youtube" to "youtube",
            "app.revanced.android.youtube" to "youtube",
            "app.rvx.android.youtube" to "youtube", // ReVanced eXtended
            "com.google.android.apps.youtube.music" to "youtube",
            "app.revanced.android.apps.youtube.music" to "youtube", // ReVanced YT Music
            "app.rvx.android.apps.youtube.music" to "youtube",      // RVX YT Music
            "com.spotify.music" to "spotify",
        )

        // Browsers — handed off as `kind: "browser"` with the URL bar value.
        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "com.chrome.beta", "com.chrome.dev", "com.chrome.canary",
            "com.brave.browser",
            "com.microsoft.emmx",
            "org.mozilla.firefox", "org.mozilla.focus",
            "com.duckduckgo.mobile.android",
            "com.sec.android.app.sbrowser",
            "com.opera.browser",
            "com.kiwibrowser.browser",
            "com.vivaldi.browser",
        )

        private val WHATSAPP_PACKAGES = setOf("com.whatsapp", "com.whatsapp.w4b")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "capture" -> result.success(capture())
                "hasAccessibilityPermission" -> result.success(hasAccessibility())
                "hasUsageStatsPermission" -> result.success(hasUsageStats())
                "hasNotificationListenerPerm" -> result.success(hasNotificationListener())
                "openAccessibilitySettings" -> {
                    open(Settings.ACTION_ACCESSIBILITY_SETTINGS); result.success(true)
                }
                "openUsageStatsSettings" -> {
                    open(Settings.ACTION_USAGE_ACCESS_SETTINGS); result.success(true)
                }
                "openNotificationListenerSettings" -> {
                    open(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS); result.success(true)
                }
                "openAppInfo" -> {
                    // For Android 13+ Restricted Settings: user must open
                    // App Info → ⋮ → Allow restricted settings before
                    // Accessibility can be toggled on for sideloaded APKs.
                    val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", context.packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(i)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("smart_switch_error", e.message, null)
        }
    }

    // ── Capture ──────────────────────────────────────────────────────────

    private fun capture(): Map<String, Any?> {
        // If NfcReceiverActivity stashed a snapshot in the last 15s, that
        // is the truth — it was the foreground at the moment of tap, before
        // anything else (NFCC's own UI, the system NFC overlay, etc.) won
        // focus. Only fall back to the live snap when there's nothing
        // pinned.
        consumePinnedNfcSnapshot()?.let { pinned ->
            val fg = pinned.foregroundPackage ?: return@let null
            return classify(fg, pinned)
        }

        val fg = resolveForegroundPackage()
            ?: return mapOf("kind" to "generic")
        return classify(fg, SmartSwitchAccessibilityService.latest)
    }

    private fun classify(
        fg: String,
        snap: SmartSwitchAccessibilityService.Snapshot,
    ): Map<String, Any?> {
        val appName = readAppLabel(fg)
        return when {
            MEDIA_PACKAGES[fg] != null -> captureMedia(fg, appName, MEDIA_PACKAGES.getValue(fg))
            fg in BROWSER_PACKAGES -> captureBrowserFromSnap(fg, appName, snap)
            fg in WHATSAPP_PACKAGES -> captureWhatsAppFromSnap(fg, appName, snap)
            else -> mapOf(
                "kind" to "generic",
                "appPkg" to fg,
                "appName" to appName,
            )
        }
    }

    /**
     * Read and clear the NFC-tap snapshot if it was saved within the last
     * 15 seconds AND its accessibility-capture timestamp is not way older
     * than that (stale snap means the user wasn't actively in any tracked
     * app — cleanest fallback is the live path).
     */
    private fun consumePinnedNfcSnapshot(): SmartSwitchAccessibilityService.Snapshot? {
        val prefs = context.getSharedPreferences(
            "nfcc_smart_switch_snapshot", Context.MODE_PRIVATE
        )
        val savedAt = prefs.getLong("savedAtMs", 0L)
        if (savedAt == 0L) return null
        val ageMs = System.currentTimeMillis() - savedAt
        // Always clear so a stale entry never leaks into a later tap.
        prefs.edit().clear().apply()
        if (ageMs < 0 || ageMs > 15_000) return null
        val fg = prefs.getString("foregroundPackage", null) ?: return null
        // Defensive: even if the accessibility service didn't filter, the
        // PC should never receive NFCC / NFC handler / shell as the
        // "current page" — that's a bug, not a handoff target.
        if (!isUserVisibleApp(fg)) return null
        return SmartSwitchAccessibilityService.Snapshot(
            foregroundPackage = fg,
            browserUrl = prefs.getString("browserUrl", null),
            whatsappChatTitle = prefs.getString("whatsappChatTitle", null),
            whatsappDraft = prefs.getString("whatsappDraft", null),
            capturedAtMs = prefs.getLong("capturedAtMs", 0L),
        )
    }

    private fun captureMedia(pkg: String, appName: String?, kind: String): Map<String, Any?> {
        val reading = MediaSessionReader.readForPackage(context, pkg)
        val rawUrl = reading?.mediaUri
        val positionMs = reading?.positionMs ?: 0L

        return when (kind) {
            "youtube" -> {
                val isMusic = pkg.contains(".youtube.music", ignoreCase = true) ||
                              pkg.endsWith(".apps.youtube.music", ignoreCase = true)
                val normalized = YouTubeUrlNormalizer.normalize(
                    rawUrl, positionMs, forceMusicHost = isMusic,
                )
                mapOf(
                    "kind" to "youtube",
                    "url" to normalized,
                    "appPkg" to pkg,
                    "appName" to appName,
                    "positionMs" to positionMs,
                    "rawUrl" to rawUrl, // for debugging
                )
            }
            "spotify" -> {
                // Prefer https://open.spotify.com/... when we get it.
                val url = if (rawUrl?.startsWith("https://open.spotify.com/") == true) rawUrl
                else if (rawUrl?.startsWith("spotify:") == true) spotifyUriToWeb(rawUrl)
                else null
                mapOf(
                    "kind" to "spotify",
                    "url" to url,
                    "appPkg" to pkg,
                    "appName" to appName,
                    "positionMs" to positionMs,
                )
            }
            else -> mapOf("kind" to "generic", "appPkg" to pkg, "appName" to appName)
        }
    }

    private fun captureBrowserFromSnap(
        pkg: String,
        appName: String?,
        snap: SmartSwitchAccessibilityService.Snapshot,
    ): Map<String, Any?> {
        var url = if (snap.foregroundPackage == pkg) snap.browserUrl else null
        // Snap URL can be stale-null when the URL bar was scrolled off-
        // screen at last event. Force a fresh scrape before giving up.
        if (url.isNullOrBlank()) {
            val fresh = SmartSwitchAccessibilityService.refreshNowIfPossible()
            if (fresh != null && fresh.foregroundPackage == pkg) {
                url = fresh.browserUrl
            }
        }
        return mapOf(
            "kind" to "browser",
            "url" to ensureScheme(url),
            "appPkg" to pkg,
            "appName" to appName,
        )
    }

    private fun captureWhatsAppFromSnap(
        pkg: String,
        appName: String?,
        snap: SmartSwitchAccessibilityService.Snapshot,
    ): Map<String, Any?> {
        val matches = snap.foregroundPackage == pkg
        return mapOf(
            "kind" to "whatsapp",
            "appPkg" to pkg,
            "appName" to appName,
            "chatHint" to if (matches) snap.whatsappChatTitle else null,
            "draftText" to if (matches) snap.whatsappDraft else null,
        )
    }

    private fun ensureScheme(url: String?): String? {
        if (url.isNullOrBlank()) return null
        val v = url.trim()
        return if (v.startsWith("http://") || v.startsWith("https://")) v
        else "https://$v"
    }

    private fun spotifyUriToWeb(uri: String): String? {
        // spotify:track:abc → https://open.spotify.com/track/abc
        val parts = uri.removePrefix("spotify:").split(":")
        if (parts.size < 2) return null
        return "https://open.spotify.com/${parts.joinToString("/")}"
    }

    // ── Foreground resolution ────────────────────────────────────────────

    /**
     * Order of truth:
     *   1. Accessibility cache (most accurate, updates on TYPE_WINDOW_STATE_CHANGED)
     *   2. UsageStatsManager fallback for the last-foreground app within ~10s
     */
    private fun resolveForegroundPackage(): String? {
        val snap = SmartSwitchAccessibilityService.latest
        if (snap.foregroundPackage != null &&
            System.currentTimeMillis() - snap.capturedAtMs < 30_000
        ) {
            return snap.foregroundPackage
        }
        return queryUsageStatsForeground()
    }

    private fun queryUsageStatsForeground(): String? {
        if (!hasUsageStats()) return null
        return try {
            val mgr = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: return null
            val now = System.currentTimeMillis()
            val stats = mgr.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY, now - 60_000, now
            )
            // Pick the most-recent app the user actually had on screen —
            // ignore NFCC itself, the NFC handler, the launcher and other
            // system shell packages, otherwise we'd hand off NFCC's own
            // window to the PC after a cold-start tap.
            stats?.asSequence()
                ?.filter { isUserVisibleApp(it.packageName) }
                ?.maxByOrNull { it.lastTimeUsed }
                ?.packageName
        } catch (_: Exception) { null }
    }

    private fun isUserVisibleApp(pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        if (pkg == context.packageName) return false
        if (pkg == "com.android.nfc") return false
        if (pkg == "com.android.systemui") return false
        if (pkg == "com.android.shell") return false
        if (pkg == "android") return false
        if (pkg.startsWith("com.android.launcher")) return false
        if (pkg.contains(".inputmethod") || pkg.contains(".keyboard")) return false
        return true
    }

    // ── Permission checks ────────────────────────────────────────────────

    private fun hasAccessibility(): Boolean {
        // Two signals: instance is alive, OR registered in secure settings.
        if (SmartSwitchAccessibilityService.isEnabled()) return true
        return try {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val expected = ComponentName(
                context, SmartSwitchAccessibilityService::class.java
            ).flattenToString()
            enabled.split(":").any { it.equals(expected, ignoreCase = true) }
        } catch (_: Exception) { false }
    }

    private fun hasUsageStats(): Boolean {
        return try {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(), context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(), context.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) { false }
    }

    private fun hasNotificationListener(): Boolean {
        return try {
            val flat = Settings.Secure.getString(
                context.contentResolver, "enabled_notification_listeners"
            ) ?: return false
            val expected = ComponentName(
                context, SmartSwitchNotificationListener::class.java
            ).flattenToString()
            flat.split(":").any { it.equals(expected, ignoreCase = true) }
        } catch (_: Exception) { false }
    }

    private fun open(action: String) {
        val i = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(i)
    }

    private fun readAppLabel(pkg: String): String? = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { null }
}
