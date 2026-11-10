# Changelog

All notable changes to this project are documented here.
Format follows [Semantic Versioning](https://semver.org): **MAJOR.MINOR.PATCH**

---

## [3.2.10] — 2026-11-09

**Source:** AI + project owner — Cloudflare Worker optimization, Windows/Termux menu fixes, CF keepalive log level reduction, live CF mode verification.

### Added

- **Cloudflare Worker v3.2.10 optimizations** (`cloudflare/tg-relay-worker.js`):
  - `MAX_MESSAGE_SIZE = 32 * 1024 * 1024` (32 MiB) ceiling for upstream payloads, matching Telegram's practical MTProto frame limit.
  - **Fixed-IP identification headers** — `CF-Connecting-IP` and `X-Forwarded-For` forwarded upstream so the Worker origin is recognizable in Telegram logs.
  - **Binary frames enforced** — `tg.binaryType = "arraybuffer"` on both upstream and server sockets; prevents text-frame corruption of MTProto blobs.
  - **Message size validation** on both `server.onmessage` and `upstream.onmessage` — oversized frames dropped with a single `DEBUG` log line.

- **Worker URL normalization** (`core/connection_selector.py`):
  - New `_WORKER_DOMAIN_RE` regex and `_normalize_worker_domain()` strip `http://`, `https://`, and any trailing `/` so the CF Worker hostname saved by the Settings menu is always a clean domain (e.g. `tg-relay-worker.parhamghahremani1401.workers.dev`).
  - CF branch in `build_kwargs()` normalizes before passing to `make_ws_connection_class()`.

### Fixed

- **`run.bat` Windows menu** — "Manage accounts" now launches `python -m userbot_own.account_management.cli` (module path) and returns to the **main menu** with `goto :menu` (was `goto :after_run` which skipped the menu loop). Matches Termux launcher behavior.
- **`install.sh` Termux/Linux launcher** (`scripts/install.sh` → generated `~/.local/bin/userbot`):
  - Main menu is now a `while true` loop; invalid input continues the loop instead of exiting the script.
  - "Manage accounts" submenu returns to the main menu after exit (was killing the entire launcher task).
  - Single-keypress input everywhere, matching `run.bat` and the reference implementation in `settings_menu/cli.py`.

- **CF connection logs moved from INFO to DEBUG** (`core/connection_ws.py`):
  - Keepalive send log: `Sent WebSocket ping frame` → `DEBUG`
  - Keepalive receive log: `Received WebSocket pong frame` → `DEBUG`
  - Keepalive interval log: `Next keepalive in Xs` → `DEBUG`
  - Result: no periodic INFO spam while connected via Cloudflare Worker; only `DEBUG` heartbeats (visible in log files at `DEBUG` level, absent from console at default `INFO`).

### Verified

- **Live CF mode test (account 2 only)** — bot ran 10+ minutes on `wss://tg-relay-worker.parhamghahremani1401.workers.dev` with single account 2:
  - Stable connection, zero `AuthKeyDuplicatedError` (previous race with dual-account CF run resolved).
  - Keepalive logs only at `DEBUG` level in `account2.log`.
  - Reconnection logic idle, no unexpected disconnects.
  - All 10 core modules loaded, `ReactionCommands` marked ready and processing.

### Files changed

- `cloudflare/tg-relay-worker.js` — Worker optimizations (MAX_MESSAGE_SIZE, CF headers, binaryType, size validation)
- `userbot_own/core/connection_selector.py` — Worker URL normalization
- `userbot_own/core/connection_ws.py` — DEBUG-level keepalive logs
- `run.bat` — Module-path account CLI + correct menu return
- `scripts/install.sh` (source for generated launcher) — loop + submenu return fixes
- `VERSION` → `3.2.10`
- `README.md` → Current version line

---

## [3.2.9] — 2026-11-04

**Source:** project owner — reliability hardening across join, connection, and logging.

### Fixed

- **B-CONN-01** — WebSocket transport: `WsStream.close()` now drains the write buffer and cancels the read task before closing the underlying TCP socket. Prevents "SSL EOF received in state CLOSED" noise on fast reconnects.

- **B-CONN-02** — Connection selector: `build_connection_kwargs()` now validates `cf_worker_domain` (must be non-empty when CF mode selected) and raises a clear `UserbotError` instead of passing an empty string to Telethon.

- **B-RECON-01** — Reconnector: `reconnect_once()` handles `AuthKeyError`/`AuthKeyDuplicatedError` by resetting the session file and forcing a fresh login — no more silent hang on corrupted session.

- **B-LOG-01** — Logging setup: expanded Telethon noise filter (`_NOISE_SUBSTRINGS`) with three new patterns that were flooding console on reconnect storms.

### Added

- **I-RECON-01** — `Reconnector` now exposes `is_healthy()` returning a `bool` — allows `ModuleManager` and health checks to query state without inspecting private attributes.

- **I-CONN-01** — `ConnectionSettings.to_dict()` added — serializes the whole settings object (mode, socks5, cf) for future CLI/remote config APIs.

### Changed

- **C-RECON-01** — Reconnect backoff strategy: initial delay reduced from 3s → 1s, max attempts increased from 5 → 8. Faster recovery on transient network flaps.

- **C-SETTINGS-01** — Settings menu: CF worker domain prompt now validates hostname format (must contain a dot, no scheme, no path).

### Files changed

- `userbot_own/core/connection_ws.py` — B-CONN-01
- `userbot_own/core/connection_selector.py` — B-CONN-02, I-CONN-01
- `userbot_own/core/reconnector.py` — B-RECON-01, C-RECON-01, I-RECON-01
- `userbot_own/core/logging_setup.py` — B-LOG-01
- `userbot_own/settings_menu/cli.py` — C-SETTINGS-01