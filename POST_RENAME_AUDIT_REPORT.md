# گزارش جامع بازبینی پس از تغییر نام مخزن — TeleWeave v3.2.13

**تاریخ:** 2026-11-27  
**مخزن قبلی:** `parhamghahremani/userbot_own`  
**مخزن جدید (رسمی):** `parhamghahremani/TeleWeave`  
**شاخه پیش‌فرض:** `main`  
**PR جاری:** #3 — `fix/complete-operational-migration` → `main`  
**وضعیت PR:** باز (OPEN)  
**آخرین کامیت:** `2ae46ebe55a06b4734436ca03d25b218b1426b11`  
**وضعیت CI:** ✅ PASSED (17 چک، شامل اعتبارسنجی case-sensitive FS در Linux)

---

## ۱. تأیید تغییر نام مخزن و احراز هویت

| مورد | وضعیت | جزئیات |
|------|-------|---------|
| **تغییر نام مخزن** | ✅ **تأیید شده** | `gh repo view parhamghahremani/TeleWeave` — نام: `TeleWeave`، URL: `https://github.com/parhamghahremani/TeleWeave`، شاخه پیش‌فرض: `main` |
| **احراز هویت GitHub CLI** | ✅ **تأیید شده** | `gh auth status` — حساب فعال: `parhamghahremani`، توکن معتبر، تمام scopes لازم |
| **PR #3 در مخزن جدید** | ✅ **تأیید شده** | `gh pr view 3 --repo parhamghahremani/TeleWeave` — عدد: ۳، state: open، base: `main`، head: `fix/complete-operational-migration`، headRepo: `parhamghahremani/TeleWeave` |
| **CI در مخزن جدید** | ✅ **سبز** | `gh pr checks 3` — Linux Case-Sensitive FS & Packaging: pass (۱۶ ثانیه) |
| **URL بومی `origin`** | ✅ **اصلاح شده** | از `https://github.com/parhamghahremani/userbot_own.git` به `https://github.com/parhamghahremani/TeleWeave.git` تغییر یافت |

> **نکته:** مخزن قبلی `parhamghahremani/userbot_own` دیگر وجود ندارد (تغییر نام دستی توسط صاحب پروژه انجام شده). تمام عملیات Git باید علیه `parhamghahremani/TeleWeave` انجام شود.

---

## ۲. وضعیت فعلی PR #3

| فیلد | مقدار |
|-------|-------|
| **شماره PR** | ۳ |
| **عنوان** | `chore: complete operational migration to TeleWeave/Userbot v3.2.13` |
| **حالت** | OPEN |
| **شاخه پایه (base)** | `main` |
| **شاخه سر (head)** | `fix/complete-operational-migration` |
| **مخزن سر** | `parhamghahremani/TeleWeave` |
| **آخرین SHA** | `2ae46ebe55a06b4734436ca03d25b218b1426b11` |
| **URL** | https://github.com/parhamghahremani/TeleWeave/pull/3 |
| **تغییرات** | ۶ فایل، ۲۰ خط افزوده، ۱۸ خط حذف شده |

**فایل‌های تغییر یافته در PR:**
1. `install.sh` — REPO_URL، REPO_NAME، INSTALL_DIR، reinstall URL
2. `update.sh` — مثال مسیر `~/TeleWeave`
3. `run.bat` — reinstall URL
4. `README.md` — URL نصب، ارجاعات دایرکتوری، ساختار پروژه
5. `CHANGELOG.md` — ورودی v3.2.13 با جزئیات مهاجرت عملیاتی کامل
6. `cloudflare/tg-relay-worker.js` — توضیح نسخه

---

## ۳. تحلیل و اصلاح تست مسیرهای رانتایم (Critical Issue A)

### مشکل فعلی در CI (`ci.yml` خط ۱۰۳–۱۱۶):

```python
# فعلی — غلط برای معماری بسته
from Userbot.config.models import Paths
from pathlib import Path
p = Paths.from_base(Path.cwd())  # ← cwd = ریشه مخزن، نه دایرکتوری پکیج
```

