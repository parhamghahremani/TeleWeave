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
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || -n "${WINDIR:-}" ]]; then
  IS_TERMUX=false
  PLATFORM="windows"
  BIN_DIR="${HOME}/.local/bin"
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

# -----------------------------------------------------------------------------
# Portable utilities
# -----------------------------------------------------------------------------

# Detect stat implementation (GNU vs BSD)
_STAT_IMPL="unknown"
if stat --version 2>&1 | head -1 | grep -q GNU; then
  _STAT_IMPL="gnu"
else
  _STAT_IMPL="bsd"
fi

get_stat() {
  local file="$1" format="$2"
  if [[ "$_STAT_IMPL" == "gnu" ]]; then
    case "$format" in
      size) stat -c%s "$file" ;;
      mtime) stat -c%Y "$file" ;;
      perms) stat -c%a "$file" ;;
    esac
  else
    case "$format" in
      size) stat -f%z "$file" ;;
      mtime) stat -f%m "$file" ;;
      perms) stat -f%Lp "$file" ;;
    esac
  fi
}

# Portable SHA256
get_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | cut -d' ' -f1
  else
    die "No SHA256 tool available (need sha256sum or shasum)"
  fi
}

# Portable realpath
get_realpath() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path"
  else
    readlink -f "$path" 2>/dev/null || {
      (cd "$(dirname "$path")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$path")")
    }
  fi
}

# Check required tools
check_required_tools() {
  local missing=()
  for tool in git find cp mkdir rm mv date; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || missing+=("sha256sum/shasum")
  # pgrep/pidof are optional - we have fallbacks
  [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}

# -----------------------------------------------------------------------------
# Migration Lock (concurrency protection)
# -----------------------------------------------------------------------------
MIGRATION_LOCK_DIR="${HOME}/.teleweave_migration.lock"
MIGRATION_LOCK_PID=""

acquire_migration_lock() {
  local lock_dir="$1"
  local max_wait=30
  local waited=0

  while true; do
    if mkdir "$lock_dir" 2>/dev/null; then
      # We got the lock
      echo $$ > "${lock_dir}/pid"
      echo "$(date -Iseconds)" > "${lock_dir}/started"
      MIGRATION_LOCK_DIR="$lock_dir"
      MIGRATION_LOCK_PID=$$
      return 0
    fi

    # Lock exists, check if stale
    local lock_pid=""
    [[ -f "${lock_dir}/pid" ]] && lock_pid=$(cat "${lock_dir}/pid" 2>/dev/null || echo "")

    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
      # Process still alive
      if [[ $waited -ge $max_wait ]]; then
        die "Migration lock held by PID $lock_pid for ${max_wait}s. Another migration may be in progress. Wait or investigate manually."
      fi
      sleep 1
      waited=$((waited + 1))
      continue
    else
      # Stale lock - but don't auto-delete unknown locks
      warn "Stale migration lock detected (PID: ${lock_pid:-unknown}). Not removing automatically."
      die "Remove ${lock_dir} manually after verifying no migration is running, then retry."
    fi
  done
}

release_migration_lock() {
  local lock_dir="$1"
  local current_pid=$$
  [[ -d "$lock_dir" ]] || return 0
  local lock_pid=""
  [[ -f "${lock_dir}/pid" ]] && lock_pid=$(cat "${lock_dir}/pid" 2>/dev/null || echo "")
  if [[ "$lock_pid" == "$current_pid" ]]; then
    rm -rf "$lock_dir"
  else
    warn "Not releasing lock owned by PID ${lock_pid:-unknown} (current: $current_pid)"
  fi
}

# -----------------------------------------------------------------------------
# Migration Marker (recovery support)
# -----------------------------------------------------------------------------
write_marker() {
  local staging_dir="$1" stage="$2"
  local marker="${staging_dir}/.migration_state"
  {
    echo "stage=${stage}"
    echo "pid=${$}"
    echo "timestamp=$(date -Iseconds)"
    echo "legacy_path=${LEGACY_DIR:-}"
    echo "backup_path=${BACKUP_DIR:-}"
    echo "new_path=${INSTALL_DIR}"
    echo "staging_path=${staging_dir}"
  } > "$marker"
}

read_marker() {
  local marker="$1"
  [[ -f "$marker" ]] || return 1
  local key value
  while IFS='=' read -r key value; do
    case "$key" in
      stage) MARKER_STAGE="$value" ;;
      pid) MARKER_PID="$value" ;;
      timestamp) MARKER_TIMESTAMP="$value" ;;
      legacy_path) MARKER_LEGACY_PATH="$value" ;;
      backup_path) MARKER_BACKUP_PATH="$value" ;;
      new_path) MARKER_NEW_PATH="$value" ;;
      staging_path) MARKER_STAGING_PATH="$value" ;;
    esac
  done < "$marker"
}

# -----------------------------------------------------------------------------
# Protected paths (user-owned data)
# -----------------------------------------------------------------------------
PROTECTED_PATHS=(
  "Userbot/accounts" "Userbot/.env" "Userbot/data"
)

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

