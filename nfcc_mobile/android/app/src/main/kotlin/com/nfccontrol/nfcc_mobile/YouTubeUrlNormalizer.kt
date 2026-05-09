package com.nfccontrol.nfcc_mobile

import android.net.Uri

/**
 * Normalize anything YouTube-shaped into a canonical web URL the PC can open:
 *   https://www.youtube.com/watch?v=<id>[&t=<sec>s]
 *
 * Handles:
 *  - vnd.youtube://<id>                    (legacy intent / ReVanced)
 *  - vnd.youtube://watch?v=<id>&t=...
 *  - https://youtu.be/<id>?t=12s
 *  - https://m.youtube.com/watch?v=<id>
 *  - https://music.youtube.com/watch?v=<id>
 *  - https://www.youtube.com/shorts/<id>
 *  - https://www.youtube.com/watch?v=<id>&list=...&t=12s   → drops list, keeps t
 *
 * Returns the input unchanged if it doesn't look YouTube-shaped at all,
 * so non-YT URLs pass through untouched.
 */
object YouTubeUrlNormalizer {

    private val ID_REGEX = Regex("[A-Za-z0-9_-]{11}")

    /**
     * @param raw       captured URL/URI (or null)
     * @param fallbackPositionMs  position from MediaSession when the URL
     *                            doesn't carry a t= param. 0 = ignore.
     */
    fun normalize(
        raw: String?,
        fallbackPositionMs: Long = 0L,
        forceMusicHost: Boolean = false,
    ): String? {
        if (raw.isNullOrBlank() && !forceMusicHost) return null
        val trimmed = raw?.trim() ?: ""

        val extracted = if (trimmed.isEmpty()) null else extract(trimmed)
        if (extracted == null && trimmed.isNotEmpty()) return trimmed
        val (videoId, urlPositionSec) = extracted ?: return null

        val seconds = when {
            urlPositionSec > 0 -> urlPositionSec
            fallbackPositionMs > 0 -> (fallbackPositionMs / 1000).toInt()
            else -> 0
        }

        // Route YT Music handoffs to music.youtube.com — desktop YT Music
        // PWA picks up the protocol and opens the song there. Plain
        // youtube.com would open the regular video player instead.
        val host = if (forceMusicHost ||
            trimmed.contains("music.youtube.com", ignoreCase = true)
        ) {
            "music.youtube.com"
        } else {
            "www.youtube.com"
        }
        val base = "https://$host/watch?v=$videoId"
        return if (seconds > 0) "$base&t=${seconds}s" else base
    }

    /** Returns (videoId, positionSec) or null if input isn't YouTube-shaped. */
    private fun extract(input: String): Pair<String, Int>? {
        // Try Uri parsing first; if it fails, fall back to regex.
        val uri: Uri? = try { Uri.parse(input) } catch (_: Exception) { null }

        val scheme = uri?.scheme?.lowercase()
        val host = uri?.host?.lowercase().orEmpty()

        when {
            scheme == "vnd.youtube" || scheme == "youtube" -> {
                // Two shapes: vnd.youtube://<id> OR vnd.youtube://watch?v=<id>
                val auth = uri?.authority.orEmpty()
                val viaParam = uri?.getQueryParameter("v")
                val id = (viaParam ?: auth).takeIf { it.isNotBlank() && ID_REGEX.matches(it) }
                    ?: return null
                val pos = parsePositionParam(uri)
                return id to pos
            }
            host.endsWith("youtu.be") -> {
                val id = uri?.lastPathSegment?.takeIf { ID_REGEX.matches(it) } ?: return null
                return id to parsePositionParam(uri)
            }
            host.endsWith("youtube.com") || host.endsWith("youtube-nocookie.com") -> {
                val v = uri?.getQueryParameter("v")
                val id = if (v != null && ID_REGEX.matches(v)) v
                else {
                    // /shorts/<id>, /embed/<id>, /live/<id>
                    val segments = uri?.pathSegments.orEmpty()
                    segments.lastOrNull()?.takeIf { ID_REGEX.matches(it) }
                } ?: return null
                return id to parsePositionParam(uri)
            }
        }

        // Not URI-parseable — try a loose regex (e.g. "youtube.com/watch?v=ID")
        val loose = Regex("(?:v=|youtu\\.be/|/shorts/|/embed/)([A-Za-z0-9_-]{11})")
            .find(input)?.groupValues?.getOrNull(1)
        return if (loose != null) loose to 0 else null
    }

    /** Reads ?t=, ?time_continue=, ?start= as seconds. Accepts "90s", "1m30s", "90". */
    private fun parsePositionParam(uri: Uri?): Int {
        if (uri == null) return 0
        val raw = uri.getQueryParameter("t")
            ?: uri.getQueryParameter("time_continue")
            ?: uri.getQueryParameter("start")
            ?: return 0
        return parseDurationToSeconds(raw)
    }

    private fun parseDurationToSeconds(s: String): Int {
        if (s.isBlank()) return 0
        // Plain integer = seconds.
        s.toIntOrNull()?.let { return it }
        // "1h2m3s" / "5m10s" / "90s"
        val re = Regex("(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?")
        val m = re.matchEntire(s.trim()) ?: return 0
        val h = m.groupValues[1].toIntOrNull() ?: 0
        val mn = m.groupValues[2].toIntOrNull() ?: 0
        val sc = m.groupValues[3].toIntOrNull() ?: 0
        return h * 3600 + mn * 60 + sc
    }
}
