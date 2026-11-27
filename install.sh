#!/usr/bin/env bash
#
# install.sh — Safe installer / updater for TeleWeave/Userbot.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/parhamghahremani/TeleWeave/main/install.sh | bash
#
# Existing installations are updated with a fast-forward-only Git merge.
# Local commits are never discarded, and protected user-data paths are checked
# before and after syncing.

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
REPO_URL="https://github.com/parhamghahremani/TeleWeave.git"
REPO_NAME="TeleWeave"
INSTALL_DIR="${HOME}/${REPO_NAME}"
LAUNCHER_NAME="teleweave"

if [[ -n "${PREFIX:-}" && "$PREFIX" == *"com.termux"* ]] && command -v pkg >/dev/null 2>&1; then
  IS_TERMUX=true
  PLATFORM="termux"
  BIN_DIR="${PREFIX}/bin"
else
  IS_TERMUX=false
  PLATFORM="linux"
  BIN_DIR="${HOME}/.local/bin"
fi

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  R=$'\033[0m'; B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; E=$'\033[31m'; C=$'\033[36m'
else
  R=""; B=""; G=""; Y=""; E=""; C=""
fi

log()  { printf '%b[install]%b %s\n' "$C" "$R" "$1"; }
ok()   { printf '%b[ OK ]%b %s\n' "$G" "$R" "$1"; }
warn() { printf '%b[WARN]%b %s\n' "$Y" "$R" "$1"; }
die()  { printf '%b[FAIL]%b %s\n' "$E" "$R" "$1" >&2; exit 1; }

on_error() {
  local status=$?
  printf '%b[FAIL]%b Installer stopped at line %s (exit %s).\n' "$E" "$R" "${BASH_LINENO[0]:-?}" "$status" >&2
  exit "$status"
}
trap on_error ERR

# User-owned data can exist in either of the layouts supported by the launcher.
PROTECTED_PATHS=(
  "accounts" ".env" "data"
  "Userbot/accounts" "Userbot/.env" "Userbot/data"
)

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

# Git status checks every file beneath a directory (including nested files),
# so rules such as "accounts/*" work without requiring the directory itself to
# match an ignore pattern. Any non-ignored untracked file makes this fail.
protected_path_is_ignored() {
  local rel="$1"
  local unignored
  unignored="$(git -C "$INSTALL_DIR" status --porcelain --untracked-files=all -- "$rel")" || return 1
  [[ -z "$unignored" ]]
}

assert_protected_paths_safe() {
  local rel tracked
  for rel in "${PROTECTED_PATHS[@]}"; do
    tracked="$(git -C "$INSTALL_DIR" ls-files -- "$rel" "${rel%/}/" 2>/dev/null || true)"
    if [[ -n "$tracked" ]]; then
      printf '%s\n' "$tracked" | sed 's/^/       /' >&2
      die "Protected user-data path '${rel}' is tracked by Git. Refusing to update because Git could modify or remove it."
    fi

    if path_exists "${INSTALL_DIR}/${rel}"; then
      if ! protected_path_is_ignored "$rel"; then
        die "Existing user data '${INSTALL_DIR}/${rel}' is not ignored by Git. Add a matching rule to .gitignore before updating; no files were changed."
      fi
    fi
  done
}

assert_remote_does_not_track_protected_paths() {
  local remote_ref="$1" rel remote_tracked
  for rel in "${PROTECTED_PATHS[@]}"; do
    remote_tracked="$(git -C "$INSTALL_DIR" ls-tree -r --name-only "$remote_ref" -- "$rel" "${rel%/}/" 2>/dev/null || true)"
    if [[ -n "$remote_tracked" ]]; then
      printf '%s\n' "$remote_tracked" | sed 's/^/       /' >&2
      die "The remote branch contains files inside protected user-data path '${rel}'. Refusing to merge it."
    fi
  done
}