protected_path_is_ignored() {
  local rel="$1"
  local unignored
  unignored="$(git -C "$INSTALL_DIR" status --porcelain --untracked-files=all -- "$rel" 2>/dev/null || true)"
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
# Special filesystem entry detection (symlinks, FIFOs, sockets, devices)
# -----------------------------------------------------------------------------
detect_special_entries() {
  local src_path="$1" src_key="$2"
  local special_found=false

  # Symlinks
  while IFS= read -r -d '' link; do
    local target
    target=$(readlink "$link" 2>/dev/null || echo "BROKEN")
    local rel="${link#$src_path/}"
    warn "SYMLINK detected in ${src_key}: ${rel} -> ${target}"
    special_found=true
  done < <(find "$src_path" -type l -print0 2>/dev/null)

  # FIFOs, sockets, block devices, character devices
  while IFS= read -r -d '' special; do
    local ftype
    ftype=$(stat -c%F "$special" 2>/dev/null || stat -f%HT "$special" 2>/dev/null || echo "unknown")
    local rel="${special#$src_path/}"
    warn "SPECIAL FILE in ${src_key}: ${rel} (${ftype})"
    special_found=true
  done < <(find "$src_path" \( -type p -o -type s -o -type b -o -type c \) -print0 2>/dev/null)

  [[ "$special_found" == false ]] || die "Special filesystem entries detected in legacy data. Migration aborted for safety. Please resolve manually."
}

# -----------------------------------------------------------------------------
# Active application detection
# -----------------------------------------------------------------------------
check_active_application() {
  local pids=()

  # Try pgrep first, then pidof, then ps fallback
  if command -v pgrep >/dev/null 2>&1; then
    # Look for teleweave launcher processes
    mapfile -t pids < <(pgrep -f "teleweave.*run" 2>/dev/null || true)

    # Look for python Userbot application processes
    mapfile -t -O "${#pids[@]}" pids < <(pgrep -f "Userbot\.app\.application\|Userbot.*main\.py\|python.*main\.py" 2>/dev/null || true)

    # Look for legacy userbot launcher
    mapfile -t -O "${#pids[@]}" pids < <(pgrep -f "userbot.*run" 2>/dev/null || true)
  elif command -v pidof >/dev/null 2>&1; then
    # pidof matches exact command names, less flexible but works for teleweave
    mapfile -t pids < <(pidof teleweave 2>/dev/null || true)
    mapfile -t -O "${#pids[@]}" pids < <(pidof python 2>/dev/null || true)
  else
    # Fallback: use ps to find matching processes
    mapfile -t pids < <(ps aux | grep -E "teleweave.*run|Userbot\.app\.application|Userbot.*main\.py|python.*main\.py|userbot.*run" | grep -v grep | awk '{print $2}' || true)
  fi

  if [[ ${#pids[@]} -gt 0 ]]; then
    warn "Active TeleWeave/Userbot processes detected:"
    for pid in "${pids[@]}"; do
      local cmd
      cmd=$(ps -p "$pid" -o pid= -o comm= -o args= 2>/dev/null | sed 's/^/  /' || echo "  PID $pid (details unavailable)")
      # Sanitize: only show pid and command name, not full args
      local pid_only comm_only
      pid_only=$(echo "$cmd" | awk '{print $1}')
      comm_only=$(echo "$cmd" | awk '{print $2}')
      printf '  PID %s: %s\n' "$pid_only" "$comm_only"
    done

    if [[ -t 0 ]]; then
      printf '\n%sActive application detected. Please stop the bot before migration.%s\n' "$Y" "$R"
      printf 'Press Enter after stopping the application, or Ctrl+C to abort: '
      IFS= read -r _ || exit 1

      # Recheck after user confirmation
      sleep 2
      local pids2=()
      if command -v pgrep >/dev/null 2>&1; then
        mapfile -t pids2 < <(pgrep -f "teleweave.*run|Userbot\.app\.application|Userbot.*main\.py|python.*main\.py|userbot.*run" 2>/dev/null || true)
      elif command -v pidof >/dev/null 2>&1; then
        mapfile -t pids2 < <(pidof teleweave python 2>/dev/null || true)
      else
        mapfile -t pids2 < <(ps aux | grep -E "teleweave.*run|Userbot\.app\.application|Userbot.*main\.py|python.*main\.py|userbot.*run" | grep -v grep | awk '{print $2}' || true)
      fi
      if [[ ${#pids2[@]} -gt 0 ]]; then
        die "Application still running. Please stop completely before migration."
      fi

      ok "Application stopped. Proceeding with migration."
    else
      die "Active application detected but running non-interactively. Stop the bot and re-run."
    fi
  fi
}

# -----------------------------------------------------------------------------
# Safe file copy with zero-byte preservation
# -----------------------------------------------------------------------------
safe_copy_file() {
  local src="$1" dst="$2"
  local dst_dir
  dst_dir=$(dirname "$dst")

  mkdir -p "$dst_dir" || return 1

  # cp -p preserves permissions, timestamps, ownership where supported
  cp -p "$src" "$dst" 2>/dev/null || return 1

  # Verify: destination exists as regular file
  [[ -f "$dst" ]] || return 1

  # Verify size matches (including zero)
  local src_size dst_size
  src_size=$(get_stat "$src" size)
  dst_size=$(get_stat "$dst" size)
  [[ "$src_size" -eq "$dst_size" ]] || return 1

  # Verify checksum matches
  local src_sum dst_sum
  src_sum=$(get_sha256 "$src")
  dst_sum=$(get_sha256 "$dst")
  [[ "$src_sum" == "$dst_sum" ]] || return 1

  return 0
}

safe_copy_dir() {
  local src="$1" dst="$2"
  local failed=false

  mkdir -p "$dst" || return 1

  # Copy all regular files (including hidden files) using find -print0
  while IFS= read -r -d '' file; do
    local rel="${file#$src/}"
    local dst_file="${dst}/${rel}"

    safe_copy_file "$file" "$dst_file" || {
      warn "Copy failed: ${file} -> ${dst_file}"
      failed=true
    }
  done < <(find "$src" -type f -print0 2>/dev/null)

  [[ "$failed" == false ]] || return 1
  return 0
}

# -----------------------------------------------------------------------------
# Legacy detection and inspection with manifest
# -----------------------------------------------------------------------------
LEGACY_DIR="${HOME}/userbot_own"
BACKUP_DIR="${INSTALL_DIR}.legacy_backup_$(date -u +%Y%m%d_%H%M%S)_$$"

do_staged_migration() {
  log "Starting staged migration from ${LEGACY_DIR} to ${INSTALL_DIR}"

  # Acquire migration lock
  acquire_migration_lock "${MIGRATION_LOCK_DIR}"

  # Check for active application
  check_active_application

  # STAGING DIRECTORY
  local STAGING_DIR="${HOME}/.teleweave_migration_staging_$$"
  mkdir -p "${STAGING_DIR}"
  write_marker "${STAGING_DIR}" "inspect"

  # ---------------------------------------------------------------------------
  # Phase 1: INSPECT - enumerate all legacy data sources
  # ---------------------------------------------------------------------------
  log "Inspecting legacy installation..."

  declare -A LEGACY_SOURCES=()   # key -> absolute path
  declare -a SOURCE_KEYS=()      # ordered keys for deterministic processing

  # Package-internal layout (v3.2.9+)
  if [[ -d "${LEGACY_DIR}/userbot_own/accounts" ]]; then
    LEGACY_SOURCES["pkg:accounts"]="${LEGACY_DIR}/userbot_own/accounts"
    SOURCE_KEYS+=("pkg:accounts")
  fi
  if [[ -d "${LEGACY_DIR}/userbot_own/data" ]]; then
    LEGACY_SOURCES["pkg:data"]="${LEGACY_DIR}/userbot_own/data"
    SOURCE_KEYS+=("pkg:data")
  fi
  if [[ -f "${LEGACY_DIR}/userbot_own/.env" ]]; then
    LEGACY_SOURCES["pkg:env"]="${LEGACY_DIR}/userbot_own/.env"
    SOURCE_KEYS+=("pkg:env")
  fi

  # Root-level layout (v3.2.7-3.2.8)
  if [[ -d "${LEGACY_DIR}/accounts" ]]; then
    LEGACY_SOURCES["root:accounts"]="${LEGACY_DIR}/accounts"
    SOURCE_KEYS+=("root:accounts")
  fi
  if [[ -d "${LEGACY_DIR}/data" ]]; then
    LEGACY_SOURCES["root:data"]="${LEGACY_DIR}/data"
    SOURCE_KEYS+=("root:data")
  fi
  if [[ -f "${LEGACY_DIR}/.env" ]]; then
    LEGACY_SOURCES["root:env"]="${LEGACY_DIR}/.env"
    SOURCE_KEYS+=("root:env")
  fi

  # Check if legacy has .git (for backup purposes)
  local legacy_has_git=false
  [[ -d "${LEGACY_DIR}/.git" ]] && legacy_has_git=true

  # Check for special entries in all sources
  for src_key in "${SOURCE_KEYS[@]}"; do
    local src_path="${LEGACY_SOURCES[$src_key]}"
    [[ -d "$src_path" ]] && detect_special_entries "$src_path" "$src_key"
  done

  # ---------------------------------------------------------------------------
  # Phase 2: BUILD MANIFEST - enumerate all files with checksums
  # ---------------------------------------------------------------------------
  log "Building migration manifest..."
  write_marker "${STAGING_DIR}" "build_manifest"

  declare -A FILE_MANIFEST=()  # dest_rel -> "src_key|size|mtime|checksum"
  declare -A CONFLICTS=()      # dest_rel -> "src_key1|src_key2|type"

  for src_key in "${SOURCE_KEYS[@]}"; do
    local src_path="${LEGACY_SOURCES[$src_key]}"

    if [[ -d "$src_path" ]]; then
      # Directory: enumerate all regular files
      while IFS= read -r -d '' file; do
        local rel="${file#$src_path/}"
        local dest_rel

        case "$src_key" in
          *:accounts) dest_rel="Userbot/accounts/${rel}" ;;
          *:data)     dest_rel="Userbot/data/${rel}" ;;
          *) continue ;;
        esac

        local size mtime checksum
        size=$(get_stat "$file" size)
        mtime=$(get_stat "$file" mtime)
        checksum=$(get_sha256 "$file")

        # Use parameter expansion to avoid 'unbound variable' with set -u
        local existing_entry="${FILE_MANIFEST[$dest_rel]-}"
        if [[ -n "$existing_entry" ]]; then
          # Conflict detected
          local existing_key="${existing_entry%%|*}"
          local existing_checksum="${existing_entry##*|}"
          if [[ "$checksum" != "$existing_checksum" ]]; then
            CONFLICTS[$dest_rel]="${existing_key}|${src_key}|content_mismatch"
          else
            CONFLICTS[$dest_rel]="${existing_key}|${src_key}|identical_duplicate"
          fi
        else
          FILE_MANIFEST[$dest_rel]="${src_key}|${size}|${mtime}|${checksum}"
        fi
      done < <(find "$src_path" -type f -print0 2>/dev/null)

    elif [[ -f "$src_path" ]]; then
      # Single file (.env)
      local dest_rel
      case "$src_key" in
        *:env) dest_rel="Userbot/.env" ;;
        *) continue ;;
      esac

      local size mtime checksum
      size=$(get_stat "$src_path" size)
      mtime=$(get_stat "$src_path" mtime)
      checksum=$(get_sha256 "$src_path")

      local existing_entry="${FILE_MANIFEST[$dest_rel]-}"
      if [[ -n "$existing_entry" ]]; then
        local existing_key="${existing_entry%%|*}"
        local existing_checksum="${existing_entry##*|}"
        if [[ "$checksum" != "$existing_checksum" ]]; then
          CONFLICTS[$dest_rel]="${existing_key}|${src_key}|content_mismatch"
        else
          CONFLICTS[$dest_rel]="${existing_key}|${src_key}|identical_duplicate"
        fi
      else
        FILE_MANIFEST[$dest_rel]="${src_key}|${size}|${mtime}|${checksum}"
      fi
    fi
  done

  # Report conflicts
  if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    warn "Data conflicts detected between legacy sources:"
    local real_conflicts=0
    for dest_rel in "${!CONFLICTS[@]}"; do
      local conflict="${CONFLICTS[$dest_rel]}"
      IFS='|' read -r key1 key2 ctype <<< "$conflict"
      case "$ctype" in
        content_mismatch)
          warn "  CONFLICT: ${dest_rel} <- ${key1} vs ${key2} (different content)"
          real_conflicts=$((real_conflicts + 1))
          ;;
        identical_duplicate)
          log "  DUPLICATE: ${dest_rel} <- ${key1} == ${key2} (identical, using first source: ${key1})"
          ;;
      esac
    done
    if [[ $real_conflicts -gt 0 ]]; then
      die "Unresolvable content conflicts detected. Manual intervention required."
    fi
  fi

  # ---------------------------------------------------------------------------
  # Phase 3: CHECK DESTINATION CONFLICTS
  # ---------------------------------------------------------------------------
  log "Checking destination for conflicts..."
  write_marker "${STAGING_DIR}" "check_destination"

  if [[ -d "${INSTALL_DIR}" ]]; then
    local dest_conflicts=()
    for dest_rel in "${!FILE_MANIFEST[@]}"; do
      [[ -e "${INSTALL_DIR}/${dest_rel}" ]] && dest_conflicts+=("$dest_rel")
    done
    if [[ ${#dest_conflicts[@]} -gt 0 ]]; then
      die "Destination ${INSTALL_DIR} already has data: ${dest_conflicts[*]}. Manual intervention required."
    fi
  fi

  # Check backup destination
  if [[ -e "${BACKUP_DIR}" ]]; then
    die "Backup destination ${BACKUP_DIR} already exists. Remove or rename it first."
  fi

  # ---------------------------------------------------------------------------
  # Phase 4: STAGE - clone repository
  # ---------------------------------------------------------------------------
  log "Cloning repository into staging area..."
  write_marker "${STAGING_DIR}" "clone"

  git clone "$REPO_URL" "${STAGING_DIR}/TeleWeave" || {
    write_marker "${STAGING_DIR}" "failed_clone"
    release_migration_lock "${MIGRATION_LOCK_DIR}"
    die "Git clone failed. Check the URL and network connection."
  }

  # Verify clone structure
  write_marker "${STAGING_DIR}" "verify_structure"
  for req in \
    main.py \
    add_account.py \
    settings.py \
    Userbot/__init__.py \
    Userbot/app/application.py \
    Userbot/config/models.py
  do
    [[ -f "${STAGING_DIR}/TeleWeave/${req}" ]] || {
      write_marker "${STAGING_DIR}" "failed_verify_structure"
      release_migration_lock "${MIGRATION_LOCK_DIR}"
      die "Clone verification failed: missing ${req}"
    }
  done

  # ---------------------------------------------------------------------------
  # Phase 5: COPY DATA
  # ---------------------------------------------------------------------------
  log "Copying legacy data to staging..."
  write_marker "${STAGING_DIR}" "copy_data"

  for dest_rel in "${!FILE_MANIFEST[@]}"; do
    local manifest_entry="${FILE_MANIFEST[$dest_rel]}"
    local src_key="${manifest_entry%%|*}"
    local src_base="${LEGACY_SOURCES[$src_key]}"

    local src_path
    case "$src_key" in
      *:accounts) src_path="${src_base}/${dest_rel#Userbot/accounts/}" ;;
      *:data)     src_path="${src_base}/${dest_rel#Userbot/data/}" ;;
      *:env)      src_path="${src_base}" ;;
      *) continue ;;
    esac

    local dst_path="${STAGING_DIR}/TeleWeave/${dest_rel}"

    if [[ "$src_key" == *:env ]]; then
      safe_copy_file "$src_path" "$dst_path" || {
        write_marker "${STAGING_DIR}" "failed_copy_env"
        release_migration_lock "${MIGRATION_LOCK_DIR}"
        die "Failed to copy .env from ${src_path}"
      }
    elif [[ -d "$src_path" ]]; then
      safe_copy_dir "$src_path" "$dst_path" || {
        write_marker "${STAGING_DIR}" "failed_copy_data"
        release_migration_lock "${MIGRATION_LOCK_DIR}"
        die "Failed to copy directory ${src_path}"
      }
    elif [[ -f "$src_path" ]]; then
      safe_copy_file "$src_path" "$dst_path" || {
        write_marker "${STAGING_DIR}" "failed_copy_file"
        release_migration_lock "${MIGRATION_LOCK_DIR}"
        die "Failed to copy file ${src_path}"
      }
    else
      write_marker "${STAGING_DIR}" "failed_copy_missing"
      release_migration_lock "${MIGRATION_LOCK_DIR}"
      die "Source not found: ${src_path} (key: ${src_key})"
    fi
  done

  # ---------------------------------------------------------------------------
  # Phase 6: VERIFY INTEGRITY
  # ---------------------------------------------------------------------------
  log "Verifying copied data integrity..."
  write_marker "${STAGING_DIR}" "verify"

  local verify_failed=false
  for dest_rel in "${!FILE_MANIFEST[@]}"; do
    local manifest_entry="${FILE_MANIFEST[$dest_rel]}"
    IFS='|' read -r src_key expected_size expected_mtime expected_checksum <<< "$manifest_entry"

    local dst_path="${STAGING_DIR}/TeleWeave/${dest_rel}"

    [[ -f "$dst_path" ]] || {
      warn "VERIFY FAIL: Missing ${dest_rel}"
      verify_failed=true
      continue
    }

    local actual_size actual_checksum
    actual_size=$(get_stat "$dst_path" size)
    actual_checksum=$(get_sha256 "$dst_path")

    if [[ "$actual_size" -ne "$expected_size" ]]; then
      warn "VERIFY FAIL: Size mismatch for ${dest_rel} (expected ${expected_size}, got ${actual_size})"
      verify_failed=true
    elif [[ "$actual_checksum" != "$expected_checksum" ]]; then
      warn "VERIFY FAIL: Checksum mismatch for ${dest_rel}"
      verify_failed=true
    fi
  done

  # Verify session files specifically
  local session_count=0 journal_count=0
  while IFS= read -r -d '' session; do
    session_count=$((session_count + 1))
    # Verify session file is not empty
    local size
    size=$(get_stat "$session" size)
    [[ "$size" -gt 0 ]] || warn "Session file is empty: ${session#${STAGING_DIR}/TeleWeave/}"
  done < <(find "${STAGING_DIR}/TeleWeave/Userbot/accounts" -name "*.session" -type f -print0 2>/dev/null)

  while IFS= read -r -d '' journal; do
    journal_count=$((journal_count + 1))
  done < <(find "${STAGING_DIR}/TeleWeave/Userbot/accounts" -name "*.session-journal" -type f -print0 2>/dev/null)

  log "Session files verified: ${session_count} sessions, ${journal_count} journals"

  [[ "$verify_failed" == false ]] || {
    write_marker "${STAGING_DIR}" "failed_verify"
    release_migration_lock "${MIGRATION_LOCK_DIR}"
    die "Integrity verification failed."
  }

  write_marker "${STAGING_DIR}" "verified"

  # ---------------------------------------------------------------------------
  # Phase 7: BACKUP LEGACY
  # ---------------------------------------------------------------------------
  log "Backing up legacy installation..."
  write_marker "${STAGING_DIR}" "backup_legacy"

  mv "${LEGACY_DIR}" "${BACKUP_DIR}" || {
    write_marker "${STAGING_DIR}" "failed_backup"
    release_migration_lock "${MIGRATION_LOCK_DIR}"
    die "Failed to backup legacy installation. Staging preserved at ${STAGING_DIR}."
  }

  # ---------------------------------------------------------------------------
  # Phase 8: ACTIVATE
  # ---------------------------------------------------------------------------
  log "Activating new installation..."
  write_marker "${STAGING_DIR}" "activate"

  mv "${STAGING_DIR}/TeleWeave" "${INSTALL_DIR}" || {
    write_marker "${STAGING_DIR}" "failed_activate"
    # Attempt rollback
    if [[ -d "${BACKUP_DIR}" && ! -d "${LEGACY_DIR}" ]]; then
      mv "${BACKUP_DIR}" "${LEGACY_DIR}" 2>/dev/null || warn "CRITICAL: Failed to restore legacy! Manual: mv ${BACKUP_DIR} ${LEGACY_DIR}"
    fi
    release_migration_lock "${MIGRATION_LOCK_DIR}"
    die "Failed to activate new installation. Staging at ${STAGING_DIR}. Legacy backup at ${BACKUP_DIR}."
  }

  # ---------------------------------------------------------------------------
  # Phase 9: CLEANUP
  # ---------------------------------------------------------------------------
  write_marker "${STAGING_DIR}" "complete"
  rm -rf "${STAGING_DIR}" 2>/dev/null || true
  release_migration_lock "${MIGRATION_LOCK_DIR}"

  ok "Legacy migration completed successfully. Backup at ${BACKUP_DIR}"
}

