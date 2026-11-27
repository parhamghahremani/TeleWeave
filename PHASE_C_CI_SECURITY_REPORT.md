# گزارش جامع فاز C: پیاده‌سازی CI، بررسی امنیتی، و اصلاحات پیش از مرج

**تاریخ:** 2026-11-27  
**شاخه:** `v3.2.13-migration`  
**PR:** #1 در `parhamghahremani/userbot_own`  
**وضعیت:** اصلاحات محلی آماده، منتظر تأیید برای push

---

## ۱. پیاده‌سازی GitHub Actions CI Workflow

### فایل ایجاد شده: `.github/workflows/ci.yml`

**هدف:** تأیید سازگاری Linux case-sensitive filesystem و بسته‌بندی — **الزامی پیش از مرج**

### بررسی‌های انجام شده در Workflow:
| مرحله | توضیح | وضعیت انتظار |
|-------|-------|--------------|
| Package directory casing | وجود `Userbot/`، عدم وجود `userbot_own/` و `userbot/` | ✅ PASS در Windows |
| Import و نسخه | `import Userbot`، `Userbot.__version__ == '3.2.13'` | ✅ PASS در Windows |
| مراجع پکیج قدیمی | `grep -r "userbot_own\."` — صفر نتیجه | ✅ PASS در Windows |
| متاداده توزیع | `teleweave` نام، نسخه `3.2.13` | ✅ PASS در Windows |
| بسته‌بندی Wheel | فقط `Userbot/` در wheel، بدون `userbot_own/` | ✅ PASS در Windows |
| مسیرهای رانتایم | `Paths.from_base()` حل صحیح | ✅ PASS در Windows |
| CLI entry points | `main.py`، `add_account.py`، `settings.py` | ✅ PASS در Windows |
| ماژول‌های هسته/extra | تمام `create_module` import می‌شوند | ✅ PASS در Windows |
| Syntax check | `python -m compileall -q .` | ✅ PASS در Windows |
| محافظت .gitignore | مسیرهای محافظت‌شده ignored هستند | ✅ PASS در Windows |

**نکته مهم:** این workflow روی `ubuntu-latest` اجرا می‌شود و **تست واقعی case-sensitive filesystem** را انجام می‌دهد. تا زمانی که CI سبز نشود، ادعای سازگاری Linux تأیید نشده باقی می‌ماند.

---

## ۲. بررسی امنیتی فایل Wrangler Cache

### فایل: `.wrangler/cache/wrangler-account.json`

**محتوا (تأیید شده):**
```json
{
  "account": {
    "id": "4aa21128fe8d75b521a944391f061348",
    "name": "Parhamghahremani1401@gmail.com's Account"
  }
}
```

### ارزیابی:
| دسته | وضعیت | توضیح |
|------|-------|-------|
| Credentials/Access Tokens | ❌ **ندارد** | فقط شناسه حساب Cloudflare و نام نمایشی |
| Private Keys | ❌ **ندارد** | کلید خصوصی یا توکن API وجود ندارد |
| Account Identifiers | ✅ **دارد** | Account ID (شناسه عمومی حساب) |
| Local Metadata | ✅ **دارد** | ایمیل حساب |

### تصمیم: **حذف از ردیابی گیت**
- فایل با `git rm --cached` از staging حذف شد
- `.wrangler/` به `.gitignore` اضافه شد
- کد Worker واقعی (`cloudflare/tg-relay-worker.js`) **تأثیر نمی‌پذیرد** — فقط cache محلی است
- **هیچ credential洩漏ی وجود ندارد** — عدم نیاز به revoke/rotate

---

## ۳. ارزیابی گزارش‌های حسابرسی فاز A

### فایل‌ها:
1. `PHASE_A_AUDIT_REPORT.md` (۳۰.۷KB) — گزارش کامل ۴۰+ چک‌لیست
2. `PHASE_A_SUPPLEMENTARY_REPORT.md` (۱۱.۸KB) — تأیید نسخه و روال بازیابی گیت

### توصیه: **حذف از مخزن تولید**
**دلایل:**
- گزارش‌های داخلی مهاجرت، مستندات تولید نیستند
- حاوی جزئیات معماری داخلی، مسیرهای فایل، استراتژی تست
- می‌توانند در wiki یا مستندات جداگانه منتقل شوند
- حجم PR را بی‌جهت افزایش می‌دهند (۲۲۵۷۰+ خطوط افزوده در PR فعلی)

**اقدام پیشنهادی:** حذف هر دو فایل از شاخه مهاجرتی، نگهداری کپی محلی در `backups/` یا خارج از مخزن

