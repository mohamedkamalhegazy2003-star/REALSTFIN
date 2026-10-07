## بناء APK عبر GitHub Actions
ارفع كل المحتويات (lib, assets, tool, .github, pubspec.yaml) ثم Actions > Build APK > Run workflow.

## إعداد النسخ الاحتياطي على Google Drive (مرة واحدة)
1. افتح https://console.cloud.google.com وأنشئ مشروعاً جديداً.
2. APIs & Services > Library > فعّل **Google Drive API**.
3. APIs & Services > OAuth consent screen:
   - User Type: External، املأ اسم التطبيق وبريدك.
   - Scopes: أضف `.../auth/drive.appdata`.
   - Test users: أضف بريد Gmail الذي ستستخدمه (مهم أثناء وضع Testing).
4. APIs & Services > Credentials > Create credentials > **OAuth client ID**:
   - Application type: **Android**
   - Package name: `com.example.real_estate_app`
   - SHA-1: `35:3B:4A:95:0D:74:49:5A:D9:72:03:50:A2:CC:02:8C:CC:0E:7B:B4`
5. ابنِ التطبيق، ثم من الإعدادات > النسخ الاحتياطي > ربط الحساب.

ملاحظة: الملف `tool/app.keystore` هو مفتاح توقيع ثابت ليبقى SHA-1 نفسه في كل بناء.
احتفظ بالمستودع **خاصاً (Private)**.
