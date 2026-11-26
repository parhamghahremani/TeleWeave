"""
Userbot/modules/router.py
════════════════════════════════════════════════════════════════
Compatibility re-export — the real module now lives in
``Userbot/modules/_infra/router.py``.

See ``Userbot/modules/base.py`` for why these shims exist.
════════════════════════════════════════════════════════════════
"""
from __future__ import annotations

from Userbot.modules._infra.router import CommandHandler, CommandRouter

__all__ = ["CommandRouter", "CommandHandler"]
