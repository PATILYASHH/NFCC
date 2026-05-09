import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/automation.dart';
import '../../models/condition_branch.dart';
import '../../models/action_item.dart';
import '../../services/database_service.dart';
import '../theme/app_theme.dart';
import 'condition_picker_screen.dart';
import 'action_picker_screen.dart';

/// Samsung Modes & Routines style editor
/// Two clear sections: IF (conditions) → THEN (actions)
class AutomationEditorScreen extends StatefulWidget {
  final Automation? automation;
  const AutomationEditorScreen({super.key, this.automation});

  @override
  State<AutomationEditorScreen> createState() => _AutomationEditorScreenState();
}

class _AutomationEditorScreenState extends State<AutomationEditorScreen> {
  late TextEditingController _nameController;
  late List<ConditionBranch> _branches;
  bool _isNew = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _isNew = widget.automation == null;
    _nameController = TextEditingController(text: widget.automation?.name ?? '');
    // Deep-copy branches so edits don't mutate widget.automation in place
    // (which would survive a "discard" / back navigation).
    _branches = (widget.automation?.branches ?? const [])
        .map((b) => b.copyWith(
              subConditions: List.of(b.subConditions),
              actions: List.of(b.actions),
            ))
        .toList();
    if (_branches.isEmpty) {
      // Fresh automation: start with an empty IF branch the user can fill in,
      // not an "Otherwise" branch (which hides the condition picker).
      _branches.add(ConditionBranch(
        orderIndex: 0,
        type: ConditionType.timeRange,
        actions: const [],
      ));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Condition management ──────────────────────────────────────────────

  void _addTimeBranch() {
    setState(() {
      final idx = _branches.length > 1 ? _branches.length - 1 : 0;
      _branches.insert(idx, ConditionBranch(
        orderIndex: idx,
        type: ConditionType.timeRange,
        subConditions: [
          SubCondition(type: 'time', params: {
            'startHour': 9, 'startMinute': 0,
            'endHour': 17, 'endMinute': 0,
          }),
        ],
        actions: [],
      ));
      _reindex();
    });
  }

  void _removeBranch(int i) {
    if (_branches.length <= 1) return;
    setState(() { _branches.removeAt(i); _reindex(); });
  }

  void _reindex() {
    for (var i = 0; i < _branches.length; i++) {
      _branches[i] = _branches[i].copyWith(orderIndex: i);
    }
  }

  Future<void> _addConditionToBranch(int branchIdx) async {
    final result = await Navigator.push<SubCondition>(
      context,
      MaterialPageRoute(builder: (_) => const ConditionPickerScreen()),
    );
    if (result != null) {
      setState(() {
        final branch = _branches[branchIdx];
        _branches[branchIdx] = branch.copyWith(
          subConditions: [...branch.subConditions, result],
        );
      });
    }
  }

  void _removeSubCondition(int branchIdx, int subIdx) {
    setState(() {
      final branch = _branches[branchIdx];
      final subs = [...branch.subConditions]..removeAt(subIdx);
      _branches[branchIdx] = branch.copyWith(subConditions: subs);
    });
  }

  // ── Action management ─────────────────────────────────────────────────

  Future<void> _addAction(int branchIdx) async {
    final action = await Navigator.push<ActionItem>(
      context,
      MaterialPageRoute(builder: (_) => const ActionPickerScreen()),
    );
    if (action != null) {
      setState(() {
        final branch = _branches[branchIdx];
        _branches[branchIdx] = branch.copyWith(
          actions: [...branch.actions, action.copyWith(orderIndex: branch.actions.length)],
        );
      });
    }
  }

  void _removeAction(int branchIdx, int actionIdx) {
    setState(() {
      final branch = _branches[branchIdx];
      _branches[branchIdx] = branch.copyWith(
        actions: [...branch.actions]..removeAt(actionIdx),
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return; // guard double-tap while DB write is in flight
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name for this Smart NFC')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final db = context.read<DatabaseService>();
      final now = DateTime.now();
      if (_isNew) {
        await db.insertAutomation(Automation(
          name: name, branches: _branches, createdAt: now, updatedAt: now,
        ));
      } else {
        await db.updateAutomation(widget.automation!.copyWith(
          name: name, branches: _branches, updatedAt: now,
        ));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isNew ? 'Add Smart NFC' : 'Edit Smart NFC',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accentBlue),
                  )
                : const Text('Save',
                    style: TextStyle(
                        color: AppColors.accentBlue,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          // ── Name ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Smart NFC name',
                hintStyle: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w400),
                border: InputBorder.none,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Branches ──
          ..._branches.asMap().entries.map((e) => _buildBranch(e.key, e.value)),

          // ── Add time block ──
          const SizedBox(height: 12),
          _addBlockButton('Add time block', Icons.add_rounded, _addTimeBranch),
        ],
      ),
    );
  }

  // ── Branch card ─────────────────────────────────────────────────────────

  Widget _buildBranch(int idx, ConditionBranch branch) {
    final isElse = branch.type == ConditionType.always;
    final isFirst = idx == 0 && !isElse;
    final label = isFirst ? 'If' : isElse ? 'Otherwise' : 'Else if';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── IF section ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppColors.accentBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (!isElse && _branches.length > 1)
                      GestureDetector(
                        onTap: () => _removeBranch(idx),
                        child: const Icon(Icons.close_rounded,
                            size: 18, color: AppColors.textTertiary),
                      ),
                  ],
                ),

