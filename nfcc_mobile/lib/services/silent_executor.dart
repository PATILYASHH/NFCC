import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/action_item.dart';
import '../models/automation.dart';
import '../models/condition_branch.dart';
import '../models/nfc_tag.dart';
import '../models/tag_scan_log.dart';
import '../models/todo.dart';
import '../models/tracker_log.dart';
import 'database_service.dart';
import 'nfc_intent_service.dart';
import 'pc_connection_service.dart';
import 'smart_switch_capture_service.dart';

/// Executes automations silently. No UI, no notifications.
/// Vibrates: 2x short = success, 1x long = failure.
class SilentExecutor {
  static final SilentExecutor _instance = SilentExecutor._();
  factory SilentExecutor() => _instance;
  SilentExecutor._();

  static const _channel = MethodChannel('com.nfccontrol/nfc_intent');
  static const _phoneChannel = MethodChannel('com.nfccontrol/phone_actions');
  final DatabaseService _db = DatabaseService();

  Future<void> init() async {}

  /// Called when an NFC tag is detected.
  Future<void> onTagDetected(String uid, String? ndefText) async {
    debugPrint('NFCC: Tag detected - UID: $uid, NDEF: $ndefText');

    // Save/update tag
    var tag = await _db.getTagByUid(uid);
    if (tag == null) {
      tag = NfcTag(uid: uid, firstScanned: DateTime.now(), lastScanned: DateTime.now());
      await _db.insertTag(tag);
    } else {
      await _db.incrementTagScan(uid);
    }

    // ── Resolve tracker/todo bindings written as NDEF (cross-install) ──
    // Writing a tag from the Tracker/TODO screens stores NFCC_T:<id> or
    // NFCC_D:<id> as NDEF. On first tap after a fresh install we use that
    // to auto-add the tag UID to the entity's tag list, so subsequent
    // UID-based dispatch picks it up.
    if (ndefText != null) {
      if (ndefText.startsWith('NFCC_T:')) {
        final id = int.tryParse(ndefText.substring(7));
        if (id != null) await _ensureTrackerTag(id, uid);
      } else if (ndefText.startsWith('NFCC_D:')) {
        final id = int.tryParse(ndefText.substring(7));
        if (id != null) await _ensureTodoTag(id, uid);
      }
    }

    // ── Dispatch trackers + todos bound to this tag (can be many) ──
    final trackerSummary = await _dispatchTrackers(uid);
    final todoSummary = await _dispatchTodos(uid);
    final extraFired = trackerSummary.isNotEmpty || todoSummary.isNotEmpty;

    // Find automation from NDEF data (NFCC:<id>)
    Automation? automation;
    if (ndefText != null && ndefText.startsWith('NFCC:')) {
      final autoId = int.tryParse(ndefText.substring(5));
      if (autoId != null) {
        automation = await _db.getAutomationById(autoId);
        debugPrint('NFCC: Found automation by NDEF: ${automation?.name}');
      }
    }
    // Fallback: DB link
    automation ??= await _db.getAutomationByTagUid(uid);

    if (automation == null || !automation.isEnabled) {
      if (extraFired) {
        debugPrint('NFCC: No automation but fired tracker/todo bindings');
        await _vibrate(success: true);
        await _logScan(uid, tag.nickname, null,
            [...trackerSummary, ...todoSummary].join(' · '), true, null);
        return;
      }
      debugPrint('NFCC: No automation found or disabled');
      await _vibrate(success: false);
      await _logScan(uid, tag.nickname, null, null, false, 'No automation');
      return;
    }

    // Evaluate conditions - first match wins (async - checks real device state)
    ConditionBranch? matched;
    for (final branch in automation.branches) {
      if (await branch.evaluate()) {
        matched = branch;
        break;
      }
    }

    if (matched == null) {
      debugPrint('NFCC: No condition matched');
      await _vibrate(success: false);
      await _logScan(uid, tag.nickname, automation.name, null, false, 'No match');
      return;
    }

    debugPrint('NFCC: Matched branch: ${matched.label}, ${matched.actions.length} actions');

    // Execute actions (with per-action conditions)
    int fails = 0;
    for (final action in matched.actions) {
      if (action.delayMs > 0) {
        await Future.delayed(Duration(milliseconds: action.delayMs));
      }

      // Check per-action "only if" condition
      if (action.onlyIf != null) {
        final condMet = await action.onlyIf!.evaluate();
        debugPrint('NFCC: Action ${action.actionType} onlyIf ${action.onlyIf!.label} -> $condMet');
        if (condMet) {
          final ok = await _exec(action);
          if (!ok) fails++;
        } else {
          // Run else actions if condition not met
          for (final elseAction in action.elseActions) {
            await _exec(elseAction);
          }
          debugPrint('NFCC: Skipped ${action.actionType} (condition not met), ran ${action.elseActions.length} else actions');
        }
      } else {
        final ok = await _exec(action);
        if (!ok) fails++;
        debugPrint('NFCC: Action ${action.actionType} -> ${ok ? "OK" : "FAIL"}');
      }
    }

    await _vibrate(success: fails == 0);
    await _logScan(uid, tag.nickname, automation.name, matched.label, fails == 0, null);
    debugPrint('NFCC: Done. $fails failures.');

    // If MainActivity was launched purely to flush this tap (cold start),
    // tell native to step back so the user stays in whatever app they
    // were using when they tapped the tag. No-op when NFCC was already
    // foreground.
    await NfcIntentService().retreatIfColdStartDispatch();
  }

