import 'dart:convert';
import 'condition_branch.dart';

enum ActionTarget { phone, pc }

enum PhoneActionType {
  wifiOn,
  wifiOff,
  toggleWifi,
  btOn,
  btOff,
  toggleBluetooth,
  mobileDataOn,
  mobileDataOff,
  toggleMobileData,
  wifiConnect,
  btConnect,
  connectWifi,
  musicPlayPause,
  musicNext,
  musicPrevious,
  musicShuffle,
  setVolume,
  toggleDnd,
  openApp,
  setBrightness,
  toggleFlashlight,
}

enum PcActionType {
  // Handoff
  smartSwitch,
  // Apps & commands
  launchApp,
  closeApp,
  openUrl,
  runCommand,
  openPath,
  openNotepad,
  openCalculator,
  openBrowser,
  openTerminal,
  openSettings,
  // Window management
  minimizeAll,
  maximizeWindow,
  snapLeft,
  snapRight,
  closeWindow,
  switchWindow,
  taskView,
  showDesktop,
  newVirtualDesktop,
  closeVirtualDesktop,
  nextVirtualDesktop,
  prevVirtualDesktop,
  projectMenu,
  // System
  lockPc,
  shutdownPc,
  restartPc,
  cancelShutdown,
  sleepPc,
  hibernatePc,
  signOut,
  setPowerPlan,
  emptyRecycleBin,
  // Volume & Media
  toggleMute,
  setVolume,
  volumeUp,
  volumeDown,
  mediaPlayPause,
  mediaNext,
  mediaPrev,
  mediaStop,
  // Input (keyboard/mouse/clipboard)
  typeText,
  sendKeys,
  copy,
  paste,
  cut,
  selectAll,
  undo,
  redo,
  zoomIn,
  zoomOut,
  mouseClick,
  mouseDoubleClick,
  mouseMove,
  scrollUp,
  scrollDown,
  setClipboard,
  clipboardHistory,
  wait,
  // Screen
  screenshot,
  printScreen,
  screenOff,
  screenOn,
  setBrightness,
  gameBar,
  toggleRecording,
  // Shortcuts
  openFileExplorer,
  openTaskManager,
  openRunDialog,
  openActionCenter,
  openNotificationCenter,
  openStartMenu,
  openSearch,
  openWidgets,
  emojiPicker,
  // Network
  wifiOn,
  wifiOff,
  wifiConnect,
  wifiDisconnect,
  ethernetOn,
  ethernetOff,
  flightMode,
  // Info
  systemInfo,
  batteryStatus,
  listProcesses,
  killProcess,
  getIp,
}

class ActionItem {
  final int? id;
  final int? conditionBranchId;
  final int orderIndex;
  final ActionTarget target;
  final String actionType;
  final Map<String, dynamic> params;
  final int delayMs;

  /// Optional "only if" condition - action runs ONLY when this is true.
  /// e.g. "play music ONLY IF BT connected to Galaxy Buds"
  final SubCondition? onlyIf;

  /// Actions to run when onlyIf is FALSE (the else branch)
  final List<ActionItem> elseActions;

  ActionItem({
    this.id,
    this.conditionBranchId,
    required this.orderIndex,
    required this.target,
    required this.actionType,
    this.params = const {},
    this.delayMs = 0,
    this.onlyIf,
    this.elseActions = const [],
  });

