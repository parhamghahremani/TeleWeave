#!/usr/bin/env python3
"""
settings.py  (repository root)
════════════════════════════════════════════════════════════════
Thin launcher — delegates to userbot_own.settings_menu.cli.main().
Supports: show, set-direct, set-socks5, set-cf-no-worker, set-cf-worker, test, help
...
"""
import sys

sys.dont_write_bytecode = True  # Prevent __pycache__ folders

from userbot_own.settings_menu.cli import main

if __name__ == "__main__":
    # Handle help at launcher level for consistency with run.bat
    if len(sys.argv) > 1 and sys.argv[1] in ("help", "--help", "-h"):
        print("Usage: python settings.py [command]\n")
        print("No command   interactive menu (single-keypress)")
        print()
        print("Commands:")
        print("  show                          print the current settings and exit")
        print("  set-direct                    switch to direct connection")
        print("  set-socks5 [host port [user] [pass]]")
        print("                                switch to SOCKS5 (prompts when args omitted)")
        print("  set-cf-no-worker              CF via Telegram's official endpoints")
        print("  set-cf-worker [domain]        CF via your relay Worker (prompts when")
        print("                                the domain is omitted)")
        print("  test                          live test of the active route")
        print("  help                          show this help and exit")
        sys.exit(0)
    main()