  Future<bool> _exec(ActionItem action) async {
    try {
      if (action.target == ActionTarget.pc) {
        final pc = PcConnectionService();
        if (!pc.isConnected) return false;

        // Smart Switch params are captured at tap time, not at save time —
        // we ship the page that's foreground RIGHT NOW. Native prefers the
        // accessibility snapshot pinned by NfcReceiverActivity at the
        // moment of the tap (see SmartSwitchCapture.kt).
        final resolved = action.actionType == 'smartSwitch'
            ? action.copyWith(params: await SmartSwitchCaptureService().capture())
            : action;
        final r = await pc.sendAction(resolved);
        return r?['success'] == true;
      } else {
        return await _execPhoneAction(action);
      }
    } catch (e) {
      debugPrint('NFCC: Action error: $e');
      return false;
    }
  }

  /// Execute a phone action via native Android platform channel
  Future<bool> _execPhoneAction(ActionItem action) async {
    try {
      final result = await _phoneChannel.invokeMethod<Map>('executeAction', {
        'actionType': action.actionType,
        'params': action.params,
      });
      final success = result?['success'] == true;
      debugPrint('NFCC: Phone action ${action.actionType} -> ${success ? "OK" : result?['message']}');
      return success;
    } catch (e) {
      debugPrint('NFCC: Phone action error: $e');
      return false;
    }
  }

