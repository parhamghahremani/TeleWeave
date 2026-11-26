#!/usr/bin/env python3
"""
add_account.py  (repository root)
════════════════════════════════════════════════════════════════
Thin launcher — delegates to Userbot.account_management.cli.main().
Supports: help
...
"""
import sys

sys.dont_write_bytecode = True  # Prevent __pycache__ folders

from Userbot.account_management.cli import main

if __name__ == "__main__":
    # Handle help at launcher level for consistency
    if len(sys.argv) > 1 and sys.argv[1] in ("help", "--help", "-h"):
        print("Usage: python add_account.py [help]\n")
        print("No args      interactive account management menu (single-keypress)")
        print()
        print("Commands:")
        print("  help          show this help and exit")
        print()
        print("Interactive menu options:")
        print("  1) Add new account (full login or import string session)")
        print("  2) Re-login / recreate session")
        print("  3) Edit account details (api_id, api_hash, phone, label)")
        print("  4) Remove account")
        print("  5) List accounts")
        print("  6) Verify session")
        print("  7) Exit")
        sys.exit(0)
    main()
