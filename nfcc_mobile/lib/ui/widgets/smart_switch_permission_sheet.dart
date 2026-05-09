import 'package:flutter/material.dart';
import '../../services/smart_switch_capture_service.dart';
import '../theme/app_theme.dart';

/// One-shot bottom sheet shown the first time the user adds a Smart
/// Switch action. Three rows, three "Open" buttons, one "Done". Doesn't
/// gate adding the action — Smart Switch degrades gracefully when a
/// permission is missing, see automation_engine + SmartSwitchCapture.
class SmartSwitchPermissionSheet extends StatefulWidget {
  const SmartSwitchPermissionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SmartSwitchPermissionSheet(),
    );
  }

  @override
  State<SmartSwitchPermissionSheet> createState() =>
      _SmartSwitchPermissionSheetState();
}

class _SmartSwitchPermissionSheetState
    extends State<SmartSwitchPermissionSheet> with WidgetsBindingObserver {
  final _svc = SmartSwitchCaptureService();
  bool _accessibility = false;
  bool _usageStats = false;
  bool _notifListener = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-poll when user comes back from a Settings screen — that's how
    // Android tells us the toggle changed.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
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
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLit,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('Enable Smart Switch',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Smart Switch reads what\'s on your phone screen at tap '
                'time so it can hand it off to your PC. Grant these three '
                'so it has full handoff data — you can skip and Smart '
                'Switch will work with whatever it has.',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.nfcGlow, strokeWidth: 2.5)),
                )
              else ...[
                _row(
                  icon: Icons.accessibility_new_rounded,
                  title: 'Accessibility',
                  subtitle: 'Read foreground app, browser URL, WhatsApp draft',
                  granted: _accessibility,
                  onOpen: _svc.openAccessibilitySettings,
                ),
                _row(
                  icon: Icons.bar_chart_rounded,
                  title: 'Usage Stats',
                  subtitle: 'Detect last-foreground app as fallback',
                  granted: _usageStats,
                  onOpen: _svc.openUsageStatsSettings,
                ),
                _row(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notification Listener',
                  subtitle: 'Required to read media session (YouTube/Spotify)',
                  granted: _notifListener,
                  onOpen: _svc.openNotificationListenerSettings,
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.accentBlue.withValues(alpha: 0.12),
                    foregroundColor: AppColors.accentBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Done',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required Future<void> Function() onOpen,
  }) {
    final color = granted ? AppColors.success : AppColors.accentBlue;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
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
                        color: AppColors.textTertiary, fontSize: 11)),
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
}
