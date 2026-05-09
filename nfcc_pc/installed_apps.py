"""Installed-application scanner + lookup index.

Powers the dashboard's "App Scanner" panel and the handoff fallback
when Smart Switch hands off a generic app the static APP_ALIASES table
doesn't know about (e.g. 'anydesk', 'figma', 'obsidian').

Scan strategy — fastest first, no third-party deps:

  1. Per-user + per-machine "App Paths" registry keys (HKCR / HKLM).
     This is what `start <name>` uses internally; if Windows can resolve
     it, we should too.
  2. PowerShell COM walk over Start Menu .lnk shortcuts, both
     ProgramData (system) and per-user. The shell's WScript.Shell
     dereferences each .lnk to its TargetPath. This catches everything
     the user actually sees in their Start Menu — far more than App
     Paths alone.
  3. Optional manual entries the user added from the dashboard, kept
     verbatim.

Results cache in ~/.nfcc/installed_apps.json so subsequent dashboard
loads are instant. The dashboard's "Rescan" button forces a fresh
walk.
"""
from __future__ import annotations

import json
import os
import subprocess
import threading
import time
from typing import Any, Dict, List, Optional

from config import CONFIG_DIR

CACHE_FILE = os.path.join(CONFIG_DIR, "installed_apps.json")

# Re-scan this often even if the user doesn't click Rescan — newly
# installed apps appear without manual intervention.
DEFAULT_TTL_SECONDS = 24 * 60 * 60

_scan_lock = threading.Lock()


# ── Cache I/O ───────────────────────────────────────────────────────────────

def _read_cache() -> Dict[str, Any]:
    if not os.path.exists(CACHE_FILE):
        return {"scannedAt": 0, "apps": [], "manual": []}
    try:
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return {"scannedAt": 0, "apps": [], "manual": []}
    data.setdefault("scannedAt", 0)
    data.setdefault("apps", [])
    data.setdefault("manual", [])
    return data


def _write_cache(data: Dict[str, Any]) -> None:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CACHE_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


# ── App Paths registry ─────────────────────────────────────────────────────

