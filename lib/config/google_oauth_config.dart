/// Google Cloud OAuth setup for Drive backup (Android/iOS).
///
/// 1. [Google Cloud Console](https://console.cloud.google.com/) → APIs → enable **Google Drive API**
/// 2. Credentials → **OAuth client ID** → Android:
///    - Package: [androidPackage]
///    - SHA-1: [debugSha1] (debug/release APK built with debug keystore)
/// 3. Credentials → **OAuth client ID** → Web application → copy Client ID into [webClientId]
class GoogleOAuthConfig {
  GoogleOAuthConfig._();

  static const String androidPackage = 'com.example.budget_pro1';

  /// Debug keystore SHA-1 (current release APK uses debug signing in build.gradle).
  static const String debugSha1 = 'C8:9C:03:BF:03:A8:E3:C3:E0:74:AF:2C:F6:9C:B7:67:13:05:01:90';

  /// Web OAuth client ID (type: Web application) — required on Android for Drive API.
  /// Create in same Google Cloud project as the Android client above.
  static const String webClientId =
      '563615922377-3to5f2jld4a27sq4k059o7vj38idq9q4.apps.googleusercontent.com';
}