---

## ۴. بررسی تاریخچه کامیت و هویت نویسنده

### دو کامیت در PR:
| کامیت | پیام | نویسنده (Git) | Committer |
|-------|------|----------------|-----------|
| `72a1b2b` | `chore: local migration state before checkout` | `parham <parhamghahremani1400@gmail.com>` |Same |
| `bac2b5b` | `chore: migrate from userbot_own to TeleWeave/Userbot v3.2.13` | `parham <parhamghahremani1400@gmail.com>` |Same |

### نتایج بررسی:
- ✅ **هویت صحیح:** `parhamghahremani1400@gmail.com` — مطابق حساب فعلی `parhamghahremani`
- ✅ **هیچ فایل داده کاربر:** `accounts/`، `data/`، `.env`، `*.session` ردیابی نمی‌شوند
- ✅ **هیچ credential:** در کامیت‌ها وجود ندارد
- ⚠️ **نمایش GitHub:** PR نویسنده را به صورت `pppppuhdtxd` نمایش می‌دهد — این **فقط متادیتای GitHub UI** است و از `author email` در کامیت ناشی می‌شود که قبلاً به حساب معلق متصل بود. کامیت‌های جدید با `parhamghahremani` ثبت می‌شوند.
- ❌ **Rewrite history:** **ممنوع** بدون تأیید صریح — تاریخچه منتشر شده تغییر نمی‌کند

---

## ۵. تأیید محافظت .gitignore

### الگوهای اضافه شده:
```gitignore
# Cloudflare Wrangler cache
.wrangler/

# Userbot package runtime paths
Userbot/accounts/
Userbot/data/
Userbot/.env*

# Local build artifacts
teleweave.egg-info/
```

### تست‌های تأیید شده:
| تست | نتیجه |
|------|-------|
| `git check-ignore Userbot/accounts Userbot/data Userbot/.env` | ✅ همه ignored |
| `git ls-files Userbot/accounts Userbot/data` | ✅ صفر فایل ردیابی‌شده |
| `git ls-files "*.session" "*.session-journal"` | ✅ صفر فایل ردیابی‌شده |
| `git ls-files "*.log"` | ✅ صفر فایل ردیابی‌شده |
| `git ls-files ".venv" "venv" "__pycache__" "*.pyc" "*.egg-info" "dist" "build"` | ✅ صفر فایل ردیابی‌شده |

**نتیجه:** تمام مسیرهای حساس به‌درستی محافظت شده‌اند.

---

## ۶. اصلاح توضیحات PR (Linux Compatibility Claim)

### قبل (ناقض گزارش):
> "Package directory renamed: `userbot_own/` → `Userbot/` (PascalCase) — **works on case-sensitive Linux/Termux filesystems**"

### بعد (صریح و دقیق):
> "Package directory renamed: `userbot_own/` → `Userbot/` (PascalCase) — **designed for case-sensitive Linux/Termux filesystems (verification pending CI)**"

### تغییرات دیگر در PR Description:
- اضافه شدن `.github/workflows/ci.yml` و تغییرات `.gitignore` در لیست فایل‌ها
- حذف ادعای تأیید Linux — صریحاً "NOT VERIFIED — pending GitHub Actions CI"
- اضافه شدن حذف `.wrangler/cache/wrangler-account.json` از ردیابی

---

## ۷. مراجعة کامل Diff PR (۹۸ فایل)

### خلاصه تغییرات:
| دسته | تعداد فایل | توضیح |
|-------|-----------|-------|
| Core package rename | ۸۸ | `userbot_own/` → `Userbot/` با `git mv` |
| Import updates | ۸۸ | `userbot_own.*` → `Userbot.*` در تمام فایل‌های Python |
| Config/Packaging | ۳ | `pyproject.toml`، `VERSION`، `Userbot/__init__.py` |
| Scripts | ۳ | `install.sh`، `update.sh`، `run.bat` — URLها، launcher، paths |
| Documentation | ۲ | `README.md`، `CHANGELOG.md` |
| CI/CD | ۱ | `.github/workflows/ci.yml` (جدید) |
| Git config | ۱ | `.gitignore` (به‌روزرسانی) |
| Cache removal | ۱ | `.wrangler/cache/wrangler-account.json` (حذف از tracking) |
| Audit reports | ۲ | `PHASE_A_*.md` (پیشنهاد حذف) |

