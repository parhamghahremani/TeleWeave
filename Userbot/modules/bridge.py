"""
Userbot/modules/bridge.py
════════════════════════════════════════════════════════════════
Compatibility re-export — the real module now lives in
``Userbot/modules/_infra/bridge.py``.

See ``Userbot/modules/base.py`` for why these shims exist.
════════════════════════════════════════════════════════════════
"""
from __future__ import annotations

from Userbot.modules._infra.bridge import MockEvent

__all__ = ["MockEvent"]