# -----------------------------------------------------------------------------
# Recovery inspection for incomplete migrations
# -----------------------------------------------------------------------------
recovery_inspection() {
  local staging_dir="$1"
  local marker="${staging_dir}/.migration_state"

  [[ -f "$marker" ]] || {
    warn "Staging directory without marker: ${staging_dir}"
    return 1
  }

  # Parse marker
  local stage="" legacy_path="" backup_path="" new_path="" timestamp="" pid="" staging_path=""
  local key value
  while IFS='=' read -r key value; do
    case "$key" in
      stage) stage="$value" ;;
      pid) pid="$value" ;;
      timestamp) timestamp="$value" ;;
      legacy_path) legacy_path="$value" ;;
      backup_path) backup_path="$value" ;;
      new_path) new_path="$value" ;;
      staging_path) staging_path="$value" ;;
    esac
  done < "$marker"

  log "Recovery inspection: stage=${stage}, pid=${pid}, time=${timestamp}"
  log "  Legacy: ${legacy_path:-none}"
  log "  Backup: ${backup_path:-none}"
  log "  New: ${new_path:-none}"
  log "  Staging: ${staging_path:-none}"

  # Check directory existence
  local legacy_exists=false backup_exists=false new_exists=false staging_exists=true
  [[ -d "$legacy_path" ]] && legacy_exists=true
  [[ -d "$backup_path" ]] && backup_exists=true
  [[ -d "$new_path" ]] && new_exists=true

  case "$stage" in
    clone|verify_structure|copy_data|verify|build_manifest|check_destination|inspect)
      # Before legacy backup - staging incomplete, legacy in place
      log "Migration failed before legacy backup. Cleaning up staging."
      rm -rf "$staging_dir"
      ok "Cleanup complete. Legacy installation intact at ${legacy_path}."
      return 0
      ;;

    backup_legacy)
      # Legacy moved to backup, staging complete
      if [[ "$backup_exists" == true && "$legacy_exists" == false ]]; then
        log "Legacy was backed up but activation not completed."
        if verify_staging_complete "$staging_dir"; then
          log "Staging verified complete. Completing activation..."
          complete_activation "$staging_dir" "$new_path" "$backup_path"
        else
          warn "Staging incomplete. Restoring legacy from backup."
          mv "$backup_path" "$legacy_path"
          rm -rf "$staging_dir"
        fi
      elif [[ "$legacy_exists" == true && "$backup_exists" == false ]]; then
        warn "Backup missing but legacy exists. Migration may not have started backup."
        rm -rf "$staging_dir"
      else
        warn "Ambiguous state. Manual recovery required."
        print_manual_recovery_instructions "$legacy_path" "$backup_path" "$new_path" "$staging_dir"
      fi
      ;;

    activate)
      # During activation
      if [[ "$new_exists" == true ]]; then
        if verify_new_installation "$new_path"; then
          log "New installation verified at ${new_path}."
          [[ "$backup_exists" == true ]] && log "Legacy backup at ${backup_path} (preserved)."
          rm -rf "$staging_dir" 2>/dev/null
          return 0
        fi
      fi

      warn "Activation incomplete. Attempting recovery..."
      if [[ "$backup_exists" == true && "$legacy_exists" == false ]]; then
        if [[ -d "$staging_dir/TeleWeave" ]]; then
          log "Retrying activation from staging..."
          complete_activation "$staging_dir" "$new_path" "$backup_path"
        else
          warn "Staging corrupted. Restoring legacy from backup."
          mv "$backup_path" "$legacy_path"
          rm -rf "$staging_dir"
        fi
      else
        warn "Ambiguous state during activate. Manual recovery required."
        print_manual_recovery_instructions "$legacy_path" "$backup_path" "$new_path" "$staging_dir"
      fi
      ;;

    complete)
      if [[ "$new_exists" == true && "$backup_exists" == true ]]; then
        log "Migration already complete. Legacy backup at ${backup_path}."
        rm -rf "$staging_dir" 2>/dev/null
        return 0
      else
        warn "Marker says complete but directories mismatch."
        print_manual_recovery_instructions "$legacy_path" "$backup_path" "$new_path" "$staging_dir"
      fi
      ;;

    failed_*)
      log "Previous migration failed at stage: ${stage}"
      if [[ "$backup_exists" == true && "$legacy_exists" == false ]]; then
        log "Restoring legacy from backup."
        mv "$backup_path" "$legacy_path"
      fi
      rm -rf "$staging_dir"
      return 0
      ;;

    *)
      warn "Unknown stage: ${stage}. Manual inspection required."
      print_manual_recovery_instructions "$legacy_path" "$backup_path" "$new_path" "$staging_dir"
      return 1
      ;;
  esac
}

