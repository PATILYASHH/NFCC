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

import mappings
from . import apps
from ._common import ActionResult, fail, key_press, ok


_DIGITS_RE = re.compile(r"\D+")

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
        return fail("No URL in payload or rule")
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
    name = (rule.get("app_name") or payload.get("appName") or "").strip()
    if name:
        return apps.launch_app({"name": name})
    pkg = (payload.get("appPkg") or "").strip()
    if pkg:
        return fail(f"Nothing to hand off (only got pkg: {pkg})")
    return fail("Nothing to hand off")


def _strat_launch_app(rule: Dict[str, Any]) -> ActionResult:
    payload = rule["_payload"]
    name = (rule.get("app_name") or payload.get("appName") or "").strip()
    if not name:
        return fail("Mapping has no `app_name`")
    return apps.launch_app({"name": name})


def _strat_whatsapp_paste(rule: Dict[str, Any]) -> ActionResult:
    payload = rule["_payload"]
    chat = (payload.get("chatHint") or "").strip()
    digits = _DIGITS_RE.sub("", chat)
    if rule.get("use_wa_me", True) and chat and digits and len(digits) >= 8:
        target = f"https://wa.me/{digits}"
    else:
        target = "https://web.whatsapp.com/"
    _open_url(target, rule.get("browser", "default"))

    draft = payload.get("draftText") or ""
    if draft and rule.get("auto_paste", True):
        wait_ms = int(rule.get("wait_ms", 2500) or 0)
        if wait_ms > 0:
            time.sleep(wait_ms / 1000.0)
        _set_clipboard(draft)
        time.sleep(0.1)
        _paste()
        return ok(f"Opened WhatsApp + pasted draft ({len(draft)} chars)")
    return ok(f"Opened WhatsApp: {target}")


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
