"""Smart Switch handoff mapping table.

When the phone hands off a captured-foreground payload, this module
resolves what the PC should actually do. The schema:

    {
      "by_kind": {
        "<kind>": { strategy + params }
      },
      "by_package": {
        "<android_pkg>": { strategy + params, optionally "kind_override" }
      }
    }

Per-package settings win over per-kind defaults. A package entry can
also carry "kind_override" so e.g. ReVanced YouTube routes through the
"youtube" kind without duplicating its config.

Strategies:
    "url"               — open `payload['url']` (or static `url`) in `browser`
    "static_url"        — open the strategy's static `url`, ignore payload URL
    "desktop_uri"       — open `payload['url']` directly so the OS routes
                           through the protocol handler (e.g. spotify:track:…)
    "desktop_uri_then_url" — try `payload['url']` if it's a non-http: scheme,
                           else open `web_url` in the chosen browser
    "url_or_launch"     — URL if present, else `launch_app` by `app_name`
    "launch_app"        — call apps.launch_app({"name": app_name})
    "whatsapp_paste"    — open WA Web (or wa.me/<digits> for phone-number
                           chat hints), wait, paste draft. Honors
                           `auto_paste`, `wait_ms`, `use_wa_me`.

`browser` is one of: "default", "chrome", "edge", "firefox", "brave".
"default" → webbrowser.open(); anything else → resolve via apps.APP_ALIASES
and exec with the URL as argv[1].

The user can override any entry via ~/.nfcc/mappings.json. Their JSON is
merged on top of the defaults, so they only need to record diffs.
"""
import json
import os
from copy import deepcopy
from typing import Any, Dict

from config import CONFIG_DIR

MAPPINGS_FILE = os.path.join(CONFIG_DIR, "mappings.json")


# ── Defaults ────────────────────────────────────────────────────────────────

# Edit these to change baked-in behavior. Anything in mappings.json wins.
DEFAULT_MAPPINGS: Dict[str, Dict[str, Dict[str, Any]]] = {
    "by_kind": {
        # YouTube — phone-side normalizer already converts ReVanced /
        # youtu.be / m. into https://www.youtube.com/watch?v=<id>&t=<s>s,
        # so we just open it.
        "youtube": {
            "strategy": "url",
            "browser": "default",
        },
        # Spotify — phone capturer normalizes spotify: URIs to
        # https://open.spotify.com/<...>. Opening that page auto-launches
        # Spotify Desktop via the registered protocol handler when
        # installed; if not, the user gets the web player. Either is
        # fine, and same-account Spotify Connect resumes playback at
        # the right position automatically.
        "spotify": {
            "strategy": "desktop_uri_then_url",
            "browser": "default",
        },
        "browser": {
            "strategy": "url",
            "browser": "default",
        },
        "whatsapp": {
            "strategy": "whatsapp_paste",
            "auto_paste": True,
            # Routes to WhatsApp Desktop via the `whatsapp:` protocol
            # handler when it's registered (Microsoft Store / standalone
            # install both register it). Falls back to WhatsApp Web
            # otherwise. Set false to always use the browser.
            "prefer_desktop": True,
            # Use https://wa.me/<digits> when chatHint is a phone number
            # AND we end up in the web fallback.
            "use_wa_me": True,
            # Defaults to 1500 ms when Desktop is used, 2500 ms for Web.
            # Pin a value here to override both.
            # "wait_ms": 2000,
        },
        "generic": {
            "strategy": "url_or_launch",
            "browser": "default",
        },
    },
    "by_package": {
        # ReVanced + ReVanced eXtended YouTube — capture is already
        # routed to the "youtube" kind by SmartSwitchCapture.kt's
        # MEDIA_PACKAGES table, so this is mostly defensive: if a future
        # capture path leaves these as kind=generic, kind_override pulls
        # them back into the YouTube pipeline.
        "app.revanced.android.youtube": {"kind_override": "youtube"},
        "app.rvx.android.youtube":      {"kind_override": "youtube"},
        "com.google.android.apps.youtube.music":      {"kind_override": "youtube"},
        "app.revanced.android.apps.youtube.music":    {"kind_override": "youtube"},
        "app.rvx.android.apps.youtube.music":         {"kind_override": "youtube"},

        # Music apps — protocol-handler-first
        "com.spotify.music":         {"kind_override": "spotify"},

        # Common apps that don't have a clean URL handoff but do have
        # a web counterpart on PC.
        "com.instagram.android":     {"strategy": "static_url",
                                      "url": "https://www.instagram.com/",
                                      "browser": "default"},
        "com.twitter.android":       {"strategy": "static_url",
                                      "url": "https://x.com/",
                                      "browser": "default"},
        "com.zhiliaoapp.musically":  {"strategy": "static_url",
                                      "url": "https://www.tiktok.com/",
                                      "browser": "default"},
        "com.netflix.mediaclient":   {"strategy": "static_url",
                                      "url": "https://www.netflix.com/",
                                      "browser": "default"},
        "tv.twitch.android.app":     {"strategy": "static_url",
                                      "url": "https://www.twitch.tv/",
                                      "browser": "default"},
        "com.reddit.frontpage":      {"strategy": "static_url",
                                      "url": "https://www.reddit.com/",
                                      "browser": "default"},
        "com.linkedin.android":      {"strategy": "static_url",
                                      "url": "https://www.linkedin.com/",
                                      "browser": "default"},
        "com.google.android.gm":     {"strategy": "static_url",
                                      "url": "https://mail.google.com/",
                                      "browser": "default"},
        "com.google.android.apps.docs": {"strategy": "static_url",
                                      "url": "https://drive.google.com/",
                                      "browser": "default"},
        "com.google.android.calendar": {"strategy": "static_url",
                                      "url": "https://calendar.google.com/",
                                      "browser": "default"},
        "com.google.android.keep":   {"strategy": "static_url",
                                      "url": "https://keep.google.com/",
                                      "browser": "default"},

        # Native-desktop-app preferences. These open the PC app directly
        # rather than a web view.
        "org.telegram.messenger":    {"strategy": "launch_app",
                                      "app_name": "telegram"},
        "org.telegram.messenger.web":{"strategy": "launch_app",
                                      "app_name": "telegram"},
        "com.discord":               {"strategy": "launch_app",
                                      "app_name": "discord"},
        "com.microsoft.teams":       {"strategy": "launch_app",
                                      "app_name": "teams"},
        "com.slack":                 {"strategy": "launch_app",
                                      "app_name": "slack"},
        "com.valvesoftware.android.steam.community":
                                     {"strategy": "launch_app",
                                      "app_name": "steam"},
    },
}


