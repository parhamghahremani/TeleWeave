## One-Click Installation (Termux / Linux)

The fastest way to get running — no manual `venv` setup, no remembering
paths. Works on **Android (Termux)** and **Debian/Ubuntu-based Linux**.

```bash
curl -fsSL https://raw.githubusercontent.com/parhamghahremani/TeleWeave/main/install.sh | bash
```

This single command will:

1. Detect whether you're on Termux or a standard Linux distro.
2. Install Python (and, on Termux, the native build tools some dependencies
   need to compile) if it isn't already present.
3. Clone this repository to `~/TeleWeave`.
4. Create an isolated virtual environment and install everything in
   `requirements.txt` into it.
5. Register a global `teleweave` command so you can launch things from
   anywhere in your terminal — no `cd`-ing into the project folder required.

Once installed, just run:

```bash
teleweave
```

You'll get an interactive menu:

```
=== TeleWeave/Userbot — v3.2.13 ===
1) Run bot
2) Manage accounts
3) Connection settings
4) Update
5) Quit
Your choice [1-5]:        ← single keypress, no Enter needed
```

- **Run bot** — starts `main.py`.
- **Manage accounts** — runs `add_account.py` to add/configure a Telegram account.
- **Connection settings** — runs `settings.py`, the interactive manager for
  the system-wide connection mode (direct / SOCKS5 / Cloudflare, each of
  them one keypress — see below). See
  [Connection modes](#connection-modes) for the full picture.
- **Update** — pulls the latest code and refreshes dependencies. This is
  always safe to run: it **never touches your `accounts/`, `.env`, or
  `data/` folders** — only the codebase and installed packages.
- **Quit** — exits without doing anything.

You can also skip the menu with direct shortcuts:

```bash
teleweave run      # start the bot directly
teleweave add      # jump straight to account management
teleweave settings # connection settings (direct / SOCKS5 / CF)
teleweave update   # update directly
```

> Re-running the install command above at any time is safe — it's
> idempotent and will simply refresh your existing installation rather
> than creating a duplicate or overwriting your account data.

> **Before you run `teleweave update` on a machine you also develop on:**
> `update.sh` makes your local checkout exactly match `origin/<branch>` —
> that's the whole point, it's how you get the latest fixes. If this
> machine has commits that were never pushed, syncing to origin would
> discard them. As of `3.0.11`, `update.sh` checks for this and refuses to
> proceed (with a clear message telling you to `git push` first) instead
> of silently overwriting local work — but the simplest fix is just to
> push before you update: `git -C ~/TeleWeave push origin main`.

If you'd rather install manually (or you're on a distro other than
Termux/Debian/Ubuntu), see the [Quick Start](#quick-start) section below.

---
# Multi-Account Telegram Userbot

A professional, async, hot-reload-capable Telegram account management system
built with Python 3.11+ and [Telethon](https://docs.telethon.dev/).

**Current version:** `3.2.13`

See [CHANGELOG.md](CHANGELOG.md) for the full history.

> **About this revision.** This README was rewritten as part of an internal
> architecture refactor. The previous copy described a `1.6.0`-era version of
> the bot — MTProxy support, an admin-permission system (`is_admin`,
> `is_admin_only`), `.reload`/`.restart`/`.accounts`/`.addaccount`/
> `.removeaccount`/`.cancelflow`/`.proxy`/`.version` commands, and "smart
> polling" for reaction detection — none of which exist in the codebase this
> refactor is based on (confirmed by reading every module directly, not by
> assumption). Every section below has been checked against the actual code.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Architecture Overview](#architecture-overview)
- [Message Classification System](#message-classification-system)
- [Account Setup](#account-setup)
- [Connection modes](#connection-modes-v327)
- [Configuration](#configuration)
- [Available Commands](#available-commands)
- [Hot-Reload System](#hot-reload-system)
- [Extra Modules (modules_extra/)](#extra-modules-modules_extra)
- [Writing a New Module](#writing-a-new-module)
- [Versioning Guide](#versioning-guide)
- [FAQ](#faq)

---

## Features

| Feature | Description |
| --- | --- |
| **Multi-account** | Run any number of Telegram accounts simultaneously, all equal (no admin/owner tiering) |
| **Hot-reload** | Add, remove, or edit module files while the bot is running — no restart |
| **Connection modes** | System-wide connection setting — direct (default), SOCKS5 proxy, or Cloudflare (CF proxy) — no VPN or special tools needed; managed from the Settings menu |
| **Message classification** | Unified priority system (`file > vid > pic > link > txt > other`) across all modules |
| **Category-based help** | RTL-friendly help output with 7 logical categories, plus per-module detail via `help <module>` |
| **Reaction commands** | Execute commands by reacting to messages with emojis — push-based (zero polling), works on bots, users, groups, and channels per-type toggle |
| **Config-change detection** | Edits to `account.json` and new `accounts/N/` folders are noticed by a file watcher and written to the log — they take effect after a restart |
| **Semantic versioning** | Every change tracked in `VERSION` + `CHANGELOG.md` |
| **Python 3.11+** | Native union types, `match` statements, `slots=True` dataclasses |
| **Dependency injection** | Composition root wires config and registries into every module's constructor — no global state reached for by import |

---

## Requirements

- Python 3.11 or newer
- A Telegram API app from [my.telegram.org/apps](https://my.telegram.org/apps)

---

## Quick Start

```bash
# 1. Clone / extract the project
cd TeleWeave

# 2. Create a virtual environment
python3.11 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate

# 3. Install dependencies (requirements.txt requires Telethon >=1.45.0,<2 — see the note in that file)
pip install -r requirements.txt

# 4. Add your first account
python add_account.py

# 5. (Optional) Configure environment variables — create Userbot/.env yourself
#    with any overrides from the Configuration table below, for example:
#    LOG_LEVEL=INFO

# 6. Run
python main.py
```

Both commands run from the **repository root** — there's no need to `cd
Userbot/` first (earlier versions required this because of how imports
resolved; this version uses proper package imports throughout).

---

## Project Structure

```
TeleWeave/
├── VERSION                        ← single source of truth for version
├── CHANGELOG.md                   ← all changes since the beginning
├── README.md                      ← this file
├── requirements.txt
├── pyproject.toml                 ← ruff configuration + project metadata
├── main.py                        ← thin launcher → Userbot.app.application.main()
├── add_account.py                 ← thin launcher → Userbot.account_management.cli.main()
├── settings.py                    ← thin launcher → Userbot.settings_menu.cli.main() (v3.2.7)
├── run.bat                        ← Windows control menu (run / accounts / settings / exit)
│
└── Userbot/
    ├── __init__.py                ← exposes __version__ (reads VERSION)
    ├── .env                        ← optional, created by you (git-ignored) — see Configuration
    │
    ├── app/                        ← composition root & application lifecycle
    │   ├── composition_root.py     ← builds the object graph; owns per-account startup
    │   └── application.py          ← run-loop orchestration; Ctrl+C / SIGTERM → graceful shutdown
    │
    ├── config/                     ← config models separated from config loading
    │   ├── models.py                ← AccountConfig, Paths, Settings (pure data)
    │   ├── loader.py                ← discover_accounts(), load_settings() (I/O)
    │   └── env.py                   ← typed env-var helpers
    │
    ├── core/
    │   ├── exceptions.py            ← structured exception hierarchy
    │   ├── context.py                ← ModuleContext (constructor-injection payload)
    │   ├── registry.py               ← AccountRegistry, AccountLoaderRegistry
    │   ├── telegram_client.py        ← TelegramClient factory (system-wide connection mode)
    │   ├── connection_selector.py    ← mode → Telethon kwargs (direct / SOCKS5 / CF)
    │   ├── connection_ws.py          ← MTProto-over-WebSocket transport (CF mode)
    │   ├── loader.py                 ← per-account plugin loader + hot-reload
    │   ├── logging_setup.py          ← centralized structured logging
    │   ├── reconnector.py            ← per-account reconnect loop
    │   └── watcher.py                ← file watchers (account.json, new account folders): detect + log only
    │
    ├── helpers/
    │   └── utils.py                  ← shared utilities + classify_message()
    │
    ├── modules/
    │   ├── _infra/                   ← shared infrastructure (NOT plugins)
    │   │   ├── base.py               ← abstract Module base class
    │   │   ├── router.py             ← CommandRouter (declarative command dispatch)
    │   │   └── bridge.py             ← MockEvent (bridges reaction triggers into normal handlers)
    │   ├── base.py / router.py / bridge.py   ← compat re-exports of _infra/
    │   │
    │   ├── single/                   ← one logical module per .py file
    │   │   ├── system.py             ← owner commands: .modules .account .stats .ping
    │   │   ├── system_info.py        ← its help texts + metadata (data only)
    │   │   ├── module_manager.py     ← .extra enable/disable/info for modules_extra/
    │   │   ├── module_manager_info.py
    │   │   ├── help_handler.py      ← `help` + `help <module>` commands
    │   │   └── help_handler_info.py
    │   │
    │   └── packages/                 ← one logical module per folder
    │       ├── join_left/            ← join/leave chats + folder management
    │       │   ├── __init__.py       ← create_module() + the module's public API
    │       │   ├── info.py           ← help texts + metadata (data only)
    │       │   ├── const.py          ← tunable numbers
    │       │   ├── types.py          ← result records
    │       │   ├── entities.py       ← pulling chat IDs out of text
    │       │   ├── folders.py        ← joined* folders + exclude_archived
    │       │   ├── post_join.py      ← mute + archive after a join
    │       │   ├── leave.py          ← leave everything + reset the folders
    │       │   └── handlers.py       ← the JoinLeft class — dispatch + flows
    │       ├── clearer/              ← manual message clearing
    │       │   ├── __init__.py       ← create_module() + the module's public API
    │       │   ├── info.py           ← help texts + metadata (data only)
    │       │   ├── filters.py        ← the type filters + valid arguments
    │       │   └── handlers.py       ← the Clearer class — dispatch + scan/delete
    │       ├── auto_clearer/         ← automatic message clearing
    │       │   ├── __init__.py
    │       │   ├── info.py
    │       │   ├── filters.py        ← the type filters, scope rules, defaults
    │       │   └── handlers.py       ← the AutoClearer class — filter + commands
    │       ├── auto_forwarder/       ← auto-forward bot messages
    │       │   ├── __init__.py
    │       │   ├── info.py
    │       │   ├── content.py       ← content classification + defaults
    │       │   └── handlers.py      ← the AutoForwarder class — flow + commands
    │       ├── info_handler/         ← message info (reply)
    │       │   ├── __init__.py
    │       │   ├── info.py
    │       │   ├── labels.py        ← the display labels for message/entity types
    │       │   └── handlers.py      ← the InfoHandler class — dispatch + report
    │       ├── whois_handler/        ← user/chat info
    │       │   ├── __init__.py
    │       │   ├── info.py
    │       │   ├── const.py         ← the caption/message limits + cache TTL
    │       │   └── handlers.py      ← the WhoisHandler class — dispatch + cache
    │       └── reaction_commands/   ← execute commands via emoji reactions
    │           ├── __init__.py
    │           ├── info.py
    │           ├── const.py         ← the tunables (caps, cooldown, heartbeat)
    │           ├── scope.py         ← the persisted chat-scope set
    │           └── handlers.py      ← the ReactionCommands class — funnel + commands
    │
    ├── modules_extra/                 ← optional plugins, per-account enable/disable
    │   ├── single/                   ← one logical module per .py file
    │   │   └── (your_plugin.py + your_plugin_info.py)
    │   ├── packages/                 ← one logical module per folder
    │   │   └── bot_link_starter/     ← start the bot links in a Quote & Reply
    │   │       ├── __init__.py
    │   │   ├── info.py
    │       │   ├── links.py
    │   │   └── handlers.py
    │   └── __init__.py
    │
    ├── account_management/
    │   └── cli.py                    ← interactive `python add_account.py` menu
    │
    ├── settings_menu/
    │   └── cli.py                    ← interactive `python settings.py` menu (connection mode)
    │
    ├── accounts/
    │   ├── 1/
    │   │   ├── account.json          ← credentials (api_id, api_hash, phone)
    │   │   └── session.session       ← Telethon session (auto-created)
    │   └── 2/ …
    │
    └── data/
        ├── logs/                     ← rotating log files
        ├── connection.json           ← system-wide connection mode (v3.2.7)
        └── settings/                 ← per-account runtime settings
            ├── account1/
            │   ├── join_left.json
            │   ├── reactions.json
            │   ├── autoclear.json
            │   ├── autoforward.json
            │   └── enabled_modules.json  ← which modules_extra/ files are on (v3.1.0)
            └── account2/ …
```

> The v3.2.7 connection layer also ships a Cloudflare Worker script outside
> the package, at [`cloudflare/tg-relay-worker.js`](cloudflare/tg-relay-worker.js)
> in the repo root — see [Connection modes](#connection-modes-v327).

---

## Architecture Overview

### Composition root

`Userbot/app/composition_root.py` is the only place that constructs the
application-scoped singletons: `AccountLoaderRegistry` and `AccountRegistry`.
Everything else — every plugin module, the loader, the reconnector —
receives what it needs through its constructor. Nothing reaches for a
global import to get at shared state.

*(v3.0.11: this used to also build an `EventBus` and `PluginMetadataStore`
here. Both were removed after a full-repo audit found neither had a real
consumer — see [FAQ](#faq).)*

### Plugin lifecycle

```
AccountLoader.load_all(client)
    └─ for each module found in the module roots
        │   (single/<name>.py  OR  packages/<name>/__init__.py)
        ├─ importlib.util.spec_from_file_location()
        ├─ create_module(context)      ← factory call, context = this account's ModuleContext
        └─ instance.setup(client)      ← handler registration
```

A module is a *logical unit* with a name. It can be written in one file
(`modules/single/<name>.py`) or as a package
(`modules/packages/<name>/`) — the loader treats both identically. The
shared infrastructure in `modules/_infra/` is skipped by discovery (the
leading underscore is the existing convention for "not a plugin"), and the
old import paths `Userbot.modules.base` / `.router` / `.bridge` still
work through thin re-export shims.

Every module also has an **info file** holding its help texts and
metadata — `single/<name>_info.py`, or `packages/<name>/info.py`. It is
pure data with no imports, so the help text can be read and edited
without touching any logic.

`ModuleContext` bundles everything a plugin might need: its own
`AccountConfig`, the shared `AccountLoaderRegistry`, `AccountRegistry`, and
global `Settings`. Every module receives the same shape, whether or not it
uses every field — see [Writing a New Module](#writing-a-new-module).

### Hot-reload (watchdog triggers)

```
AccountLoader.reload_module(stem)
    ├─ instance.teardown(client)   ← remove handlers
    └─ [re-import + re-setup]
```

Changing **any** file that belongs to a module reloads that whole module —
for a package, that includes a file inside the package folder, and the
package's own `info.py`. The whole module (and its submodules) is purged
from `sys.modules` first, so a reload always runs the new code.

Note that a reload re-creates the module instance, so any state it holds
(settings cache, pending actions) starts fresh — the same behaviour the
single-file modules have always had.

### Connection resilience

Each account runs an independent `AccountReconnector` loop:

```
AccountReconnector._reconnect_cycle()   (every ~30s when healthy — v3.1.1: interruptible)
    ├─ lightweight API call to verify the connection
    ├─ v3.1.1: a background watcher awaits Telethon's own `client.disconnected`
    │  Future and interrupts the healthy-interval wait immediately on a drop —
    │  no waiting for the next scheduled check
    └─ on failure → _recover_connection()
           ├─ detect_network_state()   → ONLINE / NO_INTERNET / TELEGRAM_DOWN / UNKNOWN
           ├─ NO_INTERNET / TELEGRAM_DOWN → exponential backoff — v3.1.1: interruptible,
           │  a cheap TCP probe (never a Telegram API call) wakes the wait early the
           │  moment connectivity returns, instead of sleeping out the full backoff
           └─ ONLINE → rebuild client (tenacity-retried) → loader.reattach(new_client)
                  ├─ logs the connection-state transition
                  ├─ v3.1.1: restarts the disconnect watcher on the new client
                  └─ v3.1.10: session no longer authorized (revoked / logged out /
                     deactivated) → one ERROR line, then re-check only every
                     10 → 20 → 30 min instead of retrying every few seconds
```

v3.1.1's fast-reconnect behavior is on by default and configurable via
environment variables — see the FAQ entry below for the full list and how
to disable it.

If a session is **revoked or logged out** (terminated from another device,
account deactivated), reconnecting cannot fix it. Since 3.1.10 the bot logs one
clear ERROR line for that account and re-checks only every 10 → 20 → 30
minutes, instead of retrying every few seconds. Re-login with
`python add_account.py`; restart the bot to bring the account back at once,
otherwise it is picked up at the next check.

### Connection modes (v3.2.7)

The bot's connection to Telegram is a **system-wide** setting — one mode for
the whole process: every account of the running bot *and* the login/verify
clients of `add_account.py` alike. It is never per-account. Three modes are
available, managed by the Settings menu (`settings.py`; on Windows run.bat
option **[3]**, on Termux/Linux `teleweave settings` or menu option **3**).
Every option in the menu is a **single keypress** that saves immediately —
no Enter, no confirmation screens:

```
1  Show current settings
2  Direct connection
3  SOCKS5 proxy                       (prompts for host/port/etc.)
4  Cloudflare — without Worker        (official endpoints)
5  Cloudflare — with Worker           (prompts for the Worker's hostname)
6  Test connection
7  Exit
```

1. **Direct** *(the default)* — pre-3.2.7 behavior exactly: a plain MTProto
   TCP connection to Telegram's DC IPs. No proxy layer to configure or fail.
2. **SOCKS5** — Telethon's native proxy tuple through your own SOCKS5 server.
3. **CF proxy (Cloudflare)** — MTProto over WebSocket through Cloudflare:
   no VPN needed. Options **4** and **5** are its two sub-routes as explicit
   choices: **4** connects to Telegram's own official web endpoints
   (`*.web.telegram.org`), which are served over Cloudflare and therefore
   behave like any normal HTTPS site on filtered networks — zero
   configuration. **5** points it at your **personal relay Worker** instead
   (see below). Switching between them is one keypress in either direction,
   and entering an empty hostname in option 5 cancels without changing
   anything.

Everything lives in one file, `data/connection.json`, and applies to all of
the above consumers. If that file is missing or invalid, the bot silently
falls back to **direct** — so a fresh install or a corrupted settings file
can never break startup. The active mode is printed on every startup as a
`Connection mode: ...` log line.

> The setting takes effect the **next time the bot (or add_account.py)
> starts** — the running process is never reconfigured mid-flight.

#### Deploying the personal relay Worker (optional, CF mode)

Only needed if your network also blocks `*.web.telegram.org`. The Worker is
a tiny Cloudflare function that relays WebSocket traffic to Telegram's MTProto
endpoint — the same technique Telegram's own web client uses.

1. On [dash.cloudflare.com](https://dash.cloudflare.com), open
   **Workers & Pages → Create application → Worker**, name it (e.g.
   `userbot-relay`), and deploy any placeholder to get past the wizard.
2. Open the created Worker → **Edit code**, paste the entire contents of
   [`cloudflare/tg-relay-worker.js`](cloudflare/tg-relay-worker.js) from this
   repository, and **Deploy**.
3. Copy the Worker's URL (`https://userbot-relay.<your-subdomain>.workers.dev`).
4. In the Settings menu, pick **Cloudflare — with Worker** (in run.bat:
   Connection settings → Change connection mode; in the interactive
   `settings.py` menu: option 5) and enter the hostname
   (`userbot-relay.<your-subdomain>.workers.dev`).

Prefer the command line? The same steps work without the menu:

```bash
python settings.py set-cf-worker userbot-relay.your-subdomain.workers.dev
python settings.py test        # verify the route answers the WS handshake
```

(On Termux/Linux: `teleweave settings set-cf-worker …` — the launcher passes
the subcommand through.)

No API keys, no secret tokens — the Worker relays WebSocket bytes only, and
Cloudflare's free tier is far more than the bot needs.

### Registries

| Component | Module | Purpose |
| --- | --- | --- |
| `AccountRegistry` | `core.registry` | Mutable, live collection of every configured `AccountConfig` |
| `AccountLoaderRegistry` | `core.registry` | `int` → `AccountLoader`, shared across every account (used by `.stats` for cross-account totals) |

Both are built once by the composition root and injected — never imported
as globals.

---

## Message Classification System

Every message processed by the bot is classified into **exactly ONE type**
based on strict priority. This ensures consistent behavior across all modules
(`clearer`, `auto_clearer`, `info_handler`, etc.).

### Priority Order (highest → lowest)

| Priority | Type | Description |
| --- | --- | --- |
| 🥇 1 | `file` | Document with filename, no video/audio/sticker attributes |
| 🥈 2 | `vid` | Document with `DocumentAttributeVideo` |
| 🥉 3 | `pic` | Photo (`MessageMediaPhoto`) or photo-like document |
| 4 | `link` | WebPage preview, URL entity, or inline-keyboard URL button |
| 5 | `txt` | Plain text message (no media, no links) |
| 6 | `other` | Sticker, voice, contact, location, poll, etc. |

### Example Classification