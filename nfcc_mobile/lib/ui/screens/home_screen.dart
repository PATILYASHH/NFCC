import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../services/pc_connection_service.dart';
import '../../services/silent_executor.dart';
import '../theme/app_theme.dart';
import '../widgets/tag_picker_sheet.dart';
import '../widgets/todo_tap_sheet.dart';
import '../../models/action_item.dart';
import '../../models/automation.dart';
import '../../models/condition_branch.dart';
import 'nfc_writer_screen.dart';
import 'routines_screen.dart';
import 'settings_screen.dart';
import 'smart_switch_screen.dart';
import 'todos_screen.dart';
import 'trackers_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int _routineCount = 0;
  int _smartSwitchTagCount = 0;
  int _trackerCount = 0;
  int _todoCount = 0;
  int _todosDoneToday = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    try {
      final db = context.read<DatabaseService>();
      final routines = await db.getAllAutomations();
      final trackers = await db.getAllTrackers();
      final todos = await db.getAllTodos();
      if (!mounted) return;
      setState(() {
        _routineCount = routines.length;
        _smartSwitchTagCount = routines.where(_isSmartSwitchOnly).length;
        _trackerCount = trackers.length;
        _todoCount = todos.length;
        _todosDoneToday = todos.where((t) => t.doneToday).length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Mirror of SmartSwitchScreen's classifier — keep in sync.
  /// Used to split the home counts so the Routines card doesn't
  /// double-count Smart Switch tags.
  static bool _isSmartSwitchOnly(Automation a) {
    if (a.tagUid == null) return false;
    if (a.branches.length != 1) return false;
    final b = a.branches.first;
    if (b.type != ConditionType.always) return false;
    if (b.actions.length != 1) return false;
    final act = b.actions.first;
    return act.target == ActionTarget.pc && act.actionType == 'smartSwitch';
  }

  Future<void> _openAndReload(Widget screen) async {
    hapticMedium();
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => screen));
    _loadCounts();
  }

  Future<void> _simulateTap() async {
    hapticMedium();
    final uids = await TagPickerSheet.show(context,
        multiSelect: false, title: 'Simulate a tap on…');
    if (uids == null || uids.isEmpty) return;
    final uid = uids.first;

    final result =
        await context.read<SilentExecutor>().foregroundTap(uid);

    if (!mounted) return;

    if (result.todos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          result.trackerSummary.isEmpty
              ? 'No trackers or TODOs paired to this tag'
              : result.trackerSummary,
        ),
        backgroundColor: result.trackerSummary.isEmpty
            ? AppColors.surfaceHigh
            : AppColors.success.withValues(alpha: 0.25),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      _loadCounts();
      return;
    }

    await TodoTapSheet.show(
      context,
      todos: result.todos,
      tagLabel: result.tagLabel,
      trackerSummary: result.trackerSummary,
    );
    _loadCounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildTabBar(),
            const SizedBox(height: 14),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSmartNfcTab(),
                  const NfcWriterScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [AppColors.accentWhite, AppColors.nfcGlow],
            ).createShader(b),
            child: const Text('NFCC',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('NFC Control',
                style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5)),
          ),
          const Spacer(),
          Consumer<PcConnectionService>(builder: (_, pc, __) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: pc.isConnected
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: pc.isConnected
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pc.isConnected
                          ? AppColors.success
                          : AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.desktop_windows_rounded,
                      size: 14,
                      color: pc.isConnected
                          ? AppColors.success
                          : AppColors.textTertiary),
                ],
              ),
            );
          }),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {
              hapticLight();
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            icon: const Icon(Icons.settings_rounded,
                size: 22, color: AppColors.textSecondary),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ─────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        onTap: (_) { hapticLight(); _loadCounts(); },
        indicator: BoxDecoration(
          color: AppColors.accentWhite,
          borderRadius: BorderRadius.circular(11),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(3),
        labelColor: Colors.black,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        tabs: const [
          Tab(text: 'Smart NFC'),
          Tab(text: 'NFC Writer'),
        ],
      ),
    );
  }

  // ── Smart NFC hub ───────────────────────────────────────────────────────

  Widget _buildSmartNfcTab() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppColors.nfcGlow, strokeWidth: 2.5));
    }
    return RefreshIndicator(
      onRefresh: _loadCounts,
      color: AppColors.nfcGlow,
      backgroundColor: AppColors.surfaceHigh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _buildCategoryCard(
            icon: Icons.swap_horiz_rounded,
            gradient: const [Color(0xFF00B0FF), Color(0xFF22D3EE)],
            title: 'Smart Switch',
            subtitle: 'Tag → send the page on your phone to PC',
            count: _smartSwitchTagCount,
            countLabel: _smartSwitchTagCount == 1 ? 'tag' : 'tags',
            onTap: () => _openAndReload(const SmartSwitchScreen()),
          ),
          const SizedBox(height: 12),
          _buildCategoryCard(
            icon: Icons.auto_awesome_rounded,
            gradient: const [Color(0xFF3B82F6), Color(0xFF00B0FF)],
            title: 'Routines',
            subtitle: 'Time / WiFi / BT based automations',
            count: _routineCount - _smartSwitchTagCount,
            countLabel:
                (_routineCount - _smartSwitchTagCount) == 1 ? 'automation' : 'automations',
            onTap: () => _openAndReload(const RoutinesScreen()),
          ),
          const SizedBox(height: 12),
          _buildCategoryCard(
            icon: Icons.timeline_rounded,
            gradient: const [Color(0xFF22D3EE), Color(0xFF3B82F6)],
            title: 'Tracking',
            subtitle: 'Water, coffee, IN / OUT — tap to log',
            count: _trackerCount,
            countLabel: _trackerCount == 1 ? 'tracker' : 'trackers',
            onTap: () => _openAndReload(const TrackersScreen()),
          ),
          const SizedBox(height: 12),
          _buildCategoryCard(
            icon: Icons.checklist_rounded,
            gradient: const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
            title: 'TODOs',
            subtitle: 'Daily tasks & streaks, tap to complete',
            count: _todoCount,
            countLabel: _todoCount == 1 ? 'task' : 'tasks',
            extra: _todoCount > 0
                ? '$_todosDoneToday / $_todoCount done today'
                : null,
            onTap: () => _openAndReload(const TodosScreen()),
          ),
          const SizedBox(height: 18),
          _buildSimulateTapButton(),
          const SizedBox(height: 18),
          _buildInfoFooter(),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required IconData icon,
    required List<Color> gradient,
    required String title,
    required String subtitle,
    required int count,
    required String countLabel,
    String? extra,
    required VoidCallback onTap,
  }) {
    final accent = gradient.first;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: -2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count $countLabel',
                            style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12.5,
                            height: 1.4)),
                    if (extra != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 12, color: accent),
                          const SizedBox(width: 4),
                          Text(extra,
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: accent.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimulateTapButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _simulateTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.nfcGlow.withValues(alpha: 0.35),
              width: 1.2,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.nfcGlow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.touch_app_rounded,
                    size: 22, color: AppColors.nfcGlow),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Simulate NFC tap',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('Fire trackers + open TODO picker for a tag UID',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11.5)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: AppColors.nfcGlow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoFooter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'One tag can belong to multiple trackers or TODOs. '
              'Tapping it will log & complete everything paired.',
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