                if (!isElse) ...[
                  const SizedBox(height: 10),
                  // Sub-conditions
                  if (branch.subConditions.isEmpty)
                    _addTriggerButton(() => _addConditionToBranch(idx))
                  else ...[
                    ...branch.subConditions.asMap().entries.map((se) =>
                        _conditionTile(se.value, idx, se.key)),
                    const SizedBox(height: 6),
                    _addMoreButton('Add condition', () => _addConditionToBranch(idx)),
                  ],
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Runs when no other conditions match',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                  ),
              ],
            ),
          ),

          // ── Divider ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 1,
            color: AppColors.divider,
          ),

          // ── THEN section ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Then',
                    style: TextStyle(
                        color: AppColors.success,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),

                if (branch.actions.isEmpty)
                  _addTriggerButton(() => _addAction(idx), isAction: true)
                else ...[
                  ...branch.actions.asMap().entries.map((ae) =>
                      _actionTile(ae.value, idx, ae.key)),
                  const SizedBox(height: 6),
                  _addMoreButton('Add action', () => _addAction(idx)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Condition tile ────────────────────────────────────────────────────

  Widget _conditionTile(SubCondition sub, int branchIdx, int subIdx) {
    IconData icon;
    Color color;
    switch (sub.type) {
      case 'time':
        icon = Icons.schedule_rounded;
        color = AppColors.accentBlue;
      case 'day':
        icon = Icons.calendar_today_rounded;
        color = AppColors.accentPurple;
      case 'btConnected':
        icon = Icons.bluetooth_rounded;
        color = AppColors.accentCyan;
      case 'wifiConnected':
        icon = Icons.wifi_rounded;
        color = AppColors.accentOrange;
      default:
        icon = Icons.tune_rounded;
        color = AppColors.textSecondary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(sub.label,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ),
          if (branchIdx < _branches.length)
            IconButton(
              onPressed: () => _removeSubCondition(branchIdx, subIdx),
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  size: 18, color: AppColors.textTertiary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
        ],
      ),
    );
  }

  // ── Action tile with optional "only if" condition ───────────────────

  Widget _actionTile(ActionItem action, int branchIdx, int actionIdx) {
    final isPhone = action.target == ActionTarget.phone;
    final color = isPhone ? AppColors.accentCyan : AppColors.accentOrange;
    final icon = isPhone ? Icons.phone_android_rounded : Icons.desktop_windows_rounded;
    final paramStr = action.params.isNotEmpty ? action.params.values.first.toString() : '';
    final hasCondition = action.onlyIf != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: hasCondition
            ? Border.all(color: AppColors.warning.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main action row
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 8, hasCondition ? 4 : 10),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(action.displayName,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      if (paramStr.isNotEmpty)
                        Text(paramStr,
                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                // Add condition button
                GestureDetector(
                  onTap: () => _addConditionToAction(branchIdx, actionIdx),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      hasCondition ? Icons.rule_rounded : Icons.add_task_rounded,
                      size: 16,
                      color: hasCondition ? AppColors.warning : AppColors.textTertiary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _removeAction(branchIdx, actionIdx),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.remove_circle_outline_rounded,
                        size: 16, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),

          // "Only if" condition display
          if (hasCondition)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.rule_rounded, size: 12, color: AppColors.warning),
                        const SizedBox(width: 4),
                        Text('only if ${action.onlyIf!.label}',
                            style: const TextStyle(color: AppColors.warning, fontSize: 11)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _removeConditionFromAction(branchIdx, actionIdx),
                          child: Icon(Icons.close_rounded, size: 12,
                              color: AppColors.warning.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                  if (action.elseActions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Text('else: ', style: TextStyle(color: AppColors.error, fontSize: 11)),
                          Text(action.elseActions.map((e) => e.displayName).join(', '),
                              style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addConditionToAction(int branchIdx, int actionIdx) async {
    final cond = await Navigator.push<SubCondition>(
      context,
      MaterialPageRoute(builder: (_) => const ConditionPickerScreen()),
    );
    if (cond == null) return;

    // Ask if user wants an else action
    ActionItem? elseAction;
    if (mounted) {
      final wantElse = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceHigh,
          title: const Text('Add else action?'),
          content: const Text('What should happen if this condition is NOT met?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, just skip', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, add else', style: TextStyle(color: AppColors.accentBlue)),
            ),
          ],
        ),
      );

      if (wantElse == true && mounted) {
        elseAction = await Navigator.push<ActionItem>(
          context,
          MaterialPageRoute(builder: (_) => const ActionPickerScreen()),
        );
      }
    }

    setState(() {
      final branch = _branches[branchIdx];
      final actions = [...branch.actions];
      actions[actionIdx] = actions[actionIdx].copyWith(
        onlyIf: cond,
        elseActions: elseAction != null ? [elseAction] : [],
      );
      _branches[branchIdx] = branch.copyWith(actions: actions);
    });
  }

  void _removeConditionFromAction(int branchIdx, int actionIdx) {
    setState(() {
      final branch = _branches[branchIdx];
      final actions = [...branch.actions];
      actions[actionIdx] = ActionItem(
        id: actions[actionIdx].id,
        conditionBranchId: actions[actionIdx].conditionBranchId,
        orderIndex: actions[actionIdx].orderIndex,
        target: actions[actionIdx].target,
        actionType: actions[actionIdx].actionType,
        params: actions[actionIdx].params,
        delayMs: actions[actionIdx].delayMs,
      );
      _branches[branchIdx] = branch.copyWith(actions: actions);
    });
  }

  // ── Buttons ───────────────────────────────────────────────────────────

  Widget _addTriggerButton(VoidCallback onTap, {bool isAction = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isAction ? AppColors.success : AppColors.accentBlue)
                .withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 18,
                color: isAction ? AppColors.success : AppColors.accentBlue),
            const SizedBox(width: 6),
            Text(
              isAction ? 'Add what this Smart NFC will do' : 'Add what will trigger this Smart NFC',
              style: TextStyle(
                color: isAction ? AppColors.success : AppColors.accentBlue,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addMoreButton(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.add_rounded, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _addBlockButton(String text, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(text,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
