# Budget Pro — User Guides (English & Urdu)

Easy step-by-step manuals for **every** feature — written in simple language for beginners.

## Files (open or share)

| Language | Word (DOCX) | PDF |
|----------|-------------|-----|
| **English** | [BudgetPro_User_Guide_English.docx](BudgetPro_User_Guide_English.docx) | [BudgetPro_User_Guide_English.pdf](BudgetPro_User_Guide_English.pdf) |
| **Urdu** | [BudgetPro_User_Guide_Urdu.docx](BudgetPro_User_Guide_Urdu.docx) | [BudgetPro_User_Guide_Urdu.pdf](BudgetPro_User_Guide_Urdu.pdf) |

**Folder:** `c:\projects\budget_pro\docs\guides\`

Send DOCX/PDF to users via WhatsApp, email, or print.

## What is covered (version 2.1.1)

1. Install APK and Windows EXE  
2. All **7 tabs**: Wallet, Reports, **Portfolio**, Diary, Notes, Vault, Settings  
3. **Portfolio / Investment Tracker** — add, edit, update prices, P/L, pie chart  
4. **Currency change** — PKR, USD, AED, and more (per profile)  
5. Accounts and categories (simple explanations for non-accountants)  
6. Income, Expense, Transfer, receipts, search  
7. Reports, charts, Word / Excel / PDF export  
8. Diary & Notes (voice, scan, photos, reminders)  
9. Vault passwords and documents  
10. Multi-profile (Personal, Shop, Family)  
11. Backup, restore, Google Drive  
12. Security — app password, Vault PIN, biometric, idle lock  
13. First-day checklist and daily habit tips  
14. Troubleshooting  

## Regenerate DOCX and PDF after edits

```powershell
cd c:\projects\budget_pro
pip install python-docx fpdf2 requests
python scripts\generate_user_guides.py
```

Edit source text in:

- `docs/guides/source/user_guide_en.md` — full English (simple / beginner)
- `docs/guides/source/user_guide_ur.md` — full Urdu (simple, no English words in body)

## Related

- `docs/GOOGLE_DRIVE_SETUP.md` — Google Drive backup setup
