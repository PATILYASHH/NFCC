package com.nfccontrol.nfcc_mobile

import android.content.ComponentName
import android.content.Context
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
        val mediaUri: String?,   // METADATA_KEY_MEDIA_URI when present
        val title: String?,
        val artist: String?,
        val positionMs: Long,    // 0 if unknown
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
                val mediaUri = md?.getString(android.media.MediaMetadata.METADATA_KEY_MEDIA_URI)
                val title = md?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE)
                val artist = md?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
                val pos = c.playbackState?.let {
                    if (it.state == PlaybackState.STATE_PLAYING ||
                        it.state == PlaybackState.STATE_PAUSED) it.position else 0L
                } ?: 0L
                return Reading(
                    pkg = c.packageName,
                    mediaUri = mediaUri,
                    title = title,
                    artist = artist,
                    positionMs = pos,
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
}
