#!/usr/bin/env python3
"""
Test runtime paths resolution for both development and installed modes.
Used by CI workflow to verify Paths.from_base() works correctly.
"""
import Userbot
from pathlib import Path
from Userbot.config.models import Paths
import tempfile
import subprocess
import sys


def get_package_base() -> Path:
    """
    Replicate production base calculation from Userbot/app/application.py:143
    userbot_dir = Path(__file__).resolve().parent.parent
    This resolves to the Userbot/ package directory.
    """
    # In installed mode: Userbot/__file__ is .../site-packages/Userbot/__init__.py
    # .parent = .../site-packages/Userbot
    # .parent.parent = .../site-packages (WRONG - this is what old test did)
    #
    # In development mode: Userbot/__file__ is .../repo/Userbot/__init__.py
    # .parent = .../repo/Userbot
    # .parent.parent = .../repo (repo root)
    #
    # Production code in application.py uses __file__ from application.py:
    # __file__ = .../repo/Userbot/app/application.py (dev) or .../site-packages/Userbot/app/application.py (installed)
    # .parent = .../repo/Userbot/app or .../site-packages/Userbot/app
    # .parent.parent = .../repo/Userbot or .../site-packages/Userbot  <-- CORRECT
    #
    # Since we don't have application.py imported here, we compute the same:
    # Userbot package dir = Path(Userbot.__file__).parent
    return Path(Userbot.__file__).resolve().parent


def test_development_mode():
    """Test development mode paths (repo checkout)."""
    print('=== DEVELOPMENT MODE ===')
    # Production base is the Userbot/ package directory
    pkg_base = get_package_base()
    p_dev = Paths.from_base(pkg_base)
    print(f'base: {p_dev.base}')
    print(f'accounts: {p_dev.accounts}')
    print(f'data: {p_dev.data}')
    print(f'settings: {p_dev.settings}')
    print(f'logs: {p_dev.logs}')

    assert p_dev.base == pkg_base, f'base mismatch: {p_dev.base} != {pkg_base}'
    assert p_dev.accounts == pkg_base / 'accounts', f'accounts mismatch: {p_dev.accounts}'
    assert p_dev.data == pkg_base / 'data', f'data mismatch: {p_dev.data}'
    assert p_dev.settings == pkg_base / 'data' / 'settings', f'settings mismatch: {p_dev.settings}'
    assert p_dev.logs == pkg_base / 'data' / 'logs', f'logs mismatch: {p_dev.logs}'
    print('OK Development mode paths correct')
    return True


def test_installed_mode():
    """Test installed mode paths (wheel installed in venv)."""
    print('\n=== INSTALLED MODE SIMULATION ===')
    subprocess.run([sys.executable, '-m', 'build', '--wheel', '--no-isolation'],
                   capture_output=True, check=True, cwd='.')
    wheel = list(Path('dist').glob('teleweave-3.2.13-*.whl'))[0]

    with tempfile.TemporaryDirectory() as tmpdir:
        venv_dir = Path(tmpdir) / 'venv'
        subprocess.run([sys.executable, '-m', 'venv', str(venv_dir)], check=True)
        if sys.platform == 'win32':
            pip = venv_dir / 'Scripts' / 'pip.exe'
            python_bin = venv_dir / 'Scripts' / 'python.exe'
        else:
            pip = venv_dir / 'bin' / 'pip'
            python_bin = venv_dir / 'bin' / 'python'
        subprocess.run([str(pip), 'install', str(wheel)], check=True, capture_output=True)
        subprocess.run([str(pip), 'install', '-r', 'requirements.txt'], check=True, capture_output=True, cwd='.')

        installed_test = '''
import Userbot
from pathlib import Path

# Replicate production base calculation from Userbot/app/application.py:143
# userbot_dir = Path(__file__).resolve().parent.parent
# In installed mode: __file__ = .../site-packages/Userbot/app/application.py
# .parent = .../site-packages/Userbot/app
# .parent.parent = .../site-packages/Userbot  <-- CORRECT
pkg_dir = Path(Userbot.__file__).resolve().parent
print(f'Installed package location: {pkg_dir}')
print(f'Package has modules: {(pkg_dir / "modules").exists()}')
print(f'Package has modules_extra: {(pkg_dir / "modules_extra").exists()}')
print(f'Package has config: {(pkg_dir / "config").exists()}')
print(f'Package has core: {(pkg_dir / "core").exists()}')
print(f'Package has account_management: {(pkg_dir / "account_management").exists()}')
print(f'Package has settings_menu: {(pkg_dir / "settings_menu").exists()}')
print(f'Package has app: {(pkg_dir / "app").exists()}')

assert Userbot.__version__ == "3.2.13", f"Version mismatch: {Userbot.__version__}"
print(f'Version: {Userbot.__version__}')

from Userbot.config.models import Paths
p_installed = Paths.from_base(pkg_dir)
print(f'base: {p_installed.base}')
print(f'accounts: {p_installed.accounts}')
print(f'data: {p_installed.data}')
print(f'settings: {p_installed.settings}')
print(f'logs: {p_installed.logs}')
print(f'modules: {p_installed.modules}')
print(f'modules_extra: {p_installed.modules_extra}')

assert p_installed.base == pkg_dir, f'base mismatch: {p_installed.base} != {pkg_dir}'
assert p_installed.accounts == pkg_dir / 'accounts', f'accounts mismatch: {p_installed.accounts}'
assert p_installed.data == pkg_dir / 'data', f'data mismatch: {p_installed.data}'
assert p_installed.settings == pkg_dir / 'data' / 'settings', f'settings mismatch: {p_installed.settings}'
assert p_installed.logs == pkg_dir / 'data' / 'logs', f'logs mismatch: {p_installed.logs}'
print("OK Installed mode paths correct")
'''
        result = subprocess.run([str(python_bin), '-c', installed_test], capture_output=True, text=True, check=True)
        print(result.stdout)

    print('\nOK Both development and installed mode paths verified')
    return True


if __name__ == '__main__':
    test_development_mode()
    test_installed_mode()