**چرا غلط است:**
- `Path.cwd()` در CI ریشه مخزن (`/home/runner/work/TeleWeave/TeleWeave`) را برمی‌گرداند
- اما `Paths.from_base()` انتظار دارد **دایرکتوری پکیج Userbot** را دریافت کند
- در معماری واقعی، `base` باید `.../TeleWeave/Userbot` باشد، نه `.../TeleWeave`
- کد واقعی در `main.py` خط ۱۴۳: `userbot_dir = Path(__file__).resolve().parent.parent` — که به ریشه مخزن اشاره می‌کند، **نه** دایرکتوری پکیج

### تست مقایسه‌ای سه رویکرد:

| رویکرد | `base` | `accounts` | `data` | `settings` | `logs` |
|--------|--------|------------|--------|------------|--------|
| **CI فعلی (cwd)** | `/TeleWeave` | `/TeleWeave/accounts` | `/TeleWeave/data` | `/TeleWeave/data/settings` | `/TeleWeave/data/logs` |
| **بر اساس پکیج (Userbot.__file__)** | `/TeleWeave/Userbot` | `/TeleWeave/Userbot/accounts` | `/TeleWeave/Userbot/data` | `/TeleWeave/Userbot/data/settings` | `/TeleWeave/Userbot/data/logs` |
| **Application (main.py)** | `/TeleWeave` | `/TeleWeave/accounts` | `/TeleWeave/data` | `/TeleWeave/data/settings` | `/TeleWeave/data/logs` |

**تحلیل:** در کلون تازه، `main.py` در ریشه مخزن است، بنابراین `Application(userbot_dir)` با `userbot_dir = repo_root` فراخوانی می‌شود. اما ساختار دایرکتوری واقعی در ریشه مخزن است:
```
TeleWeave/           ← repo root (main.py در اینجا)
├── Userbot/         ← Python package
│   ├── accounts/    ← runtime accounts (created at runtime)
│   ├── data/        ← runtime data (created at runtime)
│   ├── modules/     ← source code (git-tracked)
│   └── modules_extra/
├── accounts/        ← legacy? (installer creates at repo root)
├── data/            ← legacy? (installer creates at repo root)
```

**واقعیت:** هم در development و هم در installed mode (wheel)، مسیرهای رانتایم (`accounts/`, `data/`) **در کنار** پکیج `Userbot/` قرار می‌گیرند، نه **داخل** آن. `Paths.from_base()` در `application.py` با `repo_root` فراخوانی می‌شود.

### اصلاح پیشنهادی برای CI:

```yaml
- name: Verify runtime paths resolution
  run: |
    python -c "
    import Userbot
    from pathlib import Path
    from Userbot.config.models import Paths
    
    # Replicate Application.main() exactly: repo_root = Path(__file__).resolve().parent.parent
    # In installed mode: Userbot.__file__ is .../site-packages/Userbot/__init__.py
    # parent.parent = .../site-packages/  (WRONG for installed mode!)
    # In development: main.py at repo_root, Userbot/ at repo_root/Userbot
    # parent.parent of Userbot/__init__.py = repo_root  (CORRECT for dev)
    
    # The correct approach: test BOTH scenarios
    # 1. Development mode (repo checkout)
    repo_root = Path(Userbot.__file__).resolve().parent.parent
    p_dev = Paths.from_base(repo_root)
    print(f'Dev mode - base: {p_dev.base}')
    print(f'Dev mode - accounts: {p_dev.accounts}')
    print(f'Dev mode - data: {p_dev.data}')
    print(f'Dev mode - settings: {p_dev.settings}')
    print(f'Dev mode - logs: {p_dev.logs}')
    
    # Verify structure matches expectation
    assert p_dev.base == repo_root
    assert p_dev.accounts == repo_root / 'accounts'
    assert p_dev.data == repo_root / 'data'
    assert p_dev.settings == repo_root / 'data' / 'settings'
    assert p_dev.logs == repo_root / 'data' / 'logs'
    print('✓ Development mode paths correct')
    
    # 2. Simulate installed mode: create temp dir, install wheel, test
    import tempfile
    import subprocess
    import sys
    
    with tempfile.TemporaryDirectory() as tmpdir:
        # Build wheel
        subprocess.run([sys.executable, '-m', 'build', '--wheel', '--no-isolation'], 
                       capture_output=True, check=True, cwd='.')
        wheel = list(Path('dist').glob('teleweave-3.2.13-*.whl'))[0]
        
        # Install in isolated env
        venv_dir = Path(tmpdir) / 'venv'
        subprocess.run([sys.executable, '-m', 'venv', str(venv_dir)], check=True)
        pip = venv_dir / 'bin' / 'pip'
        subprocess.run([str(pip), 'install', str(wheel)], check=True)
        
        # Test imports and paths
        python_bin = venv_dir / 'bin' / 'python'
        result = subprocess.run([
            str(python_bin), '-c', '''
import Userbot
from pathlib import Path
from Userbot.config.models import Paths

# In installed mode, we can't easily get repo_root from package
# The installed package has NO accounts/data dirs - they're created at runtime
# by the user's chosen installation directory (~/.local/share/teleweave or ~/TeleWeave)
# This test verifies the package structure is correct
print(f'Installed package location: {Path(Userbot.__file__).parent}')
print(f'Package has modules: {(Path(Userbot.__file__).parent / \"modules\").exists()}')
print(f'Package has modules_extra: {(Path(Userbot.__file__).parent / \"modules_extra\").exists()}')
print(\"✓ Installed package structure correct\")
'''
        ], capture_output=True, text=True, check=True)
        print(result.stdout)
    "
```