verify_staging_complete() {
  local staging_dir="$1"
  # Verify TeleWeave structure exists
  [[ -d "${staging_dir}/TeleWeave" ]] || return 1
  [[ -f "${staging_dir}/TeleWeave/main.py" ]] || return 1
  [[ -f "${staging_dir}/TeleWeave/Userbot/__init__.py" ]] || return 1
  return 0
}

verify_new_installation() {
  local new_path="$1"
  [[ -f "${new_path}/main.py" ]] || return 1
  [[ -f "${new_path}/Userbot/__init__.py" ]] || return 1
  return 0
}

complete_activation() {
  local staging_dir="$1" new_path="$2" backup_path="$3"
  mv "${staging_dir}/TeleWeave" "${new_path}" || {
    warn "Failed to activate. Restoring legacy from backup."
    mv "$backup_path" "$legacy_path" 2>/dev/null || true
    return 1
  }
  rm -rf "$staging_dir" 2>/dev/null
  ok "Activation completed from recovery. Legacy backup at ${backup_path}."
  return 0
}

print_manual_recovery_instructions() {
  local legacy="$1" backup="$2" new="$3" staging="$4"
  cat <<EOF
═══════════════════════════════════════════
MANUAL RECOVERY REQUIRED
═══════════════════════════════════════════
State is ambiguous. Please inspect and choose:

Directories found:
  Legacy (original):     ${legacy:-NOT FOUND}
  Legacy Backup:         ${backup:-NOT FOUND}
  New Installation:      ${new:-NOT FOUND}
  Staging:               ${staging:-NOT FOUND}

Recommended actions:
1. If ${new:-NEW} exists and works: Keep it, delete backup after verification
2. If ${backup:-BACKUP} exists and ${new:-NEW} missing: mv ${backup} ${legacy}
3. If ${staging:-STAGING} has TeleWeave/: mv ${staging}/TeleWeave ${new}
4. When in doubt: Backup all four locations, then decide

NEVER delete ${backup:-BACKUP} or ${legacy:-LEGACY} without verification.
EOF
  return 1
}

