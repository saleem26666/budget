# Budget Pro

Personal budget, diary, notes, and secure vault - Flutter app for Android (APK) and Windows (EXE).

| | |
|--|--|
| **Version** | `2.1.x` (latest local build) |
| **Package** | `budget_pro` |
| **Android ID** | `com.example.budget_pro1` |
| **Currency** | PKR |
| **APK** | `build\app\outputs\flutter-apk\app-release.apk` |
| **Windows EXE** | `build\windows\x64\runner\Release\budget_pro.exe` |

---

## Quick start (new users)

1. Install `app-release.apk` on your phone.
2. Open **Wallet** and add **Income / Expense / Transfer**.
3. **Settings** -> add accounts and categories with monthly budgets.
4. App bar -> **Switch profile** -> create/select profile.
5. **Settings** -> use backup/import (profile or full backup).
6. Optional: enable app password, biometric, and vault PIN.

**Full English manual (DOCX + PDF):** `docs/guides/BudgetPro_User_Guide_English.docx` and `.pdf`  
**Urdu manual:** `docs/guides/BudgetPro_User_Guide_Urdu.docx` and `.pdf`  
Regenerate guides: `python scripts/generate_user_guides.py`

---

## App tabs

| Tab | Features |
|-----|----------|
| **Wallet** | Live account chips, FX convert on entry, family member tag, receipts |
| **Reports** | Account/category/date filters, charts, PDF/Excel/Urdu share |
| **Portfolio** | Holdings incl. gold (tola), stocks, crypto |
| **Journal** | Diary + Notes in one tab |
| **Vault** | PIN gate, passwords, cards, family docs + expiry center |
| **Settings** | Default currency, clear backup groups, accounts/categories, security |

---

## Multiple Profiles (New)

- Switch profile from app bar (`switch account` icon).
- Create unlimited profiles (Personal, Shop, Pharmacy, Warehouse).
- Each profile uses separate local database storage.
- Profile actions: **Export backup**, **Import backup**, **Rename**, **Delete** (default cannot be deleted).
- Profile-level settings are isolated: app password, biometric, diary categories, notebook categories, vault PIN.
- Settings screen includes dedicated **Active Profile** backup/import actions.

---

## Security

- App password: Strong/Simple mode + optional biometric unlock.
- Idle lock: 3 minutes idle/background.
- Vault PIN: separate 4-digit PIN for Vault tab.

---

## Backup & restore

| Method | How |
|--------|-----|
| **Full local / WhatsApp** | Settings -> **Backup & Share** -> `.budgetpro` |
| **Full restore** | Settings -> **Restore Data** or open shared `.budgetpro` |
| **Profile backup/import** | App bar profile menu or Settings profile section |
| **Google Drive (optional)** | Settings -> Sync / Restore (requires setup) |

Google Drive setup doc: [docs/GOOGLE_DRIVE_SETUP.md](docs/GOOGLE_DRIVE_SETUP.md)

---

## Build

```powershell
cd D:\budget_pro1
flutter pub get
flutter build apk --release
flutter build windows --release
```

Latest successful local outputs:
- APK: `build\app\outputs\flutter-apk\app-release.apk`
- EXE: `build\windows\x64\runner\Release\budget_pro.exe`

---

## Changelog (recent)

| Version | Changes |
|---------|---------|
| 2.1.x | Multi-profile accounts, profile backup/import, category report opening balance, sub-category breakdown |
| 2.0.8 | PDF English + Urdu, HTML mobile share, opening balance improvements |
| 2.0.5 | Google Drive backup section and setup dialog |
| 2.0.2 | Document scanner, idle lock, biometric fix |

---

For full UX details, read `docs/guides/source/user_guide_en.md`.