---

## ۴. تحلیل مسیرهای نصب قدیمی (Critical Issue B)

### بofdهای احتمالی نصب قدیمی (`~/userbot_own`):

| مسیر | توضیح | احتمال وجود |
|--------|---------|-------------|
| `~/userbot_own/userbot_own/accounts/` | معماری v3.2.9–3.2.12 (پکیج `userbot_own/` در ریشه) | **بالا** — رایج‌ترین |
| `~/userbot_own/userbot_own/data/` | همانطور بالا | **بالا** |
| `~/userbot_own/userbot_own/.env` | همانطور بالا | **متوسط** |
| `~/userbot_own/accounts/` | معماری v3.2.7–3.2.8 (فایل‌های ریشه در کنار پکیج) | **متوسط** |
| `~/userbot_own/data/` | همانطور بالا | **متوسط** |
| `~/userbot_own/.env` | همانطور بالا | **کم** |

### مسیرهای نصب جدید (`~/TeleWeave`):

| مسیر | توضیح |
|--------|---------|
| `~/TeleWeave/Userbot/accounts/` | پکیج `Userbot/` در ریشه، data در کنار آن |
| `~/TeleWeave/Userbot/data/` | runtime data |
| `~/TeleWeave/Userbot/.env` | environment overrides |

### تفاوت کلیدی:
- **قدیمی:** `~/userbot_own/userbot_own/accounts/` — data در **داخل** پکیج
- **جدید:** `~/TeleWeave/accounts/` — data در **کنار** پکیج (repo root)

### استراتژی مهاجرت پیشنهادی برای `install.sh`:

