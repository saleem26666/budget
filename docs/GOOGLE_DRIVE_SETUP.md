# Google Drive backup — fix sign-in error (code 10)

If you see **"Google sign-in failed"** or `sign_in_failed, 10`, the app is not registered in Google Cloud yet.

## Your app details

| Field | Value |
|--------|--------|
| Package name | `com.example.budget_pro1` |
| SHA-1 (debug APK) | `C8:9C:03:BF:03:A8:E3:C3:E0:74:AF:2C:F6:9C:B7:67:13:05:01:90` |

## Steps (5 minutes)

1. Open [Google Cloud Console](https://console.cloud.google.com/) → select or create a project.
2. **APIs & Services** → **Library** → search **Google Drive API** → **Enable**.
3. **APIs & Services** → **OAuth consent screen** → configure (External is fine for personal use) → add your Gmail as test user if in "Testing".
4. **Credentials** → **Create credentials** → **OAuth client ID**:
   - Application type: **Android**
   - Name: `Budget Pro Android`
   - Package name: `com.example.budget_pro1`
   - SHA-1: `C8:9C:03:BF:03:A8:E3:C3:E0:74:AF:2C:F6:9C:B7:67:13:05:01:90`
5. **Create credentials** again → **OAuth client ID**:
   - Application type: **Web application**
   - Name: `Budget Pro Web`
   - Copy the **Client ID** and put it in `lib/config/google_oauth_config.dart` as `webClientId` (if different from the one already there).
6. Wait **5–10 minutes**, then uninstall Budget Pro from the phone and reinstall the APK, or clear app data → try **Sync backup to Google Drive** again.

## Play Store release later

When you sign the app with a **release keystore**, run:

```bat
"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore YOUR_RELEASE.jks -alias YOUR_ALIAS
```

Add that SHA-1 as a **second** Android OAuth client (or add to the same client if the console allows multiple fingerprints).
