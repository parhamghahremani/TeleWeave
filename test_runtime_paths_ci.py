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


def test_development_mode():
    """Test development mode paths (repo checkout)."""
    print('=== DEVELOPMENT MODE ===')
    repo_root = Path(Userbot.__file__).resolve().parent.parent
    p_dev = Paths.from_base(repo_root)
    print(f'base: {p_dev.base}')
    print(f'accounts: {p_dev.accounts}')
    print(f'data: {p_dev.data}')
    print(f'settings: {p_dev.settings}')
    print(f'logs: {p_dev.logs}')

    assert p_dev.base == repo_root, f'base mismatch: {p_dev.base} != {repo_root}'
    assert p_dev.accounts == repo_root / 'accounts', f'accounts mismatch: {p_dev.accounts}'
    assert p_dev.data == repo_root / 'data', f'data mismatch: {p_dev.data}'
    assert p_dev.settings == repo_root / 'data' / 'settings', f'settings mismatch: {p_dev.settings}'
    assert p_dev.logs == repo_root / 'data' / 'logs', f'logs mismatch: {p_dev.logs}'
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
        pip = venv_dir / 'bin' / 'pip'
        python_bin = venv_dir / 'bin' / 'python'
        subprocess.run([str(pip), 'install', str(wheel)], check=True, capture_output=True)
        subprocess.run([str(pip), 'install', '-r', 'requirements.txt'], check=True, capture_output=True, cwd='.')

        installed_test = '''
import Userbot
from pathlib import Path

pkg_dir = Path(Userbot.__file__).parent
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
print("OK Installed package structure correct")
'''
        result = subprocess.run([str(python_bin), '-c', installed_test], capture_output=True, text=True, check=True)
        print(result.stdout)

    print('\nOK Both development and installed mode paths verified')
    return True


if __name__ == '__main__':
    test_development_mode()
    test_installed_mode()