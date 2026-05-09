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
                if (pkg in WHATSAPP_PACKAGES) {
                    chatTitle = readWhatsAppChatTitle(root)
                    draft = readWhatsAppDraft(root)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "node scrape failed for $pkg: ${e.message}")
        }

        latest = Snapshot(
            foregroundPackage = pkg,
            browserUrl = url,
            whatsappChatTitle = chatTitle,
            whatsappDraft = draft,
            capturedAtMs = System.currentTimeMillis(),
        )
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