# -----------------------------------------------------------------------------
# Installation state decision tree
# -----------------------------------------------------------------------------
determine_installation_state() {
  INST_HAS_LEGACY=false
  INST_HAS_NEW=false
  INST_HAS_STAGING=false
  INST_HAS_BACKUP=false
  INST_LEGACY_HAS_GIT=false
  STAGING_DIR=""
  BACKUP_DIRS=()

  [[ -d "${HOME}/userbot_own" ]] && INST_HAS_LEGACY=true
  [[ -d "${HOME}/userbot_own/.git" ]] && INST_LEGACY_HAS_GIT=true
  [[ -d "${HOME}/TeleWeave" ]] && INST_HAS_NEW=true

  # Check for staging directories
  for d in "${HOME}"/.teleweave_migration_staging_*; do
    [[ -d "$d" ]] && INST_HAS_STAGING=true && STAGING_DIR="$d" && break
  done

  # Check for backup directories
  for d in "${HOME}/TeleWeave.legacy_backup_"*; do
    [[ -d "$d" ]] && INST_HAS_BACKUP=true && BACKUP_DIRS+=("$d")
  done
  return 0
}

# -----------------------------------------------------------------------------
# Main installation flow
# -----------------------------------------------------------------------------
main() {
  log "Detected platform: ${PLATFORM}"
  check_required_tools
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

  # Determine installation state FIRST (before any migration logic)
  determine_installation_state
  log "DEBUG: INST_HAS_LEGACY=$INST_HAS_LEGACY INST_HAS_NEW=$INST_HAS_NEW INST_HAS_STAGING=$INST_HAS_STAGING INST_HAS_BACKUP=$INST_HAS_BACKUP"

  # Case E: Previous incomplete migration or backup detected - HIGHEST PRIORITY
  log "DEBUG: Checking Case E..."
  if [[ "$INST_HAS_STAGING" == true || "$INST_HAS_BACKUP" == true ]]; then
    log "Previous migration artifacts detected. Running recovery inspection."
    if [[ "$INST_HAS_STAGING" == true ]]; then
      recovery_inspection "$STAGING_DIR"
    else
      # Only backups exist - check if new installation is valid
      if [[ "$INST_HAS_NEW" == true ]] && verify_new_installation "${HOME}/TeleWeave"; then
        log "New installation verified. Legacy backups preserved at: ${BACKUP_DIRS[*]}"
      else
        warn "Backup(s) exist but new installation not verified. Manual recovery may be needed."
        for b in "${BACKUP_DIRS[@]}"; do
          log "  Backup: $b"
        done
      fi
    fi
  fi

  # Case D: Both legacy and new installations exist
  if [[ "$INST_HAS_LEGACY" == true && "$INST_HAS_NEW" == true ]]; then
    warn "Both legacy (${HOME}/userbot_own) and new (${HOME}/TeleWeave) installations exist!"
    die "Manual intervention required. Cannot auto-resolve dual installation."
  fi

  # Case C: Legacy-only migration
  if [[ "$INST_HAS_LEGACY" == true && "$INST_HAS_NEW" == false ]]; then
    log "Legacy installation detected at ${HOME}/userbot_own. Starting staged migration."
    do_staged_migration
  fi

  # Case B: Existing TeleWeave installation - safe update
  if [[ "$INST_HAS_LEGACY" == false && "$INST_HAS_NEW" == true ]]; then
    log "Existing TeleWeave installation detected. Running safe update."
    # Continue to existing repository sync below
  fi

  # Case A: Fresh installation (no legacy, no new, no staging, no backup)
  if [[ "$INST_HAS_LEGACY" == false && "$INST_HAS_NEW" == false && "$INST_HAS_STAGING" == false && "$INST_HAS_BACKUP" == false ]]; then
    log "Fresh installation detected."
    # Continue to fresh clone below
  fi

  # ---------------------------------------------------------------------------
  # Existing repository sync or fresh clone
  # ---------------------------------------------------------------------------
  OLD_VERSION="unknown"
  OLD_SHA="none (fresh install)"

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
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
  assert_protected_paths_safe
  assert_remote_does_not_track_protected_paths "HEAD"

  NEW_VERSION="$(read_version)"
  NEW_SHA="$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  ok "Repository ready at ${INSTALL_DIR}."

  # ---------------------------------------------------------------------------
  # Clear project bytecode only. Never traverse .git or the virtual environment.
  # ---------------------------------------------------------------------------
  log "Clearing stale project bytecode caches..."
  find "$INSTALL_DIR" \
    \( -type d \( -name .git -o -name .venv -o -name venv \) -prune \) -o \
    \( -type d -name '__pycache__' -prune -exec rm -rf {} + \) 2>/dev/null || true
  find "$INSTALL_DIR" \
    \( -type d \( -name .git -o -name .venv -o -name venv \) -prune \) -o \
    \( -type f -name '*.pyc' -delete \) 2>/dev/null || true
  ok "Project bytecode caches cleared."

  # ---------------------------------------------------------------------------
  # Virtual environment and dependencies
  # ---------------------------------------------------------------------------
  if [[ "${SKIP_VENV:-false}" == "true" ]]; then
    warn "SKIP_VENV=true: skipping virtual environment and dependency installation"
    VENV_DIR="${INSTALL_DIR}/.venv"
    if [[ "$PLATFORM" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
      VENV_PY="${VENV_DIR}/Scripts/python.exe"
    else
      VENV_PY="${VENV_DIR}/bin/python"
    fi
    # Use system python for syntax check
    VENV_PY="$PYTHON_BIN"
  else
    VENV_DIR="${INSTALL_DIR}/.venv"
    if [[ "$PLATFORM" == "windows" || "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
      VENV_PY="${VENV_DIR}/Scripts/python.exe"
    else
      VENV_PY="${VENV_DIR}/bin/python"
    fi
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
  fi

  # ---------------------------------------------------------------------------
  # Resolve supported project layouts and run a syntax check.
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Generate a launcher. Constants are shell-escaped separately; the body is a
  # single-quoted heredoc so its variables expand at launcher runtime, not here.
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Compatibility alias: userbot -> teleweave (for existing users)
  # ---------------------------------------------------------------------------
  USERBOT_ALIAS="${BIN_DIR}/userbot"
  if [[ ! -e "$USERBOT_ALIAS" ]]; then
    ln -s "$LAUNCHER_DEST" "$USERBOT_ALIAS"
    ok "Created compatibility alias: userbot -> teleweave"
  else
    log "Compatibility alias 'userbot' already exists; leaving as-is."
  fi

  # ---------------------------------------------------------------------------
  # Completion summary and PATH check
  # ---------------------------------------------------------------------------
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
}

# -----------------------------------------------------------------------------
# Signal handlers
# -----------------------------------------------------------------------------
handle_int_term() {
  log "Interrupted (SIGINT/SIGTERM). Running cleanup..."
  # The EXIT trap will handle cleanup based on marker state
  exit 130
}
trap handle_int_term INT TERM

handle_exit() {
  local exit_code=$?
  if [[ $exit_code -ne 0 && $exit_code -ne 130 ]]; then
    # Recovery is handled at startup via determine_installation_state
    true
  fi
}
trap handle_exit EXIT

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------
main "$@"