def _scan_app_paths() -> List[Dict[str, str]]:
    """Read HKLM + HKCU `App Paths` so `start <foo>` lookups work for us."""
    found: Dict[str, Dict[str, str]] = {}
    try:
        import winreg
    except ImportError:
        return []
    roots = (
        (winreg.HKEY_LOCAL_MACHINE,
         r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"),
        (winreg.HKEY_CURRENT_USER,
         r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"),
    )
    for root, path in roots:
        try:
            with winreg.OpenKey(root, path) as key:
                i = 0
                while True:
                    try:
                        sub = winreg.EnumKey(key, i)
                    except OSError:
                        break
                    i += 1
                    try:
                        with winreg.OpenKey(key, sub) as subkey:
                            target, _ = winreg.QueryValueEx(subkey, "")
                            if not target:
                                continue
                            target = target.strip().strip('"')
                            if not os.path.isfile(target):
                                continue
                            name = sub.removesuffix(".exe")
                            found[target.lower()] = {
                                "name": name,
                                "path": target,
                                "source": "AppPaths",
                            }
                    except OSError:
                        continue
        except OSError:
            continue
    return list(found.values())


# ── Start Menu .lnk walk via PowerShell ─────────────────────────────────────

_PS_SCRIPT = r"""
$ErrorActionPreference = 'SilentlyContinue'
$shell = New-Object -ComObject WScript.Shell
$dirs = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
)
$out = @()
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { continue }
    Get-ChildItem -LiteralPath $d -Recurse -Filter *.lnk -Force |
        ForEach-Object {
            try {
                $sc = $shell.CreateShortcut($_.FullName)
                $tp = $sc.TargetPath
                if (-not $tp) { return }
                # Skip uninstallers / docs / web-shortcuts.
                if ($tp -match '(?i)(uninstall|^https?://|\.url$|\.chm$|\.pdf$)') { return }
                if ($tp -notmatch '\.exe$') { return }
                $out += [PSCustomObject]@{
                    name = $_.BaseName
                    path = $tp
                    args = $sc.Arguments
                }
            } catch { }
        }
}
$out | ConvertTo-Json -Compress -Depth 2
"""


def _scan_start_menu() -> List[Dict[str, str]]:
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive",
             "-ExecutionPolicy", "Bypass", "-Command", _PS_SCRIPT],
            capture_output=True, text=True, timeout=30,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return []
    raw = (result.stdout or "").strip()
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if isinstance(parsed, dict):  # single result → object, not array
        parsed = [parsed]
    out: List[Dict[str, str]] = []
    seen: set[str] = set()
    for entry in parsed:
        if not isinstance(entry, dict):
            continue
        path = (entry.get("path") or "").strip()
        name = (entry.get("name") or "").strip()
        if not path or not name:
            continue
        key = path.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append({
            "name": name,
            "path": path,
            "source": "StartMenu",
            "args": entry.get("args") or "",
        })
    return out


# ── Known install-folder walks ─────────────────────────────────────────────

# Scoop, Chocolatey, per-user Programs and Microsoft Store shims —
# catches AnyDesk, VS Code (per-user installs), Spotify, Discord,
# WhatsApp Store-shim, etc. that often have no Start Menu entry.
def _scan_known_dirs() -> List[Dict[str, str]]:
    home = os.path.expanduser("~")
    local = os.environ.get("LOCALAPPDATA") or os.path.join(home, "AppData", "Local")
    dirs = [
        # Scoop — apps live at <scoop>/apps/<name>/current/<name>.exe
        os.path.join(home, "scoop", "apps"),
        # Per-user installs — VS Code, Slack, Discord, Postman, Notion, …
        os.path.join(local, "Programs"),
        # Microsoft Store app shims (run-from-anywhere proxies)
        os.path.join(local, "Microsoft", "WindowsApps"),
        # Chocolatey shims
        r"C:\ProgramData\chocolatey\bin",
    ]
    out: List[Dict[str, str]] = []
    seen: set[str] = set()
    for root in dirs:
        if not os.path.isdir(root):
            continue
        try:
            for entry in os.scandir(root):
                if entry.is_dir():
                    # Scoop / Programs layout: <root>/<app_name>/[current/]<app>.exe
                    candidates = []
                    cur = os.path.join(entry.path, "current")
                    if os.path.isdir(cur):
                        candidates.append(cur)
                    candidates.append(entry.path)
                    for cand in candidates:
                        exe = _find_likely_exe(cand, entry.name)
                        if exe and exe.lower() not in seen:
                            seen.add(exe.lower())
                            out.append({
                                "name": entry.name,
                                "path": exe,
                                "source": _source_for_root(root),
                            })
                            break
                elif entry.is_file() and entry.name.lower().endswith(".exe"):
                    if entry.path.lower() in seen:
                        continue
                    seen.add(entry.path.lower())
                    out.append({
                        "name": entry.name.removesuffix(".exe"),
                        "path": entry.path,
                        "source": _source_for_root(root),
                    })
        except OSError:
            continue
    return out


def _find_likely_exe(folder: str, hint: str) -> Optional[str]:
    """Pick the most plausible .exe in `folder` for an app called `hint`."""
    if not os.path.isdir(folder):
        return None
    try:
        exes = [e for e in os.listdir(folder) if e.lower().endswith(".exe")]
    except OSError:
        return None
    if not exes:
        return None
    h = hint.lower()
    # Prefer an exe whose stem matches the folder name.
    for e in exes:
        if e.lower().removesuffix(".exe") == h:
            return os.path.join(folder, e)
    # Then any exe containing the hint.
    for e in exes:
        if h in e.lower():
            return os.path.join(folder, e)
    # Fall back to the alphabetically-first non-uninstaller exe.
    exes = [e for e in exes if "uninst" not in e.lower()]
    return os.path.join(folder, sorted(exes)[0]) if exes else None


def _source_for_root(root: str) -> str:
    r = root.lower()
    if "scoop" in r: return "Scoop"
    if "chocolatey" in r: return "Chocolatey"
    if "windowsapps" in r: return "MS Store"
    if "appdata" in r and "programs" in r: return "User Programs"
    return "Folder"


# ── Public API ─────────────────────────────────────────────────────────────

def list_apps() -> List[Dict[str, Any]]:
    """Return cached apps (auto-scans on first call or when stale)."""
    cache = _read_cache()
    age = time.time() - float(cache.get("scannedAt") or 0)
    if not cache["apps"] or age > DEFAULT_TTL_SECONDS:
        return rescan()["apps"]
    return _merge(cache)


def rescan() -> Dict[str, Any]:
    """Force a fresh scan and persist to the cache file."""
    with _scan_lock:
        existing = _read_cache()
        manual = existing.get("manual", [])

        merged: Dict[str, Dict[str, Any]] = {}
        for app in _scan_app_paths():
            merged[app["path"].lower()] = app
        for app in _scan_start_menu():
            # Start Menu wins display name (more user-friendly), but
            # keep AppPaths source if both registered the exe.
            key = app["path"].lower()
            if key in merged:
                merged[key]["name"] = app["name"]
                merged[key]["source"] = f"{merged[key]['source']}+StartMenu"
            else:
                merged[key] = app
        for app in _scan_known_dirs():
            key = app["path"].lower()
            if key in merged:
                continue  # Start Menu / AppPaths already had it (better name)
            merged[key] = app

        cache = {
            "scannedAt": time.time(),
            "apps": sorted(merged.values(), key=lambda a: a["name"].lower()),
            "manual": manual,
        }
        _write_cache(cache)
        return _merge(cache, materialised=True)


def _merge(cache: Dict[str, Any], materialised: bool = False) -> Dict[str, Any]:
    return {
        "scannedAt": cache.get("scannedAt", 0),
        "apps": list(cache.get("apps", [])),
        "manual": list(cache.get("manual", [])),
    } if materialised else {
        **cache,
        "apps": list(cache.get("apps", [])),
        "manual": list(cache.get("manual", [])),
    }


def add_manual(name: str, path: str) -> Dict[str, Any]:
    """Persist a user-added app entry. Used when the scanner missed
    something (portable .exes, custom locations)."""
    name = name.strip()
    path = path.strip().strip('"')
    if not name or not path:
        raise ValueError("Both `name` and `path` are required")
    if not os.path.isfile(path):
        raise FileNotFoundError(f"No such file: {path}")
    cache = _read_cache()
    manual = [m for m in cache.get("manual", [])
              if m.get("path", "").lower() != path.lower()]
    manual.append({"name": name, "path": path, "source": "Manual"})
    cache["manual"] = manual
    _write_cache(cache)
    return cache


def remove_manual(path: str) -> Dict[str, Any]:
    cache = _read_cache()
    cache["manual"] = [
        m for m in cache.get("manual", [])
        if m.get("path", "").lower() != path.lower()
    ]
    _write_cache(cache)
    return cache


# Alias short names → canonical names. Lets `find_app('vscode')` find
# "Visual Studio Code", `find_app('vlc')` find "VLC media player", etc.
# Manually-added entries always trump these.
_QUERY_ALIASES = {
    "vscode":      ["visual studio code", "code"],
    "code":        ["visual studio code"],
    "vs":          ["visual studio"],
    "android":     ["android studio"],
    "as":          ["android studio"],
    "intellij":    ["intellij idea"],
    "idea":        ["intellij idea"],
    "pycharm":     ["pycharm"],
    "ps":          ["photoshop", "powershell"],
    "ai":          ["illustrator"],
    "ae":          ["after effects"],
    "pr":          ["premiere pro"],
    "rvx music":   ["youtube music", "yt music"],
    "yt music":    ["youtube music"],
    "yt":          ["youtube", "youtube music"],
    "wa":          ["whatsapp"],
}


def find_app(query: str) -> Optional[Dict[str, Any]]:
    """Best-effort lookup. Match priority:

      1. Exact name (case-insensitive)
      2. Exact name with .exe stripped
      3. Substring match — caller's query is contained in the app name
      4. Substring match the other way — app name contained in query
         (e.g. query='anydesk' → app 'AnyDesk')
      5. Alias expansion (vscode → "Visual Studio Code", etc.)
    """
    if not query:
        return None
    q = query.strip().lower().removesuffix(".exe")
    cache = _read_cache()
    pool: List[Dict[str, Any]] = list(cache.get("manual", [])) + list(cache.get("apps", []))

    # 1 + 2: exact match on name (with/without extension).
    for app in pool:
        n = app.get("name", "").lower()
        if n == q or n.removesuffix(".exe") == q:
            return app

    # 3: aliased query — run before substring search so 'wa' resolves
    #    via the alias table to WhatsApp instead of substring-matching
    #    "softWAre Updater" or similar noise.
    for alias in _QUERY_ALIASES.get(q, []):
        hit = _lookup_no_alias(pool, alias)
        if hit:
            return hit

    # 4: query is a substring of an app name. Skip when the query is so
    #    short (1–2 chars) that almost anything matches.
    if len(q) >= 3:
        subs = [a for a in pool if q in a.get("name", "").lower()]
        if subs:
            subs.sort(key=lambda a: len(a.get("name", "")))
            return subs[0]

    # 5: app name is a substring of the query.
    for app in pool:
        n = app.get("name", "").lower()
        if n and len(n) >= 3 and n in q:
            return app

    return None


def _lookup_no_alias(pool: List[Dict[str, Any]], q: str) -> Optional[Dict[str, Any]]:
    """Single-pass substring lookup — used by alias-expansion to avoid
    recursing back into find_app and re-hitting the alias table."""
    q = q.strip().lower()
    for app in pool:
        n = app.get("name", "").lower()
        if n == q:
            return app
    subs = [a for a in pool if q in a.get("name", "").lower()]
    if subs:
        subs.sort(key=lambda a: len(a.get("name", "")))
        return subs[0]
    return None


def app_for_phone_payload(payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Convenience: given a Smart Switch capture payload, return the
    best-guess installed PC app. Tries `appName`, then the last segment
    of `appPkg`, then a few common phone→PC name remaps.
    """
    candidates: List[str] = []
    name = (payload.get("appName") or "").strip()
    if name:
        candidates.append(name)
    pkg = (payload.get("appPkg") or "").strip()
    if pkg:
        candidates.append(pkg.rsplit(".", 1)[-1])  # e.g. com.foo.bar → bar
        candidates.append(pkg.split(".")[1] if pkg.count(".") >= 1 else pkg)

    # Lightweight phone→desktop name remaps. Catches the cases where
    # the Android app label differs from the Windows binary.
    REMAPS = {
        "rvx music": "youtube music",
        "yt music": "youtube music",
        "yt": "youtube",
        "wa": "whatsapp",
        "fb": "facebook",
        "msg": "messenger",
    }
    extra = []
    for c in candidates:
        r = REMAPS.get(c.lower())
        if r:
            extra.append(r)
    candidates.extend(extra)

    for c in candidates:
        hit = find_app(c)
        if hit:
            return hit
    return None
