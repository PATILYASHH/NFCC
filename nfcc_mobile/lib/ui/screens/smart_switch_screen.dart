import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:provider/provider.dart';
import '../../models/action_item.dart';
import '../../models/automation.dart';
import '../../models/condition_branch.dart';
import '../../services/database_service.dart';
import '../../services/nfc_service.dart';
import '../../services/pc_connection_service.dart';
import '../../services/smart_switch_capture_service.dart';
import '../theme/app_theme.dart';
import '../widgets/smart_switch_permission_sheet.dart';

/// Dedicated home for Smart Switch — the only PC-handoff feature with
/// its own screen. Goal: one tap to understand what's supported, what's
/// programmed, and to add another tag. Smart Switch tags here always
/// run a single `smartSwitch` action under an Always branch — never
/// time/condition-gated, never bundled with other actions.
class SmartSwitchScreen extends StatefulWidget {
  const SmartSwitchScreen({super.key});

  @override
  State<SmartSwitchScreen> createState() => _SmartSwitchScreenState();
}

class _SmartSwitchScreenState extends State<SmartSwitchScreen>
    with WidgetsBindingObserver {
  final _svc = SmartSwitchCaptureService();
  bool _accessibility = false;
  bool _usageStats = false;
  bool _notifListener = false;
  bool _permsLoading = true;

  List<Automation> _tags = [];
  bool _tagsLoading = true;
  bool _writing = false;
  String? _writeStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPerms();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_refreshPerms(), _refreshTags()]);
  }

  Future<void> _refreshPerms() async {
    final results = await Future.wait([
      _svc.hasAccessibilityPermission(),
      _svc.hasUsageStatsPermission(),
      _svc.hasNotificationListenerPermission(),
    ]);
    if (!mounted) return;
    setState(() {
      _accessibility = results[0];
      _usageStats = results[1];
      _notifListener = results[2];
      _permsLoading = false;
    });
  }

  Future<void> _refreshTags() async {
    final db = context.read<DatabaseService>();
    final all = await db.getAllAutomations();
    if (!mounted) return;
    setState(() {
      _tags = all.where(_isSmartSwitchOnly).toList();
      _tagsLoading = false;
    });
  }

  /// A Smart Switch tag is an automation with exactly one Always branch,
  /// exactly one PC `smartSwitch` action, no other actions, and a paired
  /// tag UID. We exclude anything else even if it contains smartSwitch,
  /// because mixed automations belong on the Routines screen.
  static bool _isSmartSwitchOnly(Automation a) {
    if (a.tagUid == null) return false;
    if (a.branches.length != 1) return false;
    final b = a.branches.first;
    if (b.type != ConditionType.always) return false;
    if (b.actions.length != 1) return false;
    final act = b.actions.first;
    return act.target == ActionTarget.pc && act.actionType == 'smartSwitch';
  }

  Future<void> _programNewTag() async {
    HapticFeedback.lightImpact();
    if (!_accessibility) {
      await SmartSwitchPermissionSheet.show(context);
      if (!mounted) return;
      await _refreshPerms();
      if (!mounted) return;
    }

    final nfc = context.read<NfcService>();
    if (!await nfc.isAvailable()) {
      _setWriteStatus('NFC not available');
      return;
    }
    setState(() {
      _writing = true;
      _writeStatus = 'Hold a writable NFC tag near your phone…';
    });

    final record = NdefRecord(
      typeNameFormat: TypeNameFormat.media,
      type: Uint8List.fromList(utf8.encode('application/com.nfccontrol.nfcc')),
      identifier: Uint8List(0),
      payload: Uint8List.fromList(utf8.encode('SMART_SWITCH')),
    );

    await nfc.startWriteAndIdentifySession(
      records: [record],
      onResult: (success, uid, message) async {
        if (!mounted) return;
        if (!success || uid == null || uid == 'UNKNOWN') {
          _setWriteStatus(success
              ? 'Wrote tag but could not read UID — try again'
              : 'Write failed: $message');
          return;
        }
        if (_tags.any((t) => t.tagUid == uid)) {
          _setWriteStatus('That tag is already paired as a Smart Switch tag');
          return;
        }
        try {
          await _registerTag(uid);
          _setWriteStatus('Smart Switch tag ready');
          await _refreshTags();
        } catch (e) {
          _setWriteStatus('Tag written but pairing failed: $e');
        }
      },
    );
  }

  Future<void> _registerTag(String uid) async {
    final db = context.read<DatabaseService>();
    final now = DateTime.now();
    final shortUid = uid.split(':').take(3).join('');
    await db.insertAutomation(Automation(
      name: 'Smart Switch ($shortUid)',
      tagUid: uid,
      branches: [
        ConditionBranch(
          orderIndex: 0,
          type: ConditionType.always,
          actions: [
            ActionItem(
              orderIndex: 0,
              target: ActionTarget.pc,
              actionType: 'smartSwitch',
            ),
          ],
        ),
      ],
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> _deleteTag(Automation a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('Remove Smart Switch tag?'),
        content: Text('This unpairs ${a.name}. The physical tag still has '
            'the SMART_SWITCH payload — you can re-pair or erase it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || a.id == null) return;
    await context.read<DatabaseService>().deleteAutomation(a.id!);
    await _refreshTags();
  }

  void _setWriteStatus(String msg) {
    setState(() {
      _writing = false;
      _writeStatus = msg;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Smart Switch',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _hero(),
          const SizedBox(height: 18),
          _sectionLabel('PERMISSIONS'),
          const SizedBox(height: 8),
          _permissionsCard(),
          const SizedBox(height: 18),
          _sectionLabel('SUPPORTED APPS'),
          const SizedBox(height: 8),
          ..._appMappings.map(_appCard),
          const SizedBox(height: 18),
          _sectionLabel('YOUR SMART SWITCH TAGS'),
          const SizedBox(height: 8),
          _tagsList(),
          const SizedBox(height: 18),
          _programButton(),
          if (_writeStatus != null) ...[
            const SizedBox(height: 10),
            _statusBanner(_writeStatus!),
          ],
          const SizedBox(height: 18),
          _howItWorks(),
        ],
      ),
    );
  }

  Widget _hero() {
    return Consumer<PcConnectionService>(builder: (_, pc, __) {
      final connected = pc.isConnected;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.nfcGlow.withValues(alpha: 0.18),
              AppColors.accentBlue.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.nfcGlow.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.nfcGlow.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.swap_horiz_rounded,
                  size: 30, color: AppColors.nfcGlow),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Hand off to PC',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  Text(
                    connected
                        ? 'Tap a Smart Switch tag → the page you\'re looking at opens on your PC'
                        : 'PC not connected — pair from Settings first',
                    style: TextStyle(
                        color: connected
                            ? AppColors.textSecondary
                            : AppColors.warning,
                        fontSize: 12.5,
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _permissionsCard() {
    if (_permsLoading) {
      return const SizedBox(
        height: 60,
        child: Center(
            child: CircularProgressIndicator(
                color: AppColors.nfcGlow, strokeWidth: 2.5)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (!_accessibility) _restrictedSettingsCallout(),
          _permRow(
            icon: Icons.accessibility_new_rounded,
            title: 'Accessibility',
            subtitle: 'Required — reads foreground app + URL bar',
            granted: _accessibility,
            onOpen: _svc.openAccessibilitySettings,
          ),
          _divider(),
          _permRow(
            icon: Icons.bar_chart_rounded,
            title: 'Usage Stats',
            subtitle: 'Fallback when accessibility cache is stale',
            granted: _usageStats,
            onOpen: _svc.openUsageStatsSettings,
          ),
          _divider(),
          _permRow(
            icon: Icons.notifications_active_rounded,
            title: 'Notification Listener',
            subtitle: 'Needed to read YouTube / Spotify media session',
            granted: _notifListener,
            onOpen: _svc.openNotificationListenerSettings,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _restrictedSettingsCallout() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Play Protect blocks Accessibility?',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Android 13+ blocks Accessibility for sideloaded apps until '
            'you allow restricted settings:\n'
            '1. Open NFCC App info  2. Tap ⋮ (top right)  '
            '3. "Allow restricted settings"\n'
            '4. Come back here and grant Accessibility',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _svc.openAppInfo,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open NFCC App info',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.warning,
                backgroundColor: AppColors.warning.withValues(alpha: 0.14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required Future<void> Function() onOpen,
    bool isLast = false,
  }) {
    final color = granted ? AppColors.success : AppColors.accentBlue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 11.5)),
              ],
            ),
          ),
          if (granted)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 22),
            )
          else
            TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: const Text('Open',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        height: 1,
        color: AppColors.divider,
      );

  // ── Supported apps mapping ────────────────────────────────────────────

  static final List<_AppMapping> _appMappings = [
    _AppMapping(
      icon: Icons.smart_display_rounded,
      color: Color(0xFFEF4444),
      title: 'YouTube / YT Music',
      mapsTo: 'Opens the same video on PC at the same timestamp',
      detail: 'youtube.com/watch?v=…&t=…s — works with stock YouTube and '
          'ReVanced builds.',
    ),
    _AppMapping(
      icon: Icons.music_note_rounded,
      color: Color(0xFF1DB954),
      title: 'Spotify',
      mapsTo: 'Opens the same track on Spotify Desktop / web player',
      detail: 'open.spotify.com/track/… — desktop app handles the URL '
          'when installed.',
    ),
    _AppMapping(
      icon: Icons.public_rounded,
      color: Color(0xFF3B82F6),
      title: 'Browsers',
      mapsTo: 'Opens the active tab\'s URL in your default PC browser',
      detail: 'Chrome, Brave, Edge, Firefox, Samsung Internet, DuckDuckGo, '
          'Opera, Vivaldi, Kiwi — URL is read from the omnibox via '
          'Accessibility.',
    ),
    _AppMapping(
      icon: Icons.chat_rounded,
      color: Color(0xFF25D366),
      title: 'WhatsApp',
      mapsTo: 'Opens WhatsApp Web at the chat (and pastes any draft)',
      detail: 'wa.me/<number> when the chat is a phone, otherwise '
          'web.whatsapp.com. Draft text is best-effort.',
    ),
    _AppMapping(
      icon: Icons.apps_rounded,
      color: Color(0xFF8B5CF6),
      title: 'Other apps',
      mapsTo: 'Tries to launch the matching PC app by name',
      detail: 'Phone app name is mapped to a PC executable (chrome, '
          'spotify, vscode, etc.) — falls back to "nothing to hand off" '
          'if no equivalent exists.',
    ),
  ];

  Widget _appCard(_AppMapping m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: m.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(m.icon, size: 20, color: m.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.east_rounded,
                        size: 12, color: m.color.withValues(alpha: 0.8)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(m.mapsTo,
                          style: TextStyle(
                              color: m.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.4)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(m.detail,
                    style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11.5,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tags list ─────────────────────────────────────────────────────────

  Widget _tagsList() {
    if (_tagsLoading) {
      return const SizedBox(
          height: 50,
          child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.nfcGlow, strokeWidth: 2)));
    }
    if (_tags.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: const [
            Icon(Icons.contactless_rounded,
                size: 18, color: AppColors.textTertiary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No Smart Switch tags yet. Tap “Program new Smart Switch tag” '
                'below and hold a writable NFC tag to your phone.',
                style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.5,
                    height: 1.4),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: _tags.map(_tagRow).toList(),
    );
  }

  Widget _tagRow(Automation a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.nfcGlow.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.swap_horiz_rounded,
                size: 20, color: AppColors.nfcGlow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('UID ${a.tagUid ?? "—"}',
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 11.5)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _deleteTag(a),
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _programButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _writing ? null : _programNewTag,
        icon: _writing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black))
            : const Icon(Icons.add_circle_rounded, size: 20),
        label: Text(
          _writing ? 'Hold tag to your phone…' : 'Program new Smart Switch tag',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.nfcGlow,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _statusBanner(String msg) {
    final lower = msg.toLowerCase();
    final ok = lower.contains('ready') || lower.contains('success');
    final color = ok ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(color: color, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _howItWorks() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 16, color: AppColors.textTertiary),
              SizedBox(width: 6),
              Text('How a Smart Switch tap behaves',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• Captures only the page that was on screen at tap time — '
            'background music or hidden tabs are ignored.\n'
            '• Works whether NFCC is open, in recents, or fully closed — '
            'the accessibility service is always alive.\n'
            '• Each Smart Switch tag does only one job: hand off to PC. '
            'No time blocks, no conditions, no other actions mixed in.',
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 12, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );
}

class _AppMapping {
  final IconData icon;
  final Color color;
  final String title;
  final String mapsTo;
  final String detail;

  const _AppMapping({
    required this.icon,
    required this.color,
    required this.title,
    required this.mapsTo,
    required this.detail,
  });
}