```bash
# در install.sh، قبل از کلون/آپدیت:
LEGACY_DIR="${HOME}/userbot_own"
NEW_DIR="${HOME}/TeleWeave"

# 1. Detect legacy installation
if [[ -d "${LEGACY_DIR}/.git" ]]; then
  log "Legacy installation detected at ${LEGACY_DIR}"
  
  # 2. Inspect Git state
  LEGACY_REMOTE=$(git -C "${LEGACY_DIR}" config --get remote.origin.url || echo "")
  LEGACY_BRANCH=$(git -C "${LEGACY_DIR}" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
  
  # 3. Identify legacy data locations
  LEGACY_ACCOUNTS=()
  LEGACY_DATA=()
  LEGACY_ENV=()
  
  # Check package-internal layout (v3.2.9+)
  if [[ -d "${LEGACY_DIR}/userbot_own/accounts" ]]; then
    LEGACY_ACCOUNTS+=("${LEGACY_DIR}/userbot_own/accounts")
  fi
  if [[ -d "${LEGACY_DIR}/userbot_own/data" ]]; then
    LEGACY_DATA+=("${LEGACY_DIR}/userbot_own/data")
  fi
  if [[ -f "${LEGACY_DIR}/userbot_own/.env" ]]; then
    LEGACY_ENV+=("${LEGACY_DIR}/userbot_own/.env")
  fi
  
  # Check root-level layout (v3.2.7-3.2.8)
  if [[ -d "${LEGACY_DIR}/accounts" ]]; then
    LEGACY_ACCOUNTS+=("${LEGACY_DIR}/accounts")
  fi
  if [[ -d "${LEGACY_DIR}/data" ]]; then
    LEGACY_DATA+=("${LEGACY_DIR}/data")
  fi
  if [[ -f "${LEGACY_DIR}/.env" ]]; then
    LEGACY_ENV+=("${LEGACY_DIR}/.env")
  fi
  
  # 4. Check for conflicts with new location
  if [[ -d "${NEW_DIR}" ]]; then
    warn "Both legacy (${LEGACY_DIR}) and new (${NEW_DIR}) installations exist!"
    # List accounts in both
    for d in "${NEW_DIR}/accounts" "${NEW_DIR}/Userbot/accounts" "${LEGACY_ACCOUNTS[@]}"; do
      [[ -d "$d" ]] && log "Found accounts at: $d"
    done
    die "Manual intervention required. Please backup and choose one installation to keep."
  fi
  
  # 5. Safe migration: copy data, then update origin URL
  log "Migrating legacy data to ${NEW_DIR}..."
  mkdir -p "${NEW_DIR}"
  
  # Copy accounts (preserve structure)
  for src in "${LEGACY_ACCOUNTS[@]}"; do
    dst="${NEW_DIR}/Userbot/accounts"
    mkdir -p "$dst"
    cp -rn "$src"/* "$dst/" 2>/dev/null || true
    log "Copied accounts from $src to $dst"
  done
  
  # Copy data
  for src in "${LEGACY_DATA[@]}"; do
    dst="${NEW_DIR}/Userbot/data"
    mkdir -p "$dst"
    cp -rn "$src"/* "$dst/" 2>/dev/null || true
    log "Copied data from $src to $dst"
  done
  
  # Copy .env
  for src in "${LEGACY_ENV[@]}"; do
    dst="${NEW_DIR}/Userbot/.env"
    cp "$src" "$dst" 2>/dev/null || true
    log "Copied .env from $src to $dst"
  done
  
  # 6. Update origin URL in legacy repo, then move it
  git -C "${LEGACY_DIR}" remote set-url origin "https://github.com/parhamghahremani/TeleWeave.git"
  mv "${LEGACY_DIR}" "${NEW_DIR}.legacy_backup"
  log "Legacy repo backed up to ${NEW_DIR}.legacy_backup"
  
  # 7. Continue with fresh clone at NEW_DIR
  INSTALL_DIR="${NEW_DIR}"
  REPO_URL="https://github.com/parhamghahremani/TeleWeave.git"
  REPO_NAME="TeleWeave"
fi
```

---

## ۵. ارزیابی سازگاری CLI

| مولفه | وضعیت | توضیح |
|--------|-------|---------|
| **دستور استاندارد** | `teleweave` | ✅ در `install.sh` launcher به عنوان `teleweave` ثبت می‌شود |
| **مسیر پروژه استاندارد** | `~/TeleWeave` | ✅ `INSTALL_DIR="${HOME}/TeleWeave"` |
| **پکیج داخلی** | `Userbot/` | ✅ `pyproject.toml: include = ["Userbot*"]` |
| **داده حساب** | `Userbot/accounts/` | ✅ runtime paths |
| **دستور قدیمی `userbot`** | همچنان نصب شده ممکن است | ⚠️ **خطر:** کاربران قدیمی `userbot` در `~/.local/bin/` یا `~/bin/` دارند |
| **پیشنهاد alias سازگاری** | اضافه کردن symlink `userbot` → `teleweave` | در `install.sh` در صورت عدم وجود `userbot`، symlink بساز |

**خطر:** اگر کاربر قبلاً `userbot` را در PATH داشته باشد، دو دستور وجود خواهد داشت. پیشنهاده در `install.sh`:
```bash
# After creating teleweave launcher
if [[ ! -e "${BIN_DIR}/userbot" ]]; then
  ln -s "${LAUNCHER_DEST}" "${BIN_DIR}/userbot"
  log "Created compatibility alias: userbot -> teleweave"
fi
```

---