# ── Load / save ─────────────────────────────────────────────────────────────

def load_mappings() -> Dict[str, Dict[str, Dict[str, Any]]]:
    """Return defaults merged with the user override file (if any)."""
    merged = deepcopy(DEFAULT_MAPPINGS)
    if not os.path.exists(MAPPINGS_FILE):
        return merged
    try:
        with open(MAPPINGS_FILE, "r", encoding="utf-8") as f:
            user = json.load(f)
    except (json.JSONDecodeError, OSError):
        return merged

    for bucket in ("by_kind", "by_package"):
        if not isinstance(user.get(bucket), dict):
            continue
        for key, val in user[bucket].items():
            if not isinstance(val, dict):
                continue
            if key in merged[bucket]:
                merged[bucket][key].update(val)
            else:
                merged[bucket][key] = val
    return merged


def save_mappings(data: Dict[str, Any]) -> None:
    """Write the (user-edited) mapping diff to disk.

    Caller is expected to hand us the exact JSON to persist — usually
    the full merged dict from the dashboard. Defaults are not stripped;
    that's fine, the merge is idempotent.
    """
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(MAPPINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def reset_mappings() -> None:
    if os.path.exists(MAPPINGS_FILE):
        os.remove(MAPPINGS_FILE)


# ── Resolve ─────────────────────────────────────────────────────────────────

def resolve(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Pick the strategy for a captured handoff payload.

    Returns a merged dict carrying both the strategy config and the
    original payload — handoff.py just reads keys off it.

    Lookup order:
      1. by_package[appPkg]    (with optional kind_override)
      2. by_kind[kind]
      3. by_kind['generic']    (last-resort fallback)
    """
    table = load_mappings()
    by_kind = table.get("by_kind", {}) or {}
    by_pkg  = table.get("by_package", {}) or {}

    pkg = (payload.get("appPkg") or "").strip()
    kind = (payload.get("kind") or "generic").lower().strip()

    pkg_entry: Dict[str, Any] = by_pkg.get(pkg, {}) or {}
    if pkg_entry.get("kind_override"):
        kind = str(pkg_entry["kind_override"]).lower().strip()

    kind_entry: Dict[str, Any] = (
        by_kind.get(kind)
        or by_kind.get("generic")
        or {"strategy": "url_or_launch", "browser": "default"}
    )

    resolved: Dict[str, Any] = {}
    resolved.update(kind_entry)
    # Per-package settings win, except for the kind_override marker
    # itself (which is metadata, not strategy).
    for k, v in pkg_entry.items():
        if k == "kind_override":
            continue
        resolved[k] = v
    resolved["_kind"] = kind
    resolved["_payload"] = payload
    return resolved


def get_user_mappings() -> Dict[str, Any]:
    """Return whatever the user has saved (or {} if no override file)."""
    if not os.path.exists(MAPPINGS_FILE):
        return {}
    try:
        with open(MAPPINGS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def get_effective_mappings() -> Dict[str, Any]:
    """Return defaults+user merged, for display in the dashboard."""
    return load_mappings()
