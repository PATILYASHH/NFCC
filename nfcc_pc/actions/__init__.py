"""NFCC PC action registry.

Each registered handler takes a dict of params and returns
(success: bool, message: str, data: dict).

Keep this module as a thin router — put logic in category modules.
"""

from typing import Callable, Dict

from . import apps, handoff, info, input_, media, network, screen, shortcuts, system, window
from ._common import ActionResult

Handler = Callable[[dict], ActionResult]


ACTION_MAP: Dict[str, Handler] = {
    # Handoff
    "smartSwitch": handoff.smart_switch,

    # Apps & commands
    "launchApp": apps.launch_app,
    "closeApp": apps.close_app,
    "openUrl": apps.open_url,
    "runCommand": apps.run_command,
    "openPath": apps.open_path,
    "openNotepad": apps.open_notepad,
    "openCalculator": apps.open_calculator,
    "openBrowser": apps.open_browser,
    "openTerminal": apps.open_terminal,
    "openSettings": apps.open_settings,

    # Windows
    "minimizeAll": window.minimize_all,
    "maximizeWindow": window.maximize_window,
    "snapLeft": window.snap_left,
    "snapRight": window.snap_right,
    "closeWindow": window.close_window,
    "switchWindow": window.switch_window,
    "taskView": window.task_view,
    "showDesktop": window.show_desktop,
    "newVirtualDesktop": window.vd_new,
    "closeVirtualDesktop": window.vd_close,
    "nextVirtualDesktop": window.vd_next,
    "prevVirtualDesktop": window.vd_prev,
    "projectMenu": window.open_project_menu,

    # System / power
    "lockPc": system.lock_pc,
    "shutdownPc": system.shutdown_pc,
    "restartPc": system.restart_pc,
    "cancelShutdown": system.cancel_shutdown,
    "sleepPc": system.sleep_pc,
    "hibernatePc": system.hibernate_pc,
    "signOut": system.sign_out,
    "setPowerPlan": system.set_power_plan,
    "emptyRecycleBin": system.empty_recycle_bin,

    # Volume / media
    "toggleMute": media.toggle_mute,
    "setVolume": media.set_volume,
    "volumeUp": media.volume_up,
    "volumeDown": media.volume_down,
    "mediaPlayPause": media.media_play_pause,
    "mediaNext": media.media_next,
    "mediaPrev": media.media_prev,
    "mediaStop": media.media_stop,

    # Input (keyboard/mouse/clipboard)
    "typeText": input_.type_text,
    "sendKeys": input_.send_keys,
    "copy": input_.copy_selection,
    "paste": input_.paste,
    "cut": input_.cut_selection,
    "selectAll": input_.select_all,
    "undo": input_.undo,
    "redo": input_.redo,
    "zoomIn": input_.zoom_in,
    "zoomOut": input_.zoom_out,
    "mouseClick": input_.mouse_click,
    "mouseDoubleClick": input_.mouse_double_click,
    "mouseMove": input_.mouse_move,
    "scroll": input_.scroll,
    "scrollUp": input_.scroll_up,
    "scrollDown": input_.scroll_down,
    "setClipboard": input_.set_clipboard,
    "clipboardHistory": input_.clipboard_history,
    "wait": input_.wait,

    # Screen
    "screenshot": screen.screenshot,
    "printScreen": screen.print_screen,
    "screenOff": screen.screen_off,
    "screenOn": screen.screen_on,
    "setBrightness": screen.set_brightness,
    "gameBar": screen.game_bar,
    "toggleRecording": screen.toggle_recording,

    # Shortcuts
    "openFileExplorer": shortcuts.open_file_explorer,
    "openTaskManager": shortcuts.open_task_manager,
    "openRunDialog": shortcuts.open_run_dialog,
    "openActionCenter": shortcuts.open_action_center,
    "openNotificationCenter": shortcuts.open_notification_center,
    "openStartMenu": shortcuts.open_start_menu,
    "openSearch": shortcuts.open_search,
    "openWidgets": shortcuts.open_widgets,
    "emojiPicker": shortcuts.emoji_picker,

    # Network
    "wifiOn": network.wifi_on,
    "wifiOff": network.wifi_off,
    "wifiConnect": network.wifi_connect,
    "wifiDisconnect": network.wifi_disconnect,
    "ethernetOn": network.ethernet_on,
    "ethernetOff": network.ethernet_off,
    "flightMode": network.flight_mode,

    # Info (returns data)
    "systemInfo": info.system_info,
    "batteryStatus": info.battery_status,
    "listProcesses": info.list_processes,
    "killProcess": info.kill_process,
    "getIp": info.get_ip,
}


def available_actions() -> list[str]:
    return sorted(ACTION_MAP.keys())
