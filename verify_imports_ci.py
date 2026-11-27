#!/usr/bin/env python3
"""
Verify imports and version for CI.
Used by CI workflow to avoid YAML multiline string indentation issues.
"""
import Userbot

def test_version():
    assert Userbot.__version__ == '3.2.13', f'Version mismatch: {Userbot.__version__}'
    print(f'OK Userbot.__version__ = {Userbot.__version__}')

def test_core_imports():
    from Userbot.app.application import Application
    from Userbot.app.composition_root import CompositionRoot
    from Userbot.config.loader import discover_accounts, load_settings, load_connection_settings
    from Userbot.config.models import Paths, Settings, ConnectionSettings
    from Userbot.core.registry import AccountRegistry, AccountLoaderRegistry
    from Userbot.core.loader import AccountLoader
    from Userbot.core.telegram_client import AccountClient
    from Userbot.core.reconnector import AccountReconnector
    from Userbot.core.logging_setup import setup
    print('OK All core imports successful')

def test_distribution_metadata():
    import importlib.metadata
    dist = importlib.metadata.distribution('teleweave')
    assert dist.version == '3.2.13', f'Distribution version mismatch: {dist.version}'
    print(f'OK Distribution name: {dist.metadata["Name"]}')
    print(f'OK Distribution version: {dist.version}')

def test_cli_entry_points():
    import main
    import add_account
    import settings
    print('OK Root launchers import successfully')
    from Userbot.account_management.cli import main as am_main
    from Userbot.settings_menu.cli import main as sm_main
    print('OK CLI modules import successfully')

def test_core_modules():
    from Userbot.modules.single.system import create_module as m1
    from Userbot.modules.single.help_handler import create_module as m2
    from Userbot.modules.single.module_manager import create_module as m3
    from Userbot.modules.packages.clearer import create_module as m4
    from Userbot.modules.packages.auto_clearer import create_module as m5
    from Userbot.modules.packages.auto_forwarder import create_module as m6
    from Userbot.modules.packages.join_left import create_module as m7
    from Userbot.modules.packages.info_handler import create_module as m8
    from Userbot.modules.packages.whois_handler import create_module as m9
    from Userbot.modules.packages.reaction_commands import create_module as m10
    from Userbot.modules_extra.packages.bot_link_starter import create_module as m11
    print('OK All modules import successfully')

def test_no_old_package_references():
    import os
    found = []
    for root, dirs, files in os.walk('Userbot'):
        for f in files:
            if f.endswith('.py'):
                path = os.path.join(root, f)
                with open(path, 'r', encoding='utf-8') as fp:
                    content = fp.read()
                    if 'userbot_own.' in content:
                        found.append(path)
    if found:
        print('FAIL Found old userbot_own imports:')
        for f in found:
            print(f'  {f}')
        return False
    else:
        print('OK No userbot_own imports found in source')
        return True

if __name__ == '__main__':
    test_version()
    test_core_imports()
    test_distribution_metadata()
    test_cli_entry_points()
    test_core_modules()
    if not test_no_old_package_references():
        exit(1)
    print('\n=== ALL VERIFICATIONS PASSED ===')