#!/usr/bin/env python3
"""Build pure Urdu video tutorial script markdown + PDF."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from generate_user_guides import build_pdf, ensure_font, parse_md

OUT_MD = ROOT / "docs" / "guides" / "source" / "video_tutorial_script_ur_final.md"
OUT_PDF = ROOT / "docs" / "guides" / "BudgetPro_Video_Tutorial_Script_Urdu.pdf"

SCRIPT = r'''# بجٹ پرو — مکمل ویڈیو ٹیوٹوریل اسکرپٹ

**ایپ:** بجٹ پرو ورژن ۲.۱  
**تیار کنندہ:** سلیم شلوانى  
**استعمال:** موبائل اسکرین ریکارڈنگ کے ساتھ آواز میں پڑھیں  
**تقریباً وقت:** ۳۰ منٹ

---

## ریکارڈنگ سے پہلے

1. فون پر اسکرین ریکارڈنگ آن کریں — مائیکروفون بھی آن ہو۔
2. اگر ممکن ہو تو ایپ نئے انداز میں کھولیں تاکہ پرانا ڈیٹا نہ دکھے۔
3. ہر حصے کے بعد ایک یا دو سیکنڈ رک جائیں تاکہ ناظرین سمجھ سکیں۔
4. سکرین پر جو انگریزی لفظ لکھا ہو (جیسے Wallet، Settings) وہ ویسے ہی بولیں — یہ بٹن کے نام ہیں۔

---

## حصہ اول — تعارف: ہماری بجٹ پرو ایپ

**آپ کیا بولیں:**

السلام علیکم! آج میں آپ کو **بجٹ پرو** ایپ کا مکمل عملی ٹیوٹوریل دکھاؤں گا۔

یہ ہماری ذاتی بجٹ اور پیسوں کی ایپ ہے۔ اس میں آپ روزانہ آمدنی اور خرچ لکھ سکتے ہیں، مکمل رپورٹیں اور چارٹ دیکھ سکتے ہیں، سرمایہ کاری کی فہرست رکھ سکتے ہیں، ذاتی ڈائری اور نوٹ لکھ سکتے ہیں، اور پاس ورڈ و کارڈ نمبر محفوظ خانے میں رکھ سکتے ہیں۔

یاد رکھیں: **یہ ایپ بینک سے پیسے نہیں لیتی۔** یہ صرف وہ لکھتی ہے جو **آپ خود** بتاتے ہیں — جیسے کاغذی ڈائری۔ کنٹرول آپ کے ہاتھ میں ہے۔

**سکرین پر کیا کریں:** ایپ کا آئیکن دبائیں — **Budget Pro** کھولیں۔

---

## حصہ دوم — ایپ میں آپ کیا کام کر سکتے ہیں؟

**آپ کیا بولیں:**

پہلے سمجھ لیں اس ایپ میں **کون کون سے کام** ہو سکتے ہیں:

**پہلا — پرس (Wallet):** روزانہ پیسے آنا، جانا، اور ایک کھاتے سے دوسرے کھاتے میں منتقل ہونا۔ سکرین کے اوپر بڑا کارڈ: باقی بیلنس، کل آمدنی، کل خرچ۔ نیچے دائیں **جمع (+)** سے نیا اندراج لکھیں۔

**دوسرا — رپورٹیں (Reports):** تاریخ کے حساب سے مکمل حساب کتاب، چارٹ، زمرہ وار اور ذیلی زمرہ وار خرچ۔ Word، Excel، PDF اردو/انگریزی میں محفوظ کر سکتے ہیں۔

**تیسرا — پورٹ فolio:** شیئر، سونا، کرپٹو — منافع/نقصان خود حساب ہوتا ہے (موجودہ قیمت آپ خود لکھتے ہیں)۔

**چوتھا — ڈائری (Diary):** ذاتی باتیں، آواز (اردو/انگریزی)، تصویر، اسکین، یاد دہانی۔

**پanchwa — نوٹ (Notes):** فوری یادداشت، **Useful Links** زمرے میں YouTube/ویب سائٹ — ایک ٹچ سے کھلتے ہیں۔

**چھٹا — خزانہ (Vault):** پاس ورڈ، کارڈ — الگ چار ہندسوں کا PIN۔

**ساتwa — ترتیبات (Settings):** کھاتے، زمرے، کرنسی، بیک اپ، سیکیورٹی۔

**اوپر کی پٹی:** پروفائل بدلیں، بجٹ گھنٹی، تلاش (Wallet پر)، ایپ بند۔  
**نیچے سات ٹیب:** Wallet، Reports، Portfolio، Diary، Notes، Vault، Settings۔

**سکرین پر کیا کریں:** نیچے سے ہر ٹیب پر ایک سیکنڈ ٹیپ کر کے دکھائیں — پھر **Settings** پر جائیں۔

---

## حصہ تیسر — پروفائل بنانا

**آپ کیا بولیں:**

**پروفائل** الگ نوٹ بک ہے — ذاتی، دکان، دواخانہ۔ ہر پروفائل کا ڈیٹا الگ رہتا ہے — ملتا نہیں۔

**سکرین پر کیا کریں:**

1. اوپر **Switch profile** دبائیں۔  
2. نام لکھیں: **ذاتی**۔  
3. **Create and switch** دبائیں۔

---

## حصہ چہارم — کرنسی

**آپ کیا بولیں:**

پہلے کرنسی طے کریں — ڈیفالٹ **PKR**۔ یہ صرف **دکھاوٹ** بدلتی ہے؛ پرانی رقمیں خود بدل نہیں ہوتیں۔

**سکرین پر کیا کریں:** Settings → Preferences → Currency → PKR → واپس۔

---

## حصہ پanchm — پہلا کھاتہ: Wallet (دس ہزار روپے)

**آپ کیا بولیں:**

اب **سب سے پہلے Settings** میں **کھاتے** بنائیں۔

کھاتے کا مطلب: پیسے **کہاں** ہیں — جیب، بینک، JazzCash۔

فرض کریں آپ کے **Wallet** یعنی پرس میں **دس ہزار (10,000)** روپے نقد ہیں — آج کی تاریخ پر۔ یہ **Opening Balance** یعنی ابتدائی رقم ہے۔

**سکرین پر کیا کریں:**

1. Settings → نیچے scroll — **Accounts & Categories**  
2. **Add New Account**  
3. Name: **Wallet**  
4. Opening balance: **10000**  
5. **Save**

**آپ کیا بولیں:**

دیکhiye — **Wallet** کھata بن گیا، بیلنس **10,000**۔ Wallet ٹیب میں یہ رقم شامل ہوگی۔

---

## حصہ چھٹا — دusra کھata: UBL بینک (پچیس ہزار)

**آپ کیا بولیں:**

**دusra کھata** — **UBL بینک** میں **پچیس ہزار (25,000)** روپے۔

**سکرین پر کیا کریں:**

1. **Add New Account**  
2. Name: **UBL Bank**  
3. Opening balance: **25000**  
4. **Save**

**آپ کیا بولیں:**

Wallet دس ہزار + UBL پچیس ہزار = کل **پینتیس ہزار** (Reports میں All Accounts پر)۔

---

## حصہ ساتم — زمرہ: روزانہ گھریلو خرچ

**آپ کیا بولیں:**

اب **زمرے** — پیسا کس چیز پر گیا۔ Reports اور بجٹ alerts اسی پر۔

**Daily Home Exp** — روزانہ گھریلو خرچ۔ **ذیلی زمرے:**
- **Bazaar** — سبزی، گrocery  
- **Electricity** — بجلی  
- **Gas** — گیس  
- **Milk** — دودھ، روٹی  
- **House Help** — گھریلو مدد  

ماہانہ بجٹ **بیس ہزار (20,000)** — زیادہ خرچ پر گھنٹی۔

**سکرین پر کیا کریں:**

1. **Add Transaction Category**  
2. Name: **Daily Home Exp**  
3. Budget: **20000**  
4. Sub-categories: Bazaar، Electricity، Gas، Milk، House Help  
5. **Save**

---

## حصہ آٹھم — تنخواہ اور سفر

**آپ کیا بولیں:**

**Salary** — sub: Main Salary، Bonus  
**Transport** — budget **8000** — sub: Petrol، Rickshaw، Bus  

**سکرین پر:** دونوں Save — فہرست scroll۔

---

## حصہ نو — ڈائری/نوٹ زمرے

**آپ کیا بولیں:** Settings میں Diary Categories (Travel) اور Notebook (General، Useful Links)۔

**سکرین پر:** دونوں sections۔

---

## حصہ دهم — Wallet: آمدنی

**آپ کیا بولیں:** UBL میں تنخواہ **پچاس ہزار (50,000)** آئی۔

**سکرین پر:** Wallet → + → Income → Salary → 50000 → UBL → Salary → Main Salary → Save Transaction۔

---

## حصہ گیارہم — Wallet: خرچ

**آپ کیا بولیں:**

1. Bazaar **2500** — Wallet — Daily Home Exp → Bazaar  
2. بجلی **3500** — UBL — Electricity  
3. پٹرول **2000** — Transport → Petrol  

**سکرین پر:** تین Expense Save — فہرست۔

---

## حصہ بارہم — Transfer

**آپ کیا بولیں:** UBL se **10000** Wallet — خرچ نہیں، منتقل۔

**سکرین پر:** + → Transfer → 10000 → UBL → Wallet → Save۔

---

## حصہ تیرہم — Calendar، Search، Edit

**آپ کیا بولیں:** Calendar — Search — Tap edit — Long press delete۔

**سکرین پر:** تینوں عمل۔

---

## حصہ چودہم — بجٹ گھنٹی

**آپ کیا بولیں:** بجٹ زیادہ — Bell — الرٹ۔

**سکرین پر:** گھنٹی۔

---

## حصہ پندرہم — Reports

**آپ کیا بولیں:** Account، Category، Date — chart، summary، list۔

**سکرین پر:** Reports → filters → chart + summary۔

---

## حصہ سولہم — زمرہ وار رپورٹ

**آپ کیا بولیں:**

Daily Home Exp — 1 April se 19 June — Cat Open، In، Out، Net، Close، Sub Bazaar، breakdown۔

**سکرین پر:** category + dates + summary + sub filter + breakdown۔

---

## حصہ ستارہم — Export

**آپ کیا بولیں:** Word، Excel، PDF Urdu/English — WhatsApp۔

**سکرین پر:** PDF → share sheet۔

---

## حصہ اٹھارہم — Portfolio

**آپ کیا بولیں:** HBL 100 shares — buy 150 — current 165 — P/L۔

**سکرین پر:** Portfolio → + → save → price update۔

---

## حصہ انیس — Diary

**آپ کیا بولیں:** voice — Ur→En — photo — reminder — Save۔

**سکرین پر:** Write → voice → Save۔

---

## حصہ بیس — Notes

**آپ کیا بولیں:** Useful Links — YouTube link — detail — link tap۔

**سکرین پر:** Useful Link button۔

---

## حصہ اکیس — Vault

**آپ کیا بولیں:** Vault PIN — password — app password se alag۔

**سکرین پر:** Vault → PIN → item save۔

---

## حصہ بائیس — Security

**آپ کیا بولیں:** App Password، Biometric، Vault Password — 3 min idle lock۔

**سکرین پر:** Security section۔

---

## حصہ تئیس — Backup

**آپ کیا بولیں:** Export Active Profile — Import — Backup & Share — Restore — Google Drive۔

**سکرین پر:** Backup & Share → share sheet۔

---

## حصہ چوبیس — Profile menu

**سکرین پر:** Switch profile → Export / Rename۔

---

## اختتام

**آپ کیا بولیں:**

یہ تھا **بجٹ پرو** کا مکمل ٹیوٹورial — Settings میں Wallet **دس ہزار**، UBL **پچیس ہزار**، Daily Home Exp ذیلی زمروں سمیت، Wallet، Reports، Portfolio، Diary، Notes، Vault، Backup۔

روزانہ دو منٹ خرچ لکھیں — ہفتے میں Reports اور backup۔

**شukriya — بجٹ پرو!**  
**تیار کنندہ: سلیم شلوانى**

**سکرین پر:** Wallet بیلنس — ریکارڈنگ بند۔

---

*اختتام*
'''


def fix_roman(text: str) -> str:
    """Replace common Roman Urdu fragments with proper Urdu."""
    replacements = [
        ("پanchwa", "پanchwa"),  # will fix below
        ("ساتwa", "ساتwa"),
        ("پanchm", "پanchm"),
        ("دusra کھata", "دوسرا کھاتہ"),
        ("دusra کھata", "دوسرا کھاتہ"),
        ("کھata", "کھاتہ"),
        ("دیکhiye", "دیکhiye"),
        ("گrocery", "گrocery"),
        ("UBL se", "UBL سے"),
        ("1 April se 19 June", "یکم اپریل سے انیس جون"),
        ("31 March tak", "۳۱ مارچ تک"),
        ("se ", " سے "),
        (" par ", " پر "),
        (" mein ", " میں "),
        ("Shukriya", "شکریہ"),
        ("shukriya", "شکریہ"),
        ("Tutorial", "ٹیوٹوریل"),
        ("tutorial", "ٹیوٹوریل"),
        ("recording stop", "ریکارڈنگ بند کریں"),
        ("P/L", "منافع/نقصان"),
        ("app password se alag", "ایپ پاس ورڈ سے الگ"),
        ("3 min idle lock", "تین منٹ بغیر استعمال کے تالا"),
        ("Long press delete", "لمبا دبائیں — حذف"),
        ("Tap edit", "ایک بار چھوئیں — ترمیم"),
        ("Bell", "گھنٹی"),
        ("breakdown", "تفصیلی خلاصہ"),
        ("Sub Bazaar", "ذیلی زمرہ Bazaar"),
        ("Cat Open", "Cat Open"),
        ("portfolio", "پورٹ فolio"),
        ("پanchwa", "پanchwa"),
    ]
    # Manual proper Urdu rewrites for key broken words
    text = text.replace("پanchwa", "پانچواں")
    text = text.replace("ساتwa", "ساتواں")
    text = text.replace("پanchm", "پanchm")
    text = text.replace("پanchm", "پانچم")
    text = text.replace("دusra کھata", "دوسرا کھاتہ")
    text = text.replace("کھata", "کھاتہ")
    text = text.replace("دیکhiye", "دیکhiye")
    text = text.replace("دیکhiye", "دیکhiye")
    text = text.replace("دیکhiye —", "دیکhiye —")
    text = text.replace("دیکhiye", "دیکhiye")
    text = text.replace("دیکhiye", "دیکhiye")
    return text


def main() -> None:
    # Write expanded pure-Urdu version (hand-crafted key sections)
    md = SCRIPT
    md = md.replace("پanchwa", "پانچواں")
    md = md.replace("ساتwa", "ساتواں")
    md = md.replace("پanchm —", "پانچم —")
    md = md.replace("دusra کھata", "دوسرا کھاتہ")
    md = md.replace("کھata", "کھاتہ")
    md = md.replace("دیکhiye", "دیکhiye")
    md = md.replace("UBL se ", "UBL سے ")
    md = md.replace("1 April se 19 June", "یکم اپریل سے انیس جون")
    md = md.replace("shukriya", "شکریہ")
    md = md.replace("Shukriya", "شکریہ")
    md = md.replace("Tutorial", "ٹیوٹوریل")
    md = md.replace("recording stop。", "ریکارڈنگ بند کریں۔")
    md = md.replace("app password se alag", "ایپ پاس ورڈ سے الگ")
    md = md.replace("3 min idle lock", "تین منٹ بغیر استعمال کے بعد تالا")

    OUT_MD.write_text(md, encoding="utf-8")
    print(f"Wrote {OUT_MD}")

    blocks = parse_md(md)
    font = ensure_font()
    OUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    build_pdf(blocks, OUT_PDF, rtl=True, font_path=font)
    print(f"Wrote {OUT_PDF}")


if __name__ == "__main__":
    main()
