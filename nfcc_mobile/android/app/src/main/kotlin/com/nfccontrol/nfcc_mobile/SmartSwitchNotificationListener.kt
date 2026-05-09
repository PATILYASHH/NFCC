package com.nfccontrol.nfcc_mobile

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Stub notification listener — exists ONLY to be the auth token for
 * MediaSessionManager.getActiveSessions(). We don't read or post-process
 * notifications. The component name is what MediaSessionManager wants;
 * granting the permission is what unlocks media-session reads system-wide.
 */
class SmartSwitchNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) { /* no-op */ }
    override fun onNotificationRemoved(sbn: StatusBarNotification?) { /* no-op */ }
}
