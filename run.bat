@echo off
setlocal EnableExtensions
chcp 65001 >nul

rem ────────────────────────────────────────────────────────────────
rem  Interactive launcher menu for the userbot project.
rem  - Option 1  -> python main.py                  (run the bot)
rem  - Option 2  -> python -m userbot_own.account_management.cli  (account management)
rem  - Option 3  -> connection settings sub-menu (show / change
rem                 mode / test); every action returns to that
rem                 sub-menu, [7] Back returns to the main menu
rem  - Option 4  -> exit
rem  While a task runs, press Ctrl+C to stop it and return to the
rem  menu you launched it from (answer "N" to the "Terminate batch
rem  job (Y/N)?" prompt).
rem  Supports command-line arguments:
rem    run.bat run                    - run the bot
rem    run.bat add                    - account management
rem    run.bat settings [cmd]         - connection settings
rem    run.bat reinstall              - full reinstall
rem    run.bat version                - show version
rem    run.bat help                   - show help
rem ────────────────────────────────────────────────────────────────

rem Always work from the folder this .bat lives in, so relative
rem imports and config paths resolve correctly no matter how it's launched.
cd /d "%~dp0"

rem Prevent __pycache__ directories from being created during execution
set PYTHONDONTWRITEBYTECODE=1

rem Current version, read from the VERSION file — every future
rem release updates this display automatically, nothing to edit here.
set "APP_VERSION=unknown"
if exist VERSION set /p APP_VERSION=<VERSION
title Userbot Control Menu v%APP_VERSION%

rem Sanity check: make sure Python is available before showing the menu.
where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python not found in PATH. Install Python 3.11+ first.
    pause
    exit /b 1
)

rem --- Dispatch on first argument (optional shortcuts) ---
if "%~1"=="" goto :menu
if /i "%~1"=="run" goto :bot
if /i "%~1"=="add" goto :accounts
if /i "%~1"=="settings" goto :settings_dispatch
if /i "%~1"=="reinstall" goto :reinstall
if /i "%~1"=="version" goto :version
if /i "%~1"=="help" goto :help
if /i "%~1"=="-h" goto :help
if /i "%~1"=="--help" goto :help
echo Unknown command: %~1
echo Usage: run.bat [run|add|settings [command]|reinstall|version|help]
exit /b 1

:settings_dispatch
if "%~2"=="" goto :settings
python settings.py %~2 %~3 %~4 %~5 %~6 %~7 %~8 %~9
pause
exit /b 0

:menu
cls
echo  ==============================================================
echo           USERBOT  -  CONTROL  MENU  (v%APP_VERSION%)
echo  ==============================================================
echo.
echo    [1] Run the bot
echo    [2] Manage accounts
echo    [3] Connection settings
echo    [4] Exit
echo.
echo  --------------------------------------------------------------
echo   Tip: while a task is running, press Ctrl+C to stop it and
echo   return to the menu you launched it from - answer "N" to the
echo   "Terminate batch job?" prompt.
echo  --------------------------------------------------------------
echo.
choice /C 1234 /N /M "  Your choice [1-4]: "

if errorlevel 4 goto :exit
if errorlevel 3 goto :settings
if errorlevel 2 goto :accounts
if errorlevel 1 goto :bot
goto :menu

:bot
echo.
echo  ── Starting the bot (main.py) ... press Ctrl+C to stop ──
echo.
cmd /c python main.py
pause
goto :menu

:accounts
echo.
echo  ── Starting account manager ... press Ctrl+C to stop ──
echo.
cmd /c python -m userbot_own.account_management.cli
pause
goto :menu

rem ── Connection settings ─────────────────────────────────────────
rem  Self-contained sub-menu: every action comes back HERE, so
rem  several settings can be checked/changed in a row. [4] Back is
rem  the only way out to the main menu.

:settings
cls
echo  ==============================================================
echo                     CONNECTION SETTINGS
echo  ==============================================================
echo.
echo    [1] Show current settings
echo    [2] Change connection mode
echo    [3] Test connection
echo    [4] Back to main menu
echo.
choice /C 1234 /N /M "  Your choice [1-4]: "

if errorlevel 4 goto :menu
if errorlevel 3 goto :settings_test
if errorlevel 2 goto :settings_mode
goto :settings_show

:settings_show
python settings.py show
pause
goto :settings

:settings_mode
cls
echo  ==============================================================
echo                   CHANGE CONNECTION MODE
echo  ==============================================================
echo.
echo    [1] Direct connection
echo    [2] SOCKS5 proxy
echo    [3] Cloudflare - without Worker (official endpoints)
echo    [4] Cloudflare - with Worker
echo    [5] Back to Connection Settings
echo.
choice /C 12345 /N /M "  Your choice [1-5]: "

if errorlevel 5 goto :settings
if errorlevel 4 goto :settings_cf_worker
if errorlevel 3 goto :settings_cf_noworker
if errorlevel 2 goto :settings_socks5
goto :settings_direct

:settings_direct
python settings.py set-direct
goto :settings_mode

:settings_socks5
python settings.py set-socks5
goto :settings_mode

:settings_cf_noworker
python settings.py set-cf-no-worker
goto :settings_mode

:settings_cf_worker
python settings.py set-cf-worker
goto :settings_mode

:settings_test
python settings.py test
pause
goto :settings

:reinstall
echo.
echo  ── Full reinstall ... ──
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/parhamghahremani/userbot_own/main/install.sh | iex"
goto :menu

:version
echo userbot_own version %APP_VERSION%
pause
goto :menu

:help
cls
echo  ==============================================================
echo           USERBOT  -  COMMAND REFERENCE  (v%APP_VERSION%)
echo  ==============================================================
echo.
echo  Usage: run.bat [command] [args...]
echo.
echo  Commands:
echo    run                    Start the userbot (main.py)
echo    add                    Manage accounts
echo    settings [cmd]         Connection settings menu or subcommand
echo    reinstall              Full reinstall
echo    version                Show version
echo    help                   Show this help message
echo.
echo  Settings subcommands (also work as: run.bat settings ^<cmd^>):
echo    show                   Print current connection settings
echo    set-direct             Switch to direct connection (no proxy)
echo    set-socks5 [host port [user] [pass]]
echo                           Switch to SOCKS5 proxy (prompts if args omitted)
echo    set-cf-no-worker       CF mode via Telegram's official endpoints
echo    set-cf-worker [domain] CF mode via personal relay Worker (prompts if omitted)
echo    test                   Live connection test of active route
echo.
echo  Interactive menus (no args):
echo    run.bat                Main menu (single keypress, no Enter)
echo    run.bat settings       Connection settings menu (single keypress)
echo    run.bat add            Account management menu (single keypress)
echo.
echo  Notes:
echo    * All menus use single keypress (no Enter needed) in a TTY
echo    * Invalid input in menus clears and re-prompts automatically
echo    * Ctrl+C during a running task returns to the launching menu
echo    * Connection mode is system-wide (applies to bot + account manager)
echo    * Data preserved on update: accounts/, .env/, data/ folders
echo.
pause
goto :menu

:exit
endlocal
exit /b 0
