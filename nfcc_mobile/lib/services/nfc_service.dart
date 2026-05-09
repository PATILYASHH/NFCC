import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/ndef_record.dart';

/// NFC tag scan result with extracted info
class NfcScanResult {
  final String uid;
  final String? tagType;
  final String? technology;
  final String? ndefText;
  final NfcTag rawTag;

  NfcScanResult({
    required this.uid,
    this.tagType,
    this.technology,
    this.ndefText,
    required this.rawTag,
  });
}

class NfcService {
  static final NfcService _instance = NfcService._();
  factory NfcService() => _instance;
  NfcService._();

  static const _channel = MethodChannel('com.nfccontrol/nfc_intent');
  bool _sessionActive = false;

  Future<bool> isAvailable() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      return availability == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  /// Disable native foreground dispatch so nfc_manager plugin can handle tags
  Future<void> _suppressForegroundDispatch() async {
    try {
      await _channel.invokeMethod('disableForegroundDispatch');
      debugPrint('NFCC: Foreground dispatch suppressed');
    } catch (e) {
      debugPrint('NFCC: Failed to suppress foreground dispatch: $e');
    }
  }

  /// Re-enable native foreground dispatch for silent background tag handling
  Future<void> _restoreForegroundDispatch() async {
    try {
      await _channel.invokeMethod('enableForegroundDispatch');
      debugPrint('NFCC: Foreground dispatch restored');
    } catch (e) {
      debugPrint('NFCC: Failed to restore foreground dispatch: $e');
    }
  }

