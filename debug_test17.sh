#!/usr/bin/env bash
TEST_HOME=$(mktemp -d -t test17_debug_XXXXXX)
INSTALL_SH="${TEST_HOME}/install.sh"
cp install.sh "${INSTALL_SH}"
HOME="${TEST_HOME}"

# Create legacy layout
mkdir -p "${TEST_HOME}/userbot_own/userbot_own/accounts/1"
mkdir -p "${TEST_HOME}/userbot_own/userbot_own/data/settings"
mkdir -p "${TEST_HOME}/userbot_own/userbot_own/data/logs"
echo "api_id=12345" > "${TEST_HOME}/userbot_own/userbot_own/accounts/1/account.json"
echo "api_hash=abcdef" >> "${TEST_HOME}/userbot_own/userbot_own/accounts/1/account.json"
echo "phone=+1234567890" >> "${TEST_HOME}/userbot_own/userbot_own/accounts/1/account.json"
touch "${TEST_HOME}/userbot_own/userbot_own/accounts/1/session.session"
touch "${TEST_HOME}/userbot_own/userbot_own/accounts/1/session.session-journal"
echo "connection=direct" > "${TEST_HOME}/userbot_own/userbot_own/data/connection.json"
echo "LOG_LEVEL=DEBUG" > "${TEST_HOME}/userbot_own/userbot_own/.env"

mkdir -p "${TEST_HOME}/.teleweave_migration_staging_12345/TeleWeave/Userbot"
mv "${TEST_HOME}/userbot_own" "${TEST_HOME}/TeleWeave.legacy_backup_xxx"
echo -e "stage=backup_legacy\npid=12345\ntimestamp=2024-01-01T00:00:00+00:00\nlegacy_path=${TEST_HOME}/userbot_own\nbackup_path=${TEST_HOME}/TeleWeave.legacy_backup_xxx\nnew_path=${TEST_HOME}/TeleWeave\nstaging_path=${TEST_HOME}/.teleweave_migration_staging_12345" > "${TEST_HOME}/.teleweave_migration_staging_12345/.migration_state"

HOME="${TEST_HOME}" bash "${INSTALL_SH}" 2>&1
echo "Exit code: $?"
ls -la "${TEST_HOME}/"