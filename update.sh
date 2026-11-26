#!/usr/bin/env bash
#
# update.sh — Safe fast-forward-only updater for TeleWeave/Userbot.
#
# Usage:
#   bash ~/TeleWeave/update.sh
#   teleweave update
#
# This script never uses git reset --hard. It refuses tracked local changes,
# unpushed commits, and remote changes that would track protected user data.

set -Eeuo pipefail

# Resolve the installation from this script's own location. This avoids a
# hidden dependency on the caller's current directory or HOME value.
INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
VENV_PY="${INSTALL_DIR}/.venv/bin/python"

if [[ -t 1 ]]; then
  R=$'\033[0m'; B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; E=$'\033[31m'; C=$'\033[36m'
else
  R=""; B=""; G=""; Y=""; E=""; C=""
fi

log()  { printf '%b[update]%b %s\n' "$C" "$R" "$1"; }
ok()   { printf '%b[  OK  ]%b %s\n' "$G" "$R" "$1"; }
warn() { printf '%b[ WARN ]%b %s\n' "$Y" "$R" "$1" >&2; }
die()  { printf '%b[ FAIL ]%b %s\n' "$E" "$R" "$1" >&2; exit 1; }

on_error() {
  local status=$?
  printf '%b[ FAIL ]%b Update stopped at line %s (exit %s).\n' "$E" "$R" "${BASH_LINENO[0]:-?}" "$status" >&2
  exit "$status"
}
trap on_error ERR

PROTECTED_PATHS=(
  "accounts" ".env" "data"
  "Userbot/accounts" "Userbot/.env" "Userbot/data"
)
EXISTING_PROTECTED_PATHS=()

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

read_version() {
  local value="unknown"
  if [[ -f "${INSTALL_DIR}/VERSION" ]]; then
    IFS= read -r value < "${INSTALL_DIR}/VERSION" || true
  fi
  printf '%s\n' "${value:-unknown}"
}

assert_protected_paths_safe() {
  local rel tracked
  for rel in "${PROTECTED_PATHS[@]}"; do
    tracked="$(git -C "$INSTALL_DIR" ls-files -- "$rel" "${rel%/}/" 2>/dev/null || true)"
    if [[ -n "$tracked" ]]; then
      printf '%s\n' "$tracked" | sed 's/^/         /' >&2
      die "Protected user-data path '${rel}' is tracked by Git. Refusing to update."
    fi

    if path_exists "${INSTALL_DIR}/${rel}"; then
      if ! protected_path_is_ignored "$rel"; then
        die "Existing user data '${INSTALL_DIR}/${rel}' is not ignored by Git. Add a matching .gitignore rule; no update was applied."
      fi
      EXISTING_PROTECTED_PATHS+=("$rel")
    fi
  done
}

assert_remote_does_not_track_protected_paths() {
  local remote_ref="$1" rel remote_tracked
  for rel in "${PROTECTED_PATHS[@]}"; do
    remote_tracked="$(git -C "$INSTALL_DIR" ls-tree -r --name-only "$remote_ref" -- "$rel" "${rel%/}/" 2>/dev/null || true)"
    if [[ -n "$remote_tracked" ]]; then
      printf '%s\n' "$remote_tracked" | sed 's/^/         /' >&2
      die "Remote branch contains files inside protected path '${rel}'. Refusing to merge."
    fi
  done
}

verify_protected_paths_preserved() {
  local rel
  for rel in "${EXISTING_PROTECTED_PATHS[@]}"; do
    path_exists "${INSTALL_DIR}/${rel}" \
      || die "Previously existing user data disappeared: ${INSTALL_DIR}/${rel}"
    protected_path_is_ignored "$rel" \
      || die "The updated .gitignore no longer ignores '${rel}'. The data path still exists, but future updates are blocked until this is fixed."
  done
}

# -----------------------------------------------------------------------------
# 0. Preconditions
# -----------------------------------------------------------------------------
[[ -d "${INSTALL_DIR}/.git" ]] \
  || die "Installation not found at ${INSTALL_DIR}. Run install.sh first."
[[ -x "$VENV_PY" ]] \
  || die "Virtual environment not found at ${INSTALL_DIR}/.venv. Re-run install.sh."

