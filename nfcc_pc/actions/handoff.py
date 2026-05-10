"""Smart Switch handoff handler.

Receives a payload describing what was foregrounded on the phone and
reproduces it on this PC. Dispatch is driven by ``nfcc_pc.mappings`` —
the default table covers YouTube (incl. ReVanced), Spotify, browsers,
WhatsApp and a list of common apps; the user can override anything via
``~/.nfcc/mappings.json`` or the web dashboard.

Payload schema produced by the phone-side capturer:

    {
      "kind": "youtube" | "spotify" | "browser" | "whatsapp" | "generic",
      "url": "https://...",            # canonical URL when available
      "appPkg": "com.google.android.youtube",
      "appName": "YouTube",
      "positionMs": 142000,            # for media kinds
      "draftText": "...",              # whatsapp only
      "chatHint": "Yash"|"+9198…",     # whatsapp: chat name or phone
    }

YouTube URLs are already normalized on the phone (ReVanced /
youtu.be / m. / music. → https://www.youtube.com/watch?v=<id>&t=<s>s),
so the PC handler does not re-do that.
"""

import re
import subprocess
import time
import webbrowser
from typing import Any, Dict

import installed_apps
import mappings
from . import apps
from ._common import ActionResult, fail, key_press, ok


_DIGITS_RE = re.compile(r"\D+")


