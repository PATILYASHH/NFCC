package com.nfccontrol.nfcc_mobile

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Watches accessibility events to keep a small in-memory cache of:
 *  - the package currently in the foreground
 *  - if it's a browser, the URL shown in the omnibox
 *  - if it's WhatsApp, the chat title + the text in the compose box
 *
 * Cache is read by MainActivity at NFC-tap time (Smart Switch action).
 * Nothing is persisted, logged off-device, or sent anywhere on its own.
 */
class SmartSwitchAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "NFCCSmartSwitch"

        // Browsers we know expose the URL bar via accessibility.
        // Resource IDs are the omnibox edit-text node in each build.
        private val BROWSER_URL_NODE_IDS = mapOf(
            "com.android.chrome" to "com.android.chrome:id/url_bar",
            "com.chrome.beta" to "com.chrome.beta:id/url_bar",
            "com.chrome.dev" to "com.chrome.dev:id/url_bar",
            "com.chrome.canary" to "com.chrome.canary:id/url_bar",
            "com.brave.browser" to "com.brave.browser:id/url_bar",
            "com.microsoft.emmx" to "com.microsoft.emmx:id/url_bar",
            "org.mozilla.firefox" to "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
            "org.mozilla.focus" to "org.mozilla.focus:id/mozac_browser_toolbar_url_view",
            "com.duckduckgo.mobile.android" to "com.duckduckgo.mobile.android:id/omnibarTextInput",
            "com.sec.android.app.sbrowser" to "com.sec.android.app.sbrowser:id/location_bar_edit_text",
            "com.opera.browser" to "com.opera.browser:id/url_field",
            "com.kiwibrowser.browser" to "com.kiwibrowser.browser:id/url_bar",
            "com.vivaldi.browser" to "com.vivaldi.browser:id/url_bar"
        )

        private val WHATSAPP_PACKAGES = setOf(
            "com.whatsapp",
            "com.whatsapp.w4b" // WhatsApp Business
        )

        // Singleton-ish — the service instance is created by the system.
        // We expose its latest snapshot so MainActivity can read it without
        // having to bind to the service.
        @Volatile
        var latest: Snapshot = Snapshot()
            private set

        fun isEnabled(): Boolean = instance != null

        /**
         * Trigger an immediate fresh scrape of the active window. Returns
         * the new snapshot, or null if the service isn't connected
         * (permission off, or transient teardown). Safe to call from any
         * thread; falls through harmlessly when the service is gone.
         */
        fun refreshNowIfPossible(): Snapshot? = instance?.refreshNow()

        @Volatile
        private var instance: SmartSwitchAccessibilityService? = null
    }

    /** Plain-data snapshot of the most recent foreground state. */
    data class Snapshot(
        val foregroundPackage: String? = null,
        val browserUrl: String? = null,
        val whatsappChatTitle: String? = null,
        val whatsappDraft: String? = null,
        val capturedAtMs: Long = 0L,
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance === this) instance = null
    }

    override fun onInterrupt() { /* no-op */ }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        // Ignore our own UI and any system shell or transient handler that
        // briefly steals focus when an NFC tag is tapped — none of these
        // are the user's page. com.android.nfc is the worst offender:
        // every tap routes through it for ~50ms and would otherwise
        // overwrite the real foreground snapshot.
        if (pkg == packageName ||
            pkg == "com.android.systemui" ||
            pkg.startsWith("com.android.launcher") ||
            pkg == "android" ||
            pkg == "com.android.nfc" ||
            pkg == "com.android.shell" ||
            pkg.startsWith("com.android.inputmethod") ||
            pkg.endsWith(".inputmethod.latin") ||
            pkg.endsWith(".inputmethod") ||
            pkg.contains(".keyboard") ||
            pkg == "com.samsung.android.app.cocktailbarservice"
        ) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                refreshSnapshotFor(pkg)
            }
        }
    }

    private fun refreshSnapshotFor(pkg: String) {
        // rootInActiveWindow can be null mid-transition; fall through with
        // just the package name — better to know "WhatsApp is foreground"
        // than nothing.
        val root: AccessibilityNodeInfo? = try {
            rootInActiveWindow
        } catch (e: Exception) {
            Log.w(TAG, "rootInActiveWindow threw: ${e.message}")
            null
        }

        var url: String? = null
        var chatTitle: String? = null
        var draft: String? = null

        try {
            if (root != null) {
                BROWSER_URL_NODE_IDS[pkg]?.let { id ->
                    url = readNodeText(root, id)
                    // Some browsers show the title or the bare host while
                    // not focused. Treat anything without a dot or scheme
                    // as garbage.
                    if (url != null && !looksLikeUrl(url!!)) url = null
                }
                // Generic URL scan as a fallback. Catches:
                //   - Chrome variants whose url_bar ID drifts between
                //     versions (use it when the known ID came back null)
                //   - Custom Tabs / WebView hosts where the omnibox lives
                //     in a different namespace
                if (url == null && (pkg in BROWSER_URL_NODE_IDS || isLikelyBrowser(pkg))) {
                    url = scanTreeForUrl(root)
                }
                if (pkg in WHATSAPP_PACKAGES) {
                    chatTitle = readWhatsAppChatTitle(root)
                    draft = readWhatsAppDraft(root)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "node scrape failed for $pkg: ${e.message}")
        }

        // Don't blow away a previously-good URL / chat title / draft just
        // because this particular event happened to fire while the URL
        // bar was scrolled off-screen. Chrome aggressively collapses its
        // omnibox on scroll, so events would arrive with url=null and
        // wipe the cache. Keep the last good value as long as we're still
        // looking at the same package.
        val prev = latest
        if (prev.foregroundPackage == pkg) {
            if (url == null) url = prev.browserUrl
            if (chatTitle == null) chatTitle = prev.whatsappChatTitle
            if (draft == null) draft = prev.whatsappDraft
        }

        latest = Snapshot(
            foregroundPackage = pkg,
            browserUrl = url,
            whatsappChatTitle = chatTitle,
            whatsappDraft = draft,
            capturedAtMs = System.currentTimeMillis(),
        )
    }

    /**
     * Trigger a fresh scrape on demand — called by SmartSwitchCapture at
     * NFC-tap time so we don't have to rely solely on the event-driven
     * cache. Safe to call from any thread; updates `latest` in place.
     */
    fun refreshNow(): Snapshot {
        val pkg = try { rootInActiveWindow?.packageName?.toString() } catch (_: Exception) { null }
            ?: latest.foregroundPackage
        if (pkg != null) refreshSnapshotFor(pkg)
        return latest
    }

    private fun isLikelyBrowser(pkg: String): Boolean {
        // Heuristic for browsers we don't have a known URL-bar node for.
        return "browser" in pkg || "chrome" in pkg || "firefox" in pkg ||
               "webview" in pkg || pkg.startsWith("org.mozilla.")
    }

    /**
     * Walk the AccessibilityNodeInfo tree breadth-first looking for a
     * text node whose content looks like a URL. Caps at ~400 nodes so a
     * worst-case page (Reddit / Twitter timeline) doesn't stall the
     * accessibility thread. We prefer the longest match — Chrome's tab
     * strip lists short hostnames before the full URL bar text.
     */
    private fun scanTreeForUrl(root: AccessibilityNodeInfo): String? {
        var best: String? = null
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < 400) {
            val node = queue.removeFirst()
            visited++
            try {
                val t = node.text?.toString()?.trim()
                if (!t.isNullOrEmpty() && looksLikeUrl(t)) {
                    if (best == null || t.length > best!!.length) best = t
                }
                for (i in 0 until node.childCount) {
                    val c = node.getChild(i) ?: continue
                    queue.add(c)
                }
            } catch (_: Exception) { /* node may be stale */ }
        }
        return best
    }

    private fun readNodeText(root: AccessibilityNodeInfo, viewId: String): String? {
        val nodes = root.findAccessibilityNodeInfosByViewId(viewId) ?: return null
        for (n in nodes) {
            val t = n.text?.toString()?.trim()
            if (!t.isNullOrEmpty()) return t
        }
        return null
    }

    private fun looksLikeUrl(s: String): Boolean {
        val v = s.trim()
        if (v.startsWith("http://", true) || v.startsWith("https://", true)) return true
        // Bare host like "youtube.com/watch?v=..." — accept if it has a dot
        // and no spaces. Browsers strip the scheme for display.
        return "." in v && " " !in v
    }

    /**
     * WhatsApp's conversation toolbar title node carries the chat name.
     * Resource IDs change between WA versions; we try a few known ones
     * and fall back to "the topmost text node in the action bar".
     */
    private fun readWhatsAppChatTitle(root: AccessibilityNodeInfo): String? {
        val ids = listOf(
            "com.whatsapp:id/conversation_contact_name",
            "com.whatsapp:id/conversation_contact",
            "com.whatsapp.w4b:id/conversation_contact_name"
        )
        for (id in ids) {
            readNodeText(root, id)?.let { return it }
        }
        return null
    }

    /**
     * The compose EditText in WhatsApp. WA blocks accessibility text reads
     * on some Android versions / WA builds; in that case we get an empty
     * string and the handoff falls back to "open chat without draft".
     */
    private fun readWhatsAppDraft(root: AccessibilityNodeInfo): String? {
        val ids = listOf(
            "com.whatsapp:id/entry",
            "com.whatsapp.w4b:id/entry"
        )
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id) ?: continue
            for (n in nodes) {
                val t = n.text?.toString()
                if (!t.isNullOrEmpty()) return t
            }
        }
        return null
    }
}