  /// Vibrate via native Android
  /// Success: buzz-pause-buzz (2 short vibrations)
  /// Failure: one long buzz
  Future<void> _vibrate({required bool success}) async {
    try {
      final pattern = success
          ? [0, 120, 100, 120]  // delay, buzz, pause, buzz
          : [0, 300];            // delay, long buzz
      await _channel.invokeMethod('vibrate', {'pattern': pattern});
    } catch (e) {
      // Fallback to HapticFeedback
      if (success) {
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 150));
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.vibrate();
      }
    }
  }

  Future<void> _logScan(String tagUid, String? nickname, String? autoName,
      String? branch, bool success, String? error) async {
    await _db.insertScanLog(TagScanLog(
      tagUid: tagUid,
      tagNickname: nickname,
      scannedAt: DateTime.now(),
      automationName: autoName,
      branchMatched: branch,
      success: success,
      errorMessage: error,
    ));
  }

  /// Fires every tracker paired with this tag UID.
  /// Counter → append per_tap_amount. Toggle → flip state based on last log.
  /// Returns human-readable summary strings.
  Future<List<String>> _dispatchTrackers(String uid) async {
    final summaries = <String>[];
    try {
      final trackers = await _db.getTrackersForTagUid(uid);
      for (final t in trackers) {
        if (t.id == null) continue;
        if (t.isCounter) {
          await _db.insertTrackerLog(TrackerLog(
            trackerId: t.id!,
            tagUid: uid,
            value: t.perTapAmount,
            ts: DateTime.now(),
          ));
          final total = await _db.getTodayTotal(t.id!);
          final unit = t.unit == null || t.unit!.isEmpty ? '' : ' ${t.unit}';
          summaries.add(
              '${t.name} +${_fmt(t.perTapAmount)}$unit (total ${_fmt(total)}$unit)');
        } else {
          // Toggle: flip based on last state.
          final last = await _db.getLastLogForTracker(t.id!);
          final nextState = (last == null || last.state == 'out') ? 'in' : 'out';
          await _db.insertTrackerLog(TrackerLog(
            trackerId: t.id!,
            tagUid: uid,
            value: nextState == 'in' ? 1 : 0,
            state: nextState,
            ts: DateTime.now(),
          ));
          summaries.add('${t.name} → ${nextState.toUpperCase()}');
        }
      }
    } catch (e) {
      debugPrint('NFCC: Tracker dispatch error: $e');
    }
    return summaries;
  }

  /// Toggles today's completion for every TODO paired with this tag.
  Future<List<String>> _dispatchTodos(String uid) async {
    final summaries = <String>[];
    try {
      final todos = await _db.getTodosForTagUid(uid);
      for (final t in todos) {
        if (t.id == null) continue;
        final done = await _db.toggleTodoCompletionToday(t.id!, tagUid: uid);
        summaries.add('${t.name} ${done ? "✓ done" : "↺ undone"}');
      }
    } catch (e) {
      debugPrint('NFCC: Todo dispatch error: $e');
    }
    return summaries;
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// When a tag was written with NFCC_T:<id> but its UID isn't yet in the
  /// tracker's binding list, add it. Idempotent.
  Future<void> _ensureTrackerTag(int trackerId, String uid) async {
    try {
      final t = await _db.getTrackerById(trackerId);
      if (t == null || t.tagUids.contains(uid)) return;
      await _db.updateTracker(t.copyWith(
        tagUids: [...t.tagUids, uid],
        updatedAt: DateTime.now(),
      ));
      debugPrint('NFCC: Auto-bound tag $uid to tracker ${t.name}');
    } catch (e) {
      debugPrint('NFCC: _ensureTrackerTag error: $e');
    }
  }

  Future<void> _ensureTodoTag(int todoId, String uid) async {
    try {
      final t = await _db.getTodoById(todoId);
      if (t == null || t.tagUids.contains(uid)) return;
      await _db.updateTodo(t.copyWith(
        tagUids: [...t.tagUids, uid],
        updatedAt: DateTime.now(),
      ));
      debugPrint('NFCC: Auto-bound tag $uid to todo ${t.name}');
    } catch (e) {
      debugPrint('NFCC: _ensureTodoTag error: $e');
    }
  }

  /// Foreground tap: dispatches trackers silently and returns paired TODOs
  /// (without auto-completing them) so the UI can show a picker sheet.
  /// Also logs the scan.
  Future<ForegroundTapResult> foregroundTap(String uid) async {
    var tag = await _db.getTagByUid(uid);
    if (tag == null) {
      tag = NfcTag(
          uid: uid, firstScanned: DateTime.now(), lastScanned: DateTime.now());
      await _db.insertTag(tag);
    } else {
      await _db.incrementTagScan(uid);
    }
    final trackerSummary = await _dispatchTrackers(uid);
    final todos = await _db.getTodosForTagUid(uid);
    await _logScan(
        uid,
        tag.nickname,
        null,
        trackerSummary.isEmpty ? null : trackerSummary.join(' · '),
        true,
        null);
    return ForegroundTapResult(
      tagLabel: tag.nickname ?? uid,
      trackerSummary: trackerSummary.join(' · '),
      todos: todos,
    );
  }
}

class ForegroundTapResult {
  final String tagLabel;
  final String trackerSummary;
  final List<Todo> todos;
  ForegroundTapResult({
    required this.tagLabel,
    required this.trackerSummary,
    required this.todos,
  });
}