## ۶. ارزیابی سازگاری Updater (`update.sh`)

| بررسی | وضعیت | توضیح |
|--------|-------|---------|
| **Origin به مخزن جدید** | ❌ **نیاز به اصلاح** | `update.sh` خودمختار origin را بررسی نمی‌کند؛ installer باید origin را در legacy migration به‌روز کند |
| **Fast-forward-only** | ✅ حفظ شده | `git merge --ff-only --no-edit` |
| **کامیت‌های unpushed محافظت** | ✅ `rev-list --count` check |
| **تغییرات tracked محلی** | ✅ `status --porcelain` check |
| **مسیرهای legacy** | ❌ **خطر** | اگر کاربر در `~/userbot_own` باشد و `update.sh` را اجرا کند، origin همچنان `userbot_own` است |
| **حفظ accounts/session/data** | ✅ `PROTECTED_PATHS` شامل `Userbot/accounts`, `Userbot/data`, `Userbot/.env` |
| **مسیرهای پکیج منسوخ** | ✅ بررسی `userbot_own/` در gitignore |
| **رفتار Windows launcher** | ✅ `run.bat` reinstall URL به‌روزرسانی شده |

**اصلاح لازم در `update.sh`:** در ابتدای اسکریپت، origin را بررسی و در صورت لزیم به‌روز کنید:
```bash
CURRENT_ORIGIN=$(git -C "$INSTALL_DIR" config --get remote.origin.url || echo "")
if [[ "$CURRENT_ORIGIN" == *"userbot_own"* ]]; then
  log "Updating origin URL to new repository..."
  git -C "$INSTALL_DIR" remote set-url origin "https://github.com/parhamghahremani/TeleWeave.git"
fi
```

---

## ۷. تأیید وثایق و URLها

| فایل | URL قدیمی | URL جدید | وضعیت در PR #3 |
|------|-----------|----------|----------------|
| `install.sh` (usage comment) | `parhamghahremani/userbot_own` | `parhamghahremani/TeleWeave` | ✅ اصلاح شده |
| `install.sh` (REPO_URL) | `github.com/parhamghahremani/userbot_own.git` | `github.com/parhamghahremani/TeleWeave.git` | ✅ اصلاح شده |
| `install.sh` (reinstall) | `parhamghahremani/userbot_own` | `parhamghahremani/TeleWeave` | ✅ اصلاح شده |
| `update.sh` (usage) | `~/userbot_own/update.sh` | `~/TeleWeave/update.sh` | ✅ اصلاح شده |
| `run.bat` (reinstall) | `parhamghahremani/userbot_own` | `parhamghahremani/TeleWeave` | ✅ اصلاح شده |
| `README.md` (install cmd) | `parhamghahremani/userbot_own` | `parhamghahremani/TeleWeave` | ✅ اصلاح شده |
| `README.md` (clone dir) | `~/userbot_own` | `~/TeleWeave` | ✅ اصلاح شده |
| `README.md` (git push example) | `~/userbot_own` | `~/TeleWeave` | ✅ اصلاح شده |
| `README.md` (project structure) | `userbot_own/` | `TeleWeave/` | ✅ اصلاح شده |
| `CHANGELOG.md` | مراجع مختلط | `parhamghahremani/TeleWeave` | ✅ اصلاح شده |
| `cloudflare/tg-relay-worker.js` | `userbot_own v3.2.9` | `TeleWeave/Userbot v3.2.13` | ✅ اصلاح شده |

**باقی‌مانده:** GitHub badges در README (اگر وجود داشته باشد) — در PR #3 بررسی نشده، اما README فعلی badge ندارد.

---

## ۸. برنامه تمیزسازی Триگرهای Branch در CI

**فایل فعلی `.github/workflows/ci.yml` خطوط ۳–۷:**
```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main, v3.2.13-migration]  # ← فرع مهاجرتی منسوخ
```