### مشکلات شناسایی شده و اصلاح شده:
| مشکل | وضعیت |
|-------|-------|
| LICENSE copyright به `pppppuhdtxd` برگشته | ✅ در کامیت مهاجرتی اصلاح شد به `parhamghahremani` |
| `.wrangler/cache/wrangler-account.json` در tracking | ✅ حذف شد، به `.gitignore` اضافه شد |
| ادعای تأیید Linux در PR description | ✅ اصلاح شد به "verification pending CI" |
| `.gitignore` فاقد `Userbot/` paths | ✅ الگوهای کامل اضافه شدند |
| فاقد CI workflow | ✅ `.github/workflows/ci.yml` ایجاد شد |

### فایل‌های تغییر نکردنی (محفوظ):
- `cloudflare/tg-relay-worker.js` — Worker source code
- `extras/` — helper scripts
- `backups/` — local backups (ignored)

---

## ۸. اصلاحات محلی آماده برای کامیت

### فایل‌های staged:
```
A  .github/workflows/ci.yml      (CI workflow جدید)
M  .gitignore                    (الگوهای محافظت اضافه شده)
D  .wrangler/cache/wrangler-account.json  (از tracking حذف)
```

### فایل‌های unstaged (پیشنهاد: حذف از شاخه):
```
?? PHASE_B_MIGRATION_REPORT.md   (گزارش داخلی، خارج از PR)
?? PHASE_A_AUDIT_REPORT.md       (پیشنهاد حذف)
?? PHASE_A_SUPPLEMENTARY_REPORT.md (پیشنهاد حذف)
```

### پیام کامیت پیشنهادی:
```
chore: add CI workflow, fix gitignore, remove wrangler cache from tracking

- Add .github/workflows/ci.yml for Linux case-sensitive FS & packaging verification
- Update .gitignore: add .wrangler/, Userbot/accounts/, Userbot/data/, Userbot/.env*, teleweave.egg-info/
- Remove .wrangler/cache/wrangler-account.json from git tracking (local cache only)
- Correct PR description: Linux compatibility pending CI verification

Pre-merge requirement: CI must pass on ubuntu-latest before merging.
```

---

## ۹. ریسک‌های باقی‌مانده

| ریسک | سطح | اقدام پیشگیرانه |
|------|-----|-----------------|
| **CI fail on ubuntu-latest** | 🔴 **High** | اگر import case-sensitive fail شود، باید نام دایرکتوری/import بررسی شود |
| **Audit reports در مخزن** | 🟡 Medium | حذف پیش از merge پیشنهادی است |
| **GitHub author UI showing old identity** | 🟢 Low | فقط UI؛ کامیت‌های جدید با parhamghahremani |
| **LICENSE copyright flip-flop** | 🟢 Low | در کامیت مهاجرتی اصلاح شده |
| **Missing test for Termux specifically** | 🟡 Medium | CI فقط ubuntu-latest؛ Termux needs manual test |

---

## ۱۰. خلاصه اقدامات پیش از مرج

### ✅ تکمیل شده (محلی):
1. CI workflow ایجاد و تست شده در Windows
2. Wrangler cache حذف از tracking، به gitignore اضافه
3. .gitignore کامل‌سازی برای Userbot/ paths
4. PR description اصلاح شده (Linux claim)
5. Diff کامل بررسی شده، مشکلات رفع شده
6. Build/packaging/imports در Windows تأیید شده

### ⏳ منتظر اقدام:
1. **تأیید کاربر برای push کامیت اصلاحات** (CI workflow + gitignore + cache removal)
2. **اجرای CI روی ubuntu-latest** — باید سبز شود
3. **حذف PHASE_A_*.md از شاخه** (اختیاری، توصیه شده)
4. **Merge PR #1** بعد از CI سبز
5. **Tag v3.2.13** بعد از merge
6. **تغییر نام مخزن به TeleWeave** (توسط کاربر دستی)

---

## ۱۱. دستور Push پیشنهادی (پس از تأیید)

```bash
# در شاخه v3.2.13-migration
git commit -m "chore: add CI workflow, fix gitignore, remove wrangler cache from tracking

- Add .github/workflows/ci.yml for Linux case-sensitive FS & packaging verification
- Update .gitignore: add .wrangler/, Userbot/accounts/, Userbot/data/, Userbot/.env*, teleweave.egg-info/
- Remove .wrangler/cache/wrangler-account.json from git tracking (local cache only)
- Correct PR description: Linux compatibility pending CI verification

Pre-merge requirement: CI must pass on ubuntu-latest before merging."

git push origin v3.2.13-migration
```

---

**امضا:** Phase C Migration Agent  
**تاریخ:** 2026-11-27  
**وضعیت:** ✅ اصلاحات محلی کامل — منتظر تأیید push و نتیجه CI