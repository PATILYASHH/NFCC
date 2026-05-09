"""App & command launching actions."""

import shutil
import subprocess
import webbrowser

from ._common import ActionResult, fail, ok

# Friendly app alias -> command or path. Extend freely.
APP_ALIASES = {
    "chrome": "chrome",
    "edge": "msedge",
    "firefox": "firefox",
    "vscode": "code",
    "code": "code",
    "notepad": "notepad",
    "calc": "calc",
    "calculator": "calc",
    "cmd": "cmd",
    "terminal": "wt",
    "powershell": "powershell",
    "explorer": "explorer",
    "paint": "mspaint",
    "tally": "tally",
    "spotify": "spotify",
    "discord": "discord",
    "whatsapp": "whatsapp",
    "telegram": "telegram",
    "excel": "excel",
    "word": "winword",
    "onenote": "onenote",
    "outlook": "outlook",
    "teams": "teams",
    "settings": "ms-settings:",
    "store": "ms-windows-store:",
    "photos": "ms-photos:",
    "camera": "microsoft.windows.camera:",
}


def launch_app(params: dict) -> ActionResult:
    """Launch an app, optionally passing a file/folder as its argument.

    params:
      name    — friendly alias (see APP_ALIASES) or any executable on PATH
      path    — full path to an .exe (takes precedence over name)
      target  — optional file/folder passed as argument to the app, e.g.
                name=vscode + target=C:\\repo  →  runs `code C:\\repo`
                name=chrome + target=https://… →  opens the URL in Chrome
    """
    path = (params.get("path") or "").strip()
    name = (params.get("name") or "").strip().lower()
    target = (params.get("target") or "").strip()
    app_cmd = path or APP_ALIASES.get(name, name)
    if not app_cmd:
        return fail("No path or name provided")

    # When the caller supplied no full path AND no alias matched, only
    # proceed if the bare name actually resolves to a real executable on
    # PATH or to a known shell URI scheme. Otherwise `cmd /c start "" <x>`
    # pops the system "Windows cannot find <x>" modal — which we never
    # want, especially on Smart Switch where `name` comes from whatever
    # Android reported as the foreground label.
    if not path and name and APP_ALIASES.get(name) is None:
        if not _looks_launchable(app_cmd):
            return fail(f"No PC equivalent for '{name}'")

    if target:
        # Direct exec so the app receives `target` as argv[1].
        try:
            subprocess.Popen([app_cmd, target])
            return ok(f"Launched: {app_cmd} {target}")
        except (FileNotFoundError, OSError):
            # Fall through to shell lookup.
            subprocess.Popen(
                ["cmd", "/c", "start", "", app_cmd, target], shell=False
            )
            return ok(f"Launched: {app_cmd} {target}")

    subprocess.Popen(["cmd", "/c", "start", "", app_cmd], shell=False)
    return ok(f"Launched: {app_cmd}")


def _looks_launchable(cmd: str) -> bool:
    """True if `cmd` is something `start ""` won't choke on."""
    if not cmd:
        return False
    # ms-settings:, ms-store:, mailto:, etc. — Windows resolves these.
    if ":" in cmd and not cmd[1:3] == ":\\":
        return True
    # Real binary on PATH.
    return shutil.which(cmd) is not None


def close_app(params: dict) -> ActionResult:
    pname = (params.get("processName") or "").strip()
    if not pname:
        return fail("No process name")
    if not pname.lower().endswith(".exe"):
        pname += ".exe"
    r = subprocess.run(
        ["taskkill", "/IM", pname, "/F"],
        capture_output=True, text=True,
    )
    if r.returncode == 0:
        return ok(f"Closed: {pname}")
    return fail(r.stderr.strip() or f"Could not close {pname}")


def open_url(params: dict) -> ActionResult:
    url = (params.get("url") or "").strip()
    if not url:
        return fail("No URL")
    if not url.startswith(("http://", "https://", "file:")):
        url = "https://" + url
    webbrowser.open(url)
    return ok(f"Opened: {url}")


def run_command(params: dict) -> ActionResult:
    cmd = params.get("command", "")
    if not cmd:
        return fail("No command")
    subprocess.Popen(["cmd", "/c", cmd])
    return ok(f"Running: {cmd}")


def open_path(params: dict) -> ActionResult:
    """Open a file or folder in Windows Explorer (or its default handler)."""
    path = (params.get("path") or "").strip()
    if not path:
        return fail("No path")
    subprocess.Popen(["explorer", path])
    return ok(f"Opened: {path}")


# ── Preset app shortcuts ─────────────────────────────────────────────────────

def open_notepad(_: dict) -> ActionResult:
    subprocess.Popen(["notepad"])
    return ok("Opened Notepad")


def open_calculator(_: dict) -> ActionResult:
    subprocess.Popen(["calc"])
    return ok("Opened Calculator")


def open_browser(_: dict) -> ActionResult:
    webbrowser.open("https://www.google.com")
    return ok("Opened browser")


def open_terminal(_: dict) -> ActionResult:
    try:
        subprocess.Popen(["wt"])
        return ok("Opened Windows Terminal")
    except FileNotFoundError:
        subprocess.Popen(["cmd"])
        return ok("Opened cmd")


def open_settings(_: dict) -> ActionResult:
    subprocess.Popen(["cmd", "/c", "start", "ms-settings:"])
    return ok("Opened Settings")