# -----------------------------------------------------------------------------
# Platform packages
# -----------------------------------------------------------------------------
install_python_and_git() {
  if $IS_TERMUX; then
    log "Updating Termux package index..."
    pkg update -y || warn "Termux package index update failed; continuing with installed package metadata."
    log "Ensuring Python and Git are installed..."
    pkg install -y python git || die "Could not install Python and Git with pkg."
  elif command -v apt-get >/dev/null 2>&1; then
    local -a SUDO=()
    if [[ "$EUID" -ne 0 ]]; then
      command -v sudo >/dev/null 2>&1 || die "Package installation requires root or sudo."
      SUDO=(sudo)
    fi
    log "Ensuring Python, venv support, pip, and Git are installed..."
    "${SUDO[@]}" apt-get update || warn "apt-get update had issues; trying package installation anyway."
    "${SUDO[@]}" apt-get install -y git python3 python3-venv python3-pip \
      || die "Failed to install required packages via apt-get."
  else
    warn "Non-Debian Linux detected; assuming Python 3.11+, pip, and Git are installed."
  fi

  command -v git >/dev/null 2>&1 || die "git is not available on PATH. Install Git and re-run."
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    die "No Python interpreter found on PATH. Python 3.11+ is required."
  fi
}

install_build_toolchain() {
  if $IS_TERMUX; then
    log "Installing native build tools for Termux..."
    pkg install -y clang make libffi openssl \
      || { warn "Could not install the Termux native build tools."; return 1; }
  elif command -v apt-get >/dev/null 2>&1; then
    local -a SUDO=()
    if [[ "$EUID" -ne 0 ]]; then
      command -v sudo >/dev/null 2>&1 || { warn "sudo is required to install build tools."; return 1; }
      SUDO=(sudo)
    fi
    log "Installing native build tools for Debian/Ubuntu..."
    "${SUDO[@]}" apt-get install -y build-essential libffi-dev libssl-dev python3-dev \
      || { warn "Could not install build-essential and Python headers."; return 1; }
  else
    warn "No supported package manager found for native build tools."
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Existing repository sync — fast-forward only; never reset --hard.
# -----------------------------------------------------------------------------
read_version() {
  local version_value="unknown"
  if [[ -r "${INSTALL_DIR}/VERSION" ]]; then
    version_value="$(<"${INSTALL_DIR}/VERSION")"
  fi
  printf '%s\n' "${version_value:-unknown}"
}

sync_existing_repository() {
  local old_sha branch remote_ref ahead_count rel dirty_files
  local -a EXISTING_PROTECTED_PATHS=()

  old_sha="$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  log "Existing Git installation found at ${INSTALL_DIR}. Checking local changes..."

  dirty_files="$(git -C "$INSTALL_DIR" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [[ -n "$dirty_files" ]]; then
    warn "Tracked local modifications were found:"
    printf '%s\n' "$dirty_files" | sed 's/^/       /'
    die "Refusing to update over tracked local changes. Commit or stash them, then re-run."
  fi

  assert_protected_paths_safe
  for rel in "${PROTECTED_PATHS[@]}"; do
    if path_exists "${INSTALL_DIR}/${rel}"; then
      EXISTING_PROTECTED_PATHS+=("$rel")
    fi
  done

  log "Fetching origin..."
  git -C "$INSTALL_DIR" fetch --prune origin \
    || die "git fetch failed. Check the network and the configured origin remote."

  branch="$(git -C "$INSTALL_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [[ -n "$branch" ]] || die "The local repository is in detached-HEAD state. Check out its deployment branch before updating."
  remote_ref="refs/remotes/origin/${branch}"
  git -C "$INSTALL_DIR" show-ref --verify --quiet "$remote_ref" \
    || die "Remote branch origin/${branch} does not exist. Refusing to guess another branch."

  ahead_count="$(git -C "$INSTALL_DIR" rev-list --count "${remote_ref}..HEAD")"
  if [[ "$ahead_count" != "0" ]]; then
    die "Local branch '${branch}' has ${ahead_count} commit(s) not present on origin/${branch}. Push or intentionally reconcile them first; no local commits were discarded."
  fi

  assert_remote_does_not_track_protected_paths "$remote_ref"

  log "Fast-forwarding to origin/${branch}..."
  git -C "$INSTALL_DIR" merge --ff-only --no-edit "$remote_ref" \
    || die "Fast-forward update failed. Git left the local branch intact; inspect the error and resolve it before retrying."

  # Re-check after the merge: a remote .gitignore change must not silently
  # remove protection for data that already existed on this device.
  for rel in "${EXISTING_PROTECTED_PATHS[@]}"; do
    if ! path_exists "${INSTALL_DIR}/${rel}"; then
      die "Previously existing user data disappeared: ${INSTALL_DIR}/${rel}"
    fi
    if ! protected_path_is_ignored "$rel"; then
      die "The updated .gitignore no longer protects '${rel}'. The data path still exists; fix .gitignore before proceeding."
    fi
  done

  local new_sha
  new_sha="$(git -C "$INSTALL_DIR" rev-parse --short HEAD)"
  if [[ "$old_sha" == "$new_sha" ]]; then
    ok "Repository is already up to date (${new_sha})."
  else
    ok "Repository fast-forwarded: ${old_sha} -> ${new_sha}."
  fi
}

# -----------------------------------------------------------------------------
# Main installation
# -----------------------------------------------------------------------------
log "Detected platform: ${PLATFORM}"
install_python_and_git

PY_VERSION="$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo unknown)"
log "Using ${PYTHON_BIN} (Python ${PY_VERSION})"
if [[ ! "$PY_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  die "Could not determine the Python version. Python 3.11+ is required."
fi
PY_MAJOR="${PY_VERSION%%.*}"
PY_MINOR="${PY_VERSION##*.}"
if [[ "$PY_MAJOR" -lt 3 || ( "$PY_MAJOR" -eq 3 && "$PY_MINOR" -lt 11 ) ]]; then
  die "Python ${PY_VERSION} is too old. Python 3.11 or newer is required."
fi
ok "Python version requirement satisfied."

OLD_VERSION="unknown"
OLD_SHA="none (fresh install)"

# -----------------------------------------------------------------------------
# Legacy installation detection and migration (~/userbot_own -> ~/TeleWeave)
# -----------------------------------------------------------------------------
LEGACY_DIR="${HOME}/userbot_own"
if [[ -d "${LEGACY_DIR}/.git" ]]; then
  log "Legacy installation detected at ${LEGACY_DIR}"

  # Identify legacy data locations (package-internal v3.2.9+ and root-level v3.2.7-3.2.8)
  LEGACY_ACCOUNTS=()
  LEGACY_DATA=()
  LEGACY_ENV=()

  # Package-internal layout (v3.2.9+)
  if [[ -d "${LEGACY_DIR}/userbot_own/accounts" ]]; then
    LEGACY_ACCOUNTS+=("${LEGACY_DIR}/userbot_own/accounts")
  fi
  if [[ -d "${LEGACY_DIR}/userbot_own/data" ]]; then
    LEGACY_DATA+=("${LEGACY_DIR}/userbot_own/data")
  fi
  if [[ -f "${LEGACY_DIR}/userbot_own/.env" ]]; then
    LEGACY_ENV+=("${LEGACY_DIR}/userbot_own/.env")
  fi

  # Root-level layout (v3.2.7-3.2.8)
  if [[ -d "${LEGACY_DIR}/accounts" ]]; then
    LEGACY_ACCOUNTS+=("${LEGACY_DIR}/accounts")
  fi
  if [[ -d "${LEGACY_DIR}/data" ]]; then
    LEGACY_DATA+=("${LEGACY_DIR}/data")
  fi
  if [[ -f "${LEGACY_DIR}/.env" ]]; then
    LEGACY_ENV+=("${LEGACY_DIR}/.env")
  fi

  # Check for conflicts with new location
  if [[ -d "${INSTALL_DIR}" ]]; then
    warn "Both legacy (${LEGACY_DIR}) and new (${INSTALL_DIR}) installations exist!"
    for d in "${INSTALL_DIR}/accounts" "${INSTALL_DIR}/Userbot/accounts" "${LEGACY_ACCOUNTS[@]}"; do
      [[ -d "$d" ]] && log "Found accounts at: $d"
    done
    die "Manual intervention required. Please backup and choose one installation to keep."
  fi

  # Safe migration: copy data, update origin, then move legacy aside
  log "Migrating legacy data to ${INSTALL_DIR}..."
  mkdir -p "${INSTALL_DIR}"

  # Copy accounts (preserve structure)
  for src in "${LEGACY_ACCOUNTS[@]}"; do
    dst="${INSTALL_DIR}/Userbot/accounts"
    mkdir -p "$dst"
    cp -rn "$src"/* "$dst/" 2>/dev/null || true
    log "Copied accounts from $src to $dst"
  done

  # Copy data
  for src in "${LEGACY_DATA[@]}"; do
    dst="${INSTALL_DIR}/Userbot/data"
    mkdir -p "$dst"
    cp -rn "$src"/* "$dst/" 2>/dev/null || true
    log "Copied data from $src to $dst"
  done

  # Copy .env
  for src in "${LEGACY_ENV[@]}"; do
    dst="${INSTALL_DIR}/Userbot/.env"
    cp "$src" "$dst" 2>/dev/null || true
    log "Copied .env from $src to $dst"
  done

  # Update origin URL in legacy repo, then move it aside
  log "Updating legacy repository origin to new repository..."
  git -C "${LEGACY_DIR}" remote set-url origin "https://github.com/parhamghahremani/TeleWeave.git" || warn "Could not update legacy origin; continuing anyway."
  mv "${LEGACY_DIR}" "${INSTALL_DIR}.legacy_backup"
  log "Legacy repo backed up to ${INSTALL_DIR}.legacy_backup"

  # Continue with fresh clone at INSTALL_DIR
  log "Cloning new repository into ${INSTALL_DIR}..."
  git clone "$REPO_URL" "$INSTALL_DIR" || die "git clone failed. Check the URL and network connection."

  OLD_VERSION="legacy (migrated)"
  OLD_SHA="$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

elif [[ -d "${INSTALL_DIR}/.git" ]]; then
  OLD_VERSION="$(read_version)"
  OLD_SHA="$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  sync_existing_repository
elif [[ -e "$INSTALL_DIR" ]]; then
  die "${INSTALL_DIR} exists but is not a Git repository. Move it aside manually; the installer will not overwrite it."
else
  log "Cloning repository into ${INSTALL_DIR}..."
  git clone "$REPO_URL" "$INSTALL_DIR" || die "git clone failed. Check the URL and network connection."
fi

# Apply the same data-safety checks to a fresh clone as to an existing install.
# This prevents the installer from silently accepting a repository that tracks
# account sessions, .env, or runtime data.
assert_protected_paths_safe
assert_remote_does_not_track_protected_paths "HEAD"

NEW_VERSION="$(read_version)"
NEW_SHA="$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
ok "Repository ready at ${INSTALL_DIR}."

# -----------------------------------------------------------------------------
# Clear project bytecode only. Never traverse .git or the virtual environment.
# -----------------------------------------------------------------------------
log "Clearing stale project bytecode caches..."
find "$INSTALL_DIR" \
  \( -type d \( -name .git -o -name .venv -o -name venv \) -prune \) -o \
  \( -type d -name '__pycache__' -prune -exec rm -rf {} + \) 2>/dev/null || true
find "$INSTALL_DIR" \
  \( -type d \( -name .git -o -name .venv -o -name venv \) -prune \) -o \
  \( -type f -name '*.pyc' -delete \) 2>/dev/null || true
ok "Project bytecode caches cleared."

# -----------------------------------------------------------------------------
# Virtual environment and dependencies
# -----------------------------------------------------------------------------
VENV_DIR="${INSTALL_DIR}/.venv"
VENV_PY="${VENV_DIR}/bin/python"
if [[ ! -x "$VENV_PY" ]]; then
  log "Creating virtual environment at ${VENV_DIR}..."
  "$PYTHON_BIN" -m venv "$VENV_DIR" \
    || die "Could not create the virtual environment. On Debian/Ubuntu install python3-venv, then re-run."
else
  log "Reusing existing virtual environment."
fi

"$VENV_PY" -m pip install --disable-pip-version-check --retries 1 --timeout 15 --upgrade pip >/dev/null 2>&1 \
  || warn "Could not upgrade pip; continuing with the installed version."

REQUIREMENTS_FILE="${INSTALL_DIR}/requirements.txt"
if [[ -f "$REQUIREMENTS_FILE" ]]; then
  log "Installing project dependencies..."
  if "$VENV_PY" -m pip install --disable-pip-version-check --retries 2 --timeout 20 -r "$REQUIREMENTS_FILE"; then
    if "$VENV_PY" -m pip check; then
      ok "Dependencies installed and dependency metadata is consistent."
    else
      die "pip check found incompatible or missing dependencies."
    fi
  else
    warn "Dependency installation failed; installing native build tools and retrying once..."
    install_build_toolchain || die "Could not prepare the native build toolchain. Dependency installation remains incomplete."
    "$VENV_PY" -m pip install --disable-pip-version-check --retries 2 --timeout 20 -r "$REQUIREMENTS_FILE" \
      || die "Dependency installation failed again. See pip output above."
    if "$VENV_PY" -m pip check; then
      ok "Dependencies installed after the build-toolchain retry."
    else
      die "pip check found incompatible or missing dependencies after the retry."
    fi
  fi
else
  warn "No requirements.txt found; dependency installation was skipped."
fi

# -----------------------------------------------------------------------------
# Resolve supported project layouts and run a syntax check.
# -----------------------------------------------------------------------------
if [[ -f "${INSTALL_DIR}/main.py" ]]; then
  MAIN_PY="${INSTALL_DIR}/main.py"
  ADD_ACCOUNT_PY="${INSTALL_DIR}/add_account.py"
  SETTINGS_PY="${INSTALL_DIR}/settings.py"
  RUN_DIR="$INSTALL_DIR"
elif [[ -f "${INSTALL_DIR}/Userbot/main.py" ]]; then
  MAIN_PY="${INSTALL_DIR}/Userbot/main.py"
  ADD_ACCOUNT_PY="${INSTALL_DIR}/Userbot/add_account.py"
  SETTINGS_PY="${INSTALL_DIR}/Userbot/settings.py"
  RUN_DIR="${INSTALL_DIR}/Userbot"
else
  die "Could not find main.py in the repository root or Userbot/ directory."
fi

CODE_ROOT="$RUN_DIR"
log "Checking Python syntax (excluding .git and virtual environments)..."
if "$VENV_PY" -m compileall -q -x '(^|/)(\.git|\.venv|venv|accounts|data)(/|$)' "$CODE_ROOT"; then
  ok "Python syntax check passed."
else
  die "Python syntax check failed. Review the errors above before running the bot."
fi

UPDATE_SH="${INSTALL_DIR}/update.sh"
[[ -f "$UPDATE_SH" ]] || warn "update.sh was not found. The Launcher will report this if Update is selected."

# -----------------------------------------------------------------------------
# Generate a launcher. Constants are shell-escaped separately; the body is a
# single-quoted heredoc so its variables expand at launcher runtime, not here.
# -----------------------------------------------------------------------------
mkdir -p "$BIN_DIR"
LAUNCHER_DEST="${BIN_DIR}/${LAUNCHER_NAME}"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'INSTALL_DIR=%q\n' "$INSTALL_DIR"
  printf 'VENV_PY=%q\n' "$VENV_PY"
  printf 'MAIN_PY=%q\n' "$MAIN_PY"
  printf 'ADD_ACCOUNT_PY=%q\n' "$ADD_ACCOUNT_PY"
  printf 'SETTINGS_PY=%q\n' "$SETTINGS_PY"
  printf 'RUN_DIR=%q\n' "$RUN_DIR"
  printf 'UPDATE_SH=%q\n' "$UPDATE_SH"
  printf 'VERSION_FILE=%q\n' "${INSTALL_DIR}/VERSION"
  cat <<'LAUNCHER_BODY'

set -u

if [[ -t 1 ]]; then
  R=$'\033[0m'; B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; E=$'\033[31m'; C=$'\033[36m'
else
  R=""; B=""; G=""; Y=""; E=""; C=""
fi

log()  { printf '%b[teleweave]%b %s\n' "$C" "$R" "$1"; }
ok()   { printf '%b[ OK ]%b %s\n' "$G" "$R" "$1"; }
warn() { printf '%b[WARN]%b %s\n' "$Y" "$R" "$1" >&2; }
die()  { printf '%b[FAIL]%b %s\n' "$E" "$R" "$1" >&2; return 1; }

current_version() {
  local value="unknown"
  if [[ -r "$VERSION_FILE" ]]; then
    value="$(<"$VERSION_FILE")"
  fi
  printf '%s' "${value:-unknown}"
}

pause() {
  [[ -t 0 ]] || return 0
  printf '\n%bPress Enter to continue...%b' "$Y" "$R"
  IFS= read -r _ || true
}

print_help() {
  printf '%bTeleWeave/Userbot v%s — Command Reference%b\n\n' "$B" "$(current_version)" "$R"
  cat <<'HELP_TEXT'
Usage:
  teleweave [command] [args...]

Commands:
  run                         Start the userbot
  add                         Open account management
  settings [command] [args]   Open connection settings or run a subcommand
  update                      Safely update code and dependencies
  reinstall                   Re-run the installer
  version                     Show installed version
  help                        Show this help

Connection settings subcommands:
  show
  set-direct
  set-socks5 [host port [user] [pass]]
  set-cf-no-worker
  set-cf-worker [domain]
  test

Interactive menus:
  teleweave                   Main menu
  teleweave settings          Connection settings menu
  teleweave add               Account management menu

Notes:
  - Update uses update.sh; Git sync is fast-forward-only.
  - Tracked local changes and unpushed commits block updates.
  - Existing accounts/, .env, and data/ paths are checked before updating.
HELP_TEXT
}

run_python_file() {
  local script="$1"
  shift || true
  if [[ ! -x "$VENV_PY" ]]; then
    die "Virtual environment not found: $VENV_PY"
    return 1
  fi
  if [[ ! -f "$script" ]]; then
    die "Required project script not found: $script"
    return 1
  fi
  ( cd "$RUN_DIR" && "$VENV_PY" "$script" "$@" )
}

run_update() {
  if [[ ! -f "$UPDATE_SH" ]]; then
    die "Updater not found: $UPDATE_SH. Re-run the installer."
    return 1
  fi
  bash "$UPDATE_SH" "$@"
}

run_and_pause() {
  local status=0
  "$@" || status=$?
  if [[ "$status" -ne 0 ]]; then
    warn "Command finished with exit code ${status}."
  fi
  pause
  return 0
}

settings_menu() {
  local subchoice modechoice
  while true; do
    printf '\n%b=== Connection Settings ===%b\n' "$B" "$R"
    printf '1) Show current settings\n'
    printf '2) Change connection mode\n'
    printf '3) Test connection\n'
    printf '4) Back to main menu\n'
    printf 'Your choice [1-4]: '
    subchoice=""
    IFS= read -r -n 1 subchoice || break
    printf '\n'
    case "$subchoice" in
      1)
        run_and_pause run_python_file "$SETTINGS_PY" show
        ;;
      2)
        while true; do
          printf '\n%b=== Change Connection Mode ===%b\n' "$B" "$R"
          printf '1) Direct connection\n'
          printf '2) SOCKS5 proxy\n'
          printf '3) Cloudflare - without Worker\n'
          printf '4) Cloudflare - with Worker\n'
          printf '5) Back to Connection Settings\n'
          printf 'Your choice [1-5]: '
          modechoice=""
          IFS= read -r -n 1 modechoice || return 0
          printf '\n'
          case "$modechoice" in
            1) run_and_pause run_python_file "$SETTINGS_PY" set-direct ;;
            2) run_and_pause run_python_file "$SETTINGS_PY" set-socks5 ;;
            3) run_and_pause run_python_file "$SETTINGS_PY" set-cf-no-worker ;;
            4) run_and_pause run_python_file "$SETTINGS_PY" set-cf-worker ;;
            5) break ;;
            *) warn "Invalid option. Choose 1-5." ;;
          esac
        done
        ;;
      3)
        run_and_pause run_python_file "$SETTINGS_PY" test
        ;;
      4)
        break
        ;;
      *)
        warn "Invalid option. Choose 1-4."
        ;;
    esac
  done
}

main_menu() {
  local choice
  if [[ ! -t 0 ]]; then
    die "The interactive menu requires a terminal. Use: teleweave help"
    return 1
  fi

  while true; do
    printf '\n%b=== TeleWeave/Userbot — v%s ===%b\n' "$B" "$(current_version)" "$R"
    printf '1) Run bot\n'
    printf '2) Manage accounts\n'
    printf '3) Connection settings\n'
    printf '4) Update\n'
    printf '5) Quit\n'
    printf 'Your choice [1-5]: '
    choice=""
    IFS= read -r -n 1 choice || break
    printf '\n'
    case "$choice" in
      1) run_and_pause run_python_file "$MAIN_PY" ;;
      2) run_and_pause run_python_file "$ADD_ACCOUNT_PY" ;;
      3) settings_menu ;;
      4) run_and_pause run_update ;;
      5) break ;;
      *) warn "Invalid option. Choose 1-5." ;;
    esac
  done
}

case "${1:-}" in
  run)
    shift
    run_python_file "$MAIN_PY" "$@"
    ;;
  add)
    shift
    run_python_file "$ADD_ACCOUNT_PY" "$@"
    ;;
  settings)
    shift
    if [[ "$#" -eq 0 ]]; then
      run_python_file "$SETTINGS_PY"
    else
      run_python_file "$SETTINGS_PY" "$@"
    fi
    ;;
  update)
    shift
    run_update "$@"
    ;;
  reinstall)
    exec bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/parhamghahremani/TeleWeave/main/install.sh | bash'
    ;;
  version|--version)
    printf 'TeleWeave/Userbot version %s\n' "$(current_version)"
    ;;
  help|--help|-h)
    print_help
    ;;
  "")
    main_menu
    ;;
  *)
    printf 'Usage: teleweave [run|add|settings [command]|update|reinstall|version|help]\n' >&2
    exit 2
    ;;
esac
LAUNCHER_BODY
} > "$LAUNCHER_DEST"
chmod 0755 "$LAUNCHER_DEST"
ok "Launcher generated at ${LAUNCHER_DEST}."

# -----------------------------------------------------------------------------
# Compatibility alias: userbot -> teleweave (for existing users)
# -----------------------------------------------------------------------------
USERBOT_ALIAS="${BIN_DIR}/userbot"
if [[ ! -e "$USERBOT_ALIAS" ]]; then
  ln -s "$LAUNCHER_DEST" "$USERBOT_ALIAS"
  ok "Created compatibility alias: userbot -> teleweave"
else
  log "Compatibility alias 'userbot' already exists; leaving as-is."
fi

# -----------------------------------------------------------------------------
# Completion summary and PATH check
# -----------------------------------------------------------------------------
printf '\n%b%s%b\n' "$B" '──────────────────────────────────────────' "$R"
printf '  Version: %s (%s) -> %s (%s)\n' "$OLD_VERSION" "$OLD_SHA" "$NEW_VERSION" "$NEW_SHA"
printf '%b%s%b\n\n' "$B" '──────────────────────────────────────────' "$R"

case ":${PATH}:" in
  *":${BIN_DIR}:"*)
    ok "Installation complete. Run: ${LAUNCHER_NAME}"
    ;;
  *)
    warn "Installation complete, but ${BIN_DIR} is not currently on PATH."
    printf 'Add this line to ~/.bashrc or ~/.zshrc:\n  export PATH=%q:"$PATH"\n' "$BIN_DIR"
    printf 'Then open a new terminal and run: %s\n' "$LAUNCHER_NAME"
    ;;
esac