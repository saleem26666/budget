# Budget Pro — Complete User Manual (English)

**App version:** 2.1.9+  
**Author:** Saleem Shalwani  

This guide is for everyone — even if you never used a money app before.

---

## Welcome

**Budget Pro** is your personal money + family life binder:

- Track **income, expense, transfers**
- Convert **foreign currency** (USD, AED, …) into your home currency (e.g. PKR)
- Keep **investments** (shares, gold in tola, crypto…)
- Write a **Journal** (Diary + Notes)
- Store **Vault** passwords, cards, and **family documents** (CNIC, passport…)
- Use **multiple profiles** (Personal, Shop, Pharmacy…)

**Important:** The app does **not** connect to your bank. It only records what you type. You stay in control.

---

## Part 1 — Install

### Android
1. Copy `app-release.apk` to your phone.
2. Open it → allow **Install unknown apps** if asked → **Install**.
3. Open **Budget Pro**.

### Windows
1. Run `budget_pro.exe` from the Release folder.
2. If Windows warns you, choose **More info → Run anyway** (only if you trust the file).

---

## Part 2 — Bottom tabs (6 tabs)

| Tab | Purpose |
|-----|---------|
| **Wallet** | Daily money, balances, add transactions |
| **Reports** | Charts, statements, PDF/Excel/Urdu share |
| **Portfolio** | Investments (shares, gold tola, crypto…) |
| **Journal** | **Diary** + **Notes** in one place (two sub-tabs) |
| **Vault** | Passwords, cards, family documents + expiry alerts |
| **Settings** | Currency, security, backup, accounts, categories |

---

## Part 3 — Top bar

| Control | What it does |
|---------|----------------|
| **Switch profile** | Personal / Shop / Pharmacy… (each has its own data) |
| **Bell** | **Budget alerts** or **Family expiry center** |
| **+ / Search** | Add transaction / search (on Wallet) |
| **Power** | Exit app |

---

## Part 4 — Wallet

### What you see
- **Total balance** = opening balances + income − expense  
- **Account chips** under the total = live balance per account (Cash, Bank…)  
- Income / Expense totals for the filtered list  
- Calendar to filter by day  
- Transaction list with receipts

### Add a transaction
1. Tap **+** or **Add**.
2. Choose **Expense / Income / Transfer**.
3. Enter **Title**, optional description.
4. **Currency** — defaults to your home currency (Settings).  
   - Change to **USD / AED / …** if you spent foreign money.  
   - Type amount in that currency (e.g. `5`).  
   - App shows **Final amount (PKR)** using today’s rate (or manual rate offline).
5. Optional **Family member** — tag spending to someone from Vault family docs.
6. Pick account, category, receipts → **Save**.

### Transfers
- Money moves from Account → To Account (must be different).
- **Budget** chips: **∅** (default = no budget effect), **+** or **−** if you want the transfer to affect a category budget.

### Tips
- Numbers are stored in your **home currency**.
- Changing home currency later only changes the **label**, not old amounts.
- Renaming an account updates old transactions automatically.

---

## Part 5 — Default currency & FX

1. **Settings → Default currency** (e.g. Pakistani Rupee).
2. This is your **home currency** for wallet totals and conversion.
3. In New Transaction, pick another currency to convert at today’s rate.
4. If the internet fails, use **Use manual rate**.

---

## Part 6 — Profiles

1. Tap **Switch profile** (top).
2. Tap a profile to switch, or create a new one.
3. Choose a **starter template**:
   - **Personal** — default cash & categories  
   - **Shop** — JazzCash, EasyPaisa, Bank, sales categories  
   - **Pharmacy** — counter + medicine categories  
   - **Empty** — blank start  
4. Each profile has its own database, password, vault PIN, and currency.

---

## Part 7 — Reports

- Filter by account, category, date range.
- See opening / closing balances and charts.
- Export **PDF / Excel** or share in **Urdu**.

---

## Part 8 — Portfolio

1. Add holdings: Stocks, Mutual Funds, **Gold**, Crypto, Bonds, Property…
2. For **Gold**: quantity is in **tola**; enter buy/current **per tola** rate.
3. Update current price anytime for P/L.
4. Portfolio is separate from Wallet cash (manual tracker).

---

## Part 9 — Journal (Diary + Notes)

One tab with two sub-tabs:

| Sub-tab | Use for |
|---------|---------|
| **Diary** | Daily journal, voice EN/UR, photos, share |
| **Notes** | Colored notes, links, reminders fields |

Reminders are saved in the note/entry for your own tracking.

### Document scan (CamScanner-style)
Available on **transactions**, **Journal**, and **Vault**:
1. **Scan with camera** — auto edge detect + crop  
2. **Scan from gallery** — pick photo, then adjust edges  
3. **Improve scan** sheet — filters: Enhance / Grayscale / Contrast / B&W doc  
4. **Read text (OCR)** — copy CNIC / amount hints (Android/iOS phone)

---

## Part 10 — Vault

Protected by a separate **Vault PIN** (local on this device — not cloud “E2E encryption”).

Sections:
- **Passwords**
- **Cards** (incl. PayPak and local types)
- **Family Documents** — CNIC, passport, medical, education… with expiry dates

### Family expiry center
- Tap the **bell** in Vault (or app bar → Family expiry).
- Shows docs/cards **expired** or due within **30 days**.

Share photos from WhatsApp/Gallery into Family Documents when the app asks.

---

## Part 11 — Backup & Restore (Settings)

Clear groups:

### All profiles
| Action | Meaning |
|--------|---------|
| **Backup all profiles** | Full file + pictures → WhatsApp / Files |
| **Restore all profiles** | Replaces **every** profile on this device |
| **Google Drive Sync / Restore** | Same full backup in the cloud (optional) |

### This profile only
| Action | Meaning |
|--------|---------|
| **Export this profile** | Backup only the active profile |
| **Import into this profile** | Restore into active profile only |
| **Restore file into this profile** | Pick single-profile `.budgetpro` (or old SQLite) |
| **Restore as new profile** | Creates a **new** profile from a single backup |

**Tip:** Full backup file ≠ single-profile file. The app will tell you if you pick the wrong type.

---

## Part 12 — Security

- **App password** + optional biometric  
- Idle lock after ~3 minutes  
- **Vault PIN** for Vault only  
- Reset options in Settings clear the **active profile** data (confirm carefully)

---

## Part 13 — Quick daily routine

1. Open **Wallet** → add today’s expenses/income.  
2. Foreign salary/spend? Change **Currency** on the transaction.  
3. Check **bell** for budgets & document expiry.  
4. Once a week: **Backup all profiles** to WhatsApp or Drive.  
5. Shop/pharmacy? Use a separate **profile** with the right template.

---

## Need help?

- Google Drive setup: `docs/GOOGLE_DRIVE_SETUP.md`  
- Rebuild guides (DOCX/PDF): `python scripts/generate_user_guides.py`

Made with care for Pakistan & diaspora families — money, documents, and peace of mind in one app.
