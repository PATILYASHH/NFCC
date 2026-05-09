import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Listens for NFC tag intents from Android (foreground dispatch + cold start).
/// This works even when the app is in background - Android delivers the intent
/// and we handle it silently.
class NfcIntentService {
  static final NfcIntentService _instance = NfcIntentService._();
  factory NfcIntentService() => _instance;
  NfcIntentService._();

  static const _eventChannel = EventChannel('com.nfccontrol/nfc_events');
  static const _methodChannel = MethodChannel('com.nfccontrol/nfc_intent');

  StreamSubscription? _subscription;
  void Function(String uid, String? ndefText)? _onTagDetected;

  /// Start listening for NFC tag events from native Android
  void startListening({
    required void Function(String uid, String? ndefText) onTagDetected,
  }) {
    _onTagDetected = onTagDetected;
    _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final uid = event['uid'] as String? ?? 'UNKNOWN';
          final ndefText = event['ndefText'] as String?;
          _onTagDetected?.call(uid, ndefText);
        }
      },
      onError: (e) {
        debugPrint('NFC intent error: $e');
      },
    );
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _onTagDetected = null;
  }

  Future<bool> isNfcAvailable() async {
    try {
      return await _methodChannel.invokeMethod<bool>('getNfcAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// If MainActivity was launched purely to flush a queued NFC tap (no
  /// app UI needed), tell native to drop us back behind whatever the user
  /// was looking at. No-op when the user opened NFCC normally.
  Future<void> retreatIfColdStartDispatch() async {
    try {
      await _methodChannel.invokeMethod<void>('retreatIfColdStartDispatch');
    } catch (_) { /* best-effort */ }
  }
}