PY_VERSION="$("$VENV_PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo unknown)"
if [[ ! "$PY_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  die "Could not determine the virtual environment Python version (${VENV_PY})."
fi
PY_MAJOR="${PY_VERSION%%.*}"
PY_MINOR="${PY_VERSION##*.}"
if [[ "$PY_MAJOR" -lt 3 || ( "$PY_MAJOR" -eq 3 && "$PY_MINOR" -lt 11 ) ]]; then
  die "The virtual environment uses Python ${PY_VERSION}; Python 3.11+ is required. Re-create .venv with a newer Python interpreter."
fi

OLD_VERSION="$(read_version)"
OLD_SHA="$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# -----------------------------------------------------------------------------
# 1. Refuse tracked local changes before fetching or merging.
# -----------------------------------------------------------------------------
log "Checking repository state..."
DIRTY_FILES="$(git -C "$INSTALL_DIR" status --porcelain --untracked-files=no 2>/dev/null || true)"
if [[ -n "$DIRTY_FILES" ]]; then
  warn "Tracked local modifications were found:"
  printf '%s\n' "$DIRTY_FILES" | sed 's/^/         /'
  die "Cannot safely update with tracked local changes. Commit or stash them, then retry."
fi
ok "No tracked local modifications found."

assert_protected_paths_safe

# -----------------------------------------------------------------------------
# 2. Fetch and validate branch ancestry. No hard reset is ever used.
# -----------------------------------------------------------------------------
log "Fetching latest code from origin..."
git -C "$INSTALL_DIR" fetch --prune origin \
  || die "git fetch failed. Check network access and the origin remote."

BRANCH="$(git -C "$INSTALL_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[[ -n "$BRANCH" ]] || die "Repository is in detached-HEAD state. Check out its deployment branch first."
REMOTE_REF="refs/remotes/origin/${BRANCH}"
git -C "$INSTALL_DIR" show-ref --verify --quiet "$REMOTE_REF" \
  || die "Remote branch origin/${BRANCH} was not found. Refusing to guess a branch."

AHEAD_COUNT="$(git -C "$INSTALL_DIR" rev-list --count "${REMOTE_REF}..HEAD")"
if [[ "$AHEAD_COUNT" != "0" ]]; then
  die "Local branch '${BRANCH}' has ${AHEAD_COUNT} commit(s) not present on origin/${BRANCH}. Push or intentionally reconcile them before updating. No local commits were discarded."
fi

assert_remote_does_not_track_protected_paths "$REMOTE_REF"

BEHIND_COUNT="$(git -C "$INSTALL_DIR" rev-list --count "HEAD..${REMOTE_REF}")"
if [[ "$BEHIND_COUNT" == "0" ]]; then
  ok "Code is already up to date."
else
  log "Applying ${BEHIND_COUNT} remote commit(s) with a fast-forward-only merge..."
  git -C "$INSTALL_DIR" merge --ff-only --no-edit "$REMOTE_REF" \
    || die "Fast-forward update failed. Git did not reset the local branch; inspect the error and retry after resolving it."
fi

NEW_SHA="$(git -C "$INSTALL_DIR" rev-parse --short HEAD)"
NEW_VERSION="$(read_version)"
verify_protected_paths_preserved

if [[ "$OLD_SHA" == "$NEW_SHA" ]]; then
  ok "No code changes were needed (${NEW_VERSION} @ ${NEW_SHA})."
else
  ok "Code updated: ${OLD_VERSION} @ ${OLD_SHA} -> ${NEW_VERSION} @ ${NEW_SHA}."
fi

# -----------------------------------------------------------------------------
# 3. Clear project bytecode only. Keep .venv and Git metadata intact.
# -----------------------------------------------------------------------------
log "Clearing stale project bytecode caches..."
CODE_ROOT="$INSTALL_DIR"
if [[ -d "${INSTALL_DIR}/Userbot" && -f "${INSTALL_DIR}/Userbot/main.py" ]]; then
  CODE_ROOT="${INSTALL_DIR}/Userbot"
elif [[ -f "${INSTALL_DIR}/main.py" ]]; then
  CODE_ROOT="$INSTALL_DIR"
else
  die "Could not find main.py in the repository root or Userbot/ directory. Re-run install.sh after checking the repository layout."
fi

find "$CODE_ROOT" \
  \( -type d \( -name .git -o -name .venv -o -name venv \) -prune \) -o \
  \( -type d -name '__pycache__' -prune -exec rm -rf {} + \) 2>/dev/null || true
find "$CODE_ROOT" \
  \( -type d \( -name .git -o -name .venv -o -name venv \) -prune \) -o \
  \( -type f -name '*.pyc' -delete \) 2>/dev/null || true
ok "Project bytecode caches cleared; the virtual environment was excluded."

# -----------------------------------------------------------------------------
# 4. Upgrade dependencies using the virtual environment's interpreter.
# -----------------------------------------------------------------------------
REQUIREMENTS_FILE="${INSTALL_DIR}/requirements.txt"
log "Upgrading pip inside the virtual environment..."
"$VENV_PY" -m pip install --disable-pip-version-check --retries 1 --timeout 15 --upgrade pip >/dev/null 2>&1 \
  || warn "pip self-upgrade failed; continuing with the existing pip version."

if [[ -f "$REQUIREMENTS_FILE" ]]; then
  log "Installing/upgrading dependencies from requirements.txt..."
  if "$VENV_PY" -m pip install --disable-pip-version-check --retries 2 --timeout 20 -r "$REQUIREMENTS_FILE"; then
    if "$VENV_PY" -m pip check; then
      ok "Dependencies are up to date and dependency metadata is consistent."
    else
      die "pip check found incompatible or missing dependencies. Repair the virtual environment before restarting the bot."
    fi
  else
    die "Dependency installation failed. Code has already been fast-forwarded, but the bot may not run until dependencies are repaired. Run: ${VENV_PY} -m pip install --disable-pip-version-check --retries 2 --timeout 20 -r ${REQUIREMENTS_FILE}"
  fi
else
  warn "No requirements.txt found; dependency upgrade was skipped."
fi

# -----------------------------------------------------------------------------
# 5. Syntax check. compileall does not execute imports or test runtime behavior.
# A failure is fatal: this script must not report a successful update.
# -----------------------------------------------------------------------------
log "Running Python syntax check (compileall)..."
if "$VENV_PY" -m compileall -q -x '(^|/)(\.git|\.venv|venv|accounts|data)(/|$)' "$CODE_ROOT"; then
  ok "Python syntax check passed. (This checks compilation, not runtime imports.)"
else
  die "Python syntax check failed. Update is incomplete; review the compileall errors above before starting the bot."
fi

# Reconfirm the paths after all update steps.
verify_protected_paths_preserved

# -----------------------------------------------------------------------------
# 6. Summary
# -----------------------------------------------------------------------------
printf '\n%b%s%b\n' "$B" '──────────────────────────────────────────' "$R"
printf '  Version: %s (%s) -> %s (%s)\n' "$OLD_VERSION" "$OLD_SHA" "$NEW_VERSION" "$NEW_SHA"
printf '%b%s%b\n\n' "$B" '──────────────────────────────────────────' "$R"
ok "Update completed. Run 'teleweave' to start the bot."