  String get displayName {
    final name = actionType
        .replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m.group(0)}')
        .trim();
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  IconInfo get icon {
    if (target == ActionTarget.phone) {
      switch (actionType) {
        case 'wifiOn':
          return IconInfo(0xe63e, 'WiFi ON');
        case 'wifiOff':
          return IconInfo(0xf0593, 'WiFi OFF');
        case 'toggleWifi':
          return IconInfo(0xe63e, 'WiFi');
        case 'btOn':
          return IconInfo(0xe1a7, 'BT ON');
        case 'btOff':
          return IconInfo(0xf00b1, 'BT OFF');
        case 'toggleBluetooth':
          return IconInfo(0xe1a7, 'Bluetooth');
        case 'mobileDataOn':
          return IconInfo(0xf0580, 'Data ON');
        case 'mobileDataOff':
          return IconInfo(0xf0581, 'Data OFF');
        case 'toggleMobileData':
          return IconInfo(0xf0580, 'Mobile Data');
        case 'wifiConnect':
          return IconInfo(0xe63e, 'Connect WiFi');
        case 'btConnect':
          return IconInfo(0xe1a7, 'Connect BT');
        case 'connectWifi':
          return IconInfo(0xe63e, 'Connect WiFi');
        case 'musicPlayPause':
          return IconInfo(0xe40a, 'Play/Pause');
        case 'musicNext':
          return IconInfo(0xe044, 'Next Track');
        case 'musicPrevious':
          return IconInfo(0xe045, 'Previous');
        case 'musicShuffle':
          return IconInfo(0xe043, 'Shuffle');
        case 'setVolume':
          return IconInfo(0xe050, 'Volume');
        case 'toggleDnd':
          return IconInfo(0xe510, 'DND');
        case 'openApp':
          return IconInfo(0xe5c3, 'Open App');
        case 'setBrightness':
          return IconInfo(0xe1ac, 'Brightness');
        case 'toggleFlashlight':
          return IconInfo(0xe3e8, 'Flashlight');
        default:
          return IconInfo(0xe8b8, actionType);
      }
    } else {
      switch (actionType) {
        case 'smartSwitch':
          return IconInfo(0xe8d5, 'Smart Switch'); // swap_horiz
        case 'launchApp':
          return IconInfo(0xe5c3, 'Launch App');
        case 'minimizeAll':
          return IconInfo(0xe5d6, 'Minimize All');
        case 'maximizeWindow':
          return IconInfo(0xf00a0, 'Maximize');
        case 'snapLeft':
          return IconInfo(0xf0568, 'Snap Left');
        case 'snapRight':
          return IconInfo(0xf0569, 'Snap Right');
        case 'closeApp':
          return IconInfo(0xe5cd, 'Close App');
        case 'closeWindow':
          return IconInfo(0xe5cd, 'Close Window');
        case 'switchWindow':
          return IconInfo(0xe8e1, 'Switch Window');
        case 'taskView':
          return IconInfo(0xf06df, 'Task View');
        case 'openUrl':
          return IconInfo(0xe89e, 'Open URL');
        case 'runCommand':
          return IconInfo(0xe8b8, 'Run Command');
        case 'lockPc':
          return IconInfo(0xe897, 'Lock PC');
        case 'shutdownPc':
          return IconInfo(0xe8ac, 'Shutdown');
        case 'restartPc':
          return IconInfo(0xe5d5, 'Restart');
        case 'cancelShutdown':
          return IconInfo(0xe5c9, 'Cancel Shutdown');
        case 'sleepPc':
          return IconInfo(0xef44, 'Sleep');
        case 'openSettings':
          return IconInfo(0xe8b8, 'Settings');
        case 'toggleMute':
          return IconInfo(0xe04f, 'Mute');
        case 'setVolume':
          return IconInfo(0xe050, 'Volume');
        case 'volumeUp':
          return IconInfo(0xe050, 'Volume Up');
        case 'volumeDown':
          return IconInfo(0xe04d, 'Volume Down');
        case 'mediaPlayPause':
          return IconInfo(0xe40a, 'Play/Pause');
        case 'mediaNext':
          return IconInfo(0xe044, 'Next');
        case 'mediaPrev':
          return IconInfo(0xe045, 'Previous');
        case 'mediaStop':
          return IconInfo(0xe047, 'Stop');
        case 'screenshot':
          return IconInfo(0xf0654, 'Screenshot');
        case 'openFileExplorer':
          return IconInfo(0xe2c7, 'File Explorer');
        case 'openTaskManager':
          return IconInfo(0xf06b5, 'Task Manager');
        case 'clipboardHistory':
          return IconInfo(0xe14f, 'Clipboard');
        case 'screenOff':
          return IconInfo(0xf0655, 'Screen Off');
        case 'screenOn':
          return IconInfo(0xe30b, 'Screen On');
        case 'setBrightness':
          return IconInfo(0xe1ac, 'Brightness');
        // ── Apps & shortcuts (new) ──
        case 'openPath':
          return IconInfo(0xe2c7, 'Open Path');
        case 'openNotepad':
          return IconInfo(0xe873, 'Notepad');
        case 'openCalculator':
          return IconInfo(0xea5f, 'Calculator');
        case 'openBrowser':
          return IconInfo(0xe89e, 'Browser');
        case 'openTerminal':
          return IconInfo(0xeb8e, 'Terminal');
        case 'openRunDialog':
          return IconInfo(0xe8ac, 'Run');
        case 'openActionCenter':
          return IconInfo(0xe7f4, 'Action Center');
        case 'openNotificationCenter':
          return IconInfo(0xe7f4, 'Notifications');
        case 'openStartMenu':
          return IconInfo(0xe88a, 'Start');
        case 'openSearch':
          return IconInfo(0xe8b6, 'Search');
        case 'openWidgets':
          return IconInfo(0xe8f0, 'Widgets');
        case 'emojiPicker':
          return IconInfo(0xea22, 'Emoji');
        // ── Virtual desktops ──
        case 'newVirtualDesktop':
          return IconInfo(0xe145, 'New Desktop');
        case 'closeVirtualDesktop':
          return IconInfo(0xe5cd, 'Close Desktop');
        case 'nextVirtualDesktop':
          return IconInfo(0xe5c8, 'Next Desktop');
        case 'prevVirtualDesktop':
          return IconInfo(0xe5c4, 'Prev Desktop');
        case 'projectMenu':
          return IconInfo(0xe30a, 'Projection');
        // ── System (new) ──
        case 'hibernatePc':
          return IconInfo(0xef44, 'Hibernate');
        case 'signOut':
          return IconInfo(0xe9ba, 'Sign out');
        case 'setPowerPlan':
          return IconInfo(0xe1a4, 'Power Plan');
        case 'emptyRecycleBin':
          return IconInfo(0xe872, 'Empty Bin');
        // ── Input ──
        case 'typeText':
          return IconInfo(0xe262, 'Type Text');
        case 'copy':
          return IconInfo(0xe14d, 'Copy');
        case 'paste':
          return IconInfo(0xe14f, 'Paste');
        case 'cut':
          return IconInfo(0xe14e, 'Cut');
        case 'selectAll':
          return IconInfo(0xe162, 'Select All');
        case 'undo':
          return IconInfo(0xe166, 'Undo');
        case 'redo':
          return IconInfo(0xe15a, 'Redo');
        case 'zoomIn':
          return IconInfo(0xe8ff, 'Zoom In');
        case 'zoomOut':
          return IconInfo(0xe900, 'Zoom Out');
        case 'mouseClick':
          return IconInfo(0xe323, 'Click');
        case 'mouseDoubleClick':
          return IconInfo(0xe323, 'Double Click');
        case 'mouseMove':
          return IconInfo(0xe323, 'Move Mouse');
        case 'scrollUp':
          return IconInfo(0xe316, 'Scroll Up');
        case 'scrollDown':
          return IconInfo(0xe313, 'Scroll Down');
        case 'setClipboard':
          return IconInfo(0xe14f, 'Set Clipboard');
        case 'wait':
          return IconInfo(0xe425, 'Wait');
        // ── Screen (new) ──
        case 'printScreen':
          return IconInfo(0xe8ad, 'Print Screen');
        case 'gameBar':
          return IconInfo(0xe021, 'Game Bar');
        case 'toggleRecording':
          return IconInfo(0xe61e, 'Record');
        // ── Network ──
        case 'wifiOn':
          return IconInfo(0xe63e, 'Wi-Fi On');
        case 'wifiOff':
          return IconInfo(0xf0593, 'Wi-Fi Off');
        case 'wifiConnect':
          return IconInfo(0xe63e, 'Connect Wi-Fi');
        case 'wifiDisconnect':
          return IconInfo(0xf0593, 'Disconnect Wi-Fi');
        case 'ethernetOn':
          return IconInfo(0xe80d, 'Ethernet On');
        case 'ethernetOff':
          return IconInfo(0xe80d, 'Ethernet Off');
        case 'flightMode':
          return IconInfo(0xe195, 'Airplane');
        // ── Info ──
        case 'systemInfo':
          return IconInfo(0xe88e, 'System Info');
        case 'batteryStatus':
          return IconInfo(0xe1a4, 'Battery');
        case 'listProcesses':
          return IconInfo(0xe8b5, 'Processes');
        case 'killProcess':
          return IconInfo(0xe5cd, 'Kill Process');
        case 'getIp':
          return IconInfo(0xe51a, 'IP Address');
        default:
          return IconInfo(0xe30a, actionType);
      }
    }
  }