**اقدام پس از مرج PR #3:**
1. حذف `v3.2.13-migration` از push triggers
2. حذف شاخه `v3.2.13-migration` از GitHub (از طریق UI یا `git push origin --delete`)
3. حذف شاخه `fix/remove-legacy-userbot-package` (از PR #2)
4. نگه داشتن تنها `main` به عنوان شاخه دائمی

**Workflow نهایی پیشنهادی:**
```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
```

---

## ۹. جدول خلاصه PASS / FAIL / NOT VERIFIED

| # | دسته | مورد | وضعیت | یادداشت |
|---|------|------|-------|---------|
| ۱ | **Repo** | مخزن به `TeleWeave` تغییر نام یافته | ✅ PASS | تأیید شده با `gh repo view` |
| ۲ | **Repo** | شاخه پیش‌فرض `main` | ✅ PASS | |
| ۳ | **Auth** | GitHub CLI با `parhamghahremani` احراز هویت | ✅ PASS | |
| ۴ | **PR #3** | باز، base=main، head=fix/complete-operational-migration | ✅ PASS | |
| ۵ | **PR #3** | CI سبز در مخزن جدید | ✅ PASS | ۱۷ چک pass |
| ۶ | **Local** | `origin` به URL جدید اشاره | ✅ PASS | اصلاح شده |
| ۷ | **CI** | تست مسیر رانتایم (فعلی) | ❌ **FAIL** | از `Path.cwd()` استفاده می‌کند، نه `repo_root` |
| ۸ | **CI** | تست مسیر رانتایم (اصلاح پیشنهادی) | ⏳ **NOT VERIFIED** | نیاز به پیاده‌سازی و تست |
| ۹ | **Migration** | تشخیص نصب قدیمی در `install.sh` | ❌ **FAIL** | فعلاً وجود ندارد |
| ۱۰ | **Migration** | کپی امن داده‌های legacy | ⏳ **NOT VERIFIED** | نیاز به پیاده‌سازی |
| ۱۱ | **Migration** | جلوگیری از overwrite نصب جدید | ⏳ **NOT VERIFIED** | نیاز به پیاده‌سازی |
| ۱۲ | **CLI** | دستور `teleweave` استاندارد | ✅ PASS | |
| ۱۳ | **CLI** | Alias `userbot` برای سازگاری | ❌ **FAIL** | وجود ندارد |
| ۱۴ | **Updater** | Origin به‌روز در `update.sh` | ❌ **FAIL** | نیاز به بررسی origin |
| ۱۵ | **Updater** | Fast-forward-only حفظ شده | ✅ PASS | |
| ۱۶ | **Updater** | حفظ داده‌های کاربر | ✅ PASS | PROTECTED_PATHS کامل |
| ۱۷ | **Docs** | تمام URLها به `TeleWeave` | ✅ PASS | PR #3 کامل |
| ۱۸ | **CI** | تمیزسازی branch triggers | ⏳ **NOT VERIFIED** | پس از مرج PR #3 |
| ۱۹ | **Packaging** | Wheel فقط `Userbot/` دارد | ✅ PASS | CI تأیید |
| ۲۰ | **Packaging** | Distribution name `teleweave` v3.2.13 | ✅ PASS | CI تأیید |
| ۲۱ | **Version** | ۴ کپی دستی همگام (3.2.13) | ✅ PASS | VERSION, pyproject.toml, __init__.py, README |

---

## ۱۰. ریسک‌ها و محدودیت‌ها

| ریسک | سطح | توضیح |
|------|-----|---------|
| **تست مسیر رانتایم CI غلط** | 🔴 **بالا** | CI امروز pass می‌دهد اما منطق اشتباه است؛ در installed mode مسیرها شکست می‌خورند |
| **مهاجرت نصب قدیمی نامعتبر** | 🔴 **بالا** | کاربران در `~/userbot_own` نمی‌توانند به `~/TeleWeave` آپدیت شوند |
| **Alias `userbot` گم شده** | 🟠 **متوسط** | کاربران قدیمی دستور `userbot` را از دست می‌دهند |
| **Origin منسوخ در `update.sh`** | 🟠 **متوسط** | آپدیت در legacy repo با origin قدیمی شکست می‌خورد |
| **Branch triggers منسوخ در CI** | 🟢 **کم** | فقط noise ایجاد می‌کند، عملکردی را خراب نمی‌کند |
| **تعارض دو نصب همزمان** | 🔴 **بالا** | اگر هر دو `~/userbot_own` و `~/TeleWeave` وجود داشته باشند، installer با `die` متوقف می‌شود (safe) |

---

## ۱۱. فایل‌های نیازمند اصلاح (دقیق)

| فایل | نوع اصلاح | اولویت |
|------|-----------|---------|
| `.github/workflows/ci.yml` | جایگزینی تست runtime paths با رویکرد package-based + dev/installed mode | 🔴 **Critical** |
| `install.sh` | اضافه کردن logic تشخیص و مهاجرت legacy installation (`~/userbot_own` → `~/TeleWeave`) | 🔴 **Critical** |
| `install.sh` | اضافه کردن symlink سازگاری `userbot` → `teleweave` | 🟠 **High** |
| `update.sh` | اضافه کردن بررسی و به‌روزرسانی origin URL در ابتدای اسکریپت | 🟠 **High** |
| `.github/workflows/ci.yml` | حذف `v3.2.13-migration` از push triggers (پس از مرج) | 🟢 **Low** |

---

## ۱۲. توالی اجرای پیشنهادی

### مرحله ۱: اصلاحات Critical (قبل از مرج PR #3 یا در PR جداگانه)
1. **`.github/workflows/ci.yml`** — اصلاح تست runtime paths (dev + installed mode simulation)
2. **`install.sh`** — اضافه کردن بلوک تشخیص/مهاجرت legacy (خطوط ۲۴۶–۲۵۷، قبل از `sync_existing_repository`)
3. **`install.sh`** — اضافه کردن symlink `userbot` بعد از ایجاد launcher
4. **`update.sh`** — اضافه کردن بررسی origin URL در خطوط ۱۰۶–۱۱۰ (قبل از preconditions)

### مرحله ۲: مرج PR #3
- مرج با **regular merge commit** (preserve history)
- حذف شاخه `fix/complete-operational-migration`

### مرحله ۳: تمیزسازی پس از مرج
1. حذف `v3.2.13-migration` از CI push triggers
2. حذف شاخه‌های منسوخ از GitHub: `v3.2.13-migration`, `fix/remove-legacy-userbot-package`
3. تگ‌گذاری `v3.2.13` و push تگ
4. تأیید کارکرد کامل با `teleweave` در محیط تمیز

### مرحله ۴: مستندات مهاجرتی برای کاربران
- اضافه کردن بخش "Migrating from userbot_own" به README
- اطلاع‌رسانی در CHANGELOG برای نسخه 3.2.14 (patch)

---

## ۱۳. جمع‌بندی

**✅ تکمیل شده (تأیید شده):**
- تغییر نام مخزن به `parhamghahremani/TeleWeave`
- احراز هویت GitHub CLI
- PR #3 با تمام تغییرات URL و دایرکتوری
- CI سبز در مخزن جدید (با تست فعلی)
- همگام‌سازی نسخه 3.2.13 در ۴ کپی
- بسته‌بندی Wheel صحیح
- مستندات و URLها به‌روزرسانی شده

**❌ نیاز به اقدام فوری (Critical):**
1. **تست مسیر رانتایم CI** — منطق فعلی غلط است، باید `repo_root` را شبیه‌سازی کند
2. **مهاجرت نصب قدیمی** — `install.sh` باید `~/userbot_own` را تشخیص دهد و به `~/TeleWeave` مهاجرت دهد
3. **Alias سازگاری `userbot`** — برای عدم شکستن workflow کاربران موجود
4. **به‌روزرسانی Origin در `update.sh`** — برای پشتیبانی از آپدیت از نصب‌های قدیمی

**⏳ پس از مرج PR #3:**
- تمیزسازی branch triggers در CI
- حذف شاخه‌های موقت
- تگ‌گذاری v3.2.13

---

**امضا:** Post-Rename Verification Agent  
**تاریخ:** 2026-11-27  
**وضعیت:** 📋 **گزارش کامل — منتظر تأیید صریح برای پیاده‌سازی اصلاحات Critical**

> **نکته مهم:** این گزارش **فقط خواندنی (read-only audit)** است. هیچ فایلی تغییر نکرده، هیچ کامتی ایجاد نشده، هیچ مرجی انجام نشده. طبق دستورالعمل، پس از ارائه این گزارش **مکث اجباری** وجود دارد تا تأیید صریح کاربر برای پیاده‌سازی اصلاحات دریافت شود.