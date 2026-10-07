"""يعدّل مجلد android المولَّد تلقائياً (flutter create) ليدعم:
- صلاحيات الإشعارات POST_NOTIFICATIONS والبصمة
- MainActivity من نوع FlutterFragmentActivity (مطلوب لـ local_auth)
- Desugaring (مطلوب لـ flutter_local_notifications) و appcompat
- ثيم AppCompat لنافذة البصمة
- minSdk = 24
"""
import pathlib
import re

root = pathlib.Path('android')

# ---------- AndroidManifest ----------
mf = root / 'app/src/main/AndroidManifest.xml'
t = mf.read_text(encoding='utf-8')
perms = [
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.USE_BIOMETRIC',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.VIBRATE',
]
add = ''.join(
    f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in t
)
t = re.sub(r'(<manifest\b[^>]*>)', lambda m: m.group(1) + '\n' + add, t, count=1)
t = re.sub(r'android:label="[^"]*"', 'android:label="إدارة العقارات"', t, count=1)
mf.write_text(t, encoding='utf-8')
print('manifest patched')

# ---------- MainActivity -> FlutterFragmentActivity ----------
for f in list(root.rglob('MainActivity.kt')) + list(root.rglob('MainActivity.java')):
    src = f.read_text(encoding='utf-8')
    m = re.search(r'package\s+([\w.]+)', src)
    pkg = m.group(1) if m else 'com.example.real_estate_app'
    if f.suffix == '.kt':
        f.write_text(
            f'package {pkg}\n\nimport io.flutter.embedding.android.FlutterFragmentActivity\n\n'
            'class MainActivity : FlutterFragmentActivity()\n',
            encoding='utf-8',
        )
    else:
        f.write_text(
            f'package {pkg};\n\nimport io.flutter.embedding.android.FlutterFragmentActivity;\n\n'
            'public class MainActivity extends FlutterFragmentActivity {\n}\n',
            encoding='utf-8',
        )
    print('MainActivity patched:', f)

# ---------- app/build.gradle(.kts) ----------
kts = root / 'app/build.gradle.kts'
groovy = root / 'app/build.gradle'
if kts.exists():
    g = kts
    txt = g.read_text(encoding='utf-8')
    txt = re.sub(r'(compileOptions\s*\{)',
                 lambda m: m.group(1) + '\n        isCoreLibraryDesugaringEnabled = true', txt, count=1)
    txt = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', txt)
    txt += (
        '\ndependencies {\n'
        '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
        '    implementation("androidx.appcompat:appcompat:1.7.0")\n'
        '}\n'
    )
else:
    g = groovy
    txt = g.read_text(encoding='utf-8')
    txt = re.sub(r'(compileOptions\s*\{)',
                 lambda m: m.group(1) + '\n        coreLibraryDesugaringEnabled true', txt, count=1)
    txt = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdkVersion 24', txt)
    txt += (
        '\ndependencies {\n'
        "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
        "    implementation 'androidx.appcompat:appcompat:1.7.0'\n"
        '}\n'
    )
g.write_text(txt, encoding='utf-8')
print('gradle patched:', g)

# ---------- ثيم AppCompat (نافذة البصمة) ----------
for sx in root.glob('app/src/main/res/values*/styles.xml'):
    s = sx.read_text(encoding='utf-8')
    s2 = re.sub(r'parent="@android:style/Theme\.[\w.]+"',
                'parent="Theme.AppCompat.DayNight.NoActionBar"', s)
    if s2 != s:
        sx.write_text(s2, encoding='utf-8')
        print('styles patched:', sx)

# ---------- توقيع ثابت (مطلوب لـ Google Sign-In: نفس SHA-1 في كل بناء) ----------
g = kts if kts.exists() else groovy
txt = g.read_text(encoding='utf-8')
ks = 'rootProject.file("../tool/app.keystore")'
if g == kts:
    block = (
        'signingConfigs {\n'
        '        create("fixed") {\n'
        f'            storeFile = {ks}\n'
        '            storePassword = "realestate2026"\n'
        '            keyAlias = "realestate"\n'
        '            keyPassword = "realestate2026"\n'
        '        }\n'
        '    }\n    '
    )
    txt = txt.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("fixed")')
else:
    block = (
        'signingConfigs {\n'
        '        fixed {\n'
        f'            storeFile {ks}\n'
        "            storePassword 'realestate2026'\n"
        "            keyAlias 'realestate'\n"
        "            keyPassword 'realestate2026'\n"
        '        }\n'
        '    }\n    '
    )
    txt = txt.replace('signingConfigs.debug', 'signingConfigs.fixed')
txt = re.sub(r'(\n\s*buildTypes\s*\{)', lambda m: '\n    ' + block + m.group(1).lstrip('\n').lstrip(), txt, count=1)
g.write_text(txt, encoding='utf-8')
print('signing patched:', g)
