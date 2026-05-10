package com.nfccontrol.nfcc_mobile

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.util.Log

/**
 * Thin wrapper over MediaSessionManager.getActiveSessions(). Returns the
 * active session whose package matches the foreground app, or null.
 *
 * The notification-listener ComponentName below MUST match the service
 * registered in AndroidManifest.xml — that's the auth token Android wants.
 */
object MediaSessionReader {

    private const val TAG = "NFCCMediaReader"

    data class Reading(
        val pkg: String,
        val mediaUri: String?,    // METADATA_KEY_MEDIA_URI
        val mediaId: String?,     // METADATA_KEY_MEDIA_ID — sometimes the
                                  // bare video ID (11 chars) for YouTube
        val description: String?, // DISPLAY_DESCRIPTION → DESCRIPTION,
                                  // some apps tuck the URL in here
        val title: String?,
        val artist: String?,
        val positionMs: Long,
        val durationMs: Long,
    )

    fun readForPackage(context: Context, expectedPackage: String): Reading? {
        return try {
            val mgr = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
                ?: return null
            val component = ComponentName(context, SmartSwitchNotificationListener::class.java)
            val controllers = mgr.getActiveSessions(component)
            for (c in controllers) {
                if (c.packageName != expectedPackage) continue
                val md = c.metadata
                val mediaUri    = md?.getString(MediaMetadata.METADATA_KEY_MEDIA_URI)
                val mediaId     = md?.getString(MediaMetadata.METADATA_KEY_MEDIA_ID)
                val title       = md?.getString(MediaMetadata.METADATA_KEY_TITLE)
                                ?: md?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
                val artist      = md?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                val description = md?.getString(MediaMetadata.METADATA_KEY_DISPLAY_DESCRIPTION)
                                ?: md?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
                val durationMs  = md?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L

                val pos = livePositionMs(c.playbackState)

                return Reading(
                    pkg = c.packageName,
                    mediaUri = mediaUri,
                    mediaId = mediaId,
                    description = description,
                    title = title,
                    artist = artist,
                    positionMs = pos,
                    durationMs = durationMs,
                )
            }
            null
        } catch (e: SecurityException) {
            // Notification-listener perm not granted yet.
            Log.d(TAG, "media session read denied: ${e.message}")
            null
        } catch (e: Exception) {
            Log.w(TAG, "media session read failed: ${e.message}")
            null
        }
    }

    /**
     * PlaybackState.position records where playback was at the moment the
     * state was last *updated*, not where it is right now. For a video
     * that's been playing 30s without a state change, .position can still
     * read 0. Standard fix: add the elapsed time since the last update,
     * scaled by playback speed, when state == PLAYING. PAUSED/BUFFERING
     * stay frozen at .position. Anything else means no meaningful
     * position to report.
     */
    private fun livePositionMs(ps: PlaybackState?): Long {
        if (ps == null) return 0L
        return when (ps.state) {
            PlaybackState.STATE_PLAYING -> {
                val elapsed = System.currentTimeMillis() - ps.lastPositionUpdateTime
                val speed = ps.playbackSpeed.toDouble().coerceAtLeast(0.0)
                val advance = (elapsed.coerceAtLeast(0L) * speed).toLong()
                (ps.position + advance).coerceAtLeast(0L)
            }
            PlaybackState.STATE_PAUSED,
            PlaybackState.STATE_BUFFERING -> ps.position.coerceAtLeast(0L)
            else -> 0L
        }
    }
}
