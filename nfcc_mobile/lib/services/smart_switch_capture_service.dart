import 'package:flutter/services.dart';

/// Dart-side wrapper around the `nfcc/smart_switch` method channel.
/// All heavy lifting (foreground app detection, URL bar scrape, media
/// session read, YouTube URL normalization) lives in Kotlin —
/// see SmartSwitchCapture.kt.
class SmartSwitchCaptureService {
  static const _channel = MethodChannel('nfcc/smart_switch');

  /// Returns the handoff payload for the *currently foregrounded* app.
  /// See SmartSwitchCapture.kt for the exact key set; an empty/unknown
  /// foreground returns `{ "kind": "generic" }`.
  Future<Map<String, dynamic>> capture() async {
    final raw = await _channel.invokeMethod<dynamic>('capture');
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {'kind': 'generic'};
  }

  Future<bool> hasAccessibilityPermission() =>
      _bool('hasAccessibilityPermission');
  Future<bool> hasUsageStatsPermission() => _bool('hasUsageStatsPermission');
  Future<bool> hasNotificationListenerPermission() =>
      _bool('hasNotificationListenerPerm');

  Future<void> openAccessibilitySettings() =>
      _void('openAccessibilitySettings');
  Future<void> openUsageStatsSettings() => _void('openUsageStatsSettings');
  Future<void> openNotificationListenerSettings() =>
      _void('openNotificationListenerSettings');

  /// Opens this app's "App info" page so the user can grant the
  /// "Allow restricted settings" toggle (Android 13+) — without that,
  /// Play Protect blocks the Accessibility toggle for sideloaded APKs.
  Future<void> openAppInfo() => _void('openAppInfo');

  Future<bool> _bool(String method) async {
    try {
      final v = await _channel.invokeMethod<bool>(method);
      return v ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _void(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      /* swallow — opening settings is best-effort */
    }
  }
}

/// True when the captured payload is rich enough for the PC to do
/// something useful (URL or named app). The engine uses this to surface
/// "Nothing to hand off" instead of pinging the PC pointlessly.
bool isUsefulHandoff(Map<String, dynamic> payload) {
  final kind = (payload['kind'] as String?)?.toLowerCase() ?? 'generic';
  final url = (payload['url'] as String?)?.trim();
  final appName = (payload['appName'] as String?)?.trim();
  if (url != null && url.isNotEmpty) return true;
  if (kind == 'whatsapp') return true; // WA Web alone is acceptable
  if (appName != null && appName.isNotEmpty) return true;
  return false;
}