def _whatsapp_desktop_installed() -> bool:
    """True iff the `whatsapp:` URL scheme is registered with Windows.

    Microsoft Store / UWP installs and standalone (.exe) installs both
    register the protocol but in different registry locations:
      - Standalone: HKCR\\whatsapp\\shell\\open\\command
      - Store / UWP: HKCU\\Software\\Classes\\whatsapp (dynamic, points
                     at AppX shell extension)
      - Per-machine: HKLM\\SOFTWARE\\Classes\\whatsapp

    We also look up via AssocQueryString as a final probe because the
    protocol can be live without `\\shell\\open\\command` populated
    when it's a UWP app.
    """
    try:
        import winreg
    except ImportError:
        return False

    candidates = [
        (winreg.HKEY_CLASSES_ROOT, r"whatsapp\shell\open\command"),
        (winreg.HKEY_CLASSES_ROOT, r"whatsapp"),
        (winreg.HKEY_CURRENT_USER, r"Software\Classes\whatsapp"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Classes\whatsapp"),
    ]
    for root, path in candidates:
        try:
            with winreg.OpenKey(root, path):
                return True
        except OSError:
            continue

    # AssocQueryString — works for UWP-routed protocols too.
    try:
        import ctypes
        from ctypes import wintypes
        out = ctypes.create_unicode_buffer(260)
        size = wintypes.DWORD(260)
        # ASSOCF_NONE=0, ASSOCSTR_EXECUTABLE=2
        rv = ctypes.windll.shlwapi.AssocQueryStringW(
            0, 2, "whatsapp", None, out, ctypes.byref(size)
        )
        if rv == 0 and out.value:
            return True
    except Exception:
        pass

    return False

# webbrowser.get accepts these on Windows, but only if the matching
# binary is on PATH or in a registered location. We fall back to
# launching the named exe directly via APP_ALIASES otherwise.
_BROWSER_BINARIES = {
    "chrome": "chrome",
    "edge": "msedge",
    "firefox": "firefox",
    "brave": "brave",
}


# ── Strategy helpers ────────────────────────────────────────────────────────

def _open_url(url: str, browser: str = "default") -> None:
    """Open a URL, optionally pinning to a specific browser."""
    if not url:
        return
    if not url.startswith(("http://", "https://", "file:")):
        url = "https://" + url

    name = (browser or "default").strip().lower()
    if name == "default":
        webbrowser.open(url)
        return

    binary = _BROWSER_BINARIES.get(name) or apps.APP_ALIASES.get(name) or name
    try:
        subprocess.Popen([binary, url])
    except (FileNotFoundError, OSError):
        # Fall through to shell start so Windows resolves it via App Paths.
        try:
            subprocess.Popen(["cmd", "/c", "start", "", binary, url], shell=False)
        except Exception:
            webbrowser.open(url)


def _open_uri_direct(uri: str) -> None:
    """Open a non-http: URI (spotify:track:..., zoommtg://..., etc.)
    so Windows routes through the registered protocol handler.
    """
    subprocess.Popen(["cmd", "/c", "start", "", uri], shell=False)


def _set_clipboard(text: str) -> None:
    subprocess.run(["clip"], input=text.encode("utf-16le"), check=False)


def _paste() -> None:
    # Ctrl+V via the existing Win32 helper — same VKs as input_.paste.
    key_press(0x11, 0x56)


def _is_http_url(s: str) -> bool:
    return s.startswith("http://") or s.startswith("https://")


# ── Strategy implementations ────────────────────────────────────────────────

def _strat_url(rule: Dict[str, Any]) -> ActionResult:
    payload = rule["_payload"]
    url = (payload.get("url") or rule.get("url") or "").strip()
    if not url:
        # Empty-URL fallback per kind. Better to open SOMETHING reasonable
        # than to flash a red X in the action log when the accessibility
        # scrape missed the omnibox or MediaSession returned no URI.
        kind = (rule.get("_kind") or "").lower()
        app_pkg = (payload.get("appPkg") or "").lower()
        if kind == "youtube" and "youtube.music" in app_pkg:
            fallback = "https://music.youtube.com/"
        elif kind == "youtube":
            fallback = "https://www.youtube.com/"
        elif kind == "spotify":
            fallback = "https://open.spotify.com/"
        elif kind == "browser":
            fallback = "about:blank"
        else:
            return fail("No URL in payload or rule")
        _open_url(fallback, rule.get("browser", "default"))
        return ok(f"Opened {kind} home (no specific URL captured)")
    _open_url(url, rule.get("browser", "default"))
    return ok(f"Opened: {url}")


def _strat_static_url(rule: Dict[str, Any]) -> ActionResult:
    url = (rule.get("url") or "").strip()
    if not url:
        return fail("Mapping has no static `url`")
    _open_url(url, rule.get("browser", "default"))
    return ok(f"Opened: {url}")


def _strat_desktop_uri(rule: Dict[str, Any]) -> ActionResult:
    payload = rule["_payload"]
    uri = (payload.get("url") or rule.get("uri") or "").strip()
    if not uri:
        return fail("No URI to open")
    _open_uri_direct(uri)
    return ok(f"Opened: {uri}")


def _strat_desktop_uri_then_url(rule: Dict[str, Any]) -> ActionResult:
    payload = rule["_payload"]
    raw = (payload.get("url") or "").strip()
    if raw and not _is_http_url(raw):
        _open_uri_direct(raw)
        return ok(f"Opened protocol URI: {raw}")
    web = raw or (rule.get("web_url") or "").strip()
    if not web:
        return fail("No URL or fallback")
    _open_url(web, rule.get("browser", "default"))
    return ok(f"Opened: {web}")


def _strat_url_or_launch(rule: Dict[str, Any]) -> ActionResult:
    payload = rule["_payload"]
    url = (payload.get("url") or "").strip()
    if url:
        _open_url(url, rule.get("browser", "default"))
        return ok(f"Opened: {url}")
    return _launch_via_scanner(rule, payload)


def _strat_launch_app(rule: Dict[str, Any]) -> ActionResult:
    payload = rule["_payload"]
    return _launch_via_scanner(rule, payload)


def _launch_via_scanner(
    rule: Dict[str, Any], payload: Dict[str, Any]
) -> ActionResult:
    """Resolve and launch a desktop app for this Smart Switch payload.

    Order of attempts, most specific first:
      1. Mapping `app_path` (user pinned an exact .exe in mappings.json)
      2. Mapping `app_name` (try via APP_ALIASES + PATH lookup)
      3. installed_apps scanner — fuzzy matches the phone payload's
         appName / appPkg / known aliases against the cached scan.
      4. apps.launch_app fallback (PATH / shell start)
    """
    explicit_path = (rule.get("app_path") or "").strip()
    if explicit_path:
        return apps.launch_app({"path": explicit_path})

    name = (rule.get("app_name") or payload.get("appName") or "").strip()

    # Try the alias table first — when name maps cleanly to a known
    # binary (chrome, code, etc.) we don't need a scanner round-trip.
    if name and apps.APP_ALIASES.get(name.lower()):
        return apps.launch_app({"name": name})

    # Scanner lookup — covers AnyDesk, custom installs, Store apps that
    # APP_ALIASES doesn't list. Reads from the cache so it's fast.
    try:
        hit = installed_apps.app_for_phone_payload(payload)
        if hit and hit.get("path"):
            return apps.launch_app({"path": hit["path"]})
    except Exception:
        pass  # scanner is opportunistic

    if name:
        # If neither alias nor PATH resolves the name AND the scanner
        # couldn't help, short-circuit with an actionable error instead
        # of letting apps.launch_app return the terse "No PC equivalent"
        # message. Saves the user a trip into the action log to figure
        # out what to do next.
        if (apps.APP_ALIASES.get(name.lower()) is None
                and not apps._looks_launchable(name)):
            pkg_hint = (payload.get("appPkg") or "").strip()
            extra = f" (Android pkg: {pkg_hint})" if pkg_hint else ""
            return fail(
                f"No PC app mapped for '{name}'{extra}. "
                "Open the dashboard → App Scanner → search and click Map."
            )
        return apps.launch_app({"name": name})
    pkg = (payload.get("appPkg") or "").strip()
    if pkg:
        return fail(
            f"No PC app mapped for '{pkg}'. "
            "Open the dashboard → App Scanner to pair it."
        )
    return fail("Nothing to hand off")


def _strat_whatsapp_paste(rule: Dict[str, Any]) -> ActionResult:
    payload = rule["_payload"]
    chat = (payload.get("chatHint") or "").strip()
    digits = _DIGITS_RE.sub("", chat)
    has_phone = bool(chat and digits and len(digits) >= 8)

    # Prefer WhatsApp Desktop when its protocol handler is registered.
    # Web is the fallback (covers users who only have web.whatsapp.com).
    # `force_desktop=true` skips the registry probe — useful when Store /
    # UWP installs hide the protocol from the locations we check.
    prefer_desktop = rule.get("prefer_desktop", True)
    use_desktop = prefer_desktop and (
        rule.get("force_desktop", False) or _whatsapp_desktop_installed()
    )
    if use_desktop:
        target = f"whatsapp://send?phone={digits}" if has_phone else "whatsapp://"
        _open_uri_direct(target)
        opened = "WhatsApp Desktop"
        # Desktop opens faster than web's cold load; halve the default
        # paste wait unless the user pinned a value in mappings.json.
        default_wait_ms = 1500
    elif rule.get("use_wa_me", True) and has_phone:
        target = f"https://wa.me/{digits}"
        _open_url(target, rule.get("browser", "default"))
        opened = f"WhatsApp Web ({target})"
        default_wait_ms = 2500
    else:
        target = "https://web.whatsapp.com/"
        _open_url(target, rule.get("browser", "default"))
        opened = "WhatsApp Web"
        default_wait_ms = 2500

    draft = payload.get("draftText") or ""
    if draft and rule.get("auto_paste", True):
        wait_ms = int(rule.get("wait_ms", default_wait_ms) or 0)
        if wait_ms > 0:
            time.sleep(wait_ms / 1000.0)
        _set_clipboard(draft)
        time.sleep(0.1)
        _paste()
        return ok(f"Opened {opened} + pasted draft ({len(draft)} chars)")
    return ok(f"Opened {opened}")


_STRATEGIES = {
    "url": _strat_url,
    "static_url": _strat_static_url,
    "desktop_uri": _strat_desktop_uri,
    "desktop_uri_then_url": _strat_desktop_uri_then_url,
    "url_or_launch": _strat_url_or_launch,
    "launch_app": _strat_launch_app,
    "whatsapp_paste": _strat_whatsapp_paste,
}


# ── Entry point ─────────────────────────────────────────────────────────────

def smart_switch(params: dict) -> ActionResult:
    """Resolve the captured payload via the mapping table and dispatch."""
    rule = mappings.resolve(params)
    strategy = (rule.get("strategy") or "url_or_launch").strip().lower()
    handler = _STRATEGIES.get(strategy)
    if handler is None:
        return fail(f"Unknown strategy in mapping: {strategy}")
    try:
        return handler(rule)
    except Exception as e:
        return fail(f"{strategy} failed: {e}")
