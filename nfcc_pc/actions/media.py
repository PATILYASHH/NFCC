"""Volume, mute, media transport."""

from ._common import ActionResult, fail, key_press, ok


def toggle_mute(_: dict) -> ActionResult:
    # VK_VOLUME_MUTE — works on every Windows build without pycaw.
    # Earlier the pycaw call broke on newer wheels where
    # AudioUtilities.GetSpeakers() returns an AudioDevice wrapper that
    # doesn't expose .Activate. The mute key is stateless and just toggles.
    key_press(0xAD)
    return ok("Audio mute toggled")


def _get_endpoint_volume():
    """Cross-pycaw-version helper — returns an IAudioEndpointVolume
    you can call .GetMute / .SetMasterVolumeLevelScalar on.

    Modern pycaw wheels wrap GetSpeakers() in an AudioDevice; the raw
    IMMDevice (which has .Activate) lives behind one of a few private
    attributes. Older wheels return the raw IMMDevice directly.
    """
    from ctypes import POINTER, cast
    from comtypes import CLSCTX_ALL
    from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume

    dev = AudioUtilities.GetSpeakers()

    # 1. Raw IMMDevice (older pycaw). Has .Activate directly.
    if hasattr(dev, "Activate"):
        iface = dev.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        return cast(iface, POINTER(IAudioEndpointVolume))

    # 2. Wrapped AudioDevice — drill to the underlying IMMDevice.
    for attr in ("_dev", "_device", "device", "endpoint", "_endpoint"):
        inner = getattr(dev, attr, None)
        if inner is not None and hasattr(inner, "Activate"):
            iface = inner.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
            return cast(iface, POINTER(IAudioEndpointVolume))

    raise RuntimeError(
        f"pycaw {type(dev).__name__} doesn't expose Activate; "
        "cannot read endpoint volume on this build"
    )


def set_volume(params: dict) -> ActionResult:
    try:
        level = int(params.get("level", 50))
        level = max(0, min(100, level))
    except (TypeError, ValueError):
        return fail("Invalid volume level")
    try:
        vol = _get_endpoint_volume()
        vol.SetMasterVolumeLevelScalar(level / 100.0, None)
        return ok(f"Volume: {level}%", {"level": level})
    except Exception as e:
        # Last-ditch fallback: walk to ~level via OS volume keys. Crude,
        # but better than failing silently — most users just want the
        # volume to move in the right direction.
        try:
            steps = max(1, level // 2)  # each VK_VOLUME_* is ~2%
            for _ in range(steps):
                key_press(0xAF if level > 50 else 0xAE)
            return ok(f"Volume nudged toward {level}% (pycaw unavailable: {e})",
                      {"level": level, "approximate": True})
        except Exception:
            return fail(str(e))


def volume_up(_: dict) -> ActionResult:
    key_press(0xAF)
    return ok("Volume up")


def volume_down(_: dict) -> ActionResult:
    key_press(0xAE)
    return ok("Volume down")


def media_play_pause(_: dict) -> ActionResult:
    key_press(0xB3)
    return ok("Play/Pause")


def media_next(_: dict) -> ActionResult:
    key_press(0xB0)
    return ok("Next track")


def media_prev(_: dict) -> ActionResult:
    key_press(0xB1)
    return ok("Previous track")


def media_stop(_: dict) -> ActionResult:
    key_press(0xB2)
    return ok("Media stopped")