  Map<String, dynamic> toMap() {
    final p = Map<String, dynamic>.from(params);
    if (onlyIf != null) {
      p['_onlyIf'] = onlyIf!.toMap();
    }
    if (elseActions.isNotEmpty) {
      p['_elseActions'] = elseActions.map((a) => {
        'target': a.target.name,
        'action_type': a.actionType,
        'params': a.params,
      }).toList();
    }
    return {
      if (id != null) 'id': id,
      if (conditionBranchId != null) 'condition_branch_id': conditionBranchId,
      'order_index': orderIndex,
      'target': target.name,
      'action_type': actionType,
      'params': jsonEncode(p),
      'delay_ms': delayMs,
    };
  }

  factory ActionItem.fromMap(Map<String, dynamic> map) {
    final rawParams = map['params'] is String
        ? jsonDecode(map['params'] as String) as Map<String, dynamic>
        : (map['params'] as Map<String, dynamic>?) ?? {};

    SubCondition? onlyIf;
    if (rawParams['_onlyIf'] != null) {
      onlyIf = SubCondition.fromMap(rawParams['_onlyIf'] as Map<String, dynamic>);
    }

    List<ActionItem> elseActions = [];
    if (rawParams['_elseActions'] != null) {
      elseActions = (rawParams['_elseActions'] as List).map((e) {
        final m = e as Map<String, dynamic>;
        return ActionItem(
          orderIndex: 0,
          target: ActionTarget.values.firstWhere(
            (t) => t.name == (m['target'] as String?),
            orElse: () => ActionTarget.phone,
          ),
          actionType: m['action_type'] as String,
          params: (m['params'] as Map<String, dynamic>?) ?? {},
        );
      }).toList();
    }

    // Clean internal fields from params
    final cleanParams = Map<String, dynamic>.from(rawParams)
      ..remove('_onlyIf')
      ..remove('_elseActions');

    return ActionItem(
      id: map['id'] as int?,
      conditionBranchId: map['condition_branch_id'] as int?,
      orderIndex: map['order_index'] as int? ?? 0,
      target: ActionTarget.values.firstWhere(
        (e) => e.name == (map['target'] as String?),
        orElse: () => ActionTarget.phone,
      ),
      actionType: map['action_type'] as String,
      params: cleanParams,
      delayMs: map['delay_ms'] as int? ?? 0,
      onlyIf: onlyIf,
      elseActions: elseActions,
    );
  }

  ActionItem copyWith({
    int? id,
    int? conditionBranchId,
    int? orderIndex,
    ActionTarget? target,
    String? actionType,
    Map<String, dynamic>? params,
    int? delayMs,
    SubCondition? onlyIf,
    List<ActionItem>? elseActions,
  }) =>
      ActionItem(
        id: id ?? this.id,
        conditionBranchId: conditionBranchId ?? this.conditionBranchId,
        orderIndex: orderIndex ?? this.orderIndex,
        target: target ?? this.target,
        actionType: actionType ?? this.actionType,
        params: params ?? this.params,
        delayMs: delayMs ?? this.delayMs,
        onlyIf: onlyIf ?? this.onlyIf,
        elseActions: elseActions ?? this.elseActions,
      );
}

class IconInfo {
  final int codePoint;
  final String label;
  IconInfo(this.codePoint, this.label);
}