  /// Start a read session. Calls [onDiscovered] when a tag is found.
  Future<void> startReadSession({
    required void Function(NfcScanResult result) onDiscovered,
    void Function(String error)? onError,
  }) async {
    await _stopSession();
    _sessionActive = true;
    await _suppressForegroundDispatch();

    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          final result = _extractInfo(tag);
          onDiscovered(result);
        } catch (e) {
          onError?.call(e.toString());
        }
        await _stopSession();
      },
    );
  }

  /// Start a write session to write text data to a tag (NFCC automation format)
  Future<void> startWriteSession({
    required String data,
    required void Function(bool success, String message) onResult,
  }) async {
    await _stopSession();
    _sessionActive = true;
    await _suppressForegroundDispatch();

    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          if (defaultTargetPlatform == TargetPlatform.android) {
            final ndef = NdefAndroid.from(tag);
            if (ndef == null) {
              onResult(false, 'Tag does not support NDEF');
              await _stopSession();
              return;
            }
            if (!ndef.isWritable) {
              onResult(false, 'Tag is not writable');
              await _stopSession();
              return;
            }

            final record = _makeMimeRecord(data);
            final aar = _makeAar();
            final message = NdefMessage(records: [record, aar]);

            await ndef.writeNdefMessage(message);
            onResult(true, 'Written successfully');
          } else {
            onResult(false, 'NFC write only supported on Android');
          }
        } catch (e) {
          onResult(false, 'Write failed: $e');
        }
        await _stopSession();
      },
    );
  }

  /// Start a write session for raw NDEF records (URLs, UPI, text, etc.)
  Future<void> startRawWriteSession({
    required List<NdefRecord> records,
    required void Function(bool success, String message) onResult,
  }) async {
    await _stopSession();
    _sessionActive = true;
    await _suppressForegroundDispatch();

    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          if (defaultTargetPlatform == TargetPlatform.android) {
            final ndef = NdefAndroid.from(tag);
            if (ndef == null) {
              onResult(false, 'Tag does not support NDEF');
              await _stopSession();
              return;
            }
            if (!ndef.isWritable) {
              onResult(false, 'Tag is not writable');
              await _stopSession();
              return;
            }

            final message = NdefMessage(records: records);
            await ndef.writeNdefMessage(message);
            onResult(true, 'Written successfully');
          } else {
            onResult(false, 'NFC write only supported on Android');
          }
        } catch (e) {
          onResult(false, 'Write failed: $e');
        }
        await _stopSession();
      },
    );
  }

  /// Write [records] AND return the tag UID. The Smart Switch one-tap flow
  /// uses this so it can pair the freshly-written tag to an auto-created
  /// automation in a single physical tap.
  Future<void> startWriteAndIdentifySession({
    required List<NdefRecord> records,
    required void Function(bool success, String? uid, String message) onResult,
  }) async {
    await _stopSession();
    _sessionActive = true;
    await _suppressForegroundDispatch();

    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        final uid = _extractUid(tag);
        try {
          if (defaultTargetPlatform != TargetPlatform.android) {
            onResult(false, uid, 'NFC write only supported on Android');
          } else {
            final ndef = NdefAndroid.from(tag);
            if (ndef == null) {
              onResult(false, uid, 'Tag does not support NDEF');
            } else if (!ndef.isWritable) {
              onResult(false, uid, 'Tag is not writable');
            } else {
              await ndef.writeNdefMessage(NdefMessage(records: records));
              onResult(true, uid, 'Written successfully');
            }
          }
        } catch (e) {
          onResult(false, uid, 'Write failed: $e');
        }
        await _stopSession();
      },
    );
  }

  /// Format/erase a tag by writing empty NDEF
  Future<void> startFormatSession({
    required void Function(bool success, String message) onResult,
  }) async {
    await _stopSession();
    _sessionActive = true;
    await _suppressForegroundDispatch();

    await NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          if (defaultTargetPlatform == TargetPlatform.android) {
            final ndef = NdefAndroid.from(tag);
            if (ndef != null && ndef.isWritable) {
              final record = _makeMimeRecord('');
              await ndef.writeNdefMessage(NdefMessage(records: [record]));
              onResult(true, 'Tag formatted successfully');
            } else {
              onResult(false, 'Tag cannot be formatted');
            }
          } else {
            onResult(false, 'NFC format only supported on Android');
          }
        } catch (e) {
          onResult(false, 'Format failed: $e');
        }
        await _stopSession();
      },
    );
  }

  Future<void> stopSession() => _stopSession();

  Future<void> _stopSession() async {
    if (_sessionActive) {
      _sessionActive = false;
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {}
      await _restoreForegroundDispatch();
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Build a custom MIME record so Android's default Tags app ignores it.
  /// Only our app (via foreground dispatch) will handle this MIME type.
  static NdefRecord _makeMimeRecord(String data) {
    const mimeType = 'application/com.nfccontrol.nfcc';
    return NdefRecord(
      typeNameFormat: TypeNameFormat.media,
      type: Uint8List.fromList(utf8.encode(mimeType)),
      identifier: Uint8List(0),
      payload: Uint8List.fromList(utf8.encode(data)),
    );
  }

  /// Android Application Record - ensures our app gets exclusive NFC handling.
  /// If our app is installed, Android routes the tag directly to us.
  /// If not installed, Android opens Play Store for our package.
  static NdefRecord _makeAar() {
    const packageName = 'com.nfccontrol.nfcc_mobile';
    return NdefRecord(
      typeNameFormat: TypeNameFormat.external,
      type: Uint8List.fromList(utf8.encode('android.com:pkg')),
      identifier: Uint8List(0),
      payload: Uint8List.fromList(utf8.encode(packageName)),
    );
  }

  NfcScanResult _extractInfo(NfcTag tag) {
    final uid = _extractUid(tag);
    final tagType = _detectTagType(tag);
    final technology = _detectTechnology(tag);
    final ndefText = _extractNdefText(tag);

    return NfcScanResult(
      uid: uid,
      tagType: tagType,
      technology: technology,
      ndefText: ndefText,
      rawTag: tag,
    );
  }

  String _extractUid(NfcTag tag) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final nfcTag = NfcTagAndroid.from(tag);
      if (nfcTag != null) return _bytesToHex(nfcTag.id);
    }
    return 'UNKNOWN';
  }

  String _detectTagType(NfcTag tag) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ndef = NdefAndroid.from(tag);
      if (ndef != null) {
        final type = ndef.type;
        if (type.contains('1')) return 'NTAG213';
        if (type.contains('2')) return 'NTAG215';
        if (type.contains('4')) return 'NTAG216';
        return type.isNotEmpty ? type : 'NDEF';
      }
      if (MifareClassicAndroid.from(tag) != null) return 'Mifare Classic';
      if (MifareUltralightAndroid.from(tag) != null) return 'Mifare Ultralight';
    }
    return 'Unknown';
  }

  String _detectTechnology(NfcTag tag) {
    if (defaultTargetPlatform != TargetPlatform.android) return 'Unknown';
    final techs = <String>[];
    if (NfcAAndroid.from(tag) != null) techs.add('NfcA');
    if (NfcBAndroid.from(tag) != null) techs.add('NfcB');
    if (NfcFAndroid.from(tag) != null) techs.add('NfcF');
    if (NfcVAndroid.from(tag) != null) techs.add('NfcV');
    if (IsoDepAndroid.from(tag) != null) techs.add('IsoDep');
    if (NdefAndroid.from(tag) != null) techs.add('NDEF');
    return techs.isEmpty ? 'Unknown' : techs.join(', ');
  }

  String? _extractNdefText(NfcTag tag) {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final ndef = NdefAndroid.from(tag);
    if (ndef == null) return null;
    final msg = ndef.cachedNdefMessage;
    if (msg == null || msg.records.isEmpty) return null;

    for (final record in msg.records) {
      // Our custom MIME type record
      if (record.typeNameFormat == TypeNameFormat.media) {
        final mimeType = utf8.decode(record.type);
        if (mimeType == 'application/com.nfccontrol.nfcc') {
          return utf8.decode(record.payload);
        }
      }
      // Fallback: also handle plain text records (legacy)
      if (record.typeNameFormat == TypeNameFormat.wellKnown) {
        final payload = record.payload;
        if (payload.isNotEmpty) {
          final langLength = payload[0] & 0x3f;
          if (payload.length > langLength + 1) {
            return utf8.decode(payload.sublist(langLength + 1));
          }
        }
      }
    }
    return null;
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